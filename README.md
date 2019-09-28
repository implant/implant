#### `bakerba/implant` is a Docker image that can build and install open-source Android apps

:construction: Implant is under construction. Use at your own risk :construction:

Implant is designed for use with Docker, but `implant.sh` *probably* works on Debian-based distros, and it *might* work on other platforms in the future

### Usage

* `implant list` to show available apps
* `implant install [package ...]` to build and install apps

### Example

Build and install Firefox, Syncthing, and NewPipe
```
implant install com.mozilla com.nutomic.syncthing org.schabi.newpipe
```

### Requirements

* Install Docker for [Linux](https://docs.docker.com/v17.12/install/#server), [macOS](https://docs.docker.com/docker-for-mac/install/), or [Windows](https://docs.docker.com/docker-for-windows/install/)
* [Enable USB debugging](https://developer.android.com/studio/debug/dev-options) on your Android device
* **macOS/Windows:** Start an `adb` server. Docker can't see your phone :sob:

### Recommended setup

* Generate adb and signing keys
* Create an `implant` alias

### Please contribute!

File bug reports, help add features, submit new apps, or maintain existing apps
