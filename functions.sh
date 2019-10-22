#!/bin/bash

put() {
  printf "%s" "$1" 1>&2
}

puts() {
  printf "%s\n" "${1:-}" 1>&2
}

green() {
  echo -e "\033[92;1m$1\033[0m"
}

red() {
  echo -e "\033[91;1m$1\033[0m"
}

yellow() {
  echo -e "\033[93;1m$1\033[0m"
}

url_encode() {
  echo "$1" | tr -d \\n | jq -sRr @uri
}

validate_config() {
  if ! yq r "$1" >/dev/null 2>&1; then
    puts "Invalid yml file: $1"
    exit 1
  fi
}

check_key() {
  mkdir -p "$OUT"
  if [ ! -f "$OUT/adbkey" ]; then
    puts "generating $OUT/adbkey"
    $ADB start-server >>"$LOG" 2>&1
    cp "$HOME/.android/adbkey" "$HOME/.android/adbkey.pub" "$OUT"
  fi
  if [ ! -f "$KEYSTORE" ]; then
    puts "generating $KEYSTORE"
    keytool -genkey -v -keystore "$KEYSTORE" -storepass "$KSPASS" -keypass "$KSPASS" -alias implant -keyalg RSA -keysize 2048 -validity 10000 -dname "C=US, O=Android, CN=Implant" >>"$LOG" 2>&1
  fi
  if ! keytool -list -keystore "$KEYSTORE" -storepass "$KSPASS" >>"$LOG" 2>&1; then
    puts "invalid password for $KEYSTORE"
    exit 1
  fi
  if ! keytool -list -keystore "$KEYSTORE" -storepass "$KSPASS" -alias implant >>"$LOG" 2>&1; then
    puts "missing implant alias in $KEYSTORE"
    exit 1
  fi
}

passwd() {
  if tty -s; then
    yellow "passwd requires 'docker run --interactive ...' (do not use -t/--tty flag)"
    exit 1
  fi
  IFS=""
  echo -n Enter new password:
  read -rs password
  if [ -z "$password" ]; then
    echo
    yellow "passwd requires 'docker run --interactive ...' (do not use -t/--tty flag)"
    exit 1
  fi
  if [ "${#password}" -lt 6 ]; then
    yellow "password must be at least six characters"
    exit 1
  fi
  echo -n Re-enter new password:
  read -rs verify
  if [ "$password" != "$verify" ]; then
    puts "passwords do not match"
    exit 1
  fi
  if ! keytool -keypasswd -new "$password" -storepass "$KSPASS" -keystore "$KEYSTORE" -alias implant >>"$LOG" 2>&1; then
    puts "failed to change key password"
    exit 1
  fi
  if ! keytool -storepasswd -new "$password" -storepass "$KSPASS" -keystore "$KEYSTORE" >>"$LOG" 2>&1; then
    puts "failed to change keystore password"
    exit 1
  fi
  puts "password changed successfully"
}

get_latest_tag() {
  if [ -z "$GIT_TAGS" ]; then
    GIT_TAGS="[vV]?[0-9.-]+"
  fi
  LATEST_SHA=$GIT_SHA
  for tag in $(git tag --sort=-committerdate); do
    if ! [[ "$tag" =~ ^${GIT_TAGS}$ ]]; then
      puts "$tag does not match"
      continue
    fi
    SHA=$(git rev-parse --short=7 "$tag^{}")
    if git merge-base --is-ancestor "$SHA" "$LATEST_SHA"; then
      puts "$tag ($SHA) is ancestor of $LATEST_SHA"
      continue
    fi
    OLD_DATE=$(get_commit_date "$LATEST_SHA")
    NEW_DATE=$(get_commit_date "$SHA")
    if [ "$NEW_DATE" -lt "$OLD_DATE" ]; then
      puts "$tag ($SHA) is older than $LATEST_SHA"
      continue
    fi
    LATEST_SHA=$SHA
    puts "found newer tag $tag ($LATEST_SHA)"
  done
  echo "$LATEST_SHA"
}

get_apk_version_code() {
  $APKANALYZER manifest version-code "$1"
}

find_build_tool() {
  find "$TOOLS" -name "$1" | sort | tail -n 1
}

get_installed_packages() {
  PACKAGES=()
  for p in $(adb shell pm list package | awk -F'package:' '{ print $2 }' | sort); do
    if [ -f "$METADATA/$p.yml" ]; then
      PACKAGES+=("$p")
    fi
  done
}

up_to_date() {
  if [ -z "$2" ]; then
    return 1
  fi

  if [ "$INSTALL" -eq 1 ]; then
    [ "$(get_install_version_code "$1")" == "$2" ]
  else
    [ -f "$APKS/$1-$2.apk" ]
  fi
}

get_installed_version_code() {
  adb shell dumpsys package "$1" | grep versionCode | awk '{ print $1 }' | grep -o "[0-9]\+"
}

get_commit_date() {
  git show --no-patch --no-notes --pretty='%ct' "$1"
}

get_package() {
  filename=$(basename "$1")
  echo "${filename%.yml*}"
}

