#!/bin/bash

set -u # unset variables are errors

cd "${0%/*}"

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
TOOLS=$ANDROID_HOME/build-tools
ADB=$ANDROID_HOME/platform-tools/adb
KEYSTORE=$HOME/.android/release.keystore
METADATA=$PWD/metadata
IMPLANT=$HOME/.implant
TMP=$IMPLANT/tmp
DOWNLOADS=$IMPLANT/downloads
SRC=$IMPLANT/src
OUT=$IMPLANT/output
LOG=$IMPLANT/build.log
VERBOSE=${VERBOSE:-0}
INSTALL=0
REINSTALL=0
DEFAULT_GRADLE_PROPS="org.gradle.jvmargs=-Xmx2048m -XX:MaxPermSize=2048m -XX:+HeapDumpOnOutOfMemoryError"

source ./functions.sh

load_config() {
  PACKAGE=$(get_package "$PACKAGE")
  CONFIG="$METADATA/$PACKAGE.yml"

  if [ ! -f "$CONFIG" ]; then
    puts "Invalid package: $PACKAGE"
    exit 1
  fi

  if ! yq r "$CONFIG" >/dev/null 2>&1; then
    puts "Invalid yml file: $CONFIG"
    exit 1
  fi

  puts
  puts "***** $PACKAGE $(date) *****"
  NAME=$(get_config name)
  PROJECT=$(get_config project app)
  TARGET=$(get_config target release)
  FLAVOR=$(get_config flavor)
  NDK=$(get_config ndk)
  PREBUILD=$(get_config prebuild)
  BUILD=$(get_config build)
  DEPS=$(get_config deps)
  GRADLE_VERSION=$(get_config gradle)
  GIT_URL=$(get_config git.url)
  if [ -z "${GIT_SHA:-}" ]; then
    GIT_SHA=$(get_config git.sha)
  else
    puts "git.sha=$GIT_SHA [override]"
  fi
  GIT_TAGS=$(get_config git.tags)
  VERSION=$(get_config version)
  GRADLEPROPS=$(get_config gradle_props "$DEFAULT_GRADLE_PROPS")
  puts
}

update_apps() {
  if [ "$#" -eq 0 ]; then
    APPS=(metadata/*.yml)
    set -- "${APPS[@]}"
  fi
  for PACKAGE in "$@"; do
    PACKAGE=$(get_package "$PACKAGE")
    put "updating $PACKAGE..."
    if (update_app); then
      green "OK"
    else
      red "ERROR"
    fi
  done
}

find_apk() {
  readarray -t apks < <(find "$1" -name "$2")
  num_apks="${#apks[@]}"
  if [ ! "$num_apks" -eq 1 ]; then
    puts "wanted 1 apk, found $num_apks"
    exit 1
  fi
  apk="${apks[0]}"
}

update_app() {
  set -eu # unset variables are errors & non-zero return values exit the whole script

  setup_logging

  load_config

  clone_and_cd "$GIT_URL" "$SRC/$PACKAGE" "$GIT_SHA"

  UPDATE_SHA=$(get_latest_tag)
  if [ -n "$VERSION" ] && [ "$UPDATE_SHA" == "$GIT_SHA" ]; then
    puts "up to date [$GIT_SHA]"
    exit 0
  fi

  GIT_SHA=$UPDATE_SHA
  puts "updating $PACKAGE to $GIT_SHA"
  if (build_app); then
    yq w -i "$CONFIG" git.sha "\"$GIT_SHA\""
    find_apk "$OUT" "$PACKAGE-*.apk"
    APK_VERSION=$(get_apk_version_code "$apk")
    if [ -z "$APK_VERSION" ]; then
      puts "Error parsing apk version"
      exit 1
    fi
    if [ "$APK_VERSION" == "1" ]; then
      APK_VERSION=$(("$VERSION" + 1))
    fi
    yq w -i "$CONFIG" version "\"$APK_VERSION\""
  else
    exit 1
  fi
}

build_apps() {
  if [ ! -t 0 ] && [ "$#" -eq 0 ]; then
    readarray STDIN_ARGS </dev/stdin
    set -- "${STDIN_ARGS[@]}"
  fi
  for PACKAGE in "$@"; do
    PACKAGE=$(get_package "$PACKAGE")
    CONFIG="$METADATA/$PACKAGE.yml"
    VERSION=$(get_config version 2>/dev/null)
    if [ "$REINSTALL" -eq 0 ] && up_to_date "$PACKAGE"; then
      puts "$PACKAGE up to date"
      continue
    fi
    put "building $PACKAGE..."
    if (build_app); then
      green "OK"
    else
      red "FAILED"
      continue
    fi

    if [ "$INSTALL" -eq 1 ]; then
      adb install "$OUT/$PACKAGE-$VERSION.apk" 1>&2
    fi
  done
}

build_app() {
  set -eu # unset variables are errors & non-zero return values exit the whole script

  setup_logging

  load_config

  mkdir -p "$DOWNLOADS" "$TMP"

  setup_ndk

  install_deps

  clone_and_cd "$GIT_URL" "$SRC/$PACKAGE" "$GIT_SHA"

  find "./$PROJECT" -regex '.*\.apk$' -exec rm -v {} \;

  download_gradle

  setup_gradle_properties

  sed -i \
      -e "s/.*signingConfig .*//g" \
      -e "s/apply plugin: 'com.google.gms.google-services'//g" \
      -e "s/apply plugin: 'io.fabric'//g" \
      "$PWD/$PROJECT"/build.gradle*

  prebuild

  build

  find_apk "./$PROJECT" "*.apk"

  if [ ! -f "$KEYSTORE" ]; then
    puts "Cannot sign APK: $KEYSTORE found"
    return "$INSTALL"
  fi

  rm -fv "$OUT/$PACKAGE-"*.apk

  VERSION=$(get_apk_version_code "$apk")
  target="$OUT/$PACKAGE-$VERSION.apk"
  zipalign "$apk" "$target" && sign "$target"
}

if [ "$#" -eq 0 ]; then
  puts "missing arguments"
  # TODO: print usage
  exit 1
fi

type yq >/dev/null 2>&1 || {
  # TODO: download automatically
  echo >&2 "yq must be in your PATH, please download from https://github.com/mikefarah/yq/releases"
  exit 1
}

case $1 in
  adb)
    shift
    adb "$@"
    ;;
  i | install)
    shift
    INSTALL=1
    if [ "${1:-}" == "--reinstall" ]; then
      shift
      REINSTALL=1
    fi
    build_apps "$@"
    ;;
  b | build)
    shift
    build_apps "$@"
    ;;
  u | update)
    shift
    INSTALL=1
    get_installed_packages
    build_apps "${PACKAGES[@]}"
    ;;
  l | list)
    shift
    apps=()
    if [ -z "${1:-}" ]; then
      PACKAGES=(metadata/*.yml)
    elif [ "$1" == "--installed" ]; then
      get_installed_packages
    else
      puts "invalid option $1"
      exit 1
    fi
    for PACKAGE in "${PACKAGES[@]}"; do
      PACKAGE=$(get_package "$PACKAGE")
      CONFIG="$METADATA/$PACKAGE.yml"
      NAME=$(get_config name 2>/dev/null)
      apps+=("$NAME - $PACKAGE")
    done
    IFS=$'\n' sorted=($(sort -f <<<"${apps[*]}"))
    unset IFS
    printf "%s\n" "${sorted[@]}" | less
    ;;
  keygen)
    if [ ! -f "$OUT/adbkey" ] && [ ! -f "$OUT/adbkey.pub" ]; then
      puts "Generating adbkey and adbkey.pub"
      $ADB start-server >>"$LOG" 2>&1
      cp -v "$HOME/.android/adbkey" "$HOME/.android/adbkey.pub" "$OUT"
    fi
    if [ ! -f "$OUT/release.keystore" ]; then
      puts "Generating $OUT/release.keystore (requires 'docker run --interactive --tty')"
      keytool -genkey -v -keystore "$OUT/release.keystore" -alias implant -keyalg RSA -keysize 2048 -validity 10000
    fi
    ;;
  update_apps)
    shift
    update_apps "$@"
    ;;
  -h | --help | h | help)
    puts "not implemented"
    # TODO: print usage
    exit 1
    ;;
  *)
    puts "unknown command: $1"
    exit 1
    ;;
esac
