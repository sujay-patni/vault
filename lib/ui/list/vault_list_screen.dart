import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../vault/vault_entry.dart';
import '../../vault/vault_repository.dart';
import '../../vault/vault_state.dart';
import '../entry/entry_detail_screen.dart';
import '../entry/entry_form_screen.dart';
import '../settings/settings_screen.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';

class VaultListScreen extends ConsumerStatefulWidget {
  const VaultListScreen({super.key});

  @override
  ConsumerState<VaultListScreen> createState() => _VaultListScreenState();
}

class _VaultListScreenState extends ConsumerState<VaultListScreen> {
  final _searchCtrl = TextEditingController();
  String _query = '';
  VaultItemType? _selectedType;

  @override
  void dispose() {
    _searchCtrl.dispose();
    super.dispose();
  }

  List<VaultEntry> _filter(List<VaultEntry> all) {
    final typed = _selectedType == null
        ? all
        : all.where((e) => e.itemType == _selectedType).toList(growable: false);
    if (_query.isEmpty) return typed;
    final q = _query.toLowerCase();
    return typed
        .where(
          (e) =>
              e.title.toLowerCase().contains(q) ||
              e.username.toLowerCase().contains(q) ||
              e.password.toLowerCase().contains(q) ||
              e.url.toLowerCase().contains(q) ||
              e.notes.toLowerCase().contains(q) ||
              e.tags.any((tag) => tag.toLowerCase().contains(q)) ||
              e.fields.values.any((v) => v.toLowerCase().contains(q)),
        )
        .toList(growable: false);
  }

  Future<void> _addEntry() async {
    final type = await showModalBottomSheet<VaultItemType>(
      context: context,
      showDragHandle: true,
      builder: (_) => const VaultItemTypePicker(),
    );
    if (!mounted || type == null) return;
    Navigator.of(
      context,
    ).push(MaterialPageRoute(builder: (_) => EntryFormScreen(itemType: type)));
  }

