# Pasture Walk

Pasture Walk is an Android app for recording paddock covers and grazings.

## Install (Android)

This app is distributed as an APK via GitHub Releases (no Play Store required).

1. Go to the **Releases** page for this repository.
2. Download the latest `app-release.apk`.
3. On your Android phone:
   1. Open the downloaded APK.
   2. If prompted, allow installs from your browser / file manager ("Install unknown apps").
   3. Tap **Install**.

### Updating

To update, download the newest `app-release.apk` from Releases and install it. Android will install it over the top (as long as it is signed with the same key).

## Build the APK (for maintainers)

### Prerequisites

- Flutter SDK installed
- Android SDK installed (Android Studio is fine)

### Build a release APK

From the project root:

```bash
flutter pub get
flutter build apk --release
```

The output APK will be at:

```
build/app/outputs/flutter-apk/app-release.apk
```

### (Optional) Build a universal APK

If you ever switch to ABI splits, a universal APK is simplest for end users:

```bash
flutter build apk --release --target-platform android-arm,android-arm64,android-x64
```

## Publish a new version on GitHub

1. Build the release APK (see above).
2. In GitHub:
   1. Create a new Release.
   2. Create a tag like `v0.1.0`.
   3. Attach `build/app/outputs/flutter-apk/app-release.apk` as a release asset.
   4. Write short release notes (what changed).

## Troubleshooting

- **"App not installed"**
  - You may be trying to install an APK with a different signing key than the one previously installed. Uninstall the old app and try again (this will remove local data unless you have a backup).
- **Install blocked / unknown apps**
  - Enable installs for the app you downloaded with (Chrome / Files) under Android settings.
