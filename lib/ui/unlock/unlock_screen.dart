import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../crypto/secure_bytes.dart';
import '../../crypto/vault_crypto.dart';
import '../../vault/vault_repository.dart';
import '../shared/app_theme.dart';
import '../shared/responsive.dart';

class UnlockScreen extends ConsumerStatefulWidget {
  const UnlockScreen({super.key});

  @override
  ConsumerState<UnlockScreen> createState() => _UnlockScreenState();
}

class _UnlockScreenState extends ConsumerState<UnlockScreen> {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;

  @override
  void dispose() {
    _pw.dispose();
    super.dispose();
  }

  Future<void> _unlock() async {
    setState(() {
      _error = null;
      _busy = true;
    });
    final pwBytes = passwordToUtf8Bytes(_pw.text);
    try {
      await ref
          .read(vaultStatusProvider.notifier)
          .unlock(masterPasswordUtf8: pwBytes);
      if (mounted) _pw.clear();
    } catch (_) {
      if (mounted) setState(() => _error = 'Wrong password.');
    } finally {
      pwBytes.secureZero();
      if (mounted) setState(() => _busy = false);
    }
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
              const Center(child: _LockMark()),
              const SizedBox(height: VaultSpacing.xl),
              Text(
                'Unlock Vault',
                style: Theme.of(context).textTheme.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w600,
                ),
                textAlign: TextAlign.center,
              ),
              const SizedBox(height: VaultSpacing.xl),
              TextField(
                controller: _pw,
                obscureText: true,
                autofocus: true,
                enabled: !_busy,
                onSubmitted: (_) => _unlock(),
                decoration: const InputDecoration(
                  labelText: 'Master password',
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
                onPressed: _busy ? null : _unlock,
                child: _busy
                    ? const SizedBox(
                        width: 18,
                        height: 18,
                        child: CircularProgressIndicator(strokeWidth: 2),
                      )
                    : const Text('Unlock'),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _LockMark extends StatelessWidget {
  const _LockMark();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 64,
      height: 64,
      decoration: BoxDecoration(
        color: VaultColors.surface,
        borderRadius: BorderRadius.circular(VaultRadii.md),
        border: Border.all(color: VaultColors.border),
      ),
      child: const Icon(
        Icons.lock_outline,
        size: 32,
        color: VaultColors.primary,
      ),
    );
  }
}
