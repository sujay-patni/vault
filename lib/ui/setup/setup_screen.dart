import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../backup/backup_errors.dart';
import '../../backup/backup_io.dart';
import '../../crypto/secure_bytes.dart';
import '../../crypto/vault_crypto.dart';
import '../../vault/vault_repository.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';

class SetupScreen extends ConsumerStatefulWidget {
  const SetupScreen({super.key});

  @override
  ConsumerState<SetupScreen> createState() => _SetupScreenState();
}

class _SetupScreenState extends ConsumerState<SetupScreen> {
  final _pw1 = TextEditingController();
  final _pw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw1.dispose();
    _pw2.dispose();
    super.dispose();
  }

  Future<void> _create() async {
    setState(() => _error = null);
    final p1 = _pw1.text;
    final p2 = _pw2.text;
    if (p1.length < 8) {
      setState(() => _error = 'Master password must be at least 8 characters.');
      return;
    }
    if (p1 != p2) {
      setState(() => _error = 'Passwords do not match.');
      return;
    }
    final confirmed = await _showWarningDialog();
    if (!mounted || confirmed != true) return;

    setState(() => _busy = true);
    final pwBytes = passwordToUtf8Bytes(p1);
    try {
      await ref
          .read(vaultStatusProvider.notifier)
          .setupAndUnlock(masterPasswordUtf8: pwBytes);
    } catch (e) {
      if (mounted) setState(() => _error = 'Setup failed: $e');
    } finally {
      pwBytes.secureZero();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<void> _import() async {
    setState(() => _error = null);
    final bytes = await pickBackupFile();
    if (!mounted || bytes == null) return;

    final pw = await _promptForPassword();
    if (!mounted || pw == null) return;

    setState(() => _busy = true);
    final pwBytes = passwordToUtf8Bytes(pw);
    try {
      await ref
          .read(vaultStatusProvider.notifier)
          .importBackup(masterPasswordUtf8: pwBytes, bytes: bytes);
    } on FormatException catch (e) {
      if (mounted) {
        setState(() => _error = describeBackupFormatError(e));
      }
    } catch (e) {
      if (mounted) {
        setState(
          () => _error =
              'Import failed: file could not be decrypted with that password.',
        );
      }
    } finally {
      pwBytes.secureZero();
      if (mounted) setState(() => _busy = false);
    }
  }

  Future<String?> _promptForPassword() async {
    final ctrl = TextEditingController();
    final result = await showDialog<String>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Master password'),
        content: TextField(
          controller: ctrl,
          obscureText: true,
          autofocus: true,
          decoration: const InputDecoration(
            labelText: 'Master password for the backup',
            border: OutlineInputBorder(),
          ),
          onSubmitted: (v) => Navigator.of(ctx).pop(v),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(ctrl.text),
            child: const Text('Restore'),
          ),
        ],
      ),
    );
    ctrl.dispose();
    return result;
  }

  Future<bool?> _showWarningDialog() {
    return showDialog<bool>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => AlertDialog(
        title: const Text('No recovery'),
        content: const Text(
          'There is no password reset. There is no recovery service. '
          'If you forget this master password, your vault is permanently '
          'unrecoverable — no one, including you, can decrypt it.\n\n'
          'You are responsible for exporting backups regularly.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('I understand, create vault'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: SafeArea(
        child: ResponsiveBody(
          centerVertically: true,
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Text(
                'Welcome to Vault',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
              ),
              const SizedBox(height: VaultSpacing.md),
              Text(
                'Create a master password. This password is the only thing '
                'protecting your vault. It is never stored, never sent over '
                'the network — it lives only in your head.',
                style: Theme.of(context).textTheme.bodyMedium?.copyWith(
                  color: VaultColors.textMuted,
                  height: 1.4,
                ),
              ),
              const SizedBox(height: VaultSpacing.xl),
              TextField(
                controller: _pw1,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Master password',
                  border: OutlineInputBorder(),
                ),
              ),
              const SizedBox(height: VaultSpacing.lg),
              TextField(
                controller: _pw2,
                obscureText: true,
                enabled: !_busy,
                decoration: const InputDecoration(
                  labelText: 'Confirm master password',
                  border: OutlineInputBorder(),
                ),
              ),
              if (_error != null) ...[
                const SizedBox(height: VaultSpacing.md),
                Text(
                  _error!,
                  style: TextStyle(color: Theme.of(context).colorScheme.error),
                ),
              ],
              const SizedBox(height: VaultSpacing.xl),
              FilledButton(
                onPressed: _busy ? null : _create,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Create vault'),
              ),
              const SizedBox(height: VaultSpacing.sm),
              TextButton.icon(
                onPressed: _busy ? null : _import,
                icon: const Icon(Icons.file_download_outlined),
                label: const Text('Restore from backup file'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}
