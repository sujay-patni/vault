import 'dart:io';
import 'dart:typed_data';

import '../crypto/argon2.dart';

/// Binary serialization of a vault file.
///
/// Layout (all integers are big-endian):
///
///   offset  size  field
///   0       4     magic "PMV1"
///   4       1     version (currently 1)
///   5       16    salt
///   21      4     argon_mem_kib
///   25      4     argon_iters
///   29      1     argon_parallelism
///   30      12    wrap_iv
///   42      48    wrapped_vault_key (32B key + 16B GCM tag)
///   90      12    payload_iv
///   102     4     payload_len  (length of payload ciphertext including tag)
///   106     payload_len   payload (entries JSON, AES-GCM ciphertext + tag)
///
/// The payload is encrypted with AAD = all bytes from offset 0 through 105
/// inclusive — so any tampering with the header is detected when the payload
/// is decrypted.
class VaultBlob {
  VaultBlob({
    required this.salt,
    required this.argonParams,
    required this.wrapIv,
    required this.wrappedVaultKey,
    required this.payloadIv,
    required this.payload,
  });

  static const List<int> magic = [0x50, 0x4D, 0x56, 0x31]; // "PMV1"
  static const int version = 1;

  static const int saltLen = 16;
  static const int wrapIvLen = 12;
  static const int wrappedKeyLen = 48; // 32 key + 16 tag
  static const int payloadIvLen = 12;

  /// Offset where the payload bytes begin (also the length of the AAD).
  static const int headerLen =
      4 +
      1 +
      saltLen +
      4 +
      4 +
      1 +
      wrapIvLen +
      wrappedKeyLen +
      payloadIvLen +
      4;

  final Uint8List salt;
  final Argon2idParams argonParams;
  final Uint8List wrapIv;
  final Uint8List wrappedVaultKey;
  final Uint8List payloadIv;

  /// Payload ciphertext **including** the 16-byte GCM tag.
  final Uint8List payload;

  /// The bytes that should be passed as AAD to the payload encryption.
  /// This is the entire file up to (but not including) the payload bytes.
  Uint8List headerForAad() {
    return _writeBytes(includePayload: false);
  }

  Uint8List toBytes() => _writeBytes(includePayload: true);

  Uint8List _writeBytes({required bool includePayload}) {
    if (salt.length != saltLen) {
      throw StateError('salt must be $saltLen bytes');
    }
    if (wrapIv.length != wrapIvLen) {
      throw StateError('wrapIv must be $wrapIvLen bytes');
    }
    if (wrappedVaultKey.length != wrappedKeyLen) {
      throw StateError('wrappedVaultKey must be $wrappedKeyLen bytes');
    }
    if (payloadIv.length != payloadIvLen) {
      throw StateError('payloadIv must be $payloadIvLen bytes');
    }
    final total = headerLen + (includePayload ? payload.length : 0);
    final buf = Uint8List(total);
    final view = ByteData.sublistView(buf);
    var off = 0;
    buf.setRange(off, off += magic.length, magic);
    buf[off] = version;
    off += 1;
    buf.setRange(off, off += saltLen, salt);
    view.setUint32(off, argonParams.memoryKib, Endian.big);
    off += 4;
    view.setUint32(off, argonParams.iterations, Endian.big);
    off += 4;
    buf[off] = argonParams.parallelism;
    off += 1;
    buf.setRange(off, off += wrapIvLen, wrapIv);
    buf.setRange(off, off += wrappedKeyLen, wrappedVaultKey);
    buf.setRange(off, off += payloadIvLen, payloadIv);
    view.setUint32(off, payload.length, Endian.big);
    off += 4;
    if (includePayload) {
      buf.setRange(off, off += payload.length, payload);
    }
    return buf;
  }

  static VaultBlob fromBytes(Uint8List bytes) {
    if (bytes.length < headerLen) {
      throw const FormatException('vault file truncated');
    }
    final view = ByteData.sublistView(bytes);
    var off = 0;
    for (var i = 0; i < magic.length; i++) {
      if (bytes[off + i] != magic[i]) {
        throw const FormatException('not a Vault file (bad magic)');
      }
    }
    off += magic.length;
    final v = bytes[off];
    if (v != version) {
      throw FormatException('unsupported vault version: $v');
    }
    off += 1;
    final salt = Uint8List.sublistView(bytes, off, off + saltLen);
    off += saltLen;
    final memKib = view.getUint32(off, Endian.big);
    off += 4;
    final iters = view.getUint32(off, Endian.big);
    off += 4;
    final parallelism = bytes[off];
    off += 1;
    final wrapIv = Uint8List.sublistView(bytes, off, off + wrapIvLen);
    off += wrapIvLen;
    final wrappedKey = Uint8List.sublistView(bytes, off, off + wrappedKeyLen);
    off += wrappedKeyLen;
    final payloadIv = Uint8List.sublistView(bytes, off, off + payloadIvLen);
    off += payloadIvLen;
    final payloadLen = view.getUint32(off, Endian.big);
    off += 4;
    if (bytes.length != headerLen + payloadLen) {
      throw FormatException(
        'payload length mismatch: header says $payloadLen, file has '
        '${bytes.length - headerLen}',
      );
    }
    final payload = Uint8List.sublistView(bytes, off, off + payloadLen);
    return VaultBlob(
      salt: Uint8List.fromList(salt),
      argonParams: Argon2idParams(
        memoryKib: memKib,
        iterations: iters,
        parallelism: parallelism,
      ),
      wrapIv: Uint8List.fromList(wrapIv),
      wrappedVaultKey: Uint8List.fromList(wrappedKey),
      payloadIv: Uint8List.fromList(payloadIv),
      payload: Uint8List.fromList(payload),
    );
  }
}

/// Atomic write: write to `path.tmp`, fsync, rename over `path`.
/// Rename is atomic on POSIX filesystems (Android uses ext4/f2fs).
Future<void> atomicWrite(File target, Uint8List bytes) async {
  final tmp = File('${target.path}.tmp');
  final raf = await tmp.open(mode: FileMode.write);
  try {
    await raf.writeFrom(bytes);
    await raf.flush();
  } finally {
    await raf.close();
  }
  await tmp.rename(target.path);
}
