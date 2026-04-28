# Architecture

Vault is a local-only Flutter Android app. There is no backend, account system,
analytics SDK, or sync service.

## Storage

The app stores one encrypted vault file in the app documents directory. Backup
export copies that encrypted file to a user-selected location, and import
copies a selected encrypted vault file back into app storage after the supplied
master password successfully decrypts it.

## Encryption

Vault keeps all item content inside one encrypted JSON payload. This includes
titles, usernames, passwords, URLs, notes, tags, item-type-specific fields,
favorites, and timestamps.

The readable vault header contains only the metadata needed to decrypt the
payload, including format version, salt, Argon2id parameters, IVs, and payload
length. The master password is never stored.

At unlock time:

1. The master password is converted to UTF-8 bytes.
2. Argon2id derives a master key from the password and salt.
3. The master key unwraps the random vault key.
4. The vault key decrypts the encrypted payload.

Changing the master password re-wraps the same vault key with a new
password-derived key. It does not re-encrypt each item separately.

## App Layers

- `lib/crypto/`: AES-GCM, Argon2id, byte handling, and vault crypto.
- `lib/vault/`: vault entry models, vault file IO, repository, and state.
- `lib/backup/`: backup export/import helpers and user-facing backup errors.
- `lib/security/`: Android root warning helpers.
- `lib/ui/`: setup, unlock, vault list, entry forms, detail screens, settings,
  shared responsive layout, and theme tokens.

## Compatibility

Older entries without `itemType` load as password items. The encrypted vault file
format remains the same: a readable header plus one encrypted payload.
