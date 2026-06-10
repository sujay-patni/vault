import 'dart:io';

import 'package:file_picker/file_picker.dart';
import 'package:path_provider/path_provider.dart';

/// Platform pickers and the share sheet leave plaintext copies of vault data
/// in the app cache directory: file_picker copies picked files under
/// `<cache>/file_picker/`, share_plus stages shared files under
/// `<cache>/share_plus/`, and image_picker writes captured photos (and their
/// scaled variants) to the cache root. Those copies violate the
/// "disk holds only ciphertext" invariant, so they are removed after each
/// operation and again on every lock.
///
/// All failures are swallowed: cleanup must never break the calling flow.
Future<void> sweepSensitiveCaches() async {
  try {
    await FilePicker.platform.clearTemporaryFiles();
  } catch (_) {}
  try {
    final cache = await getTemporaryDirectory();
    await for (final entity in cache.list()) {
      final name = entity.uri.pathSegments.lastWhere(
        (s) => s.isNotEmpty,
        orElse: () => '',
      );
      final isPickerDir =
          entity is Directory && (name == 'file_picker' || name == 'share_plus');
      final isPickerFile =
          entity is File &&
          (name.startsWith('image_picker') || name.startsWith('scaled_'));
      if (isPickerDir || isPickerFile) {
        try {
          await entity.delete(recursive: true);
        } catch (_) {}
      }
    }
  } catch (_) {}
}

/// Deletes a single picker temp file, e.g. the camera capture, ignoring
/// failures.
Future<void> deleteQuietly(String? path) async {
  if (path == null) return;
  try {
    final file = File(path);
    if (await file.exists()) await file.delete();
  } catch (_) {}
}
