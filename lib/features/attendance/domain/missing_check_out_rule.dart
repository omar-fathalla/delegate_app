import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:flutter/foundation.dart';

/// TAS-362: a forgotten session (no check-out) counts **zero** hours until HR
/// sets the check-out (user decision 26 Nov 2026).
///
/// Applies only to sessions that start on or after a date stored in
/// `system_config/attendance_rules.missingCheckOutRuleFrom` (user decision
/// 27 Nov 2026: not retroactive; payroll is computed when the screen opens,
/// so past months keep the old full-shift rule). No date = the rule is off.
abstract final class MissingCheckOutRule {
  static const String configPath = 'system_config/attendance_rules';
  static const String fromField = 'missingCheckOutRuleFrom';

  static DateTime? _from;
  static Future<void>? _loading;
  static bool _loaded = false;

  /// Start of the rule, or null while it is off / not loaded.
  static DateTime? get from => _from;

  /// Loads the start date once per app run. Never throws (rule stays off).
  static Future<void> ensureLoaded(FirebaseFirestore firestore) {
    if (_loaded) return Future<void>.value();
    return _loading ??= () async {
      try {
        final snap = await firestore.doc(configPath).get();
        final v = snap.data()?[fromField];
        _from = v is Timestamp ? v.toDate() : null;
      } catch (e) {
        debugPrint('MissingCheckOutRule: config unavailable, rule off ($e)');
        _from = null;
      }
      _loaded = true;
    }();
  }

  @visibleForTesting
  static void debugSet(DateTime? from) {
    _from = from;
    _loaded = true;
    _loading = null;
  }

  @visibleForTesting
  static void debugReset() {
    _from = null;
    _loaded = false;
    _loading = null;
  }

  /// True when the session must count zero hours (shown as «انصراف مش متسجل»).
  ///
  /// [flagged]: `missingCheckOut` or `isAutoCheckOut` on the check-in or the
  /// check-out record (any writer: the server job, or an old app build that
  /// still closes sessions itself). [manuallyAdjusted]: HR set the times.
  static bool isUnpaid({
    required DateTime checkIn,
    DateTime? checkOut,
    required bool flagged,
    bool manuallyAdjusted = false,
    required DateTime now,
    DateTime? ruleFrom,
  }) {
    final start = ruleFrom ?? _from;
    if (start == null || checkIn.isBefore(start)) return false;
    if (manuallyAdjusted) return false;
    if (flagged) return true;
    return checkOut == null && now.difference(checkIn) >= kAttendanceAutoCloseAfter;
  }

  /// `missingCheckOut` / `isAutoCheckOut` on any of the session's records.
  static bool flaggedIn(Iterable<Map<String, dynamic>?> records) => records.any(
        (r) => r != null && (r['missingCheckOut'] == true || r['isAutoCheckOut'] == true),
      );

  /// HR set the session times by hand on any of its records.
  static bool adjustedIn(Iterable<Map<String, dynamic>?> records) =>
      records.any((r) => r != null && r['isManuallyAdjusted'] == true);
}