setup_logging() {
  mkdir -p "$IMPLANT"
  touch "$LOG"
  if [ "$VERBOSE" -eq 1 ]; then
    exec > >(tee "$LOG") 2>&1
  else
    exec >>"$LOG" 2>&1
  fi
}

prebuild() {
  if [ -z "$PREBUILD" ]; then
    return 0
  fi
  puts "prebuild..."
  to_array "$PREBUILD"
  for step in "${array[@]}"; do
    puts "prebuild step: $step"
    if ! eval "$step"; then
      exit 1
    fi
  done
}

to_array() {
  IFS=$'\n'
  array=()
  for entry in $1; do
    array+=("$entry")
  done
}

build() {
  puts "building $PACKAGE..."
  if [ -z "$BUILD" ]; then
    TASK=assemble$FLAVOR$TARGET
    if [ -n "$PROJECT" ]; then
      TASK=$PROJECT:$TASK
    fi

    /bin/bash -c "$GRADLE --stacktrace $TASK"
  else
    eval "$BUILD"
  fi
  # shellcheck disable=SC2181
  if [ $? -ne 0 ]; then
    exit 1
  fi
}

setup_gradle_properties() {
  if [ -z "$GRADLEPROPS" ]; then
    return 0
  fi
  puts "creating gradle.properties..."
  echo "" >>gradle.properties
  echo "$GRADLEPROPS" >>gradle.properties
}

setup_ndk() {
  if [ -z "$NDK" ]; then
    return 0
  fi
  NDK_DIR=android-ndk-$NDK
  NDK_URL=https://dl.google.com/android/repository/$NDK_DIR-linux-x86_64.zip
  export ANDROID_NDK_HOME=$TMP/$NDK_DIR

  download "$NDK_URL"

  extract "$DEST"
}

get_config() {
  PROP=$1
  DEFAULT=${2:-}
  value=$(yq r "$CONFIG" "$PROP")
  if [ "$value" != null ]; then
    puts "$1=$value"
    echo "$value"
  else
    puts "$1=$DEFAULT [default]"
    echo "$DEFAULT"
  fi
}

install_deps() {
  if [ -z "$DEPS" ]; then
    return 0
  fi
  puts "installing dependencies..."
  # running sudo for use outside of a container
  sudo apt-get update
  # shellcheck disable=SC2086
  if ! sudo apt-get install --no-install-suggests --no-install-recommends -y $DEPS; then
    exit 1
  fi
}

adb() {
  HOST=$(getent hosts host.docker.internal | awk '{ printf $1 }')
  $ADB -H "${HOST:-localhost}" "$@"
}

clone_and_cd() {
  clone "$1" "$2" "$3"
  cd "$2" || exit
}

zipalign() {
  zipalign=$(find_build_tool zipalign)
  puts "aligning $1 to $2..."
  if ! $zipalign -f -v -p 4 "$1" "$2"; then
    exit 1
  fi
  puts "verifying alignment for $2"
  if ! $zipalign -c -v 4 "$2"; then
    exit 1
  fi
}

sign() {
  apksigner=$(find_build_tool apksigner)
  puts "signing $1..."
  if ! $apksigner sign --ks "$KEYSTORE" --ks-pass env:KSPASS "$1"; then
    exit 1
  fi
  puts "verifying signature for $1"
  if ! $apksigner verify "$1"; then
    exit 1
  fi
}

clone() {
  URL=$1
  DIR=$2
  SHA=$3
  if [ -d "$DIR" ]; then
    (
      cd "$DIR" || exit
      git fetch --tags --prune
    )
  else
    mkdir -p "$DIR"
    git clone "$URL" "$DIR" --recurse-submodules
  fi
  (
    cd "$DIR" || exit
    git reset --hard "$SHA"
    git submodule update --init --recursive
  )
}

download_gradle() {
  if [ -z "$GRADLE_VERSION" ]; then
    DISTRIBUTION=$(grep -e "^distributionUrl=https\\\\://services.gradle.org/" gradle/wrapper/gradle-wrapper.properties)
    GRADLE_VERSION=$(echo "$DISTRIBUTION" | grep -o "[0-9]\+\(\.[0-9]\+\)\+")
  fi
  GRADLE_ZIP_URL=https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip
  GRADLE=$TMP/gradle-$GRADLE_VERSION/bin/gradle

  download "$GRADLE_ZIP_URL.sha256"

  download "$GRADLE_ZIP_URL"

  checksum "$DEST" "$DEST.sha256"

  extract "$DEST"
}

download() {
  URL=$1
  FILENAME=$(basename "$URL")
  DEST=$DOWNLOADS/$FILENAME
  puts "downloading $URL to $DEST"
  if ! wget --continue --quiet "$URL" -O "$DEST"; then
    exit 1
  fi
}

extract() {
  ZIP=$1
  puts "unzipping $ZIP to $TMP..."
  unzip -oq "$ZIP" -d "$TMP"
}

checksum() {
  FILE=$1
  CHECKSUM=$2
  puts "checking $FILE"
  if ! sha256 "$FILE" | diff "$CHECKSUM" -; then
    rm -v "$FILE" "$CHECKSUM"
    exit 1
  fi
}

sha256() {
  sha256sum "$1" | awk '{ printf $1 }'
}
