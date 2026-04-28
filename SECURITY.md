# Security Policy

Vault is an offline Android vault. It is designed so the encrypted vault file and APK do not contain enough information to decrypt user data without the master password.

## What Vault Protects

- Stolen encrypted vault files.
- Leaked encrypted backup files.
- APK extraction and reverse engineering.
- Offline brute force, assuming a strong master password.

## What Vault Does Not Protect

- A weak or reused master password.
- Keyloggers or malicious keyboards.
- A tampered APK.
- Malware or root access while the vault is unlocked.
- Shoulder surfing.

## Reporting Security Issues

If you find a vulnerability, please do not open a public issue with exploit details. Contact the maintainer privately first, or open a minimal GitHub issue asking for a secure contact path.

## Release Builds

Release builds intentionally omit the Android `INTERNET` permission. Verify with:

```bash
~/Library/Android/sdk/build-tools/35.0.0/aapt dump permissions \
  build/app/outputs/flutter-apk/app-release.apk
```

## Backups

Backups are encrypted vault files. They are safe to store, but they are still sensitive because they can be attacked offline. Use a strong master password and keep backup files in trusted locations.
