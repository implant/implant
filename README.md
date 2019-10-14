#### Build and install open-source Android apps with Implant

:construction: Under construction :construction:

Implant is designed for use with Docker, but `implant.sh` [*should* work on Debian-based distros](https://github.com/abaker/implant/wiki/Use-implant-without-Docker)

`docker run --rm -it bakerba/implant list` to browse available apps

### Examples

First create an [`implant` alias](https://github.com/abaker/implant/wiki/Create-an-implant-alias)

**Build and Install Signal, Syncthing, and NewPipe**
```
implant install org.thoughtcrime.securesms com.nutomic.syncthing org.schabi.newpipe
```
**Read packages from a file**

Maintain a list of apps you have installed:
```
echo org.mozilla.fenix | tee -a my_apps.txt | implant install
```
Later you can update them all:
```
docker pull bakerba/implant
implant install < my_apps.txt
```
**Turn your PC into a space heater**
```
implant install org.videolan.vlc
```
**Install everything!**
```
implant list | awk '{print $NF}' | implant install
```
### Commands

* `implant list` to show available apps
* `implant list --installed` to show installed apps
* `implant build [package ...]` to build apps
* `implant install [package ...]` to build and install apps
* `implant keygen` to create adb, debug, and release keys
* `implant adb [...]` to use adb

### Requirements

* Install Docker for [Linux](https://docs.docker.com/v17.12/install/#server), [macOS](https://docs.docker.com/docker-for-mac/install/), or [Windows](https://docs.docker.com/docker-for-windows/install/)
* [Enable USB debugging](https://developer.android.com/studio/debug/dev-options) on your Android device
* **macOS/Windows:** Docker can't see your phone, so [start an `adb` server](https://github.com/abaker/implant/wiki/Start-an-adb-server) :sob:

### Please contribute!

File bug reports, help add features, submit new apps, or maintain existing apps
