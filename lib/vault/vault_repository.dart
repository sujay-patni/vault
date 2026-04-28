import 'dart:convert';
import 'dart:io';
import 'dart:typed_data';

import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:path_provider/path_provider.dart';

import '../crypto/argon2.dart';
import '../crypto/secure_bytes.dart';
import '../crypto/vault_crypto.dart';
import 'vault_entry.dart';
import 'vault_file.dart';
import 'vault_state.dart';

/// Filename of the on-disk vault inside the app's documents directory.
const String _vaultFileName = 'vault.bin';

/// Repository that manages the encrypted vault file and the in-memory
/// decrypted state. Mutating operations re-encrypt and atomically rewrite
/// the file before updating in-memory state, so a crash mid-operation never
/// produces an inconsistent on-disk vault.
class VaultRepository {
  VaultRepository({
    required File vaultFile,
    VaultCrypto crypto = const VaultCrypto(),
  }) : _file = vaultFile,
       _crypto = crypto;

  final File _file;
  final VaultCrypto _crypto;

  /// The most recently loaded blob — held while the vault is unlocked so we
  /// can carry forward salt/argon params/wrap on each persist.
  VaultBlob? _blob;

  Future<bool> exists() => _file.exists();

  /// Read the current encrypted vault file as bytes (for export).
  Future<Uint8List> readRawBytes() async {
    final list = await _file.readAsBytes();
    return Uint8List.fromList(list);
  }

  /// Validate [bytes] as a vault file decryptable with [masterPasswordUtf8],
  /// then atomically install it as the current vault. The unlocked session
  /// returned by this call uses the imported vault.
  Future<VaultUnlocked> importBackup({
    required Uint8List masterPasswordUtf8,
    required Uint8List bytes,
  }) async {
    final blob = VaultBlob.fromBytes(bytes);
    // Verify decryptability before touching disk.
    final unlocked = await _crypto.unlock(
      masterPasswordUtf8: masterPasswordUtf8,
      blob: blob,
    );
    await atomicWrite(_file, blob.toBytes());
    _blob = blob;
    final entries = _decodeEntries(unlocked.entriesJsonBytes);
    unlocked.entriesJsonBytes.secureZero();
    return VaultUnlocked(vaultKey: unlocked.vaultKey, entries: entries);
  }

  /// First-run: create a new empty vault on disk encrypted under
  /// [masterPasswordUtf8]. Caller is responsible for zeroing the password
  /// buffer afterwards.
  Future<VaultUnlocked> create({
    required Uint8List masterPasswordUtf8,
    Argon2idParams params = Argon2idParams.defaults,
  }) async {
    if (await _file.exists()) {
      throw StateError('vault already exists at ${_file.path}');
    }
    final entriesJson = utf8.encode('[]');
    final blob = await _crypto.create(
      masterPasswordUtf8: masterPasswordUtf8,
      entriesJsonBytes: Uint8List.fromList(entriesJson),
      params: params,
    );
    await atomicWrite(_file, blob.toBytes());
    _blob = blob;
    // Unlock immediately for the caller — they have the password in hand.
    return _unlockFromBlob(masterPasswordUtf8: masterPasswordUtf8, blob: blob);
  }

  /// Unlock an existing vault. Throws on wrong password.
  Future<VaultUnlocked> unlock({required Uint8List masterPasswordUtf8}) async {
    final bytes = await _file.readAsBytes();
    final blob = VaultBlob.fromBytes(Uint8List.fromList(bytes));
    return _unlockFromBlob(masterPasswordUtf8: masterPasswordUtf8, blob: blob);
  }

  Future<VaultUnlocked> _unlockFromBlob({
    required Uint8List masterPasswordUtf8,
    required VaultBlob blob,
  }) async {
    final result = await _crypto.unlock(
      masterPasswordUtf8: masterPasswordUtf8,
      blob: blob,
    );
    _blob = blob;
    final entries = _decodeEntries(result.entriesJsonBytes);
    result.entriesJsonBytes.secureZero();
    return VaultUnlocked(vaultKey: result.vaultKey, entries: entries);
  }

  /// Persist the given entry list. Re-encrypts under the current vault_key
  /// and atomically rewrites the file.
  Future<VaultUnlocked> saveEntries({
    required VaultUnlocked current,
    required List<VaultEntry> entries,
  }) async {
    final blob = _blob;
    if (blob == null) {
      throw StateError('no blob loaded — vault must be unlocked first');
    }
    final json = Uint8List.fromList(_encodeEntries(entries));
    final updated = await _crypto.persistEntries(
      existing: blob,
      vaultKey: current.vaultKey,
      entriesJsonBytes: json,
    );
    await atomicWrite(_file, updated.toBytes());
    _blob = updated;
    json.secureZero();
    return current.withEntries(entries);
  }

