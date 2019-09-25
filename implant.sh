#!/bin/bash

source /functions.sh

ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
ADB=$ANDROID_HOME/platform-tools/adb

build() {
    METADATA=/metadata/$PACKAGE

    if [ -d $METADATA ]; then
        source $METADATA/env
    elif [ -f $METADATA ]; then
        source $METADATA
    else
        printf "Invalid package: $PACKAGE\n" 1>&2
        return 1
    fi

    printf "\n\n***** $PACKAGE *****\n\n" 1>&2

    OUT_DIR=/output/$PACKAGE
    LOG=$OUT_DIR/build.log
    SUBDIR=${SUBDIR:-app}
    TARGET=${TARGET:-Debug}

    rm -f $OUT_DIR/*.apk
    mkdir -p $OUT_DIR

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
