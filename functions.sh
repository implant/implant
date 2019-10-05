#!/bin/bash

log() {
    printf "%s\n" "${1:-}" >> "$LOG"
}

put() {
    printf "%s" "$1" 1>&2
}

puts() {
    printf "%s\n" "$1" 1>&2
}

prebuild() {
    if [ -z "$PREBUILD" ]; then
        return 0
    fi
    put "prebuild..."
    eval "$PREBUILD" >> "$LOG" 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        exit 1
    fi
    puts "OK"
}

build() {
    put "building $PACKAGE..."
    if [ -z "$BUILD" ]; then
        TASK=assemble$FLAVOR$TARGET
        if [ ! -z "$PROJECT" ]; then
            TASK=$PROJECT:$TASK
        fi

        /bin/bash -c "$GRADLE --stacktrace $TASK" >> "$LOG" 2>&1
    else
        eval "$BUILD" >> "$LOG" 2>&1
    fi
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
    echo "" >> gradle.properties
    echo "$GRADLEPROPS" >> gradle.properties
    puts "OK"
}

setup_ndk() {
    if [ -z "$NDK" ]; then
        return 0
    fi
    NDK_DIR=android-ndk-$NDK
    NDK_ZIP=$NDK_DIR-linux-x86_64.zip
    NDK_URL=https://dl.google.com/android/repository/$NDK_ZIP &&
    export ANDROID_NDK_HOME=$TMP/$NDK_DIR
    put "downloading ndk..."
    wget -o /dev/null -c -O "$DOWNLOADS/$NDK_ZIP" "$NDK_URL"
    if [ $? -ne 0 ]; then
        puts "FAILED"
        exit 1
    fi
    puts "OK"
    put "unzipping ndk..."
    unzip -oq "$DOWNLOADS/$NDK_ZIP" -d "$TMP/"
    if [ $? -ne 0 ]; then
        puts "FAILED"
        exit 1
    fi
    puts "OK"
}

get_config() {
    PROP=$1
    DEFAULT=${2:-}
    value=$(yq r "$CONFIG" "$PROP")
    if [ "$value" != null ]; then
        log "$1=$value"
        echo "$value"
    else
        log "$1=$DEFAULT [default]"
        echo "$DEFAULT"
    fi
}

install_deps() {
    if [ -z "$DEPS" ]; then
        return 0
    fi
    put "installing dependencies..."
    # TODO running in container should not need sudo here
    # shellcheck disable=SC2024
    sudo apt-get update >> "$LOG" 2>&1
    # shellcheck disable=SC2024
    sudo apt-get install --no-install-suggests --no-install-recommends -y "$DEPS" >> "$LOG" 2>&1
    if [ $? -ne 0 ]; then
        puts "FAILED"
        return 1
    fi
    puts "OK"
}

adb() {
    HOST=$(getent hosts host.docker.internal | awk '{ printf $1 }')
    $ADB -H "${HOST:-localhost}" "$@" 1>&2
}

clone_and_cd() {
    clone "$1" "$2" "$3"
    cd "$2" || exit
}

clone() {
    URL=$1
    DIR=$2
    SHA=$3
    puts "cloning $URL@$SHA"
    git clone "$URL" "$DIR" >> "$LOG" 2>&1
    (cd "$DIR" || exit; git checkout "$SHA"; git submodule update --init --recursive) >> "$LOG" 2>&1
}

download_gradle() {
    if [ -z "$GRADLE_VERSION" ]; then
        DISTRIBUTION=$(grep -e "^distributionUrl=https\\\\://services.gradle.org/" gradle/wrapper/gradle-wrapper.properties)
        GRADLE_VERSION=$(echo "$DISTRIBUTION" | grep -o "[0-9]\+\(\.[0-9]\+\)\+")
    fi
    GRADLE_ZIP=$DOWNLOADS/gradle-$GRADLE_VERSION-bin.zip
    GRADLE_SHA=$GRADLE_ZIP.sha256
    GRADLE_ZIP_URL=https://services.gradle.org/distributions/gradle-$GRADLE_VERSION-bin.zip
    GRADLE_SHA_URL=$GRADLE_ZIP_URL.sha256
    GRADLE=$TMP/gradle-$GRADLE_VERSION/bin/gradle

    if [ ! -f "$GRADLE_SHA" ]; then
        puts "downloading gradle-$GRADLE_VERSION checksum"
        wget --quiet "$GRADLE_SHA_URL" -O "$GRADLE_SHA"
    fi

    if [ ! -f "$GRADLE_ZIP" ]; then
        puts "downloading gradle-$GRADLE_VERSION"
        wget --quiet "$GRADLE_ZIP_URL" -O "$GRADLE_ZIP"
    fi

    sha256sum "$GRADLE_ZIP" | awk '{ printf $1 }' | diff "$GRADLE_SHA" -

    if [ $? != 0 ]; then
        rm "$GRADLE_ZIP" "$GRADLE_SHA"
        puts "gradle download failed"
        exit 1;
    fi

    puts "unzipping gradle-$GRADLE_VERSION"

    unzip -oq "$GRADLE_ZIP" -d "$TMP/"
}

