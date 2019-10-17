#### Build and install open-source Android apps with Implant

Implant can build 90+ open-source Android apps, install them on
your phone over USB, or generate an F-Droid repository so you can 
install them with the F-Droid client

Implant is designed for use with Docker, but *might* work on a Debian-based distro

`docker run --rm -it bakerba/implant list` to browse available apps

### Examples

First create an [`implant` alias](https://github.com/abaker/implant/wiki/Create-an-implant-alias)

**Build and serve all apps as an F-Droid Repository**
```
implant fdroid --serve
```
**Build and Install Signal, Syncthing, and NewPipe over USB**
```
implant install org.thoughtcrime.securesms com.nutomic.syncthing org.schabi.newpipe
```
**Update Installed Apps Over USB**
```
docker pull bakerba/implant
implant update
```
**Install everything!**
```
implant list | awk '{print $NF}' | implant install
```
### Commands

* `list [--installed]` show available apps
* `fdroid [--serve] [package ...]` build apps, generate an F-Droid index, and start a web server
* `install [package ...]` build and install apps over USB
* `build [package ...]` build apps
* `update` update installed apps over USB
* `keygen` create adb and release keys
* `adb [...]` execute adb commands

### Requirements

* Install Docker for [Linux](https://docs.docker.com/v17.12/install/#server), [macOS](https://docs.docker.com/docker-for-mac/install/), or [Windows](https://docs.docker.com/docker-for-windows/install/)
* [Enable USB debugging](https://developer.android.com/studio/debug/dev-options) on your Android device
* **macOS/Windows:** Docker can't see your phone, so [start an `adb` server](https://github.com/abaker/implant/wiki/Start-an-adb-server) :sob:

### Please contribute!

File bug reports, help add features, submit new apps, or maintain existing apps
