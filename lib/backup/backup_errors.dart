String describeBackupFormatError(FormatException e) {
  final message = e.message.toLowerCase();
  if (message.contains('unsupported vault version')) {
    return 'Import failed: this backup was created by an unsupported Vault version.';
  }
  if (message.contains('bad magic')) {
    return 'Import failed: this does not look like a Vault backup file.';
  }
  return 'Import failed: the backup file is incomplete or malformed.';
}