  @override
  Widget build(BuildContext context) {
    final status = ref.watch(vaultStatusProvider);
    if (status is! VaultUnlocked) {
      // Will be replaced by router; transient.
      return const Scaffold(body: Center(child: CircularProgressIndicator()));
    }
    final entries = _filter(status.entries)
      ..sort((a, b) {
        if (a.favorite != b.favorite) return a.favorite ? -1 : 1;
        return a.title.toLowerCase().compareTo(b.title.toLowerCase());
      });

    return Scaffold(
      appBar: AppBar(
        title: const Text('Vault'),
        actions: [
          IconButton(
            icon: const Icon(Icons.lock_outline),
            tooltip: 'Lock vault',
            onPressed: () => ref.read(vaultStatusProvider.notifier).lock(),
          ),
          IconButton(
            icon: const Icon(Icons.settings_outlined),
            tooltip: 'Settings',
            onPressed: () => Navigator.of(
              context,
            ).push(MaterialPageRoute(builder: (_) => const SettingsScreen())),
          ),
        ],
      ),
      floatingActionButton: FloatingActionButton.extended(
        icon: const Icon(Icons.add),
        label: const Text('Add'),
        onPressed: _addEntry,
      ),
      body: LayoutBuilder(
        builder: (context, constraints) {
          final padding = responsiveHorizontalPadding(constraints.maxWidth);
          return Center(
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 900),
              child: Column(
                children: [
                  Padding(
                    padding: EdgeInsets.fromLTRB(
                      padding,
                      VaultSpacing.sm,
                      padding,
                      VaultSpacing.md,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        TextField(
                          controller: _searchCtrl,
                          decoration: InputDecoration(
                            prefixIcon: const Icon(Icons.search),
                            hintText: 'Search vault',
                            isDense: true,
                            suffixIcon: _query.isEmpty
                                ? null
                                : IconButton(
                                    icon: const Icon(Icons.close),
                                    onPressed: () {
                                      _searchCtrl.clear();
                                      setState(() => _query = '');
                                    },
                                  ),
                          ),
                          onChanged: (v) => setState(() => _query = v),
                        ),
                        const SizedBox(height: VaultSpacing.md),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              _TypeFilterChip(
                                label: 'All',
                                selected: _selectedType == null,
                                onSelected: () =>
                                    setState(() => _selectedType = null),
                              ),
                              for (final type in VaultItemType.values)
                                _TypeFilterChip(
                                  label: type.label,
                                  selected: _selectedType == type,
                                  onSelected: () =>
                                      setState(() => _selectedType = type),
                                ),
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: entries.isEmpty
                        ? Center(
                            child: Padding(
                              padding: EdgeInsets.all(padding),
                              child: Text(
                                _query.isEmpty
                                    ? 'No entries yet. Tap Add to create one.'
                                    : 'No entries match "$_query".',
                                style: Theme.of(context).textTheme.bodyMedium,
                                textAlign: TextAlign.center,
                              ),
                            ),
                          )
                        : ListView.separated(
                            keyboardDismissBehavior:
                                ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: EdgeInsets.fromLTRB(
                              padding,
                              VaultSpacing.xs,
                              padding,
                              padding + 80,
                            ),
                            itemCount: entries.length,
                            separatorBuilder: (_, _) =>
                                const SizedBox(height: VaultSpacing.sm),
                            itemBuilder: (_, i) {
                              final e = entries[i];
                              return _EntryRow(
                                entry: e,
                                onTap: () => Navigator.of(context).push(
                                  MaterialPageRoute(
                                    builder: (_) =>
                                        EntryDetailScreen(entryId: e.id),
                                  ),
                                ),
                              );
                            },
                          ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }
}

class _EntryRow extends StatelessWidget {
  const _EntryRow({required this.entry, required this.onTap});

  final VaultEntry entry;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final title = entry.title.isEmpty ? '(no title)' : entry.title;
    final meta = _metadataFor(entry);
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(8),
      child: Container(
        padding: const EdgeInsets.all(VaultSpacing.md),
        decoration: BoxDecoration(
          color: VaultColors.surface,
          borderRadius: BorderRadius.circular(VaultRadii.md),
          border: Border.all(color: VaultColors.border),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _EntryInitial(entry: entry, title: title),
            const SizedBox(width: 14),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleMedium,
                        ),
                      ),
                      if (entry.favorite) ...[
                        const SizedBox(width: 8),
                        Icon(
                          Icons.star_rounded,
                          size: 18,
                          color: theme.colorScheme.primary,
                        ),
                      ],
                    ],
                  ),
                  if (meta != null) ...[
                    const SizedBox(height: 3),
                    Text(
                      meta,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: VaultColors.textMuted,
                      ),
                    ),
                  ],
                  if (entry.tags.isNotEmpty) ...[
                    const SizedBox(height: 8),
                    Wrap(
                      spacing: 6,
                      runSpacing: 6,
                      children: [
                        for (final tag in entry.tags) _TagPill(label: tag),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _EntryInitial extends StatelessWidget {
  const _EntryInitial({required this.entry, required this.title});

  final VaultEntry entry;
  final String title;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      width: 42,
      height: 42,
      alignment: Alignment.center,
      decoration: BoxDecoration(
        color: VaultColors.surfaceHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: VaultColors.border),
      ),
      child: Text(
        _typeGlyph(entry.itemType, title),
        style: theme.textTheme.titleSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _TypeFilterChip extends StatelessWidget {
  const _TypeFilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
  });

  final String label;
  final bool selected;
  final VoidCallback onSelected;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(right: 8),
      child: ChoiceChip(
        label: Text(label),
        selected: selected,
        onSelected: (_) => onSelected(),
        visualDensity: VisualDensity.compact,
      ),
    );
  }
}

String _typeGlyph(VaultItemType type, String title) {
  return switch (type) {
    VaultItemType.password => title.isEmpty ? '?' : title[0].toUpperCase(),
    VaultItemType.secureNote => 'N',
    VaultItemType.paymentCard => 'C',
    VaultItemType.identity => 'ID',
    VaultItemType.recoveryCodes => '#',
    VaultItemType.apiKey => 'K',
    VaultItemType.wifi => 'Wi',
    VaultItemType.finance => 'F',
  };
}

String? _metadataFor(VaultEntry entry) {
  if (entry.itemType == VaultItemType.password) {
    if (entry.username.isNotEmpty) return entry.username;
    if (entry.url.isNotEmpty) return entry.url;
    return null;
  }
  final candidates = switch (entry.itemType) {
    VaultItemType.secureNote => [entry.notes, entry.fields['body']],
    VaultItemType.paymentCard => [
      entry.fields['cardholder'],
      entry.fields['expiry'],
    ],
    VaultItemType.identity => [
      entry.fields['documentType'],
      entry.fields['documentNumber'],
    ],
    VaultItemType.recoveryCodes => [entry.fields['service']],
    VaultItemType.apiKey => [entry.fields['service'], entry.fields['account']],
    VaultItemType.wifi => [
      entry.fields['networkName'],
      entry.fields['securityType'],
    ],
    VaultItemType.finance => [
      entry.fields['institution'],
      entry.fields['accountId'],
    ],
    VaultItemType.password => const <String?>[],
  };
  for (final value in candidates) {
    if (value != null && value.trim().isNotEmpty) return value.trim();
  }
  return entry.itemType.label;
}

class _TagPill extends StatelessWidget {
  const _TagPill({required this.label});

  final String label;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        border: Border.all(color: VaultColors.border),
        borderRadius: BorderRadius.circular(6),
        color: const Color(0xFF0D1219),
      ),
      child: Text(
        label,
        style: theme.textTheme.labelSmall?.copyWith(
          color: theme.colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
