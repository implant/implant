FROM openjdk:8u222-stretch

ENV SDK=https://dl.google.com/android/repository/sdk-tools-linux-4333796.zip \
    YQ=https://github.com/mikefarah/yq/releases/download/2.4.0/yq_linux_amd64 \
    HOME=/root \
    IMPLANT=/root/implant \
    ANDROID_HOME=/root/Android/Sdk

RUN apt-get update && \
    apt-get install --no-install-suggests --no-install-recommends -y sudo less zip xxd jq && \
    apt-get clean -y && rm -rf /var/lib/apt/lists/* && \
    wget $YQ -O /usr/local/bin/yq -o /dev/null && \
    chmod +x /usr/local/bin/yq && \
    wget $SDK -O sdk.zip -o /dev/null && \
    mkdir -p $ANDROID_HOME /root/.implant && \
    unzip sdk.zip -d $ANDROID_HOME && \
    rm sdk.zip && \
    yes | $ANDROID_HOME/tools/bin/sdkmanager --licenses && \
    $ANDROID_HOME/tools/bin/sdkmanager "platform-tools"

WORKDIR $IMPLANT

COPY . $IMPLANT/

ENTRYPOINT ["/root/implant/implant.sh"]
