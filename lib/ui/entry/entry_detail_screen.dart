import 'dart:async';

import 'package:file_picker/file_picker.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';
import 'package:image_picker/image_picker.dart';
import 'package:share_plus/share_plus.dart';

import '../../auth/session_manager.dart';
import '../../vault/vault_attachment.dart';
import '../../vault/vault_entry.dart';
import '../../vault/vault_repository.dart';
import '../../vault/vault_state.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';
import 'entry_form_screen.dart';

const _clipboardClearAfter = Duration(seconds: 30);

class EntryDetailScreen extends ConsumerStatefulWidget {
  const EntryDetailScreen({super.key, required this.entryId});
  final String entryId;

  @override
  ConsumerState<EntryDetailScreen> createState() => _EntryDetailScreenState();
}

class _EntryDetailScreenState extends ConsumerState<EntryDetailScreen> {
  final _visibleFields = <String>{};
  Timer? _clipboardClearTimer;
  String? _lastCopiedToken;
  bool _attachmentBusy = false;

  @override
  void dispose() {
    _clipboardClearTimer?.cancel();
    super.dispose();
  }

  VaultEntry? _findEntry(VaultStatus s) {
    if (s is! VaultUnlocked) return null;
    for (final e in s.entries) {
      if (e.id == widget.entryId) return e;
    }
    return null;
  }

  Future<void> _copy(String value, String fieldLabel) async {
    if (value.isEmpty) return;
    final token = '${DateTime.now().microsecondsSinceEpoch}';
    _lastCopiedToken = token;
    await Clipboard.setData(ClipboardData(text: value));
    if (!mounted) return;
    ScaffoldMessenger.of(context)
      ..hideCurrentSnackBar()
      ..showSnackBar(
        SnackBar(
          content: Text('$fieldLabel copied. Clears in 30s.'),
          duration: const Duration(seconds: 2),
        ),
      );
    _clipboardClearTimer?.cancel();
    _clipboardClearTimer = Timer(_clipboardClearAfter, () async {
      if (_lastCopiedToken == token) {
        await Clipboard.setData(const ClipboardData(text: ''));
      }
    });
  }

