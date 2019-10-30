Implant can build 100+ open-source Android apps, install them on your phone
over USB, or generate an F-Droid repository so you can install them with the
F-Droid client

`docker run --rm bakerba/implant list` to list available apps

#### Examples
First create an [`implant`
alias](https://github.com/abaker/implant/wiki/Create-an-implant-alias)

* Build and serve all apps as an F-Droid Repository
  ```
  implant fdroid --serve
  ```
* Install Signal, Syncthing, and NewPipe over USB
  ```
  implant install org.thoughtcrime.securesms com.nutomic.syncthing org.schabi.newpipe
  ```
* Update apps
  ```
  docker pull bakerba/implant
  implant update
  ```
### Commands

* `list [--installed]` show available apps
* `fdroid [--serve] [package ...]` build apps, generate an F-Droid index, and
  start a web server
* `install [package ...]` build and install apps over USB
* `build [package ...]` build apps
* `update` update apps
* `passwd` change signing key password
* `adb [...]` execute adb commands

### Requirements
* Docker for [Linux](https://docs.docker.com/v17.12/install/#server),
  [macOS](https://docs.docker.com/docker-for-mac/install/), or
  [Windows](https://docs.docker.com/docker-for-windows/install/)

### Additional setup for USB installs
* [Enable USB
  debugging](https://developer.android.com/studio/debug/dev-options) on your
  Android device
* **macOS/Windows:** Docker can't see your phone, so [start an `adb`
  server](https://github.com/abaker/implant/wiki/Start-an-adb-server) :sob:

### Please contribute!

File bug reports, help add features, submit new apps, or maintain existing apps
