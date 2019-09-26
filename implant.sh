#!/bin/bash

source /functions.sh

ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ADB=$ANDROID_HOME/platform-tools/adb

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
    LOG=$OUT_DIR/build.log
    SUBDIR=$(get_config subdir app)
    TARGET=$(get_config target debug)
    FLAVOR=$(get_config flavor)
    DEPS=$(get_config deps)
    GIT_URL=$(get_config git.url)
    GIT_SHA=$(get_config git.sha)

    rm -f $OUT_DIR/*.apk
    mkdir -p $OUT_DIR

    printf "\n" >> $LOG
    printf "***** $PACKAGE *****\n" >> $LOG
    printf "TIME: $(date)\n" >> $LOG
    printf "SUBDIR: $SUBDIR\n" >> $LOG
    printf "TARGET: $TARGET\n" >> $LOG
    printf "FLAVOR: $FLAVOR\n" >> $LOG
    printf "DEPS: $DEPS\n" >> $LOG
    printf "URL: $GIT_URL\n" >> $LOG
    printf "SHA: $GIT_SHA\n" >> $LOG
    printf "\n" >> $LOG

    install_deps

    clone_and_patch

    download_gradle

    TASK=assemble$FLAVOR$TARGET
    BUILDDIR=build/
    if [ ! -z $SUBDIR ]; then
        TASK=$SUBDIR:$TASK
        BUILDDIR=$SUBDIR/$BUILDDIR
    fi

    printf "building $TASK..." 1>&2

    /bin/bash -c "/gradle-$GRADLE/bin/gradle --stacktrace $TASK" >> $LOG 2>&1
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
