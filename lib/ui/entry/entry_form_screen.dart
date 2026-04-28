import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../vault/vault_entry.dart';
import '../../vault/vault_repository.dart';
import '../../vault/vault_state.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';

class EntryFormScreen extends ConsumerStatefulWidget {
  const EntryFormScreen({super.key, this.existing, this.itemType});

  final VaultEntry? existing;
  final VaultItemType? itemType;

  @override
  ConsumerState<EntryFormScreen> createState() => _EntryFormScreenState();
}

class _EntryFormScreenState extends ConsumerState<EntryFormScreen> {
  late final VaultItemType _itemType;
  late final TextEditingController _title;
  late final TextEditingController _tags;
  late final TextEditingController _notes;
  late final Map<String, TextEditingController> _fieldControllers;
  late bool _favorite;
  bool _busy = false;

  @override
  void initState() {
    super.initState();
    final e = widget.existing;
    _itemType = e?.itemType ?? widget.itemType ?? VaultItemType.password;
    _title = TextEditingController(text: e?.title ?? '');
    _tags = TextEditingController(text: e?.tags.join(', ') ?? '');
    _notes = TextEditingController(text: _initialNotes(e));
    _favorite = e?.favorite ?? false;
    _fieldControllers = {
      for (final field in _fieldsFor(_itemType))
        field.key: TextEditingController(
          text: _initialFieldValue(e, field.key),
        ),
    };
  }

  @override
  void dispose() {
    _title.dispose();
    _tags.dispose();
    _notes.dispose();
    for (final controller in _fieldControllers.values) {
      controller.dispose();
    }
    super.dispose();
  }

  String _initialNotes(VaultEntry? e) {
    if (e == null) return '';
    if (_itemType == VaultItemType.secureNote && e.fields['body'] != null) {
      return e.fields['body']!;
    }
    return e.notes;
  }

  String _initialFieldValue(VaultEntry? e, String key) {
    if (e == null) return '';
    if (_itemType == VaultItemType.password) {
      return switch (key) {
        'username' => e.username,
        'password' => e.password,
        'url' => e.url,
        _ => e.fields[key] ?? '',
      };
    }
    return e.fields[key] ?? '';
  }

  List<String> _parseTags() {
    final seen = <String>{};
    final tags = <String>[];
    for (final raw in _tags.text.split(',')) {
      final tag = raw.trim();
      if (tag.isEmpty) continue;
      final key = tag.toLowerCase();
      if (seen.add(key)) tags.add(tag);
    }
    return tags;
  }

  Map<String, String> _collectFields() {
    final fields = <String, String>{};
    for (final entry in _fieldControllers.entries) {
      final value = entry.value.text.trim();
      if (value.isNotEmpty) fields[entry.key] = value;
    }
    if (_itemType == VaultItemType.secureNote &&
        _notes.text.trim().isNotEmpty) {
      fields['body'] = _notes.text;
    }
    return fields;
  }

