# Releasing

Vault does not commit generated APK files to git. Build outputs belong in GitHub Actions artifacts or GitHub Releases.

## Local Release Build

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test --exclude-tags slow
fvm flutter build apk --release
```

APK:

```text
build/app/outputs/flutter-apk/app-release.apk
```

## GitHub Actions Artifacts

The `Build APK` workflow builds a release APK and uploads it as an Actions artifact.

## Signing

The current Android release config is suitable for local sideloading and GitHub Actions artifacts. Before Play Store distribution, create a proper release keystore and wire Android signing configuration through secrets or local `keystore.properties`.

Never commit signing keys, `keystore.properties`, or private certificates.

## Suggested Tag Flow

```bash
git tag v0.1.0
git push origin v0.1.0
```

Then attach the APK from the workflow artifact to a GitHub Release if desired.
