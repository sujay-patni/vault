# Contributing

Thanks for considering a contribution to Vault.

## Development Setup

```bash
fvm flutter pub get
fvm flutter analyze
fvm flutter test --exclude-tags slow
```

## Rules For Security-Sensitive Changes

Read `HANDOFF.md` before changing:

- crypto code
- vault file serialization
- master password handling
- Android manifest permissions
- backup import/export behavior

Do not add network dependencies, analytics, Firebase, crash reporting, or Android permissions without a clear security review.

## Pull Request Checklist

- Keep changes focused.
- Add or update tests for vault/model behavior changes.
- Run `fvm flutter analyze`.
- Run `fvm flutter test --exclude-tags slow`.
- For crypto/file-format changes, run the full `fvm flutter test`.
- Do not commit generated files, build outputs, local settings, APKs, keystores, or secrets.
