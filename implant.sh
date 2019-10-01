#!/bin/bash

cd "${0%/*}"

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ADB=$ANDROID_HOME/platform-tools/adb
METADATA=./metadata
IMPLANT=$HOME/.implant
TMP=$IMPLANT/tmp
DOWNLOADS=$IMPLANT/downloads
SRC=$IMPLANT/src
OUT=$IMPLANT/output

source ./functions.sh

load_config() {
    if [ -f $METADATA/$PACKAGE.yml ]; then
        CONFIG=$METADATA/$PACKAGE.yml
    elif [ -f $METADATA/$PACKAGE ]; then
        CONFIG=$METADATA/$PACKAGE
    elif [ -f $PACKAGE ]; then
        CONFIG=$PACKAGE
    else
        puts "Invalid package: $PACKAGE"
        return 1
    fi

    yq r $CONFIG > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        puts "Invalid yml file: $CONFIG"
        return 1
    fi

    OUT_DIR=$OUT/$PACKAGE
    LOG=$OUT_DIR/build.log
    mkdir -p $OUT_DIR $DOWNLOADS $TMP

    log
    log "***** $PACKAGE $(date) *****"
    NAME=$(get_config name)
    PROJECT=$(get_config project app)
    TARGET=$(get_config target debug)
    FLAVOR=$(get_config flavor)
    NDK=$(get_config ndk)
    PREBUILD=$(get_config prebuild)
    BUILD=$(get_config build)
    DEPS=$(get_config deps)
    GRADLE_VERSION=$(get_config gradle)
    GIT_URL=$(get_config git.url)
    GIT_SHA=$(get_config git.sha)
    GRADLEPROPS=$(get_config gradle_props)
    log
}

build_app() {
    load_config

    if [ $? -ne 0 ]; then
        return 1
    fi

    rm -f $OUT_DIR/*.apk

    setup_ndk

    install_deps

    clone_and_cd $GIT_URL $SRC/$PACKAGE $GIT_SHA

    download_gradle

    setup_gradle_properties

    prebuild

    build

    find $PROJECT -regex '^.*\.apk$' -exec cp -v {} $OUT_DIR \; >> $LOG
}

install_app() {
    for apk in $OUT_DIR/*.apk; do
        install_apk $apk
    done
}

if [ ! -t 0 ]; then
    readarray STDIN_ARGS < /dev/stdin
    set -- $@ ${STDIN_ARGS[@]}
fi

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
    i|install)
        shift
        for PACKAGE in "$@"; do
            $(build_app)
            $(install_app)
        done
        ;;
    b|build)
        shift
        for PACKAGE in "$@"; do
            $(build_app)
        done
        ;;
    l|list)
        apps=()
        for PACKAGE in metadata/*.yml; do
            load_config
            filename=$(basename $PACKAGE)
            apps+=("$NAME (${filename%.*})")
        done
        IFS=$'\n' sorted=($(sort -f <<<"${apps[*]}")); unset IFS
        printf "%s\n" "${sorted[@]}" | less
        ;;
    init|initialize)
        puts "not implemented"
        # TODO: generate keys
        exit 1
        ;;
    -h|--help|h|help)
        puts "not implemented"
        # TODO: print usage
        exit 1
        ;;
    *)
        puts "unknown command: $1"
        exit 1
esac
