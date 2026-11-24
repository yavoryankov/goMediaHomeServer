# iOS App

This directory contains the iOS client for goMediaHomeServer.

## Requirements

- macOS with Xcode installed.
- An Apple ID signed into Xcode for device installation.
- An iPhone running an iOS version supported by the project deployment target.
- The iPhone and iMac/server connected to the same LAN for local testing.

The Xcode project is located at:

```text
ios/goMediaHomеClient/goMediaHomеClient.xcodeproj
```

The project name contains a Cyrillic `е` character. Open it from Finder or copy
the path exactly when using the command line.

## Configure the server address

The first-run default is:

```text
http://YOUR-IMAC-IP:8095/api/v1
```

In the app open **Settings**, enter the server API address, and tap **Test
connection**. For the example LAN installation use:

```text
http://YOUR-IMAC-IP:8095/api/v1
```

The address is stored in the app's local UserDefaults. Use the iMac's LAN IP, not
`localhost` or `127.0.0.1`, when testing on a physical iPhone.

## Signing and team setup

1. Open the Xcode project.
2. Select the app target and open **Signing & Capabilities**.
3. Select your Apple developer Team.
4. Change the Bundle Identifier to a unique value, for example
   `com.yourcompany.goMediaHomeClient`.
5. Enable **Automatically manage signing** for development.
6. Connect the iPhone, select it as the run destination, and trust the developer
   profile on the device if iOS asks for it.

Do not commit provisioning profiles, signing certificates, private keys, or
personal Apple account files. Distribution/TestFlight signing requires an Apple
Developer Program account and should be performed through Xcode or CI secrets.

## Build in Xcode

Open the project, choose an iPhone simulator or physical iPhone, then select
**Product > Build**. To install and run on the connected iPhone, select the device
and press **Product > Run**. The first installation may require enabling Developer
Mode on the iPhone.

## Build from the command line

List available schemes and destinations:

```sh
xcodebuild -project "ios/goMediaHomеClient/goMediaHomеClient.xcodeproj" -list
xcodebuild -project "ios/goMediaHomеClient/goMediaHomеClient.xcodeproj" -showdestinations
```

For a simulator build without signing:

```sh
xcodebuild \
  -project "ios/goMediaHomеClient/goMediaHomеClient.xcodeproj" \
  -scheme "goMediaHomеClient" \
  -sdk iphonesimulator \
  -configuration Debug \
  -derivedDataPath /tmp/goMediaHomeServer-ios-derived \
  CODE_SIGNING_ALLOWED=NO build
```

For a physical device, select the device in Xcode and use **Product > Run** so
Xcode can apply the correct signing and provisioning profile. Archive and export
release builds from **Product > Archive** after configuring the distribution team.
