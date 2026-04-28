import 'dart:typed_data';

import 'package:cryptography/cryptography.dart';

/// AES-GCM-256 wrappers that produce/consume a single concatenated
/// `ciphertext || tag(16)` byte sequence — easier to serialize than
/// the package's split SecretBox shape.
class AesGcm256 {
  AesGcm256._(this._cipher);

  final AesGcm _cipher;

  static AesGcm256 instance = AesGcm256._(AesGcm.with256bits());

  static const int nonceLength = 12;
  static const int tagLength = 16;
  static const int keyLength = 32;

  /// Encrypts [plaintext] under [key] with the given 12-byte [nonce].
  /// Optional [aad] is authenticated but not encrypted — tampering with the
  /// AAD bytes will cause [decrypt] to fail.
  /// Returns `ciphertext || tag` (length = plaintext.length + 16).
  Future<Uint8List> encrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List plaintext,
    List<int> aad = const <int>[],
  }) async {
    _checkLengths(key: key, nonce: nonce);
    final box = await _cipher.encrypt(
      plaintext,
      secretKey: SecretKey(key),
      nonce: nonce,
      aad: aad,
    );
    final out = Uint8List(box.cipherText.length + tagLength);
    out.setRange(0, box.cipherText.length, box.cipherText);
    out.setRange(box.cipherText.length, out.length, box.mac.bytes);
    return out;
  }

  /// Decrypts a `ciphertext || tag` blob produced by [encrypt].
  /// [aad] must match what was used during encryption, byte for byte.
  /// Throws [SecretBoxAuthenticationError] if the tag does not verify.
  Future<Uint8List> decrypt({
    required Uint8List key,
    required Uint8List nonce,
    required Uint8List ciphertextWithTag,
    List<int> aad = const <int>[],
  }) async {
    _checkLengths(key: key, nonce: nonce);
    if (ciphertextWithTag.length < tagLength) {
      throw ArgumentError('ciphertext shorter than GCM tag');
    }
    final ctLen = ciphertextWithTag.length - tagLength;
    final cipherText = Uint8List.sublistView(ciphertextWithTag, 0, ctLen);
    final mac = Mac(Uint8List.sublistView(ciphertextWithTag, ctLen));
    final box = SecretBox(cipherText, nonce: nonce, mac: mac);
    final clear = await _cipher.decrypt(
      box,
      secretKey: SecretKey(key),
      aad: aad,
    );
    return Uint8List.fromList(clear);
  }

  void _checkLengths({required Uint8List key, required Uint8List nonce}) {
    if (key.length != keyLength) {
      throw ArgumentError('AES-GCM-256 requires a $keyLength-byte key');
    }
    if (nonce.length != nonceLength) {
      throw ArgumentError('AES-GCM nonce must be $nonceLength bytes');
    }
  }
}

/// Cryptographically strong random bytes from the package's secure RNG.
Uint8List randomBytes(int n) {
  final random = SecretKeyData.random(length: n);
  return Uint8List.fromList(random.bytes);
}
