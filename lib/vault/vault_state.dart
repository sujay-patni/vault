import 'dart:typed_data';

import 'vault_entry.dart';

/// Top-level vault status, used by the UI router to decide which screen
/// to show.
sealed class VaultStatus {
  const VaultStatus();
}

/// No vault file exists yet — show first-run setup.
class VaultUninitialized extends VaultStatus {
  const VaultUninitialized();
}

/// Vault file exists but is locked. UI shows the unlock screen.
class VaultLocked extends VaultStatus {
  const VaultLocked();
}

/// Vault is unlocked and entries are loaded into memory.
/// [vaultKey] must be zeroed on lock.
class VaultUnlocked extends VaultStatus {
  const VaultUnlocked({required this.vaultKey, required this.entries});

  final Uint8List vaultKey;
  final List<VaultEntry> entries;

  VaultUnlocked withEntries(List<VaultEntry> next) =>
      VaultUnlocked(vaultKey: vaultKey, entries: next);
}
