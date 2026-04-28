import 'dart:convert';
import 'dart:typed_data';

import '../vault/vault_file.dart';
import 'aes_gcm.dart';
import 'argon2.dart';
import 'secure_bytes.dart';

/// High-level vault crypto operations.
///
/// All callers should pass the master password as a [Uint8List] of UTF-8
/// bytes (so the buffer can be zeroed). The class never retains password,
/// master_key, or vault_key bytes after a method returns.
class VaultCrypto {
  const VaultCrypto();

  /// Build a brand-new vault: derive master_key, generate a fresh vault_key,
  /// wrap it, encrypt an empty entries payload.
  Future<VaultBlob> create({
    required Uint8List masterPasswordUtf8,
    required Uint8List entriesJsonBytes,
    Argon2idParams params = Argon2idParams.defaults,
  }) async {
    final salt = randomBytes(16);
    final masterKey = await argon2idDerive(
      password: masterPasswordUtf8,
      salt: salt,
      params: params,
    );
    try {
      final vaultKey = randomBytes(AesGcm256.keyLength);
      try {
        final wrapIv = randomBytes(AesGcm256.nonceLength);
        final wrappedVaultKey = await AesGcm256.instance.encrypt(
          key: masterKey,
          nonce: wrapIv,
          plaintext: vaultKey,
        );

        final payloadIv = randomBytes(AesGcm256.nonceLength);
        // Build the AAD from a tentative blob with empty payload, then
        // re-emit final blob with the real payload. The AAD only depends on
        // the header fields, so we can compute it before knowing payload bytes
        // — but payload_len is part of the AAD, so we must know the final
        // ciphertext length up front. AES-GCM ciphertext length is plaintext
        // length + 16 (tag), so we can compute it.
        final ciphertextLen = entriesJsonBytes.length + AesGcm256.tagLength;
        final aad = _aadFor(
          salt: salt,
          params: params,
          wrapIv: wrapIv,
          wrappedVaultKey: wrappedVaultKey,
          payloadIv: payloadIv,
          payloadLen: ciphertextLen,
        );

        final payload = await AesGcm256.instance.encrypt(
          key: vaultKey,
          nonce: payloadIv,
          plaintext: entriesJsonBytes,
          aad: aad,
        );

        return VaultBlob(
          salt: salt,
          argonParams: params,
          wrapIv: wrapIv,
          wrappedVaultKey: wrappedVaultKey,
          payloadIv: payloadIv,
          payload: payload,
        );
      } finally {
        vaultKey.secureZero();
      }
    } finally {
      masterKey.secureZero();
    }
  }

  /// Decrypt a vault: derive master_key from the password + salt in the blob,
  /// unwrap vault_key, then decrypt the payload.
  ///
  /// Returns the decrypted entries JSON bytes.
  ///
  /// The caller is responsible for zeroing the returned buffer when done.
  Future<UnlockResult> unlock({
    required Uint8List masterPasswordUtf8,
    required VaultBlob blob,
  }) async {
    final masterKey = await argon2idDerive(
      password: masterPasswordUtf8,
      salt: blob.salt,
      params: blob.argonParams,
    );
    try {
      final vaultKey = await AesGcm256.instance.decrypt(
        key: masterKey,
        nonce: blob.wrapIv,
        ciphertextWithTag: blob.wrappedVaultKey,
      );
      // From here vaultKey lives until the caller zeros it.
      try {
        final aad = blob.headerForAad();
        final entriesJsonBytes = await AesGcm256.instance.decrypt(
          key: vaultKey,
          nonce: blob.payloadIv,
          ciphertextWithTag: blob.payload,
          aad: aad,
        );
        return UnlockResult(
          vaultKey: vaultKey,
          entriesJsonBytes: entriesJsonBytes,
        );
      } catch (_) {
        vaultKey.secureZero();
        rethrow;
      }
    } finally {
      masterKey.secureZero();
    }
  }

