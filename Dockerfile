FROM openjdk:8u222-slim

ENV SDK=https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip \
    ANDROID_HOME=/root/Android/Sdk

RUN apt-get update && \
    apt-get install -y wget git unzip bzip2 && \
    rm -rf /var/lib/apt/lists/* && \
    wget $SDK -O sdk.zip -o /dev/null && \
    mkdir -p $ANDROID_HOME && \
    unzip sdk.zip -d $ANDROID_HOME && \
    rm sdk.zip && \
    yes | $ANDROID_HOME/tools/bin/sdkmanager --licenses && \
    $ANDROID_HOME/tools/bin/sdkmanager "platform-tools"

COPY functions.sh implant.sh /
COPY metadata /metadata

WORKDIR /src

ENTRYPOINT ["/implant.sh"]
