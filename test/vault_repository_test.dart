import 'dart:io';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/crypto/vault_crypto.dart';
import 'package:pwm/vault/vault_entry.dart';
import 'package:pwm/vault/vault_repository.dart';

const _fastParams = Argon2idParams(
  memoryKib: 1024,
  iterations: 2,
  parallelism: 2,
  hashLength: 32,
);

VaultEntry _entry({String title = 'gmail', String password = 's3cr3t'}) {
  final now = DateTime.now();
  return VaultEntry(
    id: VaultEntry.newId(),
    title: title,
    username: 'me@example.com',
    password: password,
    url: 'https://mail.google.com',
    notes: '',
    tags: const ['email', 'personal'],
    favorite: true,
    createdAt: now,
    updatedAt: now,
  );
}

void main() {
  late Directory tmp;
  late VaultRepository repo;

  setUp(() async {
    tmp = await Directory.systemTemp.createTemp('vault_repo_test_');
    repo = VaultRepository(vaultFile: File('${tmp.path}/vault.bin'));
  });

  tearDown(() async {
    if (await tmp.exists()) await tmp.delete(recursive: true);
  });

  test('exists() reflects file presence', () async {
    expect(await repo.exists(), isFalse);
    await repo.create(
      masterPasswordUtf8: passwordToUtf8Bytes('pw'),
      params: _fastParams,
    );
    expect(await repo.exists(), isTrue);
  });

  test('create then unlock with same password yields empty entries', () async {
    final pw = passwordToUtf8Bytes('pw');
    await repo.create(masterPasswordUtf8: pw, params: _fastParams);
    final unlocked = await repo.unlock(masterPasswordUtf8: pw);
    expect(unlocked.entries, isEmpty);
    expect(unlocked.vaultKey.length, 32);
  });

  test('saveEntries persists across unlock', () async {
    final pw = passwordToUtf8Bytes('pw');
    var u = await repo.create(masterPasswordUtf8: pw, params: _fastParams);
    final e1 = _entry(title: 'a');
    final e2 = _entry(title: 'b');
    u = await repo.saveEntries(current: u, entries: [e1, e2]);
    expect(u.entries.map((e) => e.title), containsAll(['a', 'b']));

    // Re-read from disk via a fresh repo instance.
    final repo2 = VaultRepository(vaultFile: File('${tmp.path}/vault.bin'));
    final reopened = await repo2.unlock(masterPasswordUtf8: pw);
    expect(reopened.entries.map((e) => e.title), containsAll(['a', 'b']));
    expect(reopened.entries.map((e) => e.id), containsAll([e1.id, e2.id]));
  });

  test('changePassword: new password unlocks, old does not', () async {
    final oldPw = passwordToUtf8Bytes('old-pw');
    final newPw = passwordToUtf8Bytes('new-pw');
    var u = await repo.create(masterPasswordUtf8: oldPw, params: _fastParams);
    u = await repo.saveEntries(current: u, entries: [_entry()]);

    await repo.changePassword(
      current: u,
      newMasterPasswordUtf8: newPw,
      params: _fastParams,
    );

    // Fresh repo instance to ensure we read the rewritten file.
    final repo2 = VaultRepository(vaultFile: File('${tmp.path}/vault.bin'));
    final reopened = await repo2.unlock(masterPasswordUtf8: newPw);
    expect(reopened.entries.length, 1);

    expect(
      () => repo2.unlock(masterPasswordUtf8: oldPw),
      throwsA(isA<Object>()),
    );
  });

  test('wrong password on unlock throws', () async {
    final pw = passwordToUtf8Bytes('right');
    await repo.create(masterPasswordUtf8: pw, params: _fastParams);
    expect(
      () => repo.unlock(masterPasswordUtf8: passwordToUtf8Bytes('wrong')),
      throwsA(isA<Object>()),
    );
  });

  test('VaultEntry round-trips through JSON', () {
    final e = _entry(title: 'json-test', password: 'p@ss');
    final j = e.toJson();
    final back = VaultEntry.fromJson(j);
    expect(back.id, e.id);
    expect(back.title, e.title);
    expect(back.itemType, VaultItemType.password);
    expect(back.password, e.password);
    expect(back.tags, e.tags);
    expect(back.favorite, isTrue);
    expect(
      back.createdAt.millisecondsSinceEpoch,
      e.createdAt.millisecondsSinceEpoch,
    );
    expect(
      back.updatedAt.millisecondsSinceEpoch,
      e.updatedAt.millisecondsSinceEpoch,
    );
  });

  test('VaultEntry reads old JSON without tags or favorite', () {
    final now = DateTime.now();
    final back = VaultEntry.fromJson({
      'id': 'abc',
      'title': 'old',
      'username': 'me',
      'password': 'pw',
      'url': '',
      'notes': '',
      'createdAt': now.millisecondsSinceEpoch,
      'updatedAt': now.millisecondsSinceEpoch,
    });
    expect(back.itemType, VaultItemType.password);
    expect(back.tags, isEmpty);
    expect(back.favorite, isFalse);
  });

  test('VaultEntry round-trips typed secure note fields', () {
    final now = DateTime.now();
    final e = VaultEntry(
      id: 'note-id',
      itemType: VaultItemType.secureNote,
      title: 'Locker combo',
      username: '',
      password: '',
      url: '',
      notes: 'Top shelf',
      fields: const {'body': 'Top shelf'},
      tags: const ['personal', 'codes'],
      favorite: false,
      createdAt: now,
      updatedAt: now,
    );
    final back = VaultEntry.fromJson(e.toJson());
    expect(back.itemType, VaultItemType.secureNote);
    expect(back.fields['body'], 'Top shelf');
    expect(back.tags, ['personal', 'codes']);
  });

  test('VaultEntry.newId yields distinct hex IDs', () {
    final ids = <String>{};
    for (var i = 0; i < 50; i++) {
      ids.add(VaultEntry.newId());
    }
    expect(ids.length, 50);
    for (final id in ids) {
      expect(id.length, 32);
      expect(RegExp(r'^[0-9a-f]+$').hasMatch(id), isTrue);
    }
  });
}
