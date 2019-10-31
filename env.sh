#!/bin/bash

export ANDROID_HOME=${ANDROID_HOME:-$HOME/Android/Sdk}
TOOLS=$ANDROID_HOME/build-tools
APKANALYZER=$ANDROID_HOME/tools/bin/apkanalyzer
ADB=$ANDROID_HOME/platform-tools/adb
METADATA=$PWD/metadata
IMPLANT=$HOME/.implant
TMP=$IMPLANT/tmp
DOWNLOADS=$IMPLANT/downloads
SRC=$IMPLANT/src
OUT=$IMPLANT/output
APKS=$OUT/apks
KEYSTORE=$OUT/implant.keystore
export KSPASS=${KSPASS:-implant}
LOG=$IMPLANT/build.log
VERBOSE=${VERBOSE:-0}
INSTALL=0
SERVE=0
GIT_PUSH=0
GIT_USER=implant-bot
GIT_EMAIL=implant-bot@tasks.org
DEFAULT_GRADLE_PROPS="org.gradle.jvmargs=-Xmx2048m -XX:MaxPermSize=2048m -XX:+HeapDumpOnOutOfMemoryError"
