# Vault

Vault is an Android-first, offline encrypted vault built with Flutter. It stores passwords, secure notes, recovery codes, API keys, Wi-Fi secrets, payment card details, identity documents, and finance records in one local encrypted file.

Vault is designed for people who want a small, private vault without accounts, sync, analytics, or network access.

## Highlights

- Fully offline Android app.
- No `INTERNET` permission in release builds.
- Master-password-only unlock.
- No biometrics, cloud sync, account server, Firebase, or analytics.
- Encrypted backups are byte-for-byte copies of the encrypted vault file.
- Multiple encrypted item types: Passwords, Notes, Cards, IDs, Codes, Keys, Wi-Fi, Finance.
- Tags, favorites, search, backup export, and backup restore.

## Security Model

Vault encrypts all item content together inside the vault payload: titles, usernames, passwords, URLs, notes, tags, typed fields, favorites, and timestamps.

The vault file header remains readable because it contains metadata required to decrypt the payload, such as version, salt, Argon2id parameters, IVs, and payload length. This header does not contain user secrets.

The master password is never stored. Unlock derives a key with Argon2id, unwraps the vault key, decrypts the payload, and keeps decrypted data only while the app is unlocked.

See [SECURITY.md](SECURITY.md) for threat model details and responsible disclosure guidance.

## Requirements

- macOS, Linux, or Windows development machine.
- Flutter 3.41.0. This repo includes `.fvmrc`, so FVM is recommended.
- Android SDK with emulator or Android device.
- JDK 21 for Android/Gradle builds.

## Install Dependencies

```bash
cd password-manager
fvm flutter pub get
```

If you do not use FVM, install Flutter 3.41.0 and replace `fvm flutter` with `flutter`.

## Run On Laptop Emulator

List available Android emulators:

```bash
~/Library/Android/sdk/emulator/emulator -list-avds
```

Start an emulator, for example:

```bash
~/Library/Android/sdk/emulator/emulator -avd Pixel_9a
```

In another terminal, list devices:

```bash
fvm flutter devices
```

Run Vault:

```bash
fvm flutter run -d emulator-5554
```

Use hot reload during development with `r`, hot restart with `R`, and quit with `q`.

## Build APK

Debug APK:

```bash
fvm flutter build apk --debug
```

Release APK:

```bash
fvm flutter build apk --release
```

The release APK is generated at:

```text
build/app/outputs/flutter-apk/app-release.apk
```

This repository does not commit generated APK files. GitHub Actions builds APK artifacts automatically so the source repository stays small and auditable.

## Verify No Internet Permission

Build the release APK, then inspect permissions:

```bash
~/Library/Android/sdk/build-tools/35.0.0/aapt dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

The release APK should not include `android.permission.INTERNET`.

## Test

Fast checks:

```bash
fvm flutter analyze
fvm flutter test --exclude-tags slow
```

Full test suite, including production Argon2id tests:

```bash
fvm flutter test
```

## Examples

See [docs/EXAMPLES.md](docs/EXAMPLES.md) for example item types and suggested usage.
See [docs/ARCHITECTURE.md](docs/ARCHITECTURE.md) for a short overview of the vault format and app structure.

## GitHub Releases And APKs

The project includes GitHub Actions workflows for:

- static analysis and tests
- release APK build artifact generation

For public distribution, prefer GitHub Releases or Actions artifacts instead of committing APK binaries to git.

## Project Status

Vault is a personal/offline security app. Review the threat model before relying on it for high-value secrets, and always keep encrypted backups of your vault file.

## License

MIT. See [LICENSE](LICENSE).
