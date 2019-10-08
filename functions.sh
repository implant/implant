#!/bin/bash

put() {
    printf "%s" "$1" 1>&2
}

puts() {
    printf "%s\n" "${1:-}" 1>&2
}

prebuild() {
    if [ -z "$PREBUILD" ]; then
        return 0
    fi
    puts "prebuild..."
    if ! eval "$PREBUILD"; then
        exit 1
    fi
}

build() {
    puts "building $PACKAGE..."
    if [ -z "$BUILD" ]; then
        TASK=assemble$FLAVOR$TARGET
        if [ -n "$PROJECT" ]; then
            TASK=$PROJECT:$TASK
        fi

        /bin/bash -c "$GRADLE --stacktrace $TASK"
    else
        eval "$BUILD"
    fi
    # shellcheck disable=SC2181
    if [ $? -ne 0 ]; then
        exit 1
    fi
}

setup_gradle_properties() {
    if [ -z "$GRADLEPROPS" ]; then
        return 0
    fi
    puts "creating gradle.properties..."
    echo "" >> gradle.properties
    echo "$GRADLEPROPS" >> gradle.properties
}

setup_ndk() {
    if [ -z "$NDK" ]; then
        return 0
    fi
    NDK_DIR=android-ndk-$NDK
    NDK_FILE=$NDK_DIR-linux-x86_64.zip
    NDK_URL=https://dl.google.com/android/repository/$NDK_FILE
    NDK_ZIP=$DOWNLOADS/$NDK_FILE
    export ANDROID_NDK_HOME=$TMP/$NDK_DIR
    puts "downloading $NDK_URL to $NDK_ZIP..."
    if ! wget --quiet -c -O "$NDK_ZIP" "$NDK_URL"; then
        exit 1
    fi
    puts "unzipping $NDK_ZIP to $TMP..."
    if ! unzip -oq "$NDK_ZIP" -d "$TMP/"; then
        exit 1
    fi
}

get_config() {
    PROP=$1
    DEFAULT=${2:-}
    value=$(yq r "$CONFIG" "$PROP")
    if [ "$value" != null ]; then
        puts "$1=$value"
        echo "$value"
    else
        puts "$1=$DEFAULT [default]"
        echo "$DEFAULT"
    fi
}

install_deps() {
    if [ -z "$DEPS" ]; then
        return 0
    fi
    puts "installing dependencies..."
    # running sudo for use outside of a container
    sudo apt-get update
    # shellcheck disable=SC2086
    if ! sudo apt-get install --no-install-suggests --no-install-recommends -y $DEPS; then
        exit 1
    fi
}

adb() {
    HOST=$(getent hosts host.docker.internal | awk '{ printf $1 }')
    $ADB -H "${HOST:-localhost}" "$@" 1>&2
}

clone_and_cd() {
    clone "$1" "$2" "$3"
    cd "$2" || exit
}

zipalign() {
    UNSIGNED=$1
    SIGNED=$2
    ZIPALIGN=$(find "$TOOLS" -name zipalign | sort -r | head -n 1)
    puts "aligning $UNSIGNED..."
    if ! $ZIPALIGN -f -v -p 4 "$UNSIGNED" "$SIGNED"; then
        exit 1
    fi
    if ! $ZIPALIGN -c -v 4 "$SIGNED"; then
        exit 1
    fi
}

sign() {
    SIGNED=$1
    APKSIGNER=$(find "$TOOLS" -name apksigner | sort -r | head -n 1)
    puts "signing $SIGNED..."
    if ! $APKSIGNER sign --ks "$KEYSTORE" --ks-pass env:KSPASS "$SIGNED"; then
        exit 1
    fi
    if ! $APKSIGNER verify "$SIGNED"; then
        exit 1
    fi
}

clone() {
    URL=$1
    DIR=$2
    SHA=$3
    git clone "$URL" "$DIR"
    (cd "$DIR" || exit; git checkout "$SHA"; git submodule update --init --recursive)
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

    if ! sha256sum "$GRADLE_ZIP" | awk '{ printf $1 }' | diff "$GRADLE_SHA" -; then
        rm -v "$GRADLE_ZIP" "$GRADLE_SHA"
        exit 1;
    fi

    puts "unzipping gradle-$GRADLE_VERSION"

    unzip -oq "$GRADLE_ZIP" -d "$TMP/"
}

