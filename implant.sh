#!/bin/bash
set -o errexit -o pipefail -o noclobber -o nounset

ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ADB=$ANDROID_HOME/platform-tools/adb
IMPLANT=$HOME/.implant
DOWNLOADS=$IMPLANT/downloads
METADATA=$IMPLANT/metadata
SRC=$IMPLANT/src
OUT=$IMPLANT/output

source $IMPLANT/functions.sh

build_app() {
    if [ -f $METADATA/$PACKAGE.yml ]; then
        CONFIG=$METADATA/$PACKAGE.yml
    elif [ -f $METADATA/$PACKAGE ]; then
        CONFIG=$METADATA/$PACKAGE
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

    rm -f $OUT_DIR/*.apk
    mkdir -p $OUT_DIR $DOWNLOADS

    LOG=$OUT_DIR/build.log
    log
    log "***** $PACKAGE $(date) *****"
    PROJECT=$(get_config project app)
    TARGET=$(get_config target debug)
    FLAVOR=$(get_config flavor)
    NDK=$(get_config ndk)
    PREBUILD=$(get_config prebuild)
    DEPS=$(get_config deps)
    GIT_URL=$(get_config git.url)
    GIT_SHA=$(get_config git.sha)
    GRADLEPROPS=$(get_config gradle_props)
    log

    setup_ndk

    install_deps

    clone_and_cd $GIT_URL $GIT_SHA $SRC/$PACKAGE

    download_gradle

    setup_gradle_properties

    prebuild

    TASK=assemble$FLAVOR$TARGET
    BUILDDIR=build/
    if [ ! -z $PROJECT ]; then
        TASK=$PROJECT:$TASK
        BUILDDIR=$PROJECT/$BUILDDIR
    fi

    put "building $TASK..."

    /bin/bash -c "$GRADLE --stacktrace $TASK" >> $LOG 2>&1
    if [ $? -eq 0 ]; then
        puts "OK"
    else
        puts "FAILED"
        return 1
    fi

    find $PROJECT -regex '^.*\.apk$' -exec cp -v {} $OUT_DIR \; >> $LOG
}

install_app() {
    for apk in $OUT_DIR/*.apk; do
        install_apk $apk
    done
}

if [ "$#" -eq 0 ]; then
    puts "missing arguments"
    # TODO: print usage
    exit 1
fi

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
        puts "not implemented"
        # TODO: list apps
        exit 1
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
