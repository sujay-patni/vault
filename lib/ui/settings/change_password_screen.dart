import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../crypto/secure_bytes.dart';
import '../../crypto/vault_crypto.dart';
import '../../vault/vault_repository.dart';
import '../../vault/vault_state.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';

class ChangePasswordScreen extends ConsumerStatefulWidget {
  const ChangePasswordScreen({super.key});

  @override
  ConsumerState<ChangePasswordScreen> createState() =>
      _ChangePasswordScreenState();
}

class _ChangePasswordScreenState extends ConsumerState<ChangePasswordScreen> {
  final _oldPw = TextEditingController();
  final _newPw1 = TextEditingController();
  final _newPw2 = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _oldPw.dispose();
    _newPw1.dispose();
    _newPw2.dispose();
    super.dispose();
  }

  Future<void> _change() async {
    setState(() => _error = null);
    if (_newPw1.text.length < 8) {
      setState(() => _error = 'New password must be at least 8 characters.');
      return;
    }
    if (_newPw1.text != _newPw2.text) {
      setState(() => _error = 'New passwords do not match.');
      return;
    }
    setState(() => _busy = true);

    // Verify the old password by attempting an unlock with it. We cannot trust
    // the current in-memory unlocked state alone, because a session could have
    // been left open by someone else physically holding the device.
    final repo = await ref.read(vaultRepositoryProvider.future);
    final oldBytes = passwordToUtf8Bytes(_oldPw.text);
    final newBytes = passwordToUtf8Bytes(_newPw1.text);
    try {
      final verified = await repo.unlock(masterPasswordUtf8: oldBytes);
      verified.vaultKey.secureZero();
    } catch (_) {
      oldBytes.secureZero();
      newBytes.secureZero();
      if (mounted) {
        setState(() {
          _error = 'Current password is wrong.';
          _busy = false;
        });
      }
      return;
    }

    try {
      final notifier = ref.read(vaultStatusProvider.notifier);
      final cur = ref.read(vaultStatusProvider);
      if (cur is! VaultUnlocked) {
        throw StateError('vault must be unlocked');
      }
      // Use the in-memory vault_key path (same params).
      await notifier.changePassword(newMasterPasswordUtf8: newBytes);
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('Master password changed.')),
        );
        Navigator.of(context).pop();
      }
    } catch (e) {
      if (mounted) {
        setState(() => _error = 'Change failed: $e');
      }
    } finally {
      oldBytes.secureZero();
      newBytes.secureZero();
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Change master password')),
      body: ResponsiveBody(
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            TextField(
              controller: _oldPw,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Current master password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: VaultSpacing.lg),
            TextField(
              controller: _newPw1,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'New master password',
                border: OutlineInputBorder(),
              ),
            ),
            const SizedBox(height: VaultSpacing.lg),
            TextField(
              controller: _newPw2,
              obscureText: true,
              enabled: !_busy,
              decoration: const InputDecoration(
                labelText: 'Confirm new master password',
                border: OutlineInputBorder(),
              ),
            ),
            if (_error != null) ...[
              const SizedBox(height: 12),
              Text(
                _error!,
                style: TextStyle(color: Theme.of(context).colorScheme.error),
              ),
            ],
            const SizedBox(height: VaultSpacing.xl),
            FilledButton(
              onPressed: _busy ? null : _change,
              child: _busy
                  ? const SizedBox(
                      width: 18,
                      height: 18,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : const Text('Change password'),
            ),
            const SizedBox(height: VaultSpacing.sm),
            Text(
              'After changing, the old password will no longer unlock this vault. '
              'Existing entries are preserved.',
              style: Theme.of(context).textTheme.bodySmall?.copyWith(
                color: VaultColors.textMuted,
                height: 1.4,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
