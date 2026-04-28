@Tags(['slow'])
library;

import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/crypto/vault_crypto.dart';
import 'package:pwm/vault/vault_file.dart';

void main() {
  test(
    'Argon2id production params perf (host, pure-Dart)',
    () async {
      final password = Uint8List.fromList(
        utf8.encode('correct horse battery staple'),
      );
      final salt = Uint8List(16);
      final stopwatch = Stopwatch()..start();
      await argon2idDerive(
        password: password,
        salt: salt,
        params: Argon2idParams.defaults,
      );
      stopwatch.stop();
      // ignore: avoid_print
      print(
        'Argon2id (mem=64MiB, iter=3, par=4) on host: '
        '${stopwatch.elapsedMilliseconds} ms',
      );
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );

  test(
    'full vault round-trip with production Argon2id params',
    () async {
      // This is the most important test for catching parameter
      // misserialization: a real first-launch vault is created with
      // Argon2idParams.defaults, persisted to bytes, parsed back, and unlocked.
      // If the params field were mis-serialized in VaultBlob, the user's vault
      // would be permanently unrecoverable — and only this test would catch it,
      // since the fast-param tests use a different Argon2id config entirely.
      const crypto = VaultCrypto();
      final pw = Uint8List.fromList(utf8.encode('production-params-test'));
      final entries = Uint8List.fromList(utf8.encode('[{"title":"prod"}]'));

      final blob = await crypto.create(
        masterPasswordUtf8: pw,
        entriesJsonBytes: entries,
        // Argon2idParams.defaults is the real first-launch configuration.
      );
      expect(blob.argonParams.memoryKib, 65536);
      expect(blob.argonParams.iterations, 3);
      expect(blob.argonParams.parallelism, 4);

      // Round-trip through bytes — exercises the binary format too.
      final reparsed = VaultBlob.fromBytes(blob.toBytes());
      expect(reparsed.argonParams.memoryKib, 65536);
      expect(reparsed.argonParams.iterations, 3);
      expect(reparsed.argonParams.parallelism, 4);

      final unlocked = await crypto.unlock(
        masterPasswordUtf8: pw,
        blob: reparsed,
      );
      expect(unlocked.entriesJsonBytes, equals(entries));
    },
    timeout: const Timeout(Duration(minutes: 2)),
  );
}
