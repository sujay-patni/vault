import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

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

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(vaultStatusProvider);
    final entry = _findEntry(status);
    if (entry == null) {
      return const Scaffold(body: Center(child: Text('Item not found.')));
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
