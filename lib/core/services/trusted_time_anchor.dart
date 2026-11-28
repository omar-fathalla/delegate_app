import 'dart:convert';

import 'package:shared_preferences/shared_preferences.dart';

/// The last server time the phone saw, tied to the boot clock (TAS-363).
///
/// Saved on the phone on every successful sync, so the trusted time survives
/// the app being closed: `now = serverMs + (bootNow - bootMs)`. It does not
/// survive a reboot (the boot clock restarts), which is detected.
class TrustedTimeAnchor {
  const TrustedTimeAnchor({
    required this.serverMs,
    required this.bootMs,
    required this.wallMs,
  });

  /// Server time at the sync (ms since epoch).
  final int serverMs;

  /// Boot clock at the sync (ms since boot).
  final int bootMs;

  /// The phone's own clock at the sync, only to spot a reboot.
  final int wallMs;

  Map<String, dynamic> toJson() => {
    'serverMs': serverMs,
    'bootMs': bootMs,
    'wallMs': wallMs,
  };

  static TrustedTimeAnchor? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final s = raw['serverMs'], b = raw['bootMs'], w = raw['wallMs'];
    if (s is! int || b is! int || w is! int) return null;
    return TrustedTimeAnchor(serverMs: s, bootMs: b, wallMs: w);
  }
}

/// Stores the anchor in SharedPreferences (one per device, not per user: it
/// is only a clock). Not cleared on logout.
class TrustedTimeAnchorStore {
  TrustedTimeAnchorStore(this._prefs);

  static const String key = 'trusted_time_anchor_v1';

  final SharedPreferences _prefs;

  TrustedTimeAnchor? read() {
    try {
      final raw = _prefs.getString(key);
      if (raw == null) return null;
      return TrustedTimeAnchor.fromJson(json.decode(raw));
    } catch (_) {
      return null;
    }
  }

  Future<void> write(TrustedTimeAnchor anchor) async {
    try {
      await _prefs.setString(key, json.encode(anchor.toJson()));
    } catch (_) {}
  }
}

/// Why an offline time is not trusted.
enum OfflineTimeIssue { noSync, noBootClock, rebooted }

/// The time an offline check-in / check-out is saved with.
class OfflineTimeCapture {
  const OfflineTimeCapture({
    required this.atMs,
    required this.trusted,
    this.syncedAtMs,
    this.issue,
  });

  /// Trusted time when [trusted], else the phone's own clock (display only:
  /// the server then counts from the time the record reaches it).
  final int atMs;
  final bool trusted;

  /// Server time of the last sync, sent so the server can check the limits.
  final int? syncedAtMs;
  final OfflineTimeIssue? issue;

  DateTime get at => DateTime.fromMillisecondsSinceEpoch(atMs);
}

/// A reboot is assumed when the boot clock went back, or when the implied
/// boot moment (`wall - boot`) moved by more than this. The second check
/// catches a reboot followed by a long uptime; it also fires when the user
/// changes the phone's clock, which is then flagged untrusted too (safe side:
/// hours count from arrival and HR can adjust).
const Duration kBootShiftTolerance = Duration(minutes: 10);

/// Pure decision behind [TrustedTimeService.captureOfflineTime].
OfflineTimeCapture decideOfflineCapture({
  required TrustedTimeAnchor? anchor,
  required int? bootNowMs,
  required int wallNowMs,
}) {
  if (anchor == null) {
    return OfflineTimeCapture(
      atMs: wallNowMs,
      trusted: false,
      issue: OfflineTimeIssue.noSync,
    );
  }
  if (bootNowMs == null) {
    return OfflineTimeCapture(
      atMs: wallNowMs,
      trusted: false,
      syncedAtMs: anchor.serverMs,
      issue: OfflineTimeIssue.noBootClock,
    );
  }
  final bootShift = ((wallNowMs - bootNowMs) - (anchor.wallMs - anchor.bootMs))
      .abs();
  if (bootNowMs < anchor.bootMs ||
      bootShift > kBootShiftTolerance.inMilliseconds) {
    return OfflineTimeCapture(
      atMs: wallNowMs,
      trusted: false,
      syncedAtMs: anchor.serverMs,
      issue: OfflineTimeIssue.rebooted,
    );
  }
  return OfflineTimeCapture(
    atMs: anchor.serverMs + (bootNowMs - anchor.bootMs),
    trusted: true,
    syncedAtMs: anchor.serverMs,
  );
}
