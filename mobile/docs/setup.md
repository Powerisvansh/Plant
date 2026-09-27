# PlantDoctor – Setup

## Requirements

- **Flutter 3.47+** (stable) with Dart 3.x
- **Android SDK** – API 34+ recommended, build-tools present
- A Linux/macOS/Windows host

For this repo the toolchain used was:

```
Flutter 3.47.5 (stable) on Linux
Dart 3.13.4
Java 21 (OpenJDK)          # AGP 8.x requires JDK 17+
Android SDK (platforms 34/35/36, build-tools 34/35/36)
```

## Environment notes (this machine)

- Flutter SDK cloned to `~/flutter`; add to your shell:

  ```bash
  echo 'export PATH="$HOME/flutter/bin:$PATH"' >> ~/.profile
  ```

- Android SDK at `~/Android/Sdk`. Point Flutter at it:

  ```bash
  flutter config --android-sdk ~/Android/Sdk
  ```

- Accept licenses (cmdline-tools):

  ```bash
  yes | sdkmanager --licenses
  ```

- **Emulator note:** this machine has no KVM, so hardware acceleration (and
  therefore the Android emulator) is unavailable. Use a physical Android device
  connected over USB (`adb devices`) or build the APK and install it manually.

- Optional desktop build (Linux) requires:

  ```bash
  sudo apt-get install -y clang cmake ninja-build pkg-config libgtk-3-dev
  ```

## Build the app

```bash
cd mobile
flutter pub get
flutter analyze --no-pub
flutter test
flutter build apk --debug        # quick smoke build
flutter build apk --release      # release APK (R8/shrinking)
```

The APK lands at `build/app/outputs/flutter-apk/app-debug.apk` (or
`app-release.apk`).

## Install on a device

```bash
~/Android/Sdk/platform-tools/adb install build/app/outputs/flutter-apk/app-debug.apk
```

## First build downloads

The first Android Gradle build downloads Gradle, the Android Gradle Plugin and
the NDK automatically (Flutter's default build uses the NDK for stripping).
This can take several minutes depending on the network.

## Notes

- The app declares `CAMERA` permission (`android/app/src/main/AndroidManifest.xml`).
- `minSdkVersion` is Flutter's default (24).
- Everything is offline; no API keys are required.