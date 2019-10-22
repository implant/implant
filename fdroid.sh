#!/bin/bash

make_repo() {
  set -eu # unset variables are errors & non-zero return values exit the whole script

  setup_logging

  if [ ! -d "$TOOLS" ]; then
    "$ANDROID_HOME/tools/bin/sdkmanager" "build-tools;29.0.2"
  fi
  puts "generating fdroid repo"
  url="http://localhost"
  yml="$APKS/index-v1.yml"
  json="$APKS/index-v1.json"
  jar="$APKS/index-v1.jar"
  now="$(date --utc +%s)000"
  sig="$(get_fdroid_sig)"
  yq n repo.name "Implant" >"$yml"
  write repo.timestamp "$now"
  write repo.version 18
  write repo.address "$url"
  write "repo.mirrors[+]" "$url"
  write repo.icon "default-repo-icon.png"
  write repo.description "Implant"
  write requests.install "[]"
  write requests.uninstall "[]"
  readarray -t apks < <(ls "$APKS/"*.apk)
  num_apks="${#apks[@]}"
  for i in "${!apks[@]}"; do
    apk="${apks[$i]}"
    puts "adding ($((i + 1))/$num_apks) $apk"
    package=$(get_apk_package "$apk")
    version=$(get_apk_version_code "$apk")
    updated=$(get_updated_time "$package")
    write "apps[+].name" "$(get_config name "" "$METADATA/$package.yml" 2>/dev/null)"
    write_app suggestedVersionCode "$version"
    write_app license Unknown
    write_app packageName "$package"
    write_app icon ""
    write_app added "$(get_added_time "$package")"
    write_app lastUpdated "$updated"
    write "packages.[$package].[+].apkName" "$(basename "$apk")"
    write_package packageName "$package"
    write_package versionCode "$version"
    write_package versionName "$(get_version_name "$apk")"
    write_package minSdkVersion "$(get_min_sdk "$apk")"
    write_package targetSdkVersion "$(get_target_sdk "$apk")"
    write_package hash "$(sha256 "$apk")"
    write_package hashType "sha256"
    write_package added "$updated"
    write_package sig "$sig"
    write_package size "$(get_size "$apk")"
    # nativecode
    # uses-permission
    # uses-permission-sdk-23
  done
  yq r -j "$yml" >"$json"
  rm -fv "$jar"
  zip -j "$jar" "$json"
  jarsigner -keystore "$KEYSTORE" -storepass:env KSPASS -digestalg SHA1 -sigalg SHA1withRSA "$jar" implant
}

write() {
  yq w -i "$yml" "$1" "$2"
}

write_app() {
  yq w -i "$yml" "apps[$i].$1" "$2"
}

write_package() {
  yq w -i "$yml" "packages.[$package].[0].$1" "$2"
}

get_size() {
  stat --printf="%s" "$1"
}

get_min_sdk() {
  $APKANALYZER manifest min-sdk "$1"
}

get_target_sdk() {
  $APKANALYZER manifest target-sdk "$1"
}

get_version_name() {
  $(find_build_tool aapt) dump badging "$1" | grep versionName | awk '{ print $4 }' | cut -d"'" -f2
}

get_fdroid_sig() {
  keytool -export -keystore "$KEYSTORE" -alias implant -storepass "$KSPASS" 2>/dev/null | xxd -p | tr -d '\n' | md5sum | awk '{ print $1 }'
}

get_apk_package() {
  $APKANALYZER manifest application-id "$1"
}

get_added_time() {
  git log --pretty="%ct000" "$METADATA/$1.yml" | tail -n 1
}

get_updated_time() {
  git log -1 --pretty="%ct000" "$METADATA/$1.yml"
}
