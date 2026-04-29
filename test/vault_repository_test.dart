import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/crypto/vault_crypto.dart';
import 'package:pwm/vault/vault_attachment.dart';
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

VaultAttachment _attachment({
  String fileName = 'id.png',
  List<int> bytes = const [0, 1, 2, 3, 254, 255],
}) {
  return VaultAttachment.fromBytes(
    fileName: fileName,
    bytes: Uint8List.fromList(bytes),
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

  test('saveEntries persists attachment bytes across unlock', () async {
    final pw = passwordToUtf8Bytes('pw');
    var u = await repo.create(masterPasswordUtf8: pw, params: _fastParams);
    final attachment = _attachment(bytes: [0, 10, 20, 30, 255]);
    final entry = _entry(title: 'passport').copyWith(attachments: [attachment]);
    u = await repo.saveEntries(current: u, entries: [entry]);
    expect(u.entries.single.attachments.single.decodeBytes(), [
      0,
      10,
      20,
      30,
      255,
    ]);

    final repo2 = VaultRepository(vaultFile: File('${tmp.path}/vault.bin'));
    final reopened = await repo2.unlock(masterPasswordUtf8: pw);
    final reopenedAttachment = reopened.entries.single.attachments.single;
    expect(reopenedAttachment.fileName, 'id.png');
    expect(reopenedAttachment.mimeType, 'image/png');
    expect(reopenedAttachment.decodeBytes(), [0, 10, 20, 30, 255]);
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

  test('attachments survive password rotation and backup import', () async {
    final oldPw = passwordToUtf8Bytes('old-pw');
    final newPw = passwordToUtf8Bytes('new-pw');
    var u = await repo.create(masterPasswordUtf8: oldPw, params: _fastParams);
    final entry = _entry(title: 'tax docs').copyWith(
      attachments: [
        _attachment(fileName: 'return.pdf', bytes: [9, 8, 7, 6]),
      ],
    );
    u = await repo.saveEntries(current: u, entries: [entry]);

    await repo.changePassword(
      current: u,
      newMasterPasswordUtf8: newPw,
      params: _fastParams,
    );

    final backupBytes = await repo.readRawBytes();
    final importedFile = File('${tmp.path}/imported.bin');
    final importedRepo = VaultRepository(vaultFile: importedFile);
    final imported = await importedRepo.importBackup(
      masterPasswordUtf8: newPw,
      bytes: backupBytes,
    );

    expect(imported.entries.single.attachments.single.fileName, 'return.pdf');
    expect(imported.entries.single.attachments.single.decodeBytes(), [
      9,
      8,
      7,
      6,
    ]);
    expect(
      () => importedRepo.unlock(masterPasswordUtf8: oldPw),
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
    expect(back.attachments, isEmpty);
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
    expect(back.attachments, isEmpty);
  });

  test('VaultEntry round-trips one attachment through JSON', () {
    final e = _entry(title: 'attachment-json').copyWith(
      attachments: [
        _attachment(fileName: 'scan.jpg', bytes: [1, 3, 5]),
      ],
    );
    final back = VaultEntry.fromJson(e.toJson());
    expect(back.attachments.length, 1);
    expect(back.attachments.single.fileName, 'scan.jpg');
    expect(back.attachments.single.mimeType, 'image/jpeg');
    expect(back.attachments.single.sizeBytes, 3);
    expect(back.attachments.single.decodeBytes(), [1, 3, 5]);
  });

  test('VaultEntry round-trips multiple attachments through JSON', () {
    final e = _entry(title: 'multi-attachment-json').copyWith(
      attachments: [
        _attachment(fileName: 'scan.png', bytes: [1, 2]),
        _attachment(fileName: 'note.txt', bytes: [3, 4, 5]),
      ],
    );
    final back = VaultEntry.fromJson(e.toJson());
    expect(back.attachments.map((a) => a.fileName), ['scan.png', 'note.txt']);
    expect(back.attachments[0].decodeBytes(), [1, 2]);
    expect(back.attachments[1].mimeType, 'text/plain');
    expect(back.attachments[1].decodeBytes(), [3, 4, 5]);
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
