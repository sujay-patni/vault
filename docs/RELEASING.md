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

Manual APK build from GitHub:

1. Open the repository on GitHub.
2. Go to **Actions**.
3. Select **Build APK**.
4. Click **Run workflow**.
5. Select the branch or tag to build.
6. Open the completed workflow run.
7. Download the `vault-release-apk` artifact.

Tag-based APK build:

```bash
git tag v0.1.0
git push origin v0.1.0
```

Pushing a `v*` tag automatically runs the `Build APK` workflow.

## GitHub Release With APK

Use GitHub Releases for public downloadable APKs. Do not commit APK files to git.

1. Create and push a version tag:

   ```bash
   git tag v0.1.0
   git push origin v0.1.0
   ```

2. Wait for **Actions** > **Build APK** to finish for that tag.
3. Download the `vault-release-apk` artifact from the workflow run.
4. On GitHub, go to **Releases** > **Draft a new release**.
5. Choose the same tag, for example `v0.1.0`.
6. Set the release title, for example `Vault v0.1.0`.
7. Attach `app-release.apk` from the downloaded artifact.
8. Add release notes.
9. Publish the release.

Suggested release notes template:

```markdown
## Vault v0.1.0

Initial public release of Vault, an offline encrypted Android vault.

### Highlights

- Offline encrypted vault with no account, sync, analytics, or network access.
- Supports passwords, secure notes, cards, IDs, recovery codes, API keys, Wi-Fi, and finance records.
- Tags, favorites, search, encrypted backup export, and encrypted backup restore.
- Dark Graphite minimalist Android UI.

### Security Notes

- All item content is encrypted inside the vault payload.
- The master password is never stored.
- Release APK does not request `android.permission.INTERNET`.
- Keep encrypted backups safe and use a strong master password.

### APK

Download `app-release.apk` from this release and install it on Android.
```

## Signing

The current Android release config is suitable for local sideloading and GitHub Actions artifacts. Before Play Store distribution, create a proper release keystore and wire Android signing configuration through secrets or local `keystore.properties`.

Never commit signing keys, `keystore.properties`, or private certificates.