  Future<void> _delete(VaultEntry entry) async {
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Delete item?'),
        content: Text('"${entry.title}" will be permanently removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Delete'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final cur = ref.read(vaultStatusProvider);
    if (cur is! VaultUnlocked) return;
    final next = cur.entries.where((e) => e.id != entry.id).toList();
    await ref.read(vaultStatusProvider.notifier).saveEntries(next);
    if (mounted) Navigator.of(context).pop();
  }

  Future<void> _toggleFavorite(VaultEntry entry) async {
    final cur = ref.read(vaultStatusProvider);
    if (cur is! VaultUnlocked) return;
    final now = DateTime.now();
    final next = cur.entries
        .map(
          (e) => e.id == entry.id
              ? e.copyWith(favorite: !entry.favorite, updatedAt: now)
              : e,
        )
        .toList();
    await ref.read(vaultStatusProvider.notifier).saveEntries(next);
  }

  int _vaultAttachmentBytesExcluding(VaultUnlocked current, String entryId) {
    return current.entries
        .where((entry) => entry.id != entryId)
        .fold<int>(
          0,
          (sum, entry) =>
              sum +
              entry.attachments.fold<int>(
                0,
                (entrySum, attachment) => entrySum + attachment.sizeBytes,
              ),
        );
  }

  Future<void> _addAttachment(VaultEntry entry) async {
    if (_attachmentBusy) return;
    final source = await showModalBottomSheet<_AttachmentSource>(
      context: context,
      showDragHandle: true,
      builder: (_) => const _AttachmentSourceSheet(),
    );
    if (!mounted || source == null) return;
    switch (source) {
      case _AttachmentSource.files:
        await _addFileAttachments(entry);
      case _AttachmentSource.camera:
        await _capturePhotoAttachment(entry);
    }
  }

  Future<void> _addFileAttachments(VaultEntry entry) async {
    final cur = ref.read(vaultStatusProvider);
    if (cur is! VaultUnlocked) return;
    final result = await ref
        .read(sessionManagerProvider)
        .runExternalPicker(
          () => FilePicker.platform.pickFiles(
            dialogTitle: 'Add attachments',
            type: FileType.custom,
            allowedExtensions: allowedAttachmentExtensions,
            allowMultiple: true,
            withData: true,
          ),
        );
    if (!mounted || result == null) return;

    var nextVaultBytes =
        _vaultAttachmentBytesExcluding(cur, entry.id) +
        entry.attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes);
    final accepted = <VaultAttachment>[];
    final rejected = <String>[];
    for (final file in result.files) {
      final bytes = file.bytes;
      if (!isAllowedAttachmentFileName(file.name)) {
        rejected.add('${file.name}: unsupported type');
        continue;
      }
      if (bytes == null) {
        rejected.add('${file.name}: could not read file');
        continue;
      }
      if (bytes.length > maxAttachmentBytes) {
        rejected.add(
          '${file.name}: over ${formatAttachmentSize(maxAttachmentBytes)}',
        );
        continue;
      }
      if (nextVaultBytes + bytes.length > maxVaultAttachmentBytes) {
        rejected.add(
          '${file.name}: vault attachment limit is '
          '${formatAttachmentSize(maxVaultAttachmentBytes)}',
        );
        continue;
      }
      nextVaultBytes += bytes.length;
      accepted.add(
        VaultAttachment.fromBytes(
          fileName: file.name,
          bytes: Uint8List.fromList(bytes),
        ),
      );
    }
    if (accepted.isEmpty) {
      if (rejected.isNotEmpty && mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(rejected.first)));
      }
      return;
    }
    final now = DateTime.now();
    final updated = entry.copyWith(
      attachments: [...entry.attachments, ...accepted],
      updatedAt: now,
    );
    final next = cur.entries
        .map((candidate) => candidate.id == entry.id ? updated : candidate)
        .toList(growable: false);
    await ref.read(vaultStatusProvider.notifier).saveEntries(next);
    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            rejected.isEmpty
                ? 'Attachment added.'
                : 'Added ${accepted.length}; skipped ${rejected.length}: '
                      '${rejected.first}',
          ),
        ),
      );
    }
  }

  Future<void> _capturePhotoAttachment(VaultEntry entry) async {
    final cur = ref.read(vaultStatusProvider);
    if (cur is! VaultUnlocked) return;
    setState(() => _attachmentBusy = true);
    try {
      final photo = await ref
          .read(sessionManagerProvider)
          .runExternalPicker(
            () => ImagePicker().pickImage(
              source: ImageSource.camera,
              maxWidth: 1280,
              maxHeight: 1280,
              imageQuality: 72,
              requestFullMetadata: false,
            ),
          );
      if (!mounted || photo == null) return;

      final bytes = await photo.readAsBytes();
      if (!mounted) return;
      if (bytes.length > maxAttachmentBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Photo is over ${formatAttachmentSize(maxAttachmentBytes)}.',
            ),
          ),
        );
        return;
      }
      final nextVaultBytes =
          _vaultAttachmentBytesExcluding(cur, entry.id) +
          entry.attachments.fold<int>(0, (sum, a) => sum + a.sizeBytes) +
          bytes.length;
      if (nextVaultBytes > maxVaultAttachmentBytes) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'Vault attachment limit is '
              '${formatAttachmentSize(maxVaultAttachmentBytes)}.',
            ),
          ),
        );
        return;
      }

      final updated = entry.copyWith(
        attachments: [
          ...entry.attachments,
          VaultAttachment.fromBytes(
            fileName: _photoFileName(),
            bytes: Uint8List.fromList(bytes),
            mimeType: 'image/jpeg',
          ),
        ],
        updatedAt: DateTime.now(),
      );
      final next = cur.entries
          .map((candidate) => candidate.id == entry.id ? updated : candidate)
          .toList(growable: false);
      await ref.read(vaultStatusProvider.notifier).saveEntries(next);
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(const SnackBar(content: Text('Photo attached.')));
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Photo capture failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _attachmentBusy = false);
    }
  }

  Future<void> _deleteAttachment(
    VaultEntry entry,
    VaultAttachment attachment,
  ) async {
    final cur = ref.read(vaultStatusProvider);
    if (cur is! VaultUnlocked) return;
    final ok = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Remove attachment?'),
        content: Text('"${attachment.fileName}" will be removed.'),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Remove'),
          ),
        ],
      ),
    );
    if (!mounted || ok != true) return;
    final updated = entry.copyWith(
      attachments: entry.attachments
          .where((item) => item.id != attachment.id)
          .toList(growable: false),
      updatedAt: DateTime.now(),
    );
    final next = cur.entries
        .map((candidate) => candidate.id == entry.id ? updated : candidate)
        .toList(growable: false);
    await ref.read(vaultStatusProvider.notifier).saveEntries(next);
  }

  Future<void> _exportAttachment(VaultAttachment attachment) async {
    final path = await ref
        .read(sessionManagerProvider)
        .runExternalPicker(
          () => FilePicker.platform.saveFile(
            dialogTitle: 'Export attachment',
            fileName: attachment.fileName,
            bytes: attachment.decodeBytes(),
          ),
        );
    if (!mounted) return;
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(path == null ? 'Export cancelled.' : 'Attachment saved.'),
      ),
    );
  }

  Future<void> _shareAttachment(VaultAttachment attachment) async {
    await ref
        .read(sessionManagerProvider)
        .runExternalPicker(
          () => SharePlus.instance.share(
            ShareParams(
              title: attachment.fileName,
              files: [
                XFile.fromData(
                  attachment.decodeBytes(),
                  name: attachment.fileName,
                  mimeType: attachment.mimeType,
                ),
              ],
              fileNameOverrides: [attachment.fileName],
            ),
          ),
        );
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(vaultStatusProvider);
    if (status is! VaultUnlocked) {
      return _UnavailableEntryScreen(
        title: 'Vault locked',
        message: 'Unlock the vault to view this item again.',
        buttonLabel: 'Back to unlock',
        onBack: () => Navigator.of(context).popUntil((route) => route.isFirst),
      );
    }
    final entry = _findEntry(status);
    if (entry == null) {
      return _UnavailableEntryScreen(
        title: 'Item not found',
        message: 'This item is no longer available in the unlocked vault.',
        buttonLabel: 'Back to vault',
        onBack: () => Navigator.of(context).popUntil((route) => route.isFirst),
      );
    }
    final fields = _displayFieldsFor(entry);
    return Scaffold(
      appBar: AppBar(
        title: Text(entry.title.isEmpty ? '(no title)' : entry.title),
        actions: [
          IconButton(
            icon: Icon(entry.favorite ? Icons.star : Icons.star_border),
            tooltip: entry.favorite ? 'Unpin favorite' : 'Pin favorite',
            onPressed: () => _toggleFavorite(entry),
          ),
          IconButton(
            icon: const Icon(Icons.edit_outlined),
            tooltip: 'Edit',
            onPressed: () => Navigator.of(context).push(
              MaterialPageRoute(
                builder: (_) => EntryFormScreen(existing: entry),
              ),
            ),
          ),
          IconButton(
            icon: const Icon(Icons.delete_outline),
            tooltip: 'Delete',
            onPressed: () => _delete(entry),
          ),
        ],
      ),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TypeHeader(entry: entry),
            const SizedBox(height: VaultSpacing.lg),
            for (final field in fields)
              _Field(
                label: field.label,
                value: field.value,
                multiline: field.multiline,
                obscure: field.sensitive && !_visibleFields.contains(field.key),
                onCopy: field.copyable
                    ? () => _copy(field.value, field.label)
                    : null,
                trailing: field.sensitive
                    ? IconButton(
                        icon: Icon(
                          _visibleFields.contains(field.key)
                              ? Icons.visibility_off_outlined
                              : Icons.visibility_outlined,
                        ),
                        onPressed: () => setState(() {
                          if (!_visibleFields.remove(field.key)) {
                            _visibleFields.add(field.key);
                          }
                        }),
                      )
                    : null,
              ),
            if (entry.tags.isNotEmpty) _TagsField(tags: entry.tags),
            const SizedBox(height: VaultSpacing.md),
            _AttachmentsSection(
              attachments: entry.attachments,
              busy: _attachmentBusy,
              onAdd: () => _addAttachment(entry),
              onExport: _exportAttachment,
              onShare: _shareAttachment,
              onDelete: (attachment) => _deleteAttachment(entry, attachment),
            ),
          ],
        ),
      ),
    );
  }
}