  /// Change the master password. The caller must provide the currently
  /// in-memory [VaultUnlocked] so we already have the vault_key.
  Future<VaultUnlocked> changePassword({
    required VaultUnlocked current,
    required Uint8List newMasterPasswordUtf8,
    Argon2idParams params = Argon2idParams.defaults,
  }) async {
    final json = Uint8List.fromList(_encodeEntries(current.entries));
    final rotated = await _crypto.changePassword(
      newMasterPasswordUtf8: newMasterPasswordUtf8,
      vaultKey: current.vaultKey,
      entriesJsonBytes: json,
      params: params,
    );
    await atomicWrite(_file, rotated.toBytes());
    _blob = rotated;
    json.secureZero();
    return current; // entries and vault_key unchanged
  }

  /// Forget the in-memory blob reference (called on lock).
  void forgetBlob() {
    _blob = null;
  }

  List<VaultEntry> _decodeEntries(Uint8List json) {
    final decoded = jsonDecode(utf8.decode(json));
    if (decoded is! List) {
      throw const FormatException('vault payload is not a JSON array');
    }
    return decoded
        .cast<Map<String, dynamic>>()
        .map(VaultEntry.fromJson)
        .toList(growable: false);
  }

  List<int> _encodeEntries(List<VaultEntry> entries) {
    return utf8.encode(jsonEncode(entries.map((e) => e.toJson()).toList()));
  }
}

/// Resolves the path of the vault file inside the app's private documents
/// directory. Overridden in tests.
final vaultFilePathProvider = FutureProvider<File>((ref) async {
  final dir = await getApplicationDocumentsDirectory();
  return File('${dir.path}/$_vaultFileName');
});

final vaultRepositoryProvider = FutureProvider<VaultRepository>((ref) async {
  final file = await ref.watch(vaultFilePathProvider.future);
  return VaultRepository(vaultFile: file);
});

/// Reactive top-level vault status. Drives the root router.
class VaultStatusNotifier extends StateNotifier<VaultStatus> {
  VaultStatusNotifier(this._repo) : super(const VaultLocked()) {
    _bootstrap();
  }

  final VaultRepository _repo;

  Future<void> _bootstrap() async {
    state = (await _repo.exists())
        ? const VaultLocked()
        : const VaultUninitialized();
  }

  Future<void> setupAndUnlock({required Uint8List masterPasswordUtf8}) async {
    state = await _repo.create(masterPasswordUtf8: masterPasswordUtf8);
  }

  Future<void> unlock({required Uint8List masterPasswordUtf8}) async {
    state = await _repo.unlock(masterPasswordUtf8: masterPasswordUtf8);
  }

  Future<void> saveEntries(List<VaultEntry> entries) async {
    final cur = state;
    if (cur is! VaultUnlocked) {
      throw StateError('saveEntries called while vault is not unlocked');
    }
    state = await _repo.saveEntries(current: cur, entries: entries);
  }

  Future<void> changePassword({
    required Uint8List newMasterPasswordUtf8,
  }) async {
    final cur = state;
    if (cur is! VaultUnlocked) {
      throw StateError('changePassword called while vault is not unlocked');
    }
    state = await _repo.changePassword(
      current: cur,
      newMasterPasswordUtf8: newMasterPasswordUtf8,
    );
  }

  Future<Uint8List> readRawBytes() => _repo.readRawBytes();

  Future<void> importBackup({
    required Uint8List masterPasswordUtf8,
    required Uint8List bytes,
  }) async {
    state = await _repo.importBackup(
      masterPasswordUtf8: masterPasswordUtf8,
      bytes: bytes,
    );
  }

  /// Lock: zero the vault key, drop entries from memory, drop the cached blob.
  void lock() {
    final cur = state;
    if (cur is VaultUnlocked) {
      cur.vaultKey.secureZero();
    }
    _repo.forgetBlob();
    state = const VaultLocked();
  }
}

final vaultStatusProvider =
    StateNotifierProvider<VaultStatusNotifier, VaultStatus>((ref) {
      final repoAsync = ref.watch(vaultRepositoryProvider);
      final repo = repoAsync.value;
      if (repo == null) {
        // Repository not yet ready — surface a locked state until the future
        // resolves. The UI shows a splash; callers do not act on this state.
        throw StateError('vaultRepositoryProvider not yet resolved');
      }
      return VaultStatusNotifier(repo);
    });
