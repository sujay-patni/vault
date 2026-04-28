import 'dart:io';
import 'dart:typed_data';

import 'package:file_picker/file_picker.dart';

/// Result of an export attempt. [savedPath] is null when the user cancelled
/// the system file picker.
class BackupExportResult {
  BackupExportResult({this.savedPath});
  final String? savedPath;
  bool get cancelled => savedPath == null;
}

/// Lets the user pick a destination via the Android Storage Access Framework
/// and writes [vaultBytes] there. The vault file format is identical to the
/// app-internal vault.bin — the backup is byte-for-byte the same.
Future<BackupExportResult> exportBackup({
  required Uint8List vaultBytes,
  String? suggestedFileName,
}) async {
  final fileName = suggestedFileName ?? _defaultFileName();
  final path = await FilePicker.platform.saveFile(
    dialogTitle: 'Export Vault backup',
    fileName: fileName,
    bytes: vaultBytes,
  );
  return BackupExportResult(savedPath: path);
}

/// Lets the user pick a `.pmvault` file via SAF and returns its bytes.
/// Returns null if the picker was cancelled.
Future<Uint8List?> pickBackupFile() async {
  final result = await FilePicker.platform.pickFiles(
    dialogTitle: 'Choose Vault backup',
    type: FileType.any,
    withData: true,
  );
  if (result == null || result.files.isEmpty) return null;
  final picked = result.files.first;
  if (picked.bytes != null) return picked.bytes!;
  if (picked.path != null) {
    return Uint8List.fromList(await File(picked.path!).readAsBytes());
  }
  return null;
}

String _defaultFileName() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'vault-${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}.pmvault';
}