class _DisplayField {
  const _DisplayField({
    required this.key,
    required this.label,
    required this.value,
    this.sensitive = false,
    this.multiline = false,
    this.copyable = true,
  });

  final String key;
  final String label;
  final String value;
  final bool sensitive;
  final bool multiline;
  final bool copyable;
}

List<_DisplayField> _displayFieldsFor(VaultEntry entry) {
  final fields = switch (entry.itemType) {
    VaultItemType.password => [
      _DisplayField(key: 'username', label: 'Username', value: entry.username),
      _DisplayField(
        key: 'password',
        label: 'Password',
        value: entry.password,
        sensitive: true,
      ),
      _DisplayField(key: 'url', label: 'URL', value: entry.url),
      _DisplayField(
        key: 'notes',
        label: 'Notes',
        value: entry.notes,
        multiline: true,
        copyable: false,
      ),
    ],
    VaultItemType.secureNote => [
      _DisplayField(
        key: 'note',
        label: 'Note',
        value: entry.fields['body'] ?? entry.notes,
        multiline: true,
        copyable: false,
      ),
    ],
    VaultItemType.paymentCard => [
      _field(entry, 'cardholder', 'Cardholder'),
      _field(entry, 'cardNumber', 'Card number', sensitive: true),
      _field(entry, 'expiry', 'Expiry'),
      _field(entry, 'cvv', 'CVV', sensitive: true),
      _field(entry, 'pin', 'PIN', sensitive: true),
      _noteField(entry),
    ],
    VaultItemType.identity => [
      _field(entry, 'documentType', 'Document type'),
      _field(entry, 'documentNumber', 'Document number', sensitive: true),
      _field(entry, 'name', 'Name'),
      _field(entry, 'issueDate', 'Issue date'),
      _field(entry, 'expiryDate', 'Expiry date'),
      _noteField(entry),
    ],
    VaultItemType.recoveryCodes => [
      _field(entry, 'service', 'Service'),
      _field(
        entry,
        'codes',
        'Recovery codes',
        sensitive: true,
        multiline: true,
      ),
      _noteField(entry),
    ],
    VaultItemType.apiKey => [
      _field(entry, 'service', 'Service'),
      _field(entry, 'key', 'Key or token', sensitive: true, multiline: true),
      _field(entry, 'account', 'Account or email'),
      _noteField(entry),
    ],
    VaultItemType.wifi => [
      _field(entry, 'networkName', 'Network name'),
      _field(entry, 'password', 'Password', sensitive: true),
      _field(entry, 'securityType', 'Security type'),
      _noteField(entry),
    ],
    VaultItemType.finance => [
      _field(entry, 'institution', 'Institution'),
      _field(entry, 'accountId', 'Account or customer ID', sensitive: true),
      _field(entry, 'routing', 'IFSC, routing, or SWIFT'),
      _noteField(entry),
    ],
  };
  return fields.where((field) => field.value.trim().isNotEmpty).toList();
}