  /// Re-encrypt the payload with the given [vaultKey]. Produces a new blob
  /// reusing the existing salt/argon params/wrap (i.e. just persists updated
  /// entries — no password change involved).
  Future<VaultBlob> persistEntries({
    required VaultBlob existing,
    required Uint8List vaultKey,
    required Uint8List entriesJsonBytes,
  }) async {
    final payloadIv = randomBytes(AesGcm256.nonceLength);
    final ciphertextLen = entriesJsonBytes.length + AesGcm256.tagLength;
    final aad = _aadFor(
      salt: existing.salt,
      params: existing.argonParams,
      wrapIv: existing.wrapIv,
      wrappedVaultKey: existing.wrappedVaultKey,
      payloadIv: payloadIv,
      payloadLen: ciphertextLen,
    );
    final payload = await AesGcm256.instance.encrypt(
      key: vaultKey,
      nonce: payloadIv,
      plaintext: entriesJsonBytes,
      aad: aad,
    );
    return VaultBlob(
      salt: existing.salt,
      argonParams: existing.argonParams,
      wrapIv: existing.wrapIv,
      wrappedVaultKey: existing.wrappedVaultKey,
      payloadIv: payloadIv,
      payload: payload,
    );
  }

  /// Change the master password. Vault_key is unchanged; only the wrap and
  /// the payload's AAD-bound header are rebuilt.
  ///
  /// Caller passes a freshly-derived [vaultKey] (typically obtained from a
  /// recent [unlock]) — this method does not re-derive it from the old password.
  Future<VaultBlob> changePassword({
    required Uint8List newMasterPasswordUtf8,
    required Uint8List vaultKey,
    required Uint8List entriesJsonBytes,
    Argon2idParams params = Argon2idParams.defaults,
  }) async {
    final salt = randomBytes(16);
    final masterKey = await argon2idDerive(
      password: newMasterPasswordUtf8,
      salt: salt,
      params: params,
    );
    try {
      final wrapIv = randomBytes(AesGcm256.nonceLength);
      final wrappedVaultKey = await AesGcm256.instance.encrypt(
        key: masterKey,
        nonce: wrapIv,
        plaintext: vaultKey,
      );

      final payloadIv = randomBytes(AesGcm256.nonceLength);
      final ciphertextLen = entriesJsonBytes.length + AesGcm256.tagLength;
      final aad = _aadFor(
        salt: salt,
        params: params,
        wrapIv: wrapIv,
        wrappedVaultKey: wrappedVaultKey,
        payloadIv: payloadIv,
        payloadLen: ciphertextLen,
      );
      final payload = await AesGcm256.instance.encrypt(
        key: vaultKey,
        nonce: payloadIv,
        plaintext: entriesJsonBytes,
        aad: aad,
      );

      return VaultBlob(
        salt: salt,
        argonParams: params,
        wrapIv: wrapIv,
        wrappedVaultKey: wrappedVaultKey,
        payloadIv: payloadIv,
        payload: payload,
      );
    } finally {
      masterKey.secureZero();
    }
  }
}

/// Returned by [VaultCrypto.unlock]. The caller owns [vaultKey] and is
/// responsible for zeroing it when the session ends.
class UnlockResult {
  UnlockResult({required this.vaultKey, required this.entriesJsonBytes});
  final Uint8List vaultKey;
  final Uint8List entriesJsonBytes;
}

/// Convenience: convert a plaintext password string to a UTF-8 byte buffer
/// that the caller can zero after use.
Uint8List passwordToUtf8Bytes(String password) =>
    Uint8List.fromList(utf8.encode(password));

Uint8List _aadFor({
  required Uint8List salt,
  required Argon2idParams params,
  required Uint8List wrapIv,
  required Uint8List wrappedVaultKey,
  required Uint8List payloadIv,
  required int payloadLen,
}) {
  return VaultBlob(
    salt: salt,
    argonParams: params,
    wrapIv: wrapIv,
    wrappedVaultKey: wrappedVaultKey,
    payloadIv: payloadIv,
    payload: Uint8List(payloadLen), // contents irrelevant for AAD
  ).headerForAad();
}
