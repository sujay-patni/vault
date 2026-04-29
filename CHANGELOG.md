# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.2.0] - 2026-04-29

### Added
- File attachments on vault entries — images and documents (JPG, PNG, WebP, PDF, TXT, DOC, XLS). Encrypted at rest inside the vault. Limits: 10 MB per file, 50 MB across the whole vault.
- Camera capture — take a photo from the entry form or detail screen and store it as an encrypted attachment.
- Attachment detail view — image thumbnail preview, export to device storage, share via Android share sheet, delete.
- Restore from backup on the first-run setup screen, allowing vault recovery on a new device without going through Settings.
- Backup export and restore in Settings.
- Vault list type-filter chips (Password, Card, Note, Identity, Recovery codes, API Key, Wi-Fi, Finance).
- Session picker guard — vault no longer auto-locks while the file picker or camera intent is active.

### Fixed
- Crash (`_dependents.isEmpty` framework assertion) when restoring from backup, caused by a `TextEditingController` being disposed while the password dialog's exit animation was still running. Affected both the setup screen and settings screen restore flows.
- Restore from backup spinner staying stuck indefinitely after a successful restore from Settings.

## [0.1.0] - 2026-04-28

### Added
- AES-256-GCM encrypted vault. All entries encrypted at rest under a vault key wrapped with Argon2id. Master password is never stored or transmitted.
- Vault entry types: Password, Secure note, Payment card, Identity, Recovery codes, API key, Wi-Fi, Finance.
- Create, view, edit, and delete vault entries with per-field sensitive masking.
- Full-text search across title, username, URL, notes, tags, and custom fields.
- Favorites — pin entries to the top of the vault list.
- Tags — comma-separated, searchable.
- Change master password — re-encrypts the vault key without re-encrypting entry data.
- Session lock — auto-locks after 60 seconds of inactivity and immediately on app background.
- Root detection warning banner.
- Encrypted backup export to device storage.
- Atomic on-disk writes to prevent vault corruption on crash.
- GitHub Actions CI for APK build and static analysis.

[Unreleased]: https://github.com/sujay-patni/vault/compare/v0.2.0...HEAD
[0.2.0]: https://github.com/sujay-patni/vault/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sujay-patni/vault/releases/tag/v0.1.0
