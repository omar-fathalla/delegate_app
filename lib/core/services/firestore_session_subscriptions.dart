import 'dart:async';

/// Process-wide registry of Firestore [StreamSubscription]s that must be
/// cancelled on logout *before* FirebaseAuth.signOut, not only in dispose
/// (which can run after the token is already gone and the listener gets
/// PERMISSION_DENIED).
class FirestoreSessionSubscriptions {
  FirestoreSessionSubscriptions._();
  static final FirestoreSessionSubscriptions instance =
      FirestoreSessionSubscriptions._();

  final Map<String, StreamSubscription<dynamic>> _subs = {};

  /// Replaces any previous subscription stored under [key].
  void register(String key, StreamSubscription<dynamic> sub) {
    final previous = _subs[key];
    _subs[key] = sub;
    if (previous != null && !identical(previous, sub)) {
      unawaited(previous.cancel());
    }
  }

  Future<void> cancel(String key) async {
    final sub = _subs.remove(key);
    if (sub != null) await sub.cancel();
  }

  /// Cancels every registered listener. Safe to call more than once.
  Future<void> cancelAll() async {
    final pending = _subs.values.toList(growable: false);
    _subs.clear();
    if (pending.isEmpty) return;
    await Future.wait(pending.map((s) => s.cancel()));
  }

  int get length => _subs.length;

  /// Test-only.
  void debugReset() {
    for (final s in _subs.values) {
      unawaited(s.cancel());
    }
    _subs.clear();
  }
}
