import 'package:flutter/material.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import 'auth/session_manager.dart';
import 'security/cache_janitor.dart';
import 'ui/list/vault_list_screen.dart';
import 'ui/shared/app_theme.dart';
import 'ui/setup/setup_screen.dart';
import 'ui/unlock/unlock_screen.dart';
import 'vault/vault_repository.dart';
import 'vault/vault_state.dart';

void main() {
  WidgetsFlutterBinding.ensureInitialized();
  runApp(const ProviderScope(child: VaultApp()));
}

class VaultApp extends StatelessWidget {
  const VaultApp({super.key});

  @override
  Widget build(BuildContext context) {
    return MaterialApp(
      title: 'Vault',
      debugShowCheckedModeBanner: false,
      theme: buildVaultTheme(),
      home: const _Root(),
    );
  }
}

class _Root extends ConsumerWidget {
  const _Root();

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final repoAsync = ref.watch(vaultRepositoryProvider);
    return repoAsync.when(
      loading: () => const _Splash(),
      error: (e, st) => _ErrorScreen(error: e),
      data: (_) {
        // Eagerly start the session manager once the repo is ready.
        ref.watch(sessionManagerProvider);
        // Every lock path funnels through this transition; remove any
        // plaintext picker/share residue left in the cache directory.
        ref.listen<VaultStatus>(vaultStatusProvider, (previous, next) {
          if (previous is VaultUnlocked && next is! VaultUnlocked) {
            sweepSensitiveCaches();
          }
        });
        final status = ref.watch(vaultStatusProvider);
        return IdleActivityDetector(
          child: switch (status) {
            VaultUninitialized() => const KeyedSubtree(
              key: ValueKey('vault-uninitialized'),
              child: SetupScreen(),
            ),
            VaultLocked() => const KeyedSubtree(
              key: ValueKey('vault-locked'),
              child: UnlockScreen(),
            ),
            VaultUnlocked() => const KeyedSubtree(
              key: ValueKey('vault-unlocked'),
              child: VaultListScreen(),
            ),
          },
        );
      },
    );
  }
}

class _Splash extends StatelessWidget {
  const _Splash();

  @override
  Widget build(BuildContext context) =>
      const Scaffold(body: Center(child: CircularProgressIndicator()));
}

class _ErrorScreen extends StatelessWidget {
  const _ErrorScreen({required this.error});
  final Object error;

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Padding(
        padding: const EdgeInsets.all(32),
        child: Center(
          child: Text(
            'Failed to start: $error',
            style: Theme.of(context).textTheme.bodyLarge,
          ),
        ),
      ),
    );
  }
}
