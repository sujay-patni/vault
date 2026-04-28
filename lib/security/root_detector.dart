import 'dart:io';

import 'package:flutter/foundation.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// File-system markers that indicate root/Magisk on Android. Hidden roots
/// can defeat this — we use it only for an advisory banner, never to refuse
/// to run.
const List<String> _suspiciousPaths = [
  '/system/bin/su',
  '/system/xbin/su',
  '/sbin/su',
  '/system/app/Superuser.apk',
  '/system/app/SuperSU.apk',
  '/data/local/xbin/su',
  '/data/local/bin/su',
  '/data/local/su',
  '/su/bin/su',
];

bool _isAndroid() {
  if (kIsWeb) return false;
  try {
    return Platform.isAndroid;
  } catch (_) {
    return false;
  }
}

/// True if any well-known root indicator is present on the filesystem.
final rootedDeviceProvider = FutureProvider<bool>((ref) async {
  if (!_isAndroid()) return false;
  for (final path in _suspiciousPaths) {
    try {
      if (await File(path).exists()) return true;
    } catch (_) {
      // SecurityException etc. — skip and keep checking.
    }
  }
  return false;
});
