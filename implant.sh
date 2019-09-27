#!/bin/bash

source /functions.sh

ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ADB=$ANDROID_HOME/platform-tools/adb
DOWNLOADS=$HOME/.implant/downloads

build() {
    METADATA=/metadata/$PACKAGE

    if [ -d $METADATA ]; then
        CONFIG=$METADATA/config.yml
    elif [ -f $METADATA.yml ]; then
        CONFIG=$METADATA.yml
    elif [ -f $METADATA ]; then
        CONFIG=$METADATA
    else
        puts "Invalid package: $PACKAGE"
        return 1
    fi

    yq r $CONFIG > /dev/null 2>&1
    if [ $? -ne 0 ]; then
        puts "Invalid yml file: $CONFIG"
        return 1
    fi

    OUT_DIR=/output/$PACKAGE

    rm -f $OUT_DIR/*.apk
    mkdir -p $OUT_DIR $DOWNLOADS

    LOG=$OUT_DIR/build.log
    log
    log "***** $PACKAGE $(date) *****"
    SUBDIR=$(get_config subdir app)
    TARGET=$(get_config target debug)
    FLAVOR=$(get_config flavor)
    NDK=$(get_config ndk)
    PREBUILD=$(get_config prebuild)
    DEPS=$(get_config deps)
    GIT_URL=$(get_config git.url)
    GIT_SHA=$(get_config git.sha)
    GRADLEPROPS=$(get_config gradle_props)
    log

    setup_gradle_properties

    setup_ndk

    install_deps

    clone_and_patch

    download_gradle

    prebuild

    TASK=assemble$FLAVOR$TARGET
    BUILDDIR=build/
    if [ ! -z $SUBDIR ]; then
        TASK=$SUBDIR:$TASK
        BUILDDIR=$SUBDIR/$BUILDDIR
    fi

    put "building $TASK..."

    /bin/bash -c "$GRADLE --stacktrace $TASK" >> $LOG 2>&1
    if [ $? -eq 0 ]; then
        puts "OK"
    else
        puts "FAILED"
        return 1
    fi

    find $SUBDIR -regex '^.*\.apk$' -exec cp -v {} $OUT_DIR \; >> $LOG

    for apk in $OUT_DIR/*.apk; do
        install_apk $apk
    done
}

for PACKAGE in "$@"; do
    $(build)
done
