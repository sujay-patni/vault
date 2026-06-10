import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../../auth/biometric_store.dart';
import '../../auth/biometric_unlock.dart';
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

class _UnlockScreenState extends ConsumerState<UnlockScreen>
    with WidgetsBindingObserver {
  final _pw = TextEditingController();
  bool _busy = false;
  String? _error;
  bool _bioBusy = false;
  bool _autoPrompted = false;
  bool _bioDisabledThisSession = false;

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    // The router remounts this screen on every lock, so "once per mount"
    // means one auto-prompt per lock cycle.
    WidgetsBinding.instance.addPostFrameCallback((_) => _maybeAutoPrompt());
  }

  @override
  void dispose() {
    WidgetsBinding.instance.removeObserver(this);
    _pw.dispose();
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    // Locking on background mounts this screen while the app is paused;
    // defer the auto-prompt until the user actually returns.
    if (state == AppLifecycleState.resumed) {
      _maybeAutoPrompt();
    }
  }

  Future<void> _maybeAutoPrompt() async {
    if (_autoPrompted || _bioBusy || _busy || !mounted) return;
    if (WidgetsBinding.instance.lifecycleState != AppLifecycleState.resumed) {
      return;
    }
    final enabled = await ref.read(biometricEnabledProvider.future);
    final support = await ref.read(biometricSupportProvider.future);
    if (!mounted || !enabled || support != BiometricSupport.available) return;
    _autoPrompted = true;
    await _tryBiometric();
  }

  bool get _showBiometricButton {
    if (_bioDisabledThisSession) return false;
    final enabled = ref.watch(biometricEnabledProvider).value ?? false;
    final support = ref.watch(biometricSupportProvider).value;
    return enabled && support == BiometricSupport.available;
  }

  Future<void> _tryBiometric() async {
    setState(() {
      _error = null;
      _bioBusy = true;
    });
    try {
      final outcome = await ref
          .read(biometricUnlockServiceProvider)
          .attemptUnlock();
      if (!mounted) return;
      switch (outcome) {
        case BiometricUnlockOutcome.success:
          // Router swaps to the vault list.
          break;
        case BiometricUnlockOutcome.canceled:
          break;
        case BiometricUnlockOutcome.invalidated:
          setState(() {
            _bioDisabledThisSession = true;
            _error =
                'Fingerprint sign-in needs to be set up again. Unlock with '
                'your master password, then re-enable it in Settings.';
          });
        case BiometricUnlockOutcome.unavailable:
          setState(
            () => _error = 'Fingerprint unavailable — use your master '
                'password.',
          );
      }
    } finally {
      if (mounted) setState(() => _bioBusy = false);
    }
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
                autocorrect: false,
                enableSuggestions: false,
                enableIMEPersonalizedLearning: false,
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
              if (_showBiometricButton) ...[
                const SizedBox(height: VaultSpacing.lg),
                Center(
                  child: IconButton(
                    onPressed: (_busy || _bioBusy) ? null : _tryBiometric,
                    iconSize: 36,
                    tooltip: 'Unlock with fingerprint',
                    icon: const Icon(
                      Icons.fingerprint,
                      color: VaultColors.primary,
                    ),
                  ),
                ),
              ],
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