_DisplayField _field(
  VaultEntry entry,
  String key,
  String label, {
  bool sensitive = false,
  bool multiline = false,
}) {
  return _DisplayField(
    key: key,
    label: label,
    value: entry.fields[key] ?? '',
    sensitive: sensitive,
    multiline: multiline,
  );
}

_DisplayField _noteField(VaultEntry entry) {
  return _DisplayField(
    key: 'notes',
    label: 'Notes',
    value: entry.notes,
    multiline: true,
    copyable: false,
  );
}

class _TypeHeader extends StatelessWidget {
  const _TypeHeader({required this.entry});

  final VaultEntry entry;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Row(
      children: [
        Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: VaultColors.surface,
            borderRadius: BorderRadius.circular(VaultRadii.md),
            border: Border.all(color: VaultColors.border),
          ),
          child: Icon(
            iconForItemType(entry.itemType),
            size: 20,
            color: VaultColors.primary,
          ),
        ),
        const SizedBox(width: VaultSpacing.md),
        Expanded(
          child: Text(
            entry.itemType.label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: VaultColors.textMuted,
            ),
          ),
        ),
      ],
    );
  }
}

class _UnavailableEntryScreen extends StatelessWidget {
  const _UnavailableEntryScreen({
    required this.title,
    required this.message,
    required this.buttonLabel,
    required this.onBack,
  });

