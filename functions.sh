#!/bin/bash

log() {
    printf "${1:-}\n" >> $LOG
}

put() {
    printf "$1" 1>&2
}

puts() {
    printf "$1\n" 1>&2
}

prebuild() {
    if [ -z "$PREBUILD" ]; then
        return 0
    fi
    put "prebuild..."
    eval "$PREBUILD" >> $LOG 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        exit 1
    fi
    puts "OK"
}

setup_gradle_properties() {
    if [ -z "$GRADLEPROPS" ]; then
        return 0
    fi
    put "creating gradle.properties..."
    echo $GRADLEPROPS >> gradle.properties
    puts "OK"
}

setup_ndk() {
    if [ -z "$NDK" ]; then
        return 0
    fi
    NDK_DIR=android-ndk-$NDK
    NDK_ZIP=$NDK_DIR-linux-x86_64.zip
    NDK_URL=https://dl.google.com/android/repository/$NDK_ZIP &&
    export ANDROID_NDK_HOME=/$NDK_DIR
    put "downloading ndk..."
    wget -o /dev/null -c -O $DOWNLOADS/$NDK_ZIP $NDK_URL
    if [ $? -ne 0 ]; then
        puts "FAILED"
        exit 1
    fi
    puts "OK"
    put "unzipping ndk..."
    unzip -oq $DOWNLOADS/$NDK_ZIP -d /
    if [ $? -ne 0 ]; then
        puts "FAILED"
        exit 1
    fi
    puts "OK"
}

get_config() {
    PROP=$1
    DEFAULT=${2:-}
    value=`yq r $CONFIG $PROP`
    if [ "$value" != null ]; then
        log "$1=$value"
        echo $value
    else
        log "$1=$DEFAULT [default]"
        echo $DEFAULT
    fi
}

install_deps() {
    if [ -z "$DEPS" ]; then
        return 0
    fi
    put "installing dependencies..."
    apt-get update >> $LOG 2>&1
    apt-get install -y $DEPS >> $LOG 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    puts "OK"
}

install_apk() {
    APK=$1
    HOST=$(getent hosts host.docker.internal | awk '{ printf $1 }')
    put "installing $APK..."
    $ADB -H ${HOST:-localhost} install $APK >> $LOG
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    puts "OK"
}

clone() {
    puts "cloning $GIT_URL"
    git clone --recurse-submodules $GIT_URL $PACKAGE >> $LOG 2>&1
    cd $PACKAGE
    puts "resetting HEAD to $GIT_SHA"
    git reset --hard $GIT_SHA >> $LOG 2>&1
    git submodule update >> $LOG 2>&1
}

download_gradle() {
    DISTRIBUTION=$(grep -e "^distributionUrl=https\\\\://services.gradle.org/" gradle/wrapper/gradle-wrapper.properties)
    GRADLE_VERSION=$(echo $DISTRIBUTION | grep -o "[0-9]\+\(\.[0-9]\+\)\+")
    GRADLE_ZIP=$DOWNLOADS/gradle-$GRADLE_VERSION-bin.zip
    GRADLE_SHA=$GRADLE_ZIP.sha256
    GRADLE_ZIP_URL=https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip
    GRADLE_SHA_URL=$GRADLE_ZIP_URL.sha256
    GRADLE=/gradle-$GRADLE_VERSION/bin/gradle

    if [ ! -f $GRADLE_SHA ]; then
        puts "downloading gradle-$GRADLE_VERSION checksum"
        wget --quiet $GRADLE_SHA_URL -O $GRADLE_SHA
    fi

    if [ ! -f $GRADLE_ZIP ]; then
        puts "downloading gradle-$GRADLE_VERSION"
        wget --quiet $GRADLE_ZIP_URL -O $GRADLE_ZIP
    fi

    sha256sum $GRADLE_ZIP | awk '{ printf $1 }' | diff $GRADLE_SHA -

    if [ $? != 0 ]; then
        rm $GRADLE_ZIP $GRADLE_SHA
        puts "gradle download failed"
        exit 1;
    fi

    puts "unzipping gradle-$GRADLE_VERSION"

    unzip -oq $GRADLE_ZIP -d /
}

