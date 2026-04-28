import 'dart:typed_data';

import 'package:cryptography/cryptography.dart' as c;

/// Argon2id parameters used to derive the master key.
///
/// These values follow RFC 9106's "second recommended option" for
/// interactive logins on memory-constrained devices: 64 MiB of memory,
/// 3 iterations, 4 lanes. Aim is ~1 second on a modern phone.
class Argon2idParams {
  const Argon2idParams({
    this.memoryKib = 65536,
    this.iterations = 3,
    this.parallelism = 4,
    this.hashLength = 32,
  });

  final int memoryKib;
  final int iterations;
  final int parallelism;
  final int hashLength;

  static const Argon2idParams defaults = Argon2idParams();
}

/// Derive a fixed-length key from a password and salt using Argon2id.
/// [password] should be the UTF-8 bytes of the master password.
/// [salt] should be 16+ random bytes, stored alongside the wrapped key.
Future<Uint8List> argon2idDerive({
  required Uint8List password,
  required Uint8List salt,
  Argon2idParams params = Argon2idParams.defaults,
}) async {
  final kdf = c.Argon2id(
    parallelism: params.parallelism,
    memory: params.memoryKib,
    iterations: params.iterations,
    hashLength: params.hashLength,
  );
  final key = await kdf.deriveKey(
    secretKey: c.SecretKey(password),
    nonce: salt,
  );
  final bytes = await key.extractBytes();
  return Uint8List.fromList(bytes);
}