  final String title;
  final String message;
  final String buttonLabel;
  final VoidCallback onBack;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: Text(title)),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(VaultSpacing.lg),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(message, textAlign: TextAlign.center),
              const SizedBox(height: VaultSpacing.md),
              FilledButton(onPressed: onBack, child: Text(buttonLabel)),
            ],
          ),
        ),
      ),
    );
  }
}

class _TagsField extends StatelessWidget {
  const _TagsField({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(top: 4),
      child: Wrap(
        spacing: 8,
        runSpacing: 8,
        children: [
          for (final tag in tags)
            Chip(label: Text(tag), visualDensity: VisualDensity.compact),
        ],
      ),
    );
  }
}

class _Field extends StatelessWidget {
  const _Field({
    required this.label,
    required this.value,
    this.obscure = false,
    this.multiline = false,
    this.onCopy,
    this.trailing,
  });

  final String label;
  final String value;
  final bool obscure;
  final bool multiline;
  final VoidCallback? onCopy;
  final Widget? trailing;

  @override
  Widget build(BuildContext context) {
    final display = obscure ? '•' * value.length : value;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(VaultRadii.md),
        border: Border.all(color: VaultColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.fromLTRB(16, 12, 8, 12),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(label, style: Theme.of(context).textTheme.labelMedium),
                  const SizedBox(height: 4),
                  Text(
                    display,
                    style: Theme.of(context).textTheme.bodyLarge,
                    maxLines: multiline ? null : 1,
                    overflow: multiline ? null : TextOverflow.ellipsis,
                    softWrap: true,
                  ),
                ],
              ),
            ),
            ?trailing,
            if (onCopy != null)
              IconButton(
                icon: const Icon(Icons.copy_outlined),
                tooltip: 'Copy',
                onPressed: onCopy,
              ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentsSection extends StatelessWidget {
  const _AttachmentsSection({
    required this.attachments,
    required this.busy,
    required this.onAdd,
    required this.onExport,
    required this.onShare,
    required this.onDelete,
  });

  final List<VaultAttachment> attachments;
  final bool busy;
  final VoidCallback onAdd;
  final ValueChanged<VaultAttachment> onExport;
  final ValueChanged<VaultAttachment> onShare;
  final ValueChanged<VaultAttachment> onDelete;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(VaultRadii.md),
        border: Border.all(color: VaultColors.border),
      ),
      child: Padding(
        padding: const EdgeInsets.all(VaultSpacing.md),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                const Icon(Icons.attach_file_outlined, size: 20),
                const SizedBox(width: VaultSpacing.sm),
                Expanded(
                  child: Text('Attachments', style: theme.textTheme.titleSmall),
                ),
                TextButton.icon(
                  onPressed: busy ? null : onAdd,
                  icon: busy
                      ? const SizedBox(
                          width: 16,
                          height: 16,
                          child: CircularProgressIndicator(strokeWidth: 2),
                        )
                      : const Icon(Icons.add),
                  label: Text(busy ? 'Processing' : 'Add'),
                ),
              ],
            ),
            if (attachments.isEmpty)
              Padding(
                padding: const EdgeInsets.only(top: VaultSpacing.xs),
                child: Text(
                  'No attachments.',
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: VaultColors.textMuted,
                  ),
                ),
              )
            else
              for (final attachment in attachments)
                _AttachmentTile(
                  attachment: attachment,
                  busy: busy,
                  onExport: () => onExport(attachment),
                  onShare: () => onShare(attachment),
                  onDelete: () => onDelete(attachment),
                ),
          ],
        ),
      ),
    );
  }
}

