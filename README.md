#### Implant can build and install open-source Android apps

:construction: Implant is under construction. Use at your own risk :construction:

Implant is designed for use with Docker, but `implant.sh` [*should* work on Debian-based distros](https://github.com/abaker/implant/wiki/Use-implant-without-Docker), and it *might* work on other platforms in the future

### List available apps

```
docker run --rm -it bakerba/implant list
```

### Example: Build and Install Firefox, Syncthing, and NewPipe

```
docker run --rm bakerba/implant \
    install com.mozilla com.nutomic.syncthing org.schabi.newpipe
```

### Commands

* `list` to show available apps
* `build [package ...]` to build apps
* `install [package ...]` to build and install apps

### Requirements

* Install Docker for [Linux](https://docs.docker.com/v17.12/install/#server), [macOS](https://docs.docker.com/docker-for-mac/install/), or [Windows](https://docs.docker.com/docker-for-windows/install/)
* [Enable USB debugging](https://developer.android.com/studio/debug/dev-options) on your Android device
* **macOS/Windows:** Docker can't see your phone, so [start an `adb` server](https://github.com/abaker/implant/wiki/Start-an-adb-server) :sob:

### Recommended setup

* [Generate adb and signing keys](https://github.com/abaker/implant/wiki/Don't-lose-your-keys!)
* [Create an `implant` alias](https://github.com/abaker/implant/wiki/Create-an-implant-alias)

### Please contribute!

File bug reports, help add features, submit new apps, or maintain existing apps
