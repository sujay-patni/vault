import 'dart:convert';
import 'dart:io';

import 'package:biometric_storage/biometric_storage.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

/// Filename of the plaintext marker that records "biometric unlock is
/// enabled". It is a pure UI hint (whether to show the fingerprint button)
/// and grants nothing: the vault_key itself lives in an Android Keystore
/// entry that cannot be read without a fingerprint.
const String _markerFileName = 'biometric.enabled';

/// Device capability for biometric unlock.
enum BiometricSupport { available, noHardware, notEnrolled, unavailable }

/// Normalized failure reasons for biometric storage operations.
enum BiometricFailure {
  /// User dismissed the system prompt (back button / "Use password").
  userCanceled,

  /// The Keystore key was permanently invalidated (fingerprints were
  /// added/removed on the device) or the stored entry vanished. The store
  /// must be cleared and the user must re-enable biometric unlock.
  keyInvalidated,

  /// Everything else: sensor lockout after repeated failures, hardware
  /// temporarily unavailable, unexpected platform errors. The stored entry
  /// is kept — the condition is usually transient.
  other,
}

class BiometricStoreException implements Exception {
  const BiometricStoreException(this.failure, [this.message]);

  final BiometricFailure failure;
  final String? message;

  @override
  String toString() =>
      'BiometricStoreException(${failure.name}${message == null ? '' : ': $message'})';
}

/// Hardware-backed storage for the raw vault_key, gated by the system
/// fingerprint prompt. Abstract so business logic can be tested with an
/// in-memory fake.
abstract class BiometricVaultKeyStore {
  /// Device capability. Never shows a prompt.
  Future<BiometricSupport> support();

  /// Whether a vault key has been stored (marker file). Never shows a prompt.
  Future<bool> isEnabled();

  /// Store [vaultKey]. Shows the fingerprint prompt. Copies the bytes —
  /// the caller keeps ownership of (and must zero) its buffer.
  Future<void> store(Uint8List vaultKey);

  /// Retrieve the vault key. Shows the fingerprint prompt. The caller owns
  /// the returned buffer and must zero it unless handing it to
  /// VaultUnlocked. Throws [BiometricStoreException].
  Future<Uint8List> read();

  /// Remove the stored key and marker. Idempotent, never throws on
  /// "already gone", never shows a prompt.
  Future<void> clear();
}

/// Production implementation backed by the biometric_storage plugin: the
/// value is encrypted with an Android Keystore AES key created with
/// setUserAuthenticationRequired(true), so decryption is impossible without
/// a fingerprint — even for code running inside this app.
class BiometricStorageVaultKeyStore implements BiometricVaultKeyStore {
  BiometricStorageVaultKeyStore({
    required File markerFile,
    BiometricStorage? plugin,
  }) : _markerFile = markerFile,
       _plugin = plugin ?? BiometricStorage();

  final File _markerFile;
  final BiometricStorage _plugin;

  static const String _storageName = 'pwm_vault_key';

  static const PromptInfo _promptInfo = PromptInfo(
    androidPromptInfo: AndroidPromptInfo(
      title: 'Unlock Vault',
      negativeButton: 'Use password',
      confirmationRequired: false,
    ),
  );

  /// Options apply only when the Keystore entry is first created; changing
  /// them later requires delete + recreate.
  Future<BiometricStorageFile> _storage() {
    return _plugin.getStorage(
      _storageName,
      options: StorageFileInitOptions(
        authenticationRequired: true,
        // -1 binds auth to each individual Keystore operation (CryptoObject)
        // and makes the key invalidate on new fingerprint enrollment.
        authenticationValidityDurationSeconds: -1,
        // No PIN/pattern fallback — the master password is our fallback.
        androidBiometricOnly: true,
      ),
      promptInfo: _promptInfo,
    );
  }

  @override
  Future<BiometricSupport> support() async {
    final res = await _plugin.canAuthenticate();
    return switch (res) {
      CanAuthenticateResponse.success => BiometricSupport.available,
      CanAuthenticateResponse.errorNoHardware ||
      CanAuthenticateResponse.unsupported => BiometricSupport.noHardware,
      CanAuthenticateResponse.errorNoBiometricEnrolled =>
        BiometricSupport.notEnrolled,
      _ => BiometricSupport.unavailable,
    };
  }

  @override
  Future<bool> isEnabled() => _markerFile.exists();

  @override
  Future<void> store(Uint8List vaultKey) async {
    // NOTE: the plugin API is String-based, so the base64 of the vault key
    // transiently exists as an unzeroable Dart String. Accepted limitation —
    // same exposure class as the password TextEditingController.
    final storage = await _storage();
    try {
      await storage.write(base64Encode(vaultKey));
    } catch (e) {
      throw _mapError(e);
    }
    await _markerFile.writeAsString('1', flush: true);
  }

  @override
  Future<Uint8List> read() async {
    final storage = await _storage();
    String? value;
    try {
      value = await storage.read();
    } catch (e) {
      throw _mapError(e);
    }
    if (value == null) {
      // biometric_storage 5.x silently deletes the entry when the Keystore
      // key was invalidated by a fingerprint enrollment change, so "entry
      // missing while our marker says enabled" means invalidation.
      throw const BiometricStoreException(
        BiometricFailure.keyInvalidated,
        'stored vault key is gone',
      );
    }
    return Uint8List.fromList(base64Decode(value));
  }

  @override
  Future<void> clear() async {
    try {
      final storage = await _storage();
      await storage.delete();
    } catch (_) {
      // Best-effort: a stale Keystore entry without its marker is inert.
    }
    if (await _markerFile.exists()) {
      await _markerFile.delete();
    }
  }

  static BiometricStoreException _mapError(Object e) {
    if (e is BiometricStoreException) return e;
    if (e is AuthException) {
      return switch (e.code) {
        AuthExceptionCode.userCanceled ||
        AuthExceptionCode.canceled ||
        AuthExceptionCode.timeout => BiometricStoreException(
          BiometricFailure.userCanceled,
          e.message,
        ),
        _ => BiometricStoreException(_failureFromMessage(e.message), e.message),
      };
    }
    if (e is PlatformException) {
      return BiometricStoreException(
        _failureFromMessage('${e.code} ${e.message}'),
        e.message,
      );
    }
    return BiometricStoreException(BiometricFailure.other, e.toString());
  }

  /// Defensive: key invalidation surfaces differently across plugin
  /// versions; match the Keystore exception name anywhere in the message.
  static BiometricFailure _failureFromMessage(String? message) =>
      (message ?? '').contains('KeyPermanentlyInvalidated')
      ? BiometricFailure.keyInvalidated
      : BiometricFailure.other;
}

/// Marker file lives next to vault.bin in the app documents directory.
final biometricMarkerFileProvider = FutureProvider<File>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$_markerFileName');
});

/// Overridden in tests with an in-memory fake.
final biometricVaultKeyStoreProvider = FutureProvider<BiometricVaultKeyStore>((
  ref,
) async {
  final marker = await ref.watch(biometricMarkerFileProvider.future);
  return BiometricStorageVaultKeyStore(markerFile: marker);
});
