import 'package:cloud_firestore/cloud_firestore.dart';

/// TAS-370: one leave as the overlap check sees it (dates only, by day).
class LeaveSpan {
  const LeaveSpan({
    required this.id,
    required this.type,
    required this.isHourly,
    required this.status,
    required this.start,
    required this.end,
  });

  final String id;
  final String type;
  final bool isHourly;
  final String status;

  /// First and last day of the leave, at local midnight.
  final DateTime start;
  final DateTime end;

  bool get isApproved => status == 'approved';

  /// Rejected (and cancelled) requests never block anything.
  bool get counts => status == 'pending' || status == 'approved';

  /// Reads a `leave_requests` document; null when it has no usable start.
  static LeaveSpan? fromMap(String id, Map<String, dynamic> data) {
    final start = _day(data['startDate']);
    if (start == null) return null;
    final end = _day(data['endDate']) ?? start;
    return LeaveSpan(
      id: id,
      type: (data['type'] ?? 'annual').toString(),
      isHourly: data['isHourly'] == true,
      status: (data['status'] ?? '').toString(),
      start: start,
      end: end.isBefore(start) ? start : end,
    );
  }

  static DateTime? _day(Object? v) {
    final DateTime? d = v is Timestamp
        ? v.toDate()
        : (v is DateTime ? v : null);
    return d == null ? null : DateTime(d.year, d.month, d.day);
  }
}

/// TAS-370 (L-1): a new or approved leave must not cover days another live
/// leave of the same delegate already covers. Payroll adds `daysCount` per
/// approved leave, so an overlap would be counted twice.
class LeaveOverlap {
  const LeaveOverlap._();

  /// The first pending or approved leave in [existing] that shares a day with
  /// [candidate], approved ones first; null when there is none.
  ///
  /// Two hourly excuses on the same day (a late arrival and an early leave)
  /// are allowed; an hourly excuse inside a full-day leave is not.
  static LeaveSpan? find(LeaveSpan candidate, Iterable<LeaveSpan> existing) {
    LeaveSpan? pending;
    for (final other in existing) {
      if (other.id == candidate.id || !other.counts) continue;
      if (candidate.isHourly && other.isHourly) continue;
      final shares =
          !other.end.isBefore(candidate.start) &&
          !candidate.end.isBefore(other.start);
      if (!shares) continue;
      if (other.isApproved) return other;
      pending ??= other;
    }
    return pending;
  }

  /// Every leave of one delegate in one company (HR side, before approving).
  /// Uses the existing `companyUID + delegateUid` index.
  static Future<List<LeaveSpan>> loadForDelegate(
    FirebaseFirestore db, {
    required String companyUID,
    required String delegateUid,
  }) async {
    final snap = await db
        .collection('leave_requests')
        .where('companyUID', isEqualTo: companyUID)
        .where('delegateUid', isEqualTo: delegateUid)
        .get();
    return [for (final d in snap.docs) ?LeaveSpan.fromMap(d.id, d.data())];
  }
}

/// TAS-370 (L-2, user decision 2026-11-27): how many days back a delegate may
/// file. The rules enforce the same numbers (`leaveBackdateDays`).
class LeaveBackdate {
  const LeaveBackdate._();

  static int daysFor(String type, {required bool isHourly}) {
    if (isHourly) return 30;
    return const {'sick', 'emergency', 'absence'}.contains(type) ? 7 : 0;
  }

  /// First day the date picker offers.
  static DateTime firstDate(
    DateTime today,
    String type, {
    required bool isHourly,
  }) {
    final d = DateTime(today.year, today.month, today.day);
    return d.subtract(Duration(days: daysFor(type, isHourly: isHourly)));
  }
}
