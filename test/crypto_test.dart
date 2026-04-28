import 'dart:convert';
import 'dart:typed_data';

import 'package:flutter_test/flutter_test.dart';
import 'package:pwm/crypto/aes_gcm.dart';
import 'package:pwm/crypto/argon2.dart';
import 'package:pwm/crypto/secure_bytes.dart';

void main() {
  group('AES-GCM-256', () {
    test('round-trip encrypt/decrypt recovers plaintext', () async {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('hello, vault'));

      final ct = await AesGcm256.instance.encrypt(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
      );
      expect(ct.length, plaintext.length + 16);

      final pt = await AesGcm256.instance.decrypt(
        key: key,
        nonce: nonce,
        ciphertextWithTag: ct,
      );
      expect(pt, equals(plaintext));
    });

    test('rejects ciphertext when a single byte is flipped', () async {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('tamper-me'));

      final ct = await AesGcm256.instance.encrypt(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
      );
      ct[0] ^= 0x01;
      expect(
        () => AesGcm256.instance.decrypt(
          key: key,
          nonce: nonce,
          ciphertextWithTag: ct,
        ),
        throwsA(isA<Object>()),
      );
    });

    test('rejects ciphertext when the tag is flipped', () async {
      final key = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('tamper-tag'));

      final ct = await AesGcm256.instance.encrypt(
        key: key,
        nonce: nonce,
        plaintext: plaintext,
      );
      ct[ct.length - 1] ^= 0x01;
      expect(
        () => AesGcm256.instance.decrypt(
          key: key,
          nonce: nonce,
          ciphertextWithTag: ct,
        ),
        throwsA(isA<Object>()),
      );
    });

    test('rejects ciphertext under wrong key', () async {
      final keyA = randomBytes(32);
      final keyB = randomBytes(32);
      final nonce = randomBytes(12);
      final plaintext = Uint8List.fromList(utf8.encode('wrong-key'));

      final ct = await AesGcm256.instance.encrypt(
        key: keyA,
        nonce: nonce,
        plaintext: plaintext,
      );
      expect(
        () => AesGcm256.instance.decrypt(
          key: keyB,
          nonce: nonce,
          ciphertextWithTag: ct,
        ),
        throwsA(isA<Object>()),
      );
    });

    test('encrypt validates key/nonce sizes', () async {
      expect(
        () => AesGcm256.instance.encrypt(
          key: Uint8List(16),
          nonce: Uint8List(12),
          plaintext: Uint8List(0),
        ),
        throwsArgumentError,
      );
      expect(
        () => AesGcm256.instance.encrypt(
          key: Uint8List(32),
          nonce: Uint8List(8),
          plaintext: Uint8List(0),
        ),
        throwsArgumentError,
      );
    });
  });

  group('Argon2id', () {
    // Fast params keep the test suite snappy. Production parameters are
    // exercised manually; correctness here is about parameter wiring and
    // determinism — not security strength.
    const fast = Argon2idParams(
      memoryKib: 1024,
      iterations: 2,
      parallelism: 2,
      hashLength: 32,
    );

    test('same password + salt + params → same key (deterministic)', () async {
      final password = Uint8List.fromList(
        utf8.encode('correct horse battery staple'),
      );
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));

      final k1 = await argon2idDerive(
        password: password,
        salt: salt,
        params: fast,
      );
      final k2 = await argon2idDerive(
        password: password,
        salt: salt,
        params: fast,
      );
      expect(k1, equals(k2));
      expect(k1.length, 32);
    });

    test('different salt → different key', () async {
      final password = Uint8List.fromList(utf8.encode('hunter2'));
      final saltA = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final saltB = Uint8List.fromList(List<int>.generate(16, (i) => i + 1));

      final kA = await argon2idDerive(
        password: password,
        salt: saltA,
        params: fast,
      );
      final kB = await argon2idDerive(
        password: password,
        salt: saltB,
        params: fast,
      );
      expect(kA, isNot(equals(kB)));
    });

    test('different password → different key', () async {
      final salt = Uint8List.fromList(List<int>.generate(16, (i) => i));
      final kA = await argon2idDerive(
        password: Uint8List.fromList(utf8.encode('hunter2')),
        salt: salt,
        params: fast,
      );
      final kB = await argon2idDerive(
        password: Uint8List.fromList(utf8.encode('hunter3')),
        salt: salt,
        params: fast,
      );
      expect(kA, isNot(equals(kB)));
    });

    test('respects requested hash length', () async {
      final password = Uint8List.fromList(utf8.encode('len-test'));
      final salt = Uint8List(16);
      final k = await argon2idDerive(
        password: password,
        salt: salt,
        params: const Argon2idParams(
          memoryKib: 1024,
          iterations: 2,
          parallelism: 2,
          hashLength: 64,
        ),
      );
      expect(k.length, 64);
    });
  });

  group('SecureZero', () {
    test('zeros all bytes', () {
      final b = Uint8List.fromList([1, 2, 3, 4, 5]);
      b.secureZero();
      expect(b, equals(Uint8List(5)));
    });
  });

  group('constantTimeEquals', () {
    test('equal same-length sequences', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 3]), isTrue);
    });

    test('different sequences', () {
      expect(constantTimeEquals([1, 2, 3], [1, 2, 4]), isFalse);
    });

    test('different lengths', () {
      expect(constantTimeEquals([1, 2], [1, 2, 3]), isFalse);
    });
  });
}
