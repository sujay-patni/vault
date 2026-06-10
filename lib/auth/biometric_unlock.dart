import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../crypto/secure_bytes.dart';
import '../vault/vault_repository.dart';
import '../vault/vault_state.dart';
import 'biometric_store.dart';
import 'session_manager.dart';

/// Result of a biometric unlock attempt, for the unlock screen to map to UX.
enum BiometricUnlockOutcome {
  /// Vault is now unlocked.
  success,

  /// User dismissed the prompt — no error message warranted.
  canceled,

  /// The stored key is gone or no longer matches this vault (fingerprint
  /// enrollment changed, or a different vault was imported). The store has
  /// been cleared; the user must unlock with the master password and
  /// re-enable biometrics in Settings.
  invalidated,

  /// Transient failure (sensor lockout, hardware busy). Stored key kept.
  unavailable,
}

/// Orchestrates biometric enable/disable/unlock on top of the store and the
/// vault providers.
class BiometricUnlockService {
  BiometricUnlockService(this._ref);

  final Ref _ref;

  Future<BiometricVaultKeyStore> _store() =>
      _ref.read(biometricVaultKeyStoreProvider.future);

  /// Read the vault key from biometric storage (shows the fingerprint
  /// prompt) and unlock the vault with it.
  Future<BiometricUnlockOutcome> attemptUnlock() async {
    final store = await _store();
    final Uint8List vaultKey;
    try {
      vaultKey = await store.read();
    } on BiometricStoreException catch (e) {
      switch (e.failure) {
        case BiometricFailure.userCanceled:
          return BiometricUnlockOutcome.canceled;
        case BiometricFailure.keyInvalidated:
          await _clearAndRefresh(store);
          return BiometricUnlockOutcome.invalidated;
        case BiometricFailure.other:
          return BiometricUnlockOutcome.unavailable;
      }
    }
    try {
      await _ref
          .read(vaultStatusProvider.notifier)
          .unlockWithVaultKey(vaultKey: vaultKey);
      return BiometricUnlockOutcome.success;
    } catch (_) {
      // GCM auth failure: the stored key does not belong to the current
      // vault file (e.g. a foreign backup was imported). Treat as stale.
      vaultKey.secureZero();
      await _clearAndRefresh(store);
      return BiometricUnlockOutcome.invalidated;
    }
  }

  /// Store the current in-memory vault key under fingerprint protection.
  /// Requires the vault to be unlocked. Returns false if the user canceled
  /// or the operation failed.
  Future<bool> enable() async {
    final status = _ref.read(vaultStatusProvider);
    if (status is! VaultUnlocked) {
      throw StateError('biometric enable requires an unlocked vault');
    }
    final store = await _store();
    final keyCopy = Uint8List.fromList(status.vaultKey);
    try {
      // Some OEMs pause the activity behind BiometricPrompt, which would
      // auto-lock the vault mid-enable — use the same bounded exemption as
      // the system file pickers.
      await _ref
          .read(sessionManagerProvider)
          .runExternalPicker(() => store.store(keyCopy));
      return true;
    } on BiometricStoreException {
      return false;
    } finally {
      keyCopy.secureZero();
      _ref.invalidate(biometricEnabledProvider);
    }
  }

  /// Remove the stored vault key. Safe to call in any state; never prompts.
  Future<void> disable() async {
    final store = await _store();
    await _clearAndRefresh(store);
  }

  Future<void> _clearAndRefresh(BiometricVaultKeyStore store) async {
    await store.clear();
    _ref.invalidate(biometricEnabledProvider);
  }
}

final biometricSupportProvider = FutureProvider<BiometricSupport>((ref) async {
  final store = await ref.watch(biometricVaultKeyStoreProvider.future);
  return store.support();
});

/// Whether biometric unlock is currently set up. Invalidated by the service
/// after every enable/disable/cleanup.
final biometricEnabledProvider = FutureProvider<bool>((ref) async {
  final store = await ref.watch(biometricVaultKeyStoreProvider.future);
  return store.isEnabled();
});

final biometricUnlockServiceProvider = Provider<BiometricUnlockService>(
  (ref) => BiometricUnlockService(ref),
);

/// One-shot flag: set by SetupScreen right before creating the vault so the
/// first unlocked screen can offer to enable biometric unlock.
final offerBiometricSetupProvider = StateProvider<bool>((ref) => false);
