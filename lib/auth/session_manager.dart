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
    Duration pickerTimeout = const Duration(minutes: 10),
  }) : _idleTimeout = idleTimeout,
       _pickerTimeout = pickerTimeout;

  final Reader _read;
  final Duration _idleTimeout;
  final Duration _pickerTimeout;
  Timer? _idleTimer;
  Timer? _pickerFallbackTimer;
  int _externalPickerDepth = 0;

  void start() {
    WidgetsBinding.instance.addObserver(this);
    _resetIdleTimer();
  }

  void stop() {
    _idleTimer?.cancel();
    _idleTimer = null;
    _pickerFallbackTimer?.cancel();
    _pickerFallbackTimer = null;
    WidgetsBinding.instance.removeObserver(this);
  }

  /// Call this on user activity (pointer events) to extend the idle window.
  void bumpActivity() {
    _resetIdleTimer();
  }

  /// Temporarily keep the vault unlocked while Android hands control to a
  /// trusted system picker/camera intent. Normal backgrounding still locks.
  /// The exemption is bounded: if the picker has not returned within
  /// [_pickerTimeout] (e.g. the user wandered off from the share sheet),
  /// the vault locks anyway.
  Future<T> runExternalPicker<T>(Future<T> Function() action) async {
    _externalPickerDepth += 1;
    _idleTimer?.cancel();
    _pickerFallbackTimer ??= Timer(_pickerTimeout, _lockIfUnlocked);
    try {
      return await action();
    } finally {
      _externalPickerDepth -= 1;
      if (_externalPickerDepth <= 0) {
        _externalPickerDepth = 0;
        _pickerFallbackTimer?.cancel();
        _pickerFallbackTimer = null;
        _resetIdleTimer();
      }
    }
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
        if (_externalPickerDepth == 0) {
          _lockIfUnlocked();
        }
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