class _AttachmentTile extends StatelessWidget {
  const _AttachmentTile({
    required this.attachment,
    required this.busy,
    required this.onExport,
    required this.onShare,
    required this.onDelete,
  });

  final VaultAttachment attachment;
  final bool busy;
  final VoidCallback onExport;
  final VoidCallback onShare;
  final VoidCallback onDelete;

  @override
  Widget build(BuildContext context) {
    return Container(
      margin: const EdgeInsets.only(top: VaultSpacing.sm),
      padding: const EdgeInsets.all(VaultSpacing.sm),
      decoration: BoxDecoration(
        color: VaultColors.surfaceHigh,
        borderRadius: BorderRadius.circular(VaultRadii.sm),
        border: Border.all(color: VaultColors.border),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (attachment.isImage) ...[
            ClipRRect(
              borderRadius: BorderRadius.circular(VaultRadii.sm),
              child: Image.memory(
                attachment.decodeBytes(),
                height: 180,
                fit: BoxFit.cover,
                errorBuilder: (_, _, _) => const SizedBox.shrink(),
              ),
            ),
            const SizedBox(height: VaultSpacing.sm),
          ],
          Row(
            children: [
              Icon(
                attachment.isImage
                    ? Icons.image_outlined
                    : Icons.description_outlined,
              ),
              const SizedBox(width: VaultSpacing.sm),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      attachment.fileName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      '${attachment.mimeType} • '
                      '${formatAttachmentSize(attachment.sizeBytes)}',
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: Theme.of(context).textTheme.bodySmall?.copyWith(
                        color: VaultColors.textMuted,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                tooltip: 'Download unencrypted copy',
                icon: const Icon(Icons.file_download_outlined),
                onPressed: busy ? null : onExport,
              ),
              IconButton(
                tooltip: 'Share unencrypted copy',
                icon: const Icon(Icons.ios_share_outlined),
                onPressed: busy ? null : onShare,
              ),
              IconButton(
                tooltip: 'Remove attachment',
                icon: const Icon(Icons.delete_outline),
                onPressed: busy ? null : onDelete,
              ),
            ],
          ),
        ],
      ),
    );
  }
}

enum _AttachmentSource { files, camera }

class _AttachmentSourceSheet extends StatelessWidget {
  const _AttachmentSourceSheet();

  @override
  Widget build(BuildContext context) {
    return SafeArea(
      child: ListView(
        shrinkWrap: true,
        padding: const EdgeInsets.fromLTRB(
          VaultSpacing.md,
          VaultSpacing.sm,
          VaultSpacing.md,
          VaultSpacing.lg,
        ),
        children: [
          ListTile(
            leading: const Icon(Icons.upload_file_outlined),
            title: const Text('Choose files'),
            subtitle: const Text('Images and documents'),
            onTap: () => Navigator.of(context).pop(_AttachmentSource.files),
          ),
          ListTile(
            leading: const Icon(Icons.photo_camera_outlined),
            title: const Text('Take photo'),
            subtitle: const Text('Capture with camera'),
            onTap: () => Navigator.of(context).pop(_AttachmentSource.camera),
          ),
          const Divider(),
          ListTile(
            leading: const Icon(Icons.close),
            title: const Text('Cancel'),
            onTap: () => Navigator.of(context).pop(),
          ),
        ],
      ),
    );
  }
}

String _photoFileName() {
  final now = DateTime.now();
  String two(int v) => v.toString().padLeft(2, '0');
  return 'photo-${now.year}${two(now.month)}${two(now.day)}-'
      '${two(now.hour)}${two(now.minute)}${two(now.second)}.jpg';
}