  Future<void> _save() async {
    setState(() => _busy = true);
    final cur = ref.read(vaultStatusProvider);
    if (cur is! VaultUnlocked) return;

    final now = DateTime.now();
    final fields = _collectFields();
    final username = _itemType == VaultItemType.password
        ? (_fieldControllers['username']?.text ?? '')
        : '';
    final password = _itemType == VaultItemType.password
        ? (_fieldControllers['password']?.text ?? '')
        : '';
    final url = _itemType == VaultItemType.password
        ? (_fieldControllers['url']?.text ?? '')
        : '';
    final notes = _notes.text;

    final List<VaultEntry> next;
    if (widget.existing == null) {
      final e = VaultEntry(
        id: VaultEntry.newId(),
        itemType: _itemType,
        title: _title.text,
        username: username,
        password: password,
        url: url,
        notes: notes,
        fields: fields,
        tags: _parseTags(),
        favorite: _favorite,
        createdAt: now,
        updatedAt: now,
      );
      next = [...cur.entries, e];
    } else {
      next = cur.entries
          .map(
            (e) => e.id == widget.existing!.id
                ? e.copyWith(
                    itemType: _itemType,
                    title: _title.text,
                    username: username,
                    password: password,
                    url: url,
                    notes: notes,
                    fields: fields,
                    tags: _parseTags(),
                    favorite: _favorite,
                    updatedAt: now,
                  )
                : e,
          )
          .toList();
    }
    try {
      await ref.read(vaultStatusProvider.notifier).saveEntries(next);
      if (mounted) Navigator.of(context).pop();
    } catch (e) {
      if (mounted) {
        setState(() => _busy = false);
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Save failed: $e')));
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final isEdit = widget.existing != null;
    final typeTitle = _singularLabel(_itemType);
    return Scaffold(
      appBar: AppBar(
        title: Text(isEdit ? 'Edit $typeTitle' : 'Add $typeTitle'),
        actions: [
          TextButton(
            onPressed: _busy ? null : _save,
            child: _busy
                ? const SizedBox(
                    width: 18,
                    height: 18,
                    child: CircularProgressIndicator(strokeWidth: 2),
                  )
                : const Text('Save'),
          ),
        ],
      ),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            _TypeBanner(itemType: _itemType),
            const SizedBox(height: VaultSpacing.lg),
            _input('Title', _title, autofocus: !isEdit),
            for (final field in _fieldsFor(_itemType))
              _input(
                field.label,
                _fieldControllers[field.key]!,
                obscure: field.sensitive && !field.multiline,
                maxLines: field.multiline ? 5 : 1,
              ),
            _input(
              _itemType == VaultItemType.secureNote ? 'Note' : 'Notes',
              _notes,
              maxLines: 6,
            ),
            _input(
              'Tags',
              _tags,
              helperText: 'Use commas for multiple tags, e.g. work, banking',
              onChanged: (_) => setState(() {}),
            ),
            _TagPreview(tags: _parseTags()),
            const SizedBox(height: VaultSpacing.md),
            Container(
              decoration: BoxDecoration(
                color: VaultColors.surface,
                borderRadius: BorderRadius.circular(VaultRadii.md),
                border: Border.all(color: VaultColors.border),
              ),
              child: SwitchListTile(
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: VaultSpacing.lg,
                ),
                title: const Text('Pinned favorite'),
                value: _favorite,
                onChanged: _busy ? null : (v) => setState(() => _favorite = v),
                secondary: const Icon(Icons.star_border),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _input(
    String label,
    TextEditingController controller, {
    bool obscure = false,
    int maxLines = 1,
    bool autofocus = false,
    String? helperText,
    ValueChanged<String>? onChanged,
  }) {
    return Padding(
      padding: const EdgeInsets.only(bottom: 12),
      child: TextField(
        controller: controller,
        obscureText: obscure,
        autofocus: autofocus,
        enabled: !_busy,
        maxLines: obscure ? 1 : maxLines,
        onChanged: onChanged,
        decoration: InputDecoration(
          labelText: label,
          helperText: helperText,
          border: const OutlineInputBorder(),
        ),
      ),
    );
  }
}

class _TypeBanner extends StatelessWidget {
  const _TypeBanner({required this.itemType});

  final VaultItemType itemType;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.all(VaultSpacing.md),
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(VaultRadii.md),
        border: Border.all(color: VaultColors.border),
      ),
      child: Row(
        children: [
          Icon(iconForItemType(itemType), color: VaultColors.primary),
          const SizedBox(width: VaultSpacing.md),
          Expanded(
            child: Text(
              _typeDescription(itemType),
              style: theme.textTheme.bodyMedium?.copyWith(
                color: VaultColors.textMuted,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

class VaultItemTypePicker extends StatelessWidget {
  const VaultItemTypePicker({super.key});

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
          for (final type in VaultItemType.values)
            Padding(
              padding: const EdgeInsets.only(bottom: VaultSpacing.sm),
              child: ListTile(
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(VaultRadii.md),
                  side: const BorderSide(color: VaultColors.border),
                ),
                tileColor: VaultColors.surfaceHigh,
                leading: Icon(
                  iconForItemType(type),
                  color: VaultColors.primary,
                ),
                title: Text(_singularLabel(type)),
                subtitle: Text(_typeDescription(type)),
                onTap: () => Navigator.of(context).pop(type),
              ),
            ),
        ],
      ),
    );
  }
}

class _FormFieldSpec {
  const _FormFieldSpec(
    this.key,
    this.label, {
    this.sensitive = false,
    this.multiline = false,
  });

  final String key;
  final String label;
  final bool sensitive;
  final bool multiline;
}

List<_FormFieldSpec> _fieldsFor(VaultItemType type) {
  return switch (type) {
    VaultItemType.password => const [
      _FormFieldSpec('username', 'Username'),
      _FormFieldSpec('password', 'Password', sensitive: true),
      _FormFieldSpec('url', 'URL'),
    ],
    VaultItemType.secureNote => const [],
    VaultItemType.paymentCard => const [
      _FormFieldSpec('cardholder', 'Cardholder'),
      _FormFieldSpec('cardNumber', 'Card number', sensitive: true),
      _FormFieldSpec('expiry', 'Expiry'),
      _FormFieldSpec('cvv', 'CVV', sensitive: true),
      _FormFieldSpec('pin', 'PIN', sensitive: true),
    ],
    VaultItemType.identity => const [
      _FormFieldSpec('documentType', 'Document type'),
      _FormFieldSpec('documentNumber', 'Document number', sensitive: true),
      _FormFieldSpec('name', 'Name'),
      _FormFieldSpec('issueDate', 'Issue date'),
      _FormFieldSpec('expiryDate', 'Expiry date'),
    ],
    VaultItemType.recoveryCodes => const [
      _FormFieldSpec('service', 'Service'),
      _FormFieldSpec(
        'codes',
        'Recovery codes',
        sensitive: true,
        multiline: true,
      ),
    ],
    VaultItemType.apiKey => const [
      _FormFieldSpec('service', 'Service'),
      _FormFieldSpec('key', 'Key or token', sensitive: true, multiline: true),
      _FormFieldSpec('account', 'Account or email'),
    ],
    VaultItemType.wifi => const [
      _FormFieldSpec('networkName', 'Network name'),
      _FormFieldSpec('password', 'Password', sensitive: true),
      _FormFieldSpec('securityType', 'Security type'),
    ],
    VaultItemType.finance => const [
      _FormFieldSpec('institution', 'Institution'),
      _FormFieldSpec('accountId', 'Account or customer ID', sensitive: true),
      _FormFieldSpec('routing', 'IFSC, routing, or SWIFT'),
    ],
  };
}

IconData iconForItemType(VaultItemType type) {
  return switch (type) {
    VaultItemType.password => Icons.password_outlined,
    VaultItemType.secureNote => Icons.notes_outlined,
    VaultItemType.paymentCard => Icons.credit_card_outlined,
    VaultItemType.identity => Icons.badge_outlined,
    VaultItemType.recoveryCodes => Icons.pin_outlined,
    VaultItemType.apiKey => Icons.key_outlined,
    VaultItemType.wifi => Icons.wifi_password_outlined,
    VaultItemType.finance => Icons.account_balance_outlined,
  };
}

String _singularLabel(VaultItemType type) {
  return switch (type) {
    VaultItemType.password => 'Password',
    VaultItemType.secureNote => 'Note',
    VaultItemType.paymentCard => 'Card',
    VaultItemType.identity => 'ID',
    VaultItemType.recoveryCodes => 'Recovery codes',
    VaultItemType.apiKey => 'Key',
    VaultItemType.wifi => 'Wi-Fi',
    VaultItemType.finance => 'Finance',
  };
}

String _typeDescription(VaultItemType type) {
  return switch (type) {
    VaultItemType.password => 'Username, password, URL, and notes',
    VaultItemType.secureNote => 'Title and encrypted note body',
    VaultItemType.paymentCard => 'Card number, expiry, CVV, PIN',
    VaultItemType.identity => 'Documents, IDs, and expiry details',
    VaultItemType.recoveryCodes => 'Backup codes for accounts',
    VaultItemType.apiKey => 'API keys, tokens, and secrets',
    VaultItemType.wifi => 'Network name and password',
    VaultItemType.finance => 'Banking and account details',
  };
}

class _TagPreview extends StatelessWidget {
  const _TagPreview({required this.tags});

  final List<String> tags;

  @override
  Widget build(BuildContext context) {
    if (tags.isEmpty) return const SizedBox.shrink();
    final theme = Theme.of(context);
    return Wrap(
      spacing: 6,
      runSpacing: 6,
      children: [
        for (final tag in tags)
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              color: VaultColors.surface,
              border: Border.all(color: VaultColors.border),
              borderRadius: BorderRadius.circular(6),
            ),
            child: Text(
              tag,
              style: theme.textTheme.labelMedium?.copyWith(
                color: theme.colorScheme.onSurfaceVariant,
              ),
            ),
          ),
      ],
    );
  }
}
