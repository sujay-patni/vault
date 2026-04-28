import 'dart:io';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/vault/vault_file.dart';

VaultBlob _sampleBlob({Uint8List? payload}) {
  return VaultBlob(
    salt: Uint8List.fromList(List<int>.generate(16, (i) => i)),
    argonParams: const Argon2idParams(
      memoryKib: 65536,
      iterations: 3,
      parallelism: 4,
    ),
    wrapIv: Uint8List.fromList(List<int>.generate(12, (i) => 0x10 + i)),
    wrappedVaultKey: Uint8List.fromList(
      List<int>.generate(48, (i) => 0x20 + i),
    ),
    payloadIv: Uint8List.fromList(List<int>.generate(12, (i) => 0x30 + i)),
    payload:
        payload ?? Uint8List.fromList(List<int>.generate(64, (i) => i + 0x40)),
  );
}

void main() {
  group('VaultBlob', () {
    test('toBytes -> fromBytes round-trip', () {
      final original = _sampleBlob();
      final bytes = original.toBytes();
      final parsed = VaultBlob.fromBytes(bytes);

      expect(parsed.salt, equals(original.salt));
      expect(parsed.argonParams.memoryKib, original.argonParams.memoryKib);
      expect(parsed.argonParams.iterations, original.argonParams.iterations);
      expect(parsed.argonParams.parallelism, original.argonParams.parallelism);
      expect(parsed.wrapIv, equals(original.wrapIv));
      expect(parsed.wrappedVaultKey, equals(original.wrappedVaultKey));
      expect(parsed.payloadIv, equals(original.payloadIv));
      expect(parsed.payload, equals(original.payload));
    });

    test(
      'headerForAad length matches headerLen and equals first headerLen bytes',
      () {
        final blob = _sampleBlob();
        final aad = blob.headerForAad();
        final full = blob.toBytes();
        expect(aad.length, VaultBlob.headerLen);
        expect(
          aad,
          equals(Uint8List.sublistView(full, 0, VaultBlob.headerLen)),
        );
      },
    );

    test('rejects bad magic', () {
      final bytes = _sampleBlob().toBytes();
      bytes[0] = 0x00;
      expect(() => VaultBlob.fromBytes(bytes), throwsFormatException);
    });

    test('rejects unsupported version', () {
      final bytes = _sampleBlob().toBytes();
      bytes[4] = 99;
      expect(() => VaultBlob.fromBytes(bytes), throwsFormatException);
    });

    test('rejects truncated file', () {
      final bytes = _sampleBlob().toBytes();
      final truncated = Uint8List.sublistView(bytes, 0, bytes.length - 5);
      expect(() => VaultBlob.fromBytes(truncated), throwsFormatException);
    });

    test('rejects when payload_len does not match remaining bytes', () {
      final blob = _sampleBlob();
      final bytes = blob.toBytes();
      // Tamper with the payload_len field (last 4 bytes of header).
      bytes[VaultBlob.headerLen - 1] = 0xFF;
      expect(() => VaultBlob.fromBytes(bytes), throwsFormatException);
    });

    test('handles 0-byte payload', () {
      final blob = _sampleBlob(payload: Uint8List(0));
      final bytes = blob.toBytes();
      final parsed = VaultBlob.fromBytes(bytes);
      expect(parsed.payload.length, 0);
    });
  });

  group('atomicWrite', () {
    late Directory tmpDir;

    setUp(() async {
      tmpDir = await Directory.systemTemp.createTemp('vault_file_test_');
    });

    tearDown(() async {
      if (await tmpDir.exists()) {
        await tmpDir.delete(recursive: true);
      }
    });

    test('creates target file with given bytes', () async {
      final target = File('${tmpDir.path}/vault.bin');
      final bytes = Uint8List.fromList(List<int>.generate(128, (i) => i));
      await atomicWrite(target, bytes);
      expect(await target.exists(), isTrue);
      expect(await target.readAsBytes(), equals(bytes));
    });

    test('overwrites existing file atomically', () async {
      final target = File('${tmpDir.path}/vault.bin');
      await target.writeAsBytes([1, 2, 3]);
      final newBytes = Uint8List.fromList(
        List<int>.generate(64, (i) => i + 100),
      );
      await atomicWrite(target, newBytes);
      expect(await target.readAsBytes(), equals(newBytes));
      // Tmp file should not be lingering.
      expect(await File('${target.path}.tmp').exists(), isFalse);
    });
  });
}
