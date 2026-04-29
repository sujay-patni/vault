import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../backup/backup_errors.dart';
import '../../backup/backup_io.dart';
import '../../auth/session_manager.dart';
import '../../crypto/secure_bytes.dart';
import '../../crypto/vault_crypto.dart';
import '../../security/root_detector.dart';
import '../../vault/vault_repository.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';
import 'change_password_screen.dart';

class SettingsScreen extends ConsumerStatefulWidget {
  const SettingsScreen({super.key});

  @override
  ConsumerState<SettingsScreen> createState() => _SettingsScreenState();
}

class _SettingsScreenState extends ConsumerState<SettingsScreen> {
  bool _exporting = false;
  bool _importing = false;

  Future<void> _export() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Export encrypted backup?'),
        content: const Text(
          'This opens Android file storage so you can choose where to save the '
          'encrypted vault backup. You can cancel here without opening files.',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(false),
            child: const Text('Cancel'),
          ),
          FilledButton(
            onPressed: () => Navigator.of(ctx).pop(true),
            child: const Text('Choose location'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    setState(() => _exporting = true);
    try {
      final bytes = await ref.read(vaultStatusProvider.notifier).readRawBytes();
      final result = await ref
          .read(sessionManagerProvider)
          .runExternalPicker(() => exportBackup(vaultBytes: bytes));
      if (!mounted) return;
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            result.cancelled ? 'Export cancelled.' : 'Backup saved.',
          ),
        ),
      );
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text('Export failed: $e')));
      }
    } finally {
      if (mounted) setState(() => _exporting = false);
    }
  }

  Future<void> _import() async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('Replace vault from backup?'),
        content: const Text(
          'The selected encrypted backup will replace every entry currently '
          'in this vault. Export a fresh backup first if you want to keep the '
          'current vault file.',
        ),
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
            child: const Text('Replace vault'),
          ),
        ],
      ),
    );
    if (!mounted || confirmed != true) return;

    final bytes = await ref
        .read(sessionManagerProvider)
        .runExternalPicker(pickBackupFile);
    if (!mounted || bytes == null) return;

    final password = await _promptForBackupPassword();
    if (!mounted || password == null) return;

    setState(() => _importing = true);
    final pwBytes = passwordToUtf8Bytes(password);
    var imported = false;
    try {
      await _settleExternalRoute();
      if (!mounted) return;
      await ref
          .read(vaultStatusProvider.notifier)
          .importBackup(masterPasswordUtf8: pwBytes, bytes: bytes);
      imported = true;
    } on FormatException catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(
          context,
        ).showSnackBar(SnackBar(content: Text(describeBackupFormatError(e))));
      }
    } catch (_) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(
            content: Text(
              'Import failed: file could not be decrypted with that password.',
            ),
          ),
        );
      }
    } finally {
      pwBytes.secureZero();
      if (mounted) setState(() => _importing = false);
      if (mounted && imported) Navigator.of(context).pop();
    }
  }

  Future<void> _settleExternalRoute() async {
    await Future<void>.delayed(Duration.zero);
    await WidgetsBinding.instance.endOfFrame;
  }

  Future<String?> _promptForBackupPassword() {
    return showDialog<String>(
      context: context,
      builder: (ctx) => _BackupPasswordDialog(),
    );
  }

  @override
  Widget build(BuildContext context) {
    final rooted = ref.watch(rootedDeviceProvider);
    return Scaffold(
      appBar: AppBar(title: const Text('Settings')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            rooted.maybeWhen(
              data: (isRooted) => isRooted
                  ? Container(
                      margin: const EdgeInsets.only(bottom: VaultSpacing.md),
                      padding: const EdgeInsets.all(VaultSpacing.md),
                      decoration: BoxDecoration(
                        color: const Color(0xFF2A1518),
                        borderRadius: BorderRadius.circular(VaultRadii.md),
                        border: Border.all(color: const Color(0xFF5F2930)),
                      ),
                      child: Row(
                        children: [
                          Icon(
                            Icons.warning_amber_rounded,
                            color: Theme.of(context).colorScheme.error,
                          ),
                          const SizedBox(width: VaultSpacing.md),
                          Expanded(
                            child: Text(
                              'Root / jailbreak detected. The vault remains '
                              'encrypted at rest, but a hostile process running '
                              'as root could read your master password while '
                              'you type it.',
                              style: TextStyle(
                                color: Theme.of(context).colorScheme.error,
                              ),
                            ),
                          ),
                        ],
                      ),
                    )
                  : const SizedBox.shrink(),
              orElse: () => const SizedBox.shrink(),
            ),
            _SettingsTile(
              leading: const Icon(Icons.file_upload_outlined),
              title: const Text('Export backup'),
              subtitle: const Text(
                'Save an encrypted copy of the vault to your phone.',
              ),
              trailing: _exporting
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _exporting ? null : _export,
            ),
            _SettingsTile(
              leading: const Icon(Icons.file_download_outlined),
              title: const Text('Restore from backup'),
              subtitle: const Text(
                'Replace this vault with an encrypted backup file.',
              ),
              trailing: _importing
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : null,
              onTap: _importing ? null : _import,
            ),
            _SettingsTile(
              leading: const Icon(Icons.password_outlined),
              title: const Text('Change master password'),
              onTap: () => Navigator.of(context).push(
                MaterialPageRoute(builder: (_) => const ChangePasswordScreen()),
              ),
            ),
            _SettingsTile(
              leading: const Icon(Icons.lock_outline),
              title: const Text('Lock now'),
              onTap: () {
                ref.read(vaultStatusProvider.notifier).lock();
                Navigator.of(context).popUntil((r) => r.isFirst);
              },
            ),
          ],
        ),
      ),
    );
  }
}

class _BackupPasswordDialog extends StatefulWidget {
  const _BackupPasswordDialog();

  @override
  State<_BackupPasswordDialog> createState() => _BackupPasswordDialogState();
}

class _BackupPasswordDialogState extends State<_BackupPasswordDialog> {
  final _ctrl = TextEditingController();

  @override
  void dispose() {
    _ctrl.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AlertDialog(
      title: const Text('Backup master password'),
      content: TextField(
        controller: _ctrl,
        obscureText: true,
        autofocus: true,
        decoration: const InputDecoration(
          labelText: 'Master password for the backup',
          border: OutlineInputBorder(),
        ),
        onSubmitted: (v) => Navigator.of(context).pop(v),
      ),
      actions: [
        TextButton(
          onPressed: () => Navigator.of(context).pop(),
          child: const Text('Cancel'),
        ),
        FilledButton(
          onPressed: () => Navigator.of(context).pop(_ctrl.text),
          child: const Text('Restore'),
        ),
      ],
    );
  }
}

class _SettingsTile extends StatelessWidget {
  const _SettingsTile({
    required this.leading,
    required this.title,
    this.subtitle,
    this.trailing,
    this.onTap,
  });

  final Widget leading;
  final Widget title;
  final Widget? subtitle;
  final Widget? trailing;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.only(bottom: VaultSpacing.sm),
      child: ListTile(
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(VaultRadii.md),
          side: const BorderSide(color: VaultColors.border),
        ),
        tileColor: VaultColors.surface,
        leading: leading,
        title: title,
        subtitle: subtitle,
        trailing: trailing,
        onTap: onTap,
      ),
    );
  }
}
