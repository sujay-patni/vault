# Running Vault

## Install Dependencies

```bash
fvm flutter pub get
```

## Start Android Emulator

List installed Android virtual devices:

```bash
~/Library/Android/sdk/emulator/emulator -list-avds
```

Start one:

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_9a
```

## Run The App

In another terminal:

```bash
fvm flutter devices
fvm flutter run -d emulator-5554
```

If your emulator has a different ID, replace `emulator-5554` with the device ID shown by `fvm flutter devices`.

## Build APKs

Debug:

```bash
fvm flutter build apk --debug
```

Release:

```bash
fvm flutter build apk --release
```

Release APK output:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## Install APK On Emulator

```bash
adb install -r build/app/outputs/flutter-apk/app-release.apk
adb shell monkey -p com.sujay.pwm -c android.intent.category.LAUNCHER 1
```

## Verify Release Permissions

```bash
~/Library/Android/sdk/build-tools/35.0.0/aapt dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

Release builds should not include `android.permission.INTERNET`.
