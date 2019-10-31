#!/bin/bash

set -u # unset variables are errors

cd_implant() {
  cd "${0%/*}"
}

cd_implant

source ./env.sh
source ./functions.sh
source ./fdroid.sh

load_config() {
  PACKAGE=$(get_package "$PACKAGE")
  CONFIG="$METADATA/$PACKAGE.yml"

  if [ ! -f "$CONFIG" ]; then
    puts "Invalid package: $PACKAGE"
    exit 1
  fi

  validate_config "$CONFIG"

  puts
  puts "***** $PACKAGE $(date) *****"
  NAME=$(get_config name)
  PROJECT=$(get_config project app)
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
  GRADLE_OPTS=$(get_config gradle_opts)
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
      print_log_tail
    fi
  done
}

find_apk() {
  readarray -t apks < <(find "$1" -name "$2")
  num_apks="${#apks[@]}"
  if [ ! "$num_apks" -eq 1 ]; then
    puts "wanted 1 apk, found $num_apks:"
    printf "%s\n" "${apks[@]}"
    exit 1
  fi
  apk="${apks[0]}"
}

update_app() {
  set -eu # unset variables are errors & non-zero return values exit the whole script

  setup_logging

  load_config

  clone_and_cd "$GIT_URL" "$SRC/$PACKAGE" "$GIT_SHA" 1

  UPDATE_SHA=$(get_latest_tag)
  if [ -n "$VERSION" ] && [ "$UPDATE_SHA" == "$GIT_SHA" ]; then
    puts "up to date [$GIT_SHA]"
    exit 0
  fi

  GIT_SHA=$UPDATE_SHA
  puts "updating $PACKAGE to $GIT_SHA"
  if (build_app); then
    find_apk "$APKS" "$PACKAGE-*.apk"
    APK_VERSION=$(get_apk_version_code "$apk")
    if [ -z "$APK_VERSION" ]; then
      puts "Error parsing apk version"
      exit 1
    fi
    if [ "$APK_VERSION" == "1" ]; then
      APK_VERSION=$(("$VERSION" + 1))
    fi

    yq w -i "$CONFIG" git.sha "\"$GIT_SHA\""
    yq w -i "$CONFIG" version "\"$APK_VERSION\""

    validate_config "$CONFIG"

    cd_implant
    git add "$CONFIG"
    TAG=$(cd "$SRC/$PACKAGE" && git describe --contains "$GIT_SHA")
    TAG=${TAG%^0}
    git -c "user.name=$GIT_USER" -c "user.email=$GIT_EMAIL" commit -m "$NAME ${TAG:-$APK_VERSION}"
    git pull --rebase https://github.com/abaker/implant.git master
    if [ "$GIT_PUSH" -eq 1 ]; then
      git push "https://$(url_encode "$GIT_USER"):$(url_encode "$GIT_PASS")@github.com/abaker/implant.git"
    fi
  else
    exit 1
  fi
}

build_apps() {
  if [ ! -d "$OUT" ]; then
    yellow "WARNING: $OUT not mounted, see https://github.com/abaker/implant/wiki/Create-an-implant-alias"
  fi

  if [ ! -t 0 ] && [ "$#" -eq 0 ]; then
    readarray STDIN_ARGS </dev/stdin
    set -- "${STDIN_ARGS[@]}"
  fi
  for PACKAGE in "$@"; do
    PACKAGE=$(get_package "$PACKAGE")
    VERSION=$(get_config version "" "$METADATA/$PACKAGE.yml" 2>/dev/null)
    if up_to_date "$PACKAGE" "$VERSION"; then
      puts "$PACKAGE up to date"
      continue
    fi
    put "building $PACKAGE..."
    if (build_app); then
      green "OK"
    else
      red "FAILED"
      print_log_tail
      continue
    fi

    if [ "$INSTALL" -eq 1 ]; then
      adb install "$APKS/$PACKAGE-$VERSION.apk" 1>&2
    fi
  done
}

build_app() {
  set -eu # unset variables are errors & non-zero return values exit the whole script

  if ! check_key; then
    exit 1
  fi

  setup_logging

  load_config

  mkdir -p "$APKS" "$DOWNLOADS" "$TMP"

  setup_ndk

  install_deps

  clone_and_cd "$GIT_URL" "$SRC/$PACKAGE" "$GIT_SHA"

  cd "$(get_subdir "$PROJECT")"
  PROJECT="$(get_project "$PROJECT")"

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

  if [ -z "$(get_version_name "$apk")" ]; then
    puts "Missing version name"
    exit 1
  fi

  rm -fv "$APKS/$PACKAGE-"*.apk

  VERSION=$(get_apk_version_code "$apk")
  target="$APKS/$PACKAGE-$VERSION.apk"
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
    build_apps "$@"
    ;;
  b | build)
    shift
    build_apps "$@"
    ;;
  fdroid)
    shift
    if [ "${1:-}" == "--serve" ]; then
      shift
      SERVE=1
    fi
    if [ "$#" -eq 0 ]; then
      APPS=(metadata/*.yml)
      set -- "${APPS[@]}"
    fi
    build_apps "$@"
    put "generating fdroid index..."
    if (make_repo); then
      green "OK"
    else
      red "FAILED"
      exit 1
    fi
    if [ "$SERVE" -eq 1 ]; then
      puts "starting web server"
      setup_logging
      cd "$APKS"
      python -m SimpleHTTPServer 80
    fi
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
      NAME=$(get_config name "" "$METADATA/$PACKAGE.yml" 2>/dev/null)
      apps+=("$NAME - $PACKAGE")
    done
    IFS=$'\n' sorted=($(sort -f <<<"${apps[*]}"))
    unset IFS
    printf "%s\n" "${sorted[@]}" | less
    ;;
  passwd)
    passwd
    ;;
  update_apps)
    shift
    if [ "${1:-}" == "--push" ]; then
      if [ -z "${GIT_PASS:-}" ]; then
        puts "Must provide GIT_PASS"
        exit 1
      fi
      shift
      GIT_PUSH=1
    fi
    update_apps "$@"
    ;;
  test)
    ./test_functions.sh && ./test_fdroid.sh
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
