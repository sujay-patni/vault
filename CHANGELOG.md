# Changelog

All notable changes to this project will be documented in this file.

The format is based on [Keep a Changelog](https://keepachangelog.com/en/1.1.0/),
and this project adheres to [Semantic Versioning](https://semver.org/spec/v2.0.0.html).

## [Unreleased]

## [0.4.0] - 2026-06-10

### Added
- Fingerprint unlock (optional, off by default). The vault key is stored in an Android Keystore entry that cryptographically requires a system-enrolled fingerprint to read (`biometric_storage`); the master password is never persisted and always works as a fallback. Enable via Settings → "Unlock with fingerprint" or the offer shown right after first-time setup. Unlocking with a fingerprint skips the ~1 s key derivation entirely.
- The unlock screen auto-shows the fingerprint prompt when enabled, with a retry button and password entry always available.

### Changed
- Fingerprint unlock survives master-password changes (the inner vault key is unchanged by rotation), but is automatically turned off when a backup is restored, and must be re-enabled after adding/removing fingerprints on the device.
- `MainActivity` now extends `FlutterFragmentActivity` (required by the system biometric prompt).

## [0.3.0] - 2026-06-10

### Added
- Password generator in the entry form — length 8–64, charset toggles (upper/lower/digits/symbols), at least one character from each enabled set, secure RNG.
- Release builds are now signed with a dedicated release keystore (`android/key.properties`, gitignored) instead of debug keys, with automatic fallback to debug signing when the keystore is absent.

### Security
- Clipboard clearing moved to an app-wide guard: the 30-second clear timer now survives navigation and vault lock. Previously, locking the vault disposed the detail screen and cancelled the timer, leaving the copied secret on the clipboard indefinitely.
- Plaintext cache residue from pickers is now removed: file_picker copies, image_picker camera captures (and scaled variants), and share_plus staged files are deleted after each operation and swept again on every lock.
- Sensitive text fields (master password, entry passwords, card/CVV/PIN, recovery codes, API keys, secure-note body) now disable autocorrect, keyboard suggestions, and IME personalized learning.
- Argon2id parameters read from an imported backup header are bounds-checked (memory 64 KiB–2 GiB, iterations 1–100, parallelism 1–16), preventing memory-exhaustion from corrupt or hostile backup files.
- The picker/camera auto-lock exemption is now bounded: the vault force-locks if a picker has not returned within 10 minutes.
- Attachment flows re-verify the vault is still unlocked after a picker returns.

### Fixed
- Typing in the entry form now resets the idle auto-lock timer; previously only touch events did, so the vault could lock mid-edit and discard the form.
- Attachment image previews are decoded once instead of on every rebuild.
- Camera captures from the entry form are now downscaled/compressed the same way as captures from the detail screen.

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

[Unreleased]: https://github.com/sujay-patni/vault/compare/v0.3.0...HEAD
[0.3.0]: https://github.com/sujay-patni/vault/compare/v0.2.0...v0.3.0
[0.2.0]: https://github.com/sujay-patni/vault/compare/v0.1.0...v0.2.0
[0.1.0]: https://github.com/sujay-patni/vault/releases/tag/v0.1.0
