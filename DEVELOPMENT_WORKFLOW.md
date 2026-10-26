# Flutter Development Workflow (Windows)

This project was moved from Linux. The old tmux/lazygit/ranger workflow is gone;
everything below is the Windows equivalent.

## What is installed where

| Tool | Location |
|---|---|
| Flutter SDK 3.47.2 (stable, Dart 3.13.2) | `C:\src\flutter` |
| JDK 21 (Temurin, LTS) | `C:\Program Files\Eclipse Adoptium\jdk-21.0.12.101-hotspot` |
| Git | `C:\Program Files\Git` |
| Android SDK | `%LOCALAPPDATA%\Android\Sdk` |
| Android platform / build-tools / NDK | `android-36`, `36.0.0`, `28.2.13676358` |

These are already on your user `PATH`, and `JAVA_HOME` / `ANDROID_HOME` are set.
`flutter config` also knows the SDK and JDK paths.

## Quick start

Open a **new** PowerShell window (or restart Android Studio so it picks up PATH),
then:

```powershell
fstart      # jump to the project
fdev        # flutter run --debug (hot reload)
fbuild      # flutter build apk --release
ftest       # flutter test
fanalyze    # flutter analyze
fdoctor     # flutter doctor -v
```

The helpers come from `scripts/dev-workflow.ps1`, dot-sourced by your
PowerShell profile.

## Aliases available

```powershell
# Navigation / build
fstart        # cd to project
proj          # same
frun          # flutter run
fdev          # flutter run --debug
fbuild        # flutter build apk --release
fdapk         # flutter build apk --debug
fclean        # flutter clean && flutter pub get
fpub          # flutter pub get
ftest         # flutter test
fanalyze      # flutter analyze
ffix          # dart fix --apply
fdoctor       # flutter doctor -v
fdevices      # flutter devices

# Git (replaces lazygit shortcuts)
gs            # git status
gd            # git diff
gl            # git log --graph
ga            # git add -A
gc "message"  # git commit -m "message"
gp            # git push
gu            # git pull --ff-only

# Search (replaces ffind / fgrep / ripgrep)
ffind *.dart  # find files by name, skipping build/.dart_tool
fgrep "text"  # grep inside .dart files
```

For a graphical Git UI, install **GitHub Desktop**, **Fork** or **Sourcetree** —
or just use Android Studio's built-in Git panel (`Alt+9` → Log tab).

## Android Studio

* The Gradle project is `android/` (not the repo root).
* Flutter SDK path: **Settings → Languages & Frameworks → Flutter → Flutter SDK path**
  should be `C:\src\flutter`.
* Gradle JDK: **Settings → Build, Execution, Deployment → Build Tools → Gradle →
  Gradle JDK** should be the Temurin 21 JDK.
* Run configurations already exist (`.vscode/launch.json` for VS Code,
  `lib/main.dart` run config for Android Studio).

## Required one-time Windows settings

1. **Developer Mode** must be ON. Flutter needs symlink support to build plugins.
   Windows Settings → System → For developers → **Developer Mode: On**, or run:
   ```powershell
   start ms-settings:developers
   ```
   Without this, `flutter pub get` / `flutter run` fails with
   *"Building with plugins requires symlink support"*.

2. **Long paths** (recommended). Android/Gradle build paths exceed the legacy
   260-character limit. Run once in an **Administrator** PowerShell:
   ```powershell
   reg add "HKLM\SYSTEM\CurrentControlSet\Control\FileSystem" /v LongPathsEnabled /t REG_DWORD /d 1 /f
   ```
   Note: this cannot be set from a non-elevated shell.

## Release builds

Release signing is read from `android/key.properties`, which is **not** in git.
Debug and profile builds work without it. To build a signed release APK, create
`android/key.properties`:

```properties
storePassword=<your store password>
keyPassword=<your key password>
keyAlias=pasturewalk
storeFile=../../pasturewalk.keystore
```

`storeFile` is resolved relative to `android/app/`, hence `../../`.

Then:

```powershell
fbuild
# output: build\app\outputs\flutter-apk\app-release.apk
```

See `README.md` for how to publish that APK to GitHub Releases.
