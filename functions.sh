#!/bin/bash

put() {
  printf "%s" "$1" 1>&2
}

puts() {
  printf "%s\n" "${1:-}" 1>&2
}

green() {
    echo -e "\033[32;1m$1\033[0m"
}

red() {
    echo -e "\033[31;1m$1\033[0m"
}

prebuild() {
  if [ -z "$PREBUILD" ]; then
    return 0
  fi
  puts "prebuild..."
  if ! eval "$PREBUILD"; then
    exit 1
  fi
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
  $ADB -H "${HOST:-localhost}" "$@" 1>&2
}

clone_and_cd() {
  clone "$1" "$2" "$3"
  cd "$2" || exit
}

zipalign() {
  UNSIGNED=$1
  SIGNED=$2
  ZIPALIGN=$(find "$TOOLS" -name zipalign | sort -r | head -n 1)
  puts "aligning $UNSIGNED..."
  if ! $ZIPALIGN -f -v -p 4 "$UNSIGNED" "$SIGNED"; then
    exit 1
  fi
  if ! $ZIPALIGN -c -v 4 "$SIGNED"; then
    exit 1
  fi
}

sign() {
  SIGNED=$1
  APKSIGNER=$(find "$TOOLS" -name apksigner | sort -r | head -n 1)
  puts "signing $SIGNED..."
  if ! $APKSIGNER sign --ks "$KEYSTORE" --ks-pass env:KSPASS "$SIGNED"; then
    exit 1
  fi
  if ! $APKSIGNER verify "$SIGNED"; then
    exit 1
  fi
}

clone() {
  URL=$1
  DIR=$2
  SHA=$3
  git clone "$URL" "$DIR"
  (
    cd "$DIR" || exit
    git checkout "$SHA"
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
  if ! sha256sum "$FILE" | awk '{ printf $1 }' | diff "$CHECKSUM" -; then
    rm -v "$FILE" "$CHECKSUM"
    exit 1
  fi
}
