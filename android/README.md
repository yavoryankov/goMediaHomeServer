# Android App

This directory contains the Android client for goMediaHomeServer.

## Requirements

- Android Studio with the Android SDK and an emulator or Android device.
- ARM64 JDK 21 or newer on Apple Silicon, or an x86_64 JDK 21 or newer on Intel/Windows/Linux.
- Android SDK platform/build tools required by the project.
- A phone and the iMac/server connected to the same LAN for local testing.

The application currently uses package `com.gomediahomecllient`, minimum Android
API 29, and target API 37.

## Configure the server address

The first-run default is a placeholder:

```text
http://YOUR-IMAC-IP:8095/api/v1
```

Run the app, open **Settings**, enter the server API address, and tap **Test
connection**. For the example LAN installation use:

```text
http://YOUR-IMAC-IP:8095/api/v1
```

The value is stored locally in Android preferences. Replace the address when the
server is installed on another network.

## Build from the command line

On Apple Silicon, make sure Gradle is using an ARM64 JDK. An Intel-only JDK
will fail with `Bad CPU type in executable` before Gradle can start:

```sh
/usr/libexec/java_home -v 21
export JAVA_HOME=$(/usr/libexec/java_home -v 21)
java -version
```

If JDK 21 is not installed, install an ARM64 JDK 21 distribution such as
Temurin, then repeat the commands above. GitHub Actions uses Java 21 for the
reproducible CI build.

From the repository root:

```sh
cd android
./gradlew --no-daemon :app:assembleDebug
```

The debug APK is written to:

```text
android/app/build/outputs/apk/debug/app-debug.apk
```

Run unit tests with:

```sh
./gradlew --no-daemon test
```

## Install on a device

Enable **Developer options** and **USB debugging** on the Android device, connect
it by USB, accept the debugging prompt, and verify it with `adb devices`. Then:

```sh
./gradlew --no-daemon :app:installDebug
```

Alternatively install the generated APK with:

```sh
adb install -r app/build/outputs/apk/debug/app-debug.apk
```

The server must be reachable from the phone. Do not use `127.0.0.1` in the app
when the server runs on the iMac; use the iMac's LAN IP instead.

## Android Studio

Open the `android` directory as a project, allow Gradle sync to finish, select a
device, and run the `app` configuration. For a release build, configure a private
keystore in Android Studio or Gradle; never commit the keystore, passwords, or
`local.properties`.
