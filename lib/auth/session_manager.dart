import 'dart:async';

import 'package:flutter/widgets.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

import '../vault/vault_repository.dart';
import '../vault/vault_state.dart';

/// Locks the vault on backgrounding and after a configurable idle timeout
/// while in foreground. Intended to be installed once at the root of the
/// widget tree.
class SessionManager with WidgetsBindingObserver {
  SessionManager(
    this._read, {
    Duration idleTimeout = const Duration(seconds: 60),
  }) : _idleTimeout = idleTimeout;

  final Reader _read;
  final Duration _idleTimeout;
  Timer? _idleTimer;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _resetIdleTimer();
  }

  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Call this on user activity (pointer events) to extend the idle window.
  void bumpActivity() {
    _resetIdleTimer();
  }

  void _resetIdleTimer() {
    _idleTimer?.cancel();
    _idleTimer = Timer(_idleTimeout, _lockIfUnlocked);
  }

  void _lockIfUnlocked() {
    final status = _read(vaultStatusProvider);
    if (status is VaultUnlocked) {
      _read(vaultStatusProvider.notifier).lock();
    }
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    switch (state) {
      case AppLifecycleState.paused:
      case AppLifecycleState.hidden:
      case AppLifecycleState.detached:
        _idleTimer?.cancel();
        _lockIfUnlocked();
        break;
      case AppLifecycleState.resumed:
        _resetIdleTimer();
        break;
      case AppLifecycleState.inactive:
        // Transient (e.g. incoming call overlay). Don't lock here — wait for
        // a hard pause.
        break;
    }
  }
}

typedef Reader = T Function<T>(ProviderListenable<T> provider);

/// Provider that owns the [SessionManager] singleton for the app lifetime.
final sessionManagerProvider = Provider<SessionManager>((ref) {
  final manager = SessionManager(ref.read);
  manager.start();
  ref.onDispose(manager.stop);
  return manager;
});

/// Wraps the app in a Listener that bumps the SessionManager's idle timer
/// on every pointer event.
class IdleActivityDetector extends ConsumerWidget {
  const IdleActivityDetector({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context, WidgetRef ref) {
    final session = ref.watch(sessionManagerProvider);
    return Listener(
      behavior: HitTestBehavior.translucent,
      onPointerDown: (_) => session.bumpActivity(),
      onPointerMove: (_) => session.bumpActivity(),
      child: child,
    );
  }
}
