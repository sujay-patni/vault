import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:pwm/auth/biometric_store.dart';
import 'package:pwm/auth/biometric_unlock.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/crypto/vault_crypto.dart';
import 'package:pwm/vault/vault_repository.dart';
import 'package:pwm/vault/vault_state.dart';

const _fastParams = Argon2idParams(
  memoryKib: 1024,
  iterations: 2,
  parallelism: 2,
  hashLength: 32,
);

class FakeBiometricVaultKeyStore implements BiometricVaultKeyStore {
  Uint8List? stored;
  BiometricStoreException? nextReadError;
  BiometricSupport supportValue = BiometricSupport.available;
  int readCount = 0;
  int storeCount = 0;
  int clearCount = 0;

  @override
  Future<BiometricSupport> support() async => supportValue;

  @override
  Future<bool> isEnabled() async => stored != null;

  @override
  Future<void> store(Uint8List vaultKey) async {
    storeCount += 1;
    stored = Uint8List.fromList(vaultKey);
  }

  @override
  Future<Uint8List> read() async {
    readCount += 1;
    final err = nextReadError;
    if (err != null) {
      nextReadError = null;
      throw err;
    }
    final s = stored;
    if (s == null) {
      throw const BiometricStoreException(BiometricFailure.keyInvalidated);
    }
    return Uint8List.fromList(s);
  }

  @override
  Future<void> clear() async {
    clearCount += 1;
    stored = null;
  }
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();

  late Directory tmp;
  late FakeBiometricVaultKeyStore fake;
  late ProviderContainer container;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('biometric_unlock_test_');
    fake = FakeBiometricVaultKeyStore();
    container = ProviderContainer(
      overrides: [
        vaultFilePathProvider.overrideWith(
          (ref) async => File('${tmp.path}/vault.bin'),
        ),
        biometricVaultKeyStoreProvider.overrideWith((ref) async => fake),
      ],
    );
  });

  tearDown(() async {
    container.dispose();
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  /// Creates a vault with fast Argon2 params and unlocks it through the
  /// notifier (the notifier's own setup path uses production params).
  Future<void> createAndUnlock() async {
    final repo = await container.read(vaultRepositoryProvider.future);
    final pw = passwordToUtf8Bytes('pw');
    await repo.create(masterPasswordUtf8: pw, params: _fastParams);
    await container
        .read(vaultStatusProvider.notifier)
        .unlock(masterPasswordUtf8: passwordToUtf8Bytes('pw'));
  }

  BiometricUnlockService service() =>
      container.read(biometricUnlockServiceProvider);

  test('enable stores a copy of the current vault key', () async {
    await createAndUnlock();
    final unlocked = container.read(vaultStatusProvider) as VaultUnlocked;

    expect(await service().enable(), isTrue);
    expect(fake.storeCount, 1);
    expect(fake.stored, equals(unlocked.vaultKey));
    expect(identical(fake.stored, unlocked.vaultKey), isFalse);
    // Session stays unlocked and usable.
    expect(container.read(vaultStatusProvider), isA<VaultUnlocked>());
    expect(await container.read(biometricEnabledProvider.future), isTrue);
  });

  test('enable throws while locked', () async {
    final repo = await container.read(vaultRepositoryProvider.future);
    await repo.create(
      masterPasswordUtf8: passwordToUtf8Bytes('pw'),
      params: _fastParams,
    );
    expect(container.read(vaultStatusProvider), isA<VaultLocked>());
    await expectLater(service().enable(), throwsStateError);
  });

  test('attemptUnlock succeeds with the stored key', () async {
    await createAndUnlock();
    await service().enable();
    container.read(vaultStatusProvider.notifier).lock();
    expect(container.read(vaultStatusProvider), isA<VaultLocked>());

    final outcome = await service().attemptUnlock();
    expect(outcome, BiometricUnlockOutcome.success);
    expect(container.read(vaultStatusProvider), isA<VaultUnlocked>());
  });

  test('attemptUnlock maps user cancel and stays locked', () async {
    await createAndUnlock();
    await service().enable();
    container.read(vaultStatusProvider.notifier).lock();

    fake.nextReadError = const BiometricStoreException(
      BiometricFailure.userCanceled,
    );
    final outcome = await service().attemptUnlock();
    expect(outcome, BiometricUnlockOutcome.canceled);
    expect(container.read(vaultStatusProvider), isA<VaultLocked>());
    // Cancel must not throw away the stored key.
    expect(fake.stored, isNotNull);
  });

  test('attemptUnlock clears the store on key invalidation', () async {
    await createAndUnlock();
    await service().enable();
    container.read(vaultStatusProvider.notifier).lock();

    fake.nextReadError = const BiometricStoreException(
      BiometricFailure.keyInvalidated,
    );
    final outcome = await service().attemptUnlock();
    expect(outcome, BiometricUnlockOutcome.invalidated);
    expect(fake.clearCount, 1);
    expect(await container.read(biometricEnabledProvider.future), isFalse);
  });

  test('attemptUnlock keeps the key on transient failures', () async {
    await createAndUnlock();
    await service().enable();
    container.read(vaultStatusProvider.notifier).lock();

    fake.nextReadError = const BiometricStoreException(
      BiometricFailure.other,
      'lockout',
    );
    final outcome = await service().attemptUnlock();
    expect(outcome, BiometricUnlockOutcome.unavailable);
    expect(fake.clearCount, 0);
    expect(fake.stored, isNotNull);
  });

  test('attemptUnlock treats a stale key as invalidated and clears', () async {
    await createAndUnlock();
    container.read(vaultStatusProvider.notifier).lock();

    // A key that does not belong to this vault (e.g. after importing a
    // foreign backup): GCM authentication fails.
    fake.stored = Uint8List.fromList(List.generate(32, (i) => i + 1));
    final outcome = await service().attemptUnlock();
    expect(outcome, BiometricUnlockOutcome.invalidated);
    expect(fake.clearCount, 1);
    expect(fake.stored, isNull);
    expect(container.read(vaultStatusProvider), isA<VaultLocked>());
  });

  test('disable clears the store', () async {
    await createAndUnlock();
    await service().enable();
    expect(await container.read(biometricEnabledProvider.future), isTrue);

    await service().disable();
    expect(fake.stored, isNull);
    expect(await container.read(biometricEnabledProvider.future), isFalse);
  });

  test('plugin store isEnabled reflects the marker file', () async {
    final marker = File('${tmp.path}/biometric.enabled');
    final store = BiometricStorageVaultKeyStore(markerFile: marker);
    expect(await store.isEnabled(), isFalse);
    await marker.writeAsString('1');
    expect(await store.isEnabled(), isTrue);
  });
}
