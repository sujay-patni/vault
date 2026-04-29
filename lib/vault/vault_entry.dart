import '../crypto/aes_gcm.dart';
import 'vault_attachment.dart';

enum VaultItemType {
  password('password', 'Passwords'),
  secureNote('secureNote', 'Notes'),
  paymentCard('paymentCard', 'Cards'),
  identity('identity', 'IDs'),
  recoveryCodes('recoveryCodes', 'Codes'),
  apiKey('apiKey', 'Keys'),
  wifi('wifi', 'Wi-Fi'),
  finance('finance', 'Finance');

  const VaultItemType(this.storageKey, this.label);

  final String storageKey;
  final String label;

  static VaultItemType fromStorageKey(String? value) {
    for (final type in values) {
      if (type.storageKey == value) return type;
    }
    return VaultItemType.password;
  }
}

/// One encrypted vault item. The legacy password fields stay top-level so old
/// vault payloads keep loading; newer item-type-specific fields live in
/// [fields].
class VaultEntry {
  const VaultEntry({
    required this.id,
    this.itemType = VaultItemType.password,
    required this.title,
    required this.username,
    required this.password,
    required this.url,
    required this.notes,
    this.fields = const {},
    this.tags = const [],
    this.favorite = false,
    this.attachments = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  final String id;
  final VaultItemType itemType;
  final String title;
  final String username;
  final String password;
  final String url;
  final String notes;
  final Map<String, String> fields;
  final List<String> tags;
  final bool favorite;
  final List<VaultAttachment> attachments;
  final DateTime createdAt;
  final DateTime updatedAt;

  VaultEntry copyWith({
    VaultItemType? itemType,
    String? title,
    String? username,
    String? password,
    String? url,
    String? notes,
    Map<String, String>? fields,
    List<String>? tags,
    bool? favorite,
    List<VaultAttachment>? attachments,
    DateTime? updatedAt,
  }) {
    return VaultEntry(
      id: id,
      itemType: itemType ?? this.itemType,
      title: title ?? this.title,
      username: username ?? this.username,
      password: password ?? this.password,
      url: url ?? this.url,
      notes: notes ?? this.notes,
      fields: fields ?? this.fields,
      tags: tags ?? this.tags,
      favorite: favorite ?? this.favorite,
      attachments: attachments ?? this.attachments,
      createdAt: createdAt,
      updatedAt: updatedAt ?? this.updatedAt,
    );
  }

  Map<String, dynamic> toJson() => {
    'id': id,
    'itemType': itemType.storageKey,
    'title': title,
    'username': username,
    'password': password,
    'url': url,
    'notes': notes,
    'fields': fields,
    'tags': tags,
    'favorite': favorite,
    'attachments': attachments.map((a) => a.toJson()).toList(),
    'createdAt': createdAt.millisecondsSinceEpoch,
    'updatedAt': updatedAt.millisecondsSinceEpoch,
  };

  factory VaultEntry.fromJson(Map<String, dynamic> json) {
    final rawTags = json['tags'];
    final rawFields = json['fields'];
    final rawAttachments = json['attachments'];
    return VaultEntry(
      id: json['id'] as String,
      itemType: VaultItemType.fromStorageKey(json['itemType'] as String?),
      title: json['title'] as String? ?? '',
      username: json['username'] as String? ?? '',
      password: json['password'] as String? ?? '',
      url: json['url'] as String? ?? '',
      notes: json['notes'] as String? ?? '',
      fields: rawFields is Map
          ? rawFields.map(
              (key, value) => MapEntry(key.toString(), value.toString()),
            )
          : const {},
      tags: rawTags is List
          ? rawTags.whereType<String>().toList(growable: false)
          : const [],
      favorite: json['favorite'] as bool? ?? false,
      attachments: rawAttachments is List
          ? rawAttachments
                .whereType<Map>()
                .map(
                  (raw) => VaultAttachment.fromJson(
                    raw.map((key, value) => MapEntry(key.toString(), value)),
                  ),
                )
                .toList(growable: false)
          : const [],
      createdAt: DateTime.fromMillisecondsSinceEpoch(json['createdAt'] as int),
      updatedAt: DateTime.fromMillisecondsSinceEpoch(json['updatedAt'] as int),
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
