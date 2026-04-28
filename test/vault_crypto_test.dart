import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/crypto/vault_crypto.dart';
import 'package:pwm/vault/vault_file.dart';

// Fast Argon2id params keep the suite snappy. Production params are tested
// separately in crypto_perf_test.dart.
const _fastParams = Argon2idParams(
  memoryKib: 1024,
  iterations: 2,
  parallelism: 2,
  hashLength: 32,
);

Uint8List _bytes(String s) => Uint8List.fromList(utf8.encode(s));

void main() {
  const crypto = VaultCrypto();

  group('create + unlock', () {
    test('round-trip recovers the entries payload', () async {
      final pw = _bytes('correct horse battery staple');
      final entries = _bytes(
        jsonEncode([
          {'title': 'gmail', 'password': 'secret1'},
          {'title': 'github', 'password': 'secret2'},
        ]),
      );

      final blob = await crypto.create(
        masterPasswordUtf8: pw,
        entriesJsonBytes: entries,
        params: _fastParams,
      );
      final result = await crypto.unlock(masterPasswordUtf8: pw, blob: blob);
      expect(result.entriesJsonBytes, equals(entries));
      expect(result.vaultKey.length, 32);
    });

    test('wrong password fails to unlock', () async {
      final right = _bytes('right-password');
      final wrong = _bytes('wrong-password');
      final entries = _bytes('[]');

      final blob = await crypto.create(
        masterPasswordUtf8: right,
        entriesJsonBytes: entries,
        params: _fastParams,
      );
      expect(
        () => crypto.unlock(masterPasswordUtf8: wrong, blob: blob),
        throwsA(isA<Object>()),
      );
    });

    test('round-trips through file format (toBytes -> fromBytes)', () async {
      final pw = _bytes('hunter2');
      final entries = _bytes('{"e":[]}');

      final blob = await crypto.create(
        masterPasswordUtf8: pw,
        entriesJsonBytes: entries,
        params: _fastParams,
      );
      final bytes = blob.toBytes();
      final reparsed = VaultBlob.fromBytes(bytes);
      final result = await crypto.unlock(
        masterPasswordUtf8: pw,
        blob: reparsed,
      );
      expect(result.entriesJsonBytes, equals(entries));
    });

    test(
      'header tampering causes payload decryption to fail (AAD bound)',
      () async {
        final pw = _bytes('aad-test');
        final entries = _bytes('hello');
        final blob = await crypto.create(
          masterPasswordUtf8: pw,
          entriesJsonBytes: entries,
          params: _fastParams,
        );
        final bytes = blob.toBytes();
        // Flip a byte inside the wrap_iv region — keeps the file structurally
        // valid but breaks the AAD authentication on the payload.
        // wrap_iv starts at offset 30 (4 magic + 1 ver + 16 salt + 4 + 4 + 1).
        bytes[30] ^= 0x01;
        final tampered = VaultBlob.fromBytes(bytes);
        expect(
          () => crypto.unlock(masterPasswordUtf8: pw, blob: tampered),
          throwsA(isA<Object>()),
        );
      },
    );
  });

  group('changePassword', () {
    test(
      'new password unlocks; old password rejected; entries unchanged',
      () async {
        final oldPw = _bytes('old-password');
        final newPw = _bytes('new-password');
        final entries = _bytes(
          jsonEncode([
            {'title': 'paypal', 'password': 'p@yp4l'},
          ]),
        );

        final created = await crypto.create(
          masterPasswordUtf8: oldPw,
          entriesJsonBytes: entries,
          params: _fastParams,
        );
        // First unlock to obtain the vault_key, as the change-password flow
        // would in production.
        final unlocked = await crypto.unlock(
          masterPasswordUtf8: oldPw,
          blob: created,
        );

        final rotated = await crypto.changePassword(
          newMasterPasswordUtf8: newPw,
          vaultKey: unlocked.vaultKey,
          entriesJsonBytes: unlocked.entriesJsonBytes,
          params: _fastParams,
        );

        // New password unlocks rotated blob, recovers same entries.
        final reopened = await crypto.unlock(
          masterPasswordUtf8: newPw,
          blob: rotated,
        );
        expect(reopened.entriesJsonBytes, equals(entries));

        // Old password no longer unlocks rotated blob.
        expect(
          () => crypto.unlock(masterPasswordUtf8: oldPw, blob: rotated),
          throwsA(isA<Object>()),
        );

        // Salt and wrap_iv should differ from the original (fresh randomness).
        expect(rotated.salt, isNot(equals(created.salt)));
        expect(rotated.wrapIv, isNot(equals(created.wrapIv)));
      },
    );
  });

  group('persistEntries', () {
    test('updated entries readable, salt and wrap unchanged', () async {
      final pw = _bytes('persist-test');
      final v1Entries = _bytes(jsonEncode(['a']));
      final v2Entries = _bytes(jsonEncode(['a', 'b']));

      final v1 = await crypto.create(
        masterPasswordUtf8: pw,
        entriesJsonBytes: v1Entries,
        params: _fastParams,
      );
      final unlocked = await crypto.unlock(masterPasswordUtf8: pw, blob: v1);

      final v2 = await crypto.persistEntries(
        existing: v1,
        vaultKey: unlocked.vaultKey,
        entriesJsonBytes: v2Entries,
      );

      expect(v2.salt, equals(v1.salt));
      expect(v2.wrapIv, equals(v1.wrapIv));
      expect(v2.wrappedVaultKey, equals(v1.wrappedVaultKey));
      expect(v2.payloadIv, isNot(equals(v1.payloadIv))); // fresh nonce
      expect(v2.payload, isNot(equals(v1.payload)));

      final reopened = await crypto.unlock(masterPasswordUtf8: pw, blob: v2);
      expect(reopened.entriesJsonBytes, equals(v2Entries));
    });
  });
}
