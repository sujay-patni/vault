import 'dart:convert';
import 'dart:typed_data';

import '../crypto/aes_gcm.dart';

const int maxAttachmentBytes = 10 * 1024 * 1024;
const int maxVaultAttachmentBytes = 50 * 1024 * 1024;

const List<String> allowedAttachmentExtensions = [
  'jpg',
  'jpeg',
  'png',
  'webp',
  'pdf',
  'txt',
  'doc',
  'docx',
  'xls',
  'xlsx',
];

class VaultAttachment {
  const VaultAttachment({
    required this.id,
    required this.fileName,
    required this.mimeType,
    required this.sizeBytes,
    required this.base64Data,
    required this.createdAt,
    this.description,
  });

  final String id;
  final String fileName;
  final String mimeType;
  final int sizeBytes;
  final String base64Data;
  final DateTime createdAt;
  final String? description;

  bool get isImage => mimeType.startsWith('image/');

  Uint8List decodeBytes() => base64Decode(base64Data);

  VaultAttachment copyWith({String? description}) {
    return VaultAttachment(
      id: id,
      fileName: fileName,
      mimeType: mimeType,
      sizeBytes: sizeBytes,
      base64Data: base64Data,
      createdAt: createdAt,
      description: description ?? this.description,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'fileName': fileName,
    'mimeType': mimeType,
    'sizeBytes': sizeBytes,
    'base64Data': base64Data,
    'createdAt': createdAt.millisecondsSinceEpoch,
    if (description != null && description!.trim().isNotEmpty)
      'description': description,
  };

  factory VaultAttachment.fromJson(Map<String, dynamic> json) {
    return VaultAttachment(
      id: json['id'] as String? ?? newId(),
      fileName: json['fileName'] as String? ?? 'attachment',
      mimeType: json['mimeType'] as String? ?? 'application/octet-stream',
      sizeBytes: json['sizeBytes'] as int? ?? 0,
      base64Data: json['base64Data'] as String? ?? '',
      createdAt: DateTime.fromMillisecondsSinceEpoch(
        json['createdAt'] as int? ?? 0,
      ),
      description: json['description'] as String?,
    );
  }

  static VaultAttachment fromBytes({
    required String fileName,
    required Uint8List bytes,
    String? mimeType,
    String? description,
  }) {
    return VaultAttachment(
      id: newId(),
      fileName: fileName,
      mimeType: mimeType ?? mimeTypeForFileName(fileName),
      sizeBytes: bytes.length,
      base64Data: base64Encode(bytes),
      createdAt: DateTime.now(),
      description: description,
    );
  }

  static String newId() {
    final bytes = randomBytes(16);
    final sb = StringBuffer();
    for (final b in bytes) {
      sb.write(b.toRadixString(16).padLeft(2, '0'));
    }
    return sb.toString();
  }
}

bool isAllowedAttachmentFileName(String fileName) {
  final ext = extensionForFileName(fileName);
  return allowedAttachmentExtensions.contains(ext);
}

String extensionForFileName(String fileName) {
  final dot = fileName.lastIndexOf('.');
  if (dot == -1 || dot == fileName.length - 1) return '';
  return fileName.substring(dot + 1).toLowerCase();
}

String mimeTypeForFileName(String fileName) {
  return switch (extensionForFileName(fileName)) {
    'jpg' || 'jpeg' => 'image/jpeg',
    'png' => 'image/png',
    'webp' => 'image/webp',
    'pdf' => 'application/pdf',
    'txt' => 'text/plain',
    'doc' => 'application/msword',
    'docx' =>
      'application/vnd.openxmlformats-officedocument.wordprocessingml.document',
    'xls' => 'application/vnd.ms-excel',
    'xlsx' =>
      'application/vnd.openxmlformats-officedocument.spreadsheetml.sheet',
    _ => 'application/octet-stream',
  };
}

String formatAttachmentSize(int bytes) {
  if (bytes < 1024) return '$bytes B';
  final kib = bytes / 1024;
  if (kib < 1024) return '${kib.toStringAsFixed(kib < 10 ? 1 : 0)} KB';
  final mib = kib / 1024;
  return '${mib.toStringAsFixed(mib < 10 ? 1 : 0)} MB';
}
