#!/bin/bash

cd "${0%/*}"

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
TOOLS=$ANDROID_HOME/build-tools
ADB=$ANDROID_HOME/platform-tools/adb
KEYSTORE=$HOME/.android/release.keystore
METADATA=./metadata
IMPLANT=$HOME/.implant
TMP=$IMPLANT/tmp
DOWNLOADS=$IMPLANT/downloads
SRC=$IMPLANT/src
OUT=$IMPLANT/output
LOG=$IMPLANT/build.log
INSTALL=0
DEFAULT_GRADLE_PROPS="org.gradle.jvmargs=-Xmx4096m -XX:MaxPermSize=4096m -XX:+HeapDumpOnOutOfMemoryError"

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
    mkdir -p $OUT_DIR $DOWNLOADS $TMP

    log
    log "***** $PACKAGE $(date) *****"
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
    GIT_SHA=$(get_config git.sha)
    GRADLEPROPS=$(get_config gradle_props "$DEFAULT_GRADLE_PROPS")
    log
}

build_apps() {
    if [ ! -t 0 ] && [ "$#" -eq 0 ]; then
        readarray STDIN_ARGS < /dev/stdin
        set -- ${STDIN_ARGS[@]}
    fi
    for PACKAGE in "$@"; do
        $(build_app)
    done
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

    sed -i 's/.*signingConfig .*//g' $PWD/$PROJECT/build.gradle*

    prebuild

    build

    find $PROJECT -regex '.*\.apk$' -exec cp -v {} $OUT_DIR \; >> $LOG

    if [ ! -f $KEYSTORE ]; then
        puts "Cannot sign APK: $KEYSTORE found"
        return $INSTALL
    fi

    for apk in $OUT_DIR/*.apk; do
        sign_and_install $apk
    done
}

sign_and_install() {
    UNSIGNED=$1
    SIGNED=$(echo $UNSIGNED | sed 's/[-]unsigned//g;s/\.apk$/-signed\.apk/')
    ZIPALIGN=$(find $TOOLS -name zipalign | sort -r | head -n 1)
    APKSIGNER=$(find $TOOLS -name apksigner | sort -r | head -n 1)
    put "aligning $UNSIGNED..."
    $ZIPALIGN -f -v -p 4 $UNSIGNED $SIGNED >> $LOG 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    $ZIPALIGN -c -v 4 $SIGNED >> $LOG 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    puts "OK"
    put "signing $SIGNED..."
    $APKSIGNER sign --ks $KEYSTORE --ks-pass env:KSPASS $SIGNED >> $LOG 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    $APKSIGNER verify $SIGNED >> $LOG 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    puts "OK"
    if [ $INSTALL -eq 1 ]; then
        adb install $SIGNED
    fi
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
    i|install)
        shift
        INSTALL=1
        build_apps "$@"
        ;;
    b|build)
        shift
        build_apps "$@"
        ;;
    l|list)
        apps=()
        for PACKAGE in metadata/*.yml; do
            load_config
            filename=$(basename $PACKAGE)
            apps+=("$NAME - ${filename%.*}")
        done
        IFS=$'\n' sorted=($(sort -f <<<"${apps[*]}")); unset IFS
        printf "%s\n" "${sorted[@]}" | less
        ;;
    init|initialize)
        puts "not implemented"
        # TODO: generate keys
        exit 1
        ;;
    keygen)
        if [ ! -f $OUT/adbkey ] && [ ! -f $OUT/adbkey.pub ]; then
            puts "Generating adbkey and adbkey.pub"
            $ADB start-server >> $LOG 2>&1
            cp -v $HOME/.android/adbkey $HOME/.android/adbkey.pub $OUT
        fi
        if [ ! -f $OUT/debug.keystore ]; then
            puts "Generating $OUT/debug.keystore"
            keytool -genkey -v -keystore $OUT/debug.keystore -storepass android -alias androiddebugkey -keypass android -keyalg RSA -keysize 2048 -validity 10000 -dname "C=US, O=Android, CN=Android Debug" >> $LOG 2>&1
        fi
        if [ ! -f $OUT/release.keystore ]; then
            puts "Generating $OUT/release.keystore (requires 'docker run --interactive --tty')"
            keytool -genkey -v -keystore $OUT/release.keystore -alias implant -keyalg RSA -keysize 2048 -validity 10000
        fi
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
