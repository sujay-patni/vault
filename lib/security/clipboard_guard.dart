import 'dart:async';

import 'package:flutter/services.dart';
import 'package:hooks_riverpod/hooks_riverpod.dart';

/// How long a copied secret may stay on the system clipboard.
const clipboardClearAfter = Duration(seconds: 30);

/// Owns the lifetime of sensitive values placed on the system clipboard.
///
/// Lives for the whole app session (not a screen) so the clear timer survives
/// navigation and vault lock — the copy-then-paste-into-another-app flow must
/// keep working through the auto-lock that backgrounding triggers, which is
/// why locking does not clear the clipboard immediately.
///
/// Best-effort by design: Android may freeze the process before the timer
/// fires. Android 13+ additionally auto-clears the clipboard after a while.
class ClipboardGuard {
  Timer? _timer;
  bool _ownsClipboard = false;

  /// Puts [value] on the clipboard and (re)arms the clear timer.
  Future<void> copySensitive(String value) async {
    await Clipboard.setData(ClipboardData(text: value));
    _ownsClipboard = true;
    _timer?.cancel();
    _timer = Timer(clipboardClearAfter, clearNow);
  }

  /// Clears the clipboard if the most recent write came from us. Never
  /// throws — the platform channel can fail while backgrounded.
  Future<void> clearNow() async {
    _timer?.cancel();
    _timer = null;
    if (!_ownsClipboard) return;
    _ownsClipboard = false;
    try {
      await Clipboard.setData(const ClipboardData(text: ''));
    } catch (_) {}
  }

  void dispose() {
    _timer?.cancel();
    _timer = null;
  }
}

final clipboardGuardProvider = Provider<ClipboardGuard>((ref) {
  final guard = ClipboardGuard();
  ref.onDispose(guard.dispose);
  return guard;
});
