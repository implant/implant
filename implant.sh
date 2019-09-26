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
    else
        printf "Invalid package: $PACKAGE\n" 1>&2
        return 1
    fi

    OUT_DIR=/output/$PACKAGE

    rm -f $OUT_DIR/*.apk
    mkdir -p $OUT_DIR $DOWNLOADS

    LOG=$OUT_DIR/build.log
    printf "\n" >> $LOG
    printf "***** $PACKAGE *****\n" >> $LOG
    printf "TIME: $(date)\n" >> $LOG
    SUBDIR=$(get_config subdir app)
    printf "SUBDIR: $SUBDIR\n" >> $LOG
    TARGET=$(get_config target debug)
    printf "TARGET: $TARGET\n" >> $LOG
    FLAVOR=$(get_config flavor)
    printf "FLAVOR: $FLAVOR\n" >> $LOG
    NDK=$(get_config ndk)
    printf "NDK: $NDK\n" >> $LOG
    PREBUILD=$(get_config prebuild)
    printf "PREBUILD: $PREBUILD\n" >> $LOG
    DEPS=$(get_config deps)
    printf "DEPS: $DEPS\n" >> $LOG
    GIT_URL=$(get_config git.url)
    printf "URL: $GIT_URL\n" >> $LOG
    GIT_SHA=$(get_config git.sha)
    printf "SHA: $GIT_SHA\n" >> $LOG
    GRADLEPROPS=$(get_config gradle_props)
    printf "GRADLEPROPS: $GRADLEPROPS\n" >> $LOG
    printf "\n" >> $LOG

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

    printf "building $TASK..." 1>&2

    /bin/bash -c "$GRADLE --stacktrace $TASK" >> $LOG 2>&1
    if [ $? -eq 0 ]; then
        printf "OK\n" 1>&2
    else
        printf "FAILED\n" 1>&2
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
