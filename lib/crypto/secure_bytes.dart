import 'dart:typed_data';

extension SecureZero on Uint8List {
  /// Best-effort overwrite of the underlying buffer with zeros.
  /// Cannot prevent the GC from having moved copies elsewhere; meant only
  /// to reduce the window in which key material is recoverable from heap.
  void secureZero() {
    for (var i = 0; i < length; i++) {
      this[i] = 0;
    }
  }
}

/// Constant-time equality check for two byte sequences of equal length.
/// Returns false immediately if lengths differ; otherwise compares all bytes
/// without short-circuiting on a mismatch.
bool constantTimeEquals(List<int> a, List<int> b) {
  if (a.length != b.length) return false;
  var diff = 0;
  for (var i = 0; i < a.length; i++) {
    diff |= a[i] ^ b[i];
  }
  return diff == 0;
}
