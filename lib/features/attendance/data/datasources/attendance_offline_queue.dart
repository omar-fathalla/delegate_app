import 'dart:convert';

import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// One check-in or check-out saved on the phone without network (TAS-363).
///
/// [id] is the idempotency key: for a check-in it is also the attendance doc
/// id the server writes (`requestId`), so sending it twice gives one record.
/// A check-out points to its check-in by [attendanceId] (the server id of an
/// online check-in, or the [id] of an offline one still in the queue).
class OfflineAttendanceAction {
  const OfflineAttendanceAction({
    required this.id,
    required this.kind,
    required this.delegateId,
    required this.attendanceId,
    required this.lat,
    required this.lng,
    required this.capturedAtMs,
    required this.timeTrusted,
    this.syncedAtMs,
    this.checkIn = const {},
  });

  static const String checkInKind = 'check_in';
  static const String checkOutKind = 'check_out';

  final String id;
  final String kind;
  final String delegateId;
  final String attendanceId;
  final double lat;
  final double lng;

  /// Trusted time when [timeTrusted], else the phone's own clock.
  final int capturedAtMs;
  final bool timeTrusted;
  final int? syncedAtMs;

  /// Check-in fields the callable needs (organizationId, companyId,
  /// branchId, branchOrganizationUID, branchName, deviceInfo and the
  /// display fields). Empty for a check-out.
  final Map<String, dynamic> checkIn;

  bool get isCheckIn => kind == checkInKind;
  DateTime get capturedAt => DateTime.fromMillisecondsSinceEpoch(capturedAtMs);

  /// The data sent to `delegateCheckIn` / `delegateCheckOut`. The identity
  /// is never sent: the server takes it from the token.
  Map<String, dynamic> toCallableData() => {
    if (isCheckIn) ...checkIn,
    if (isCheckIn) 'requestId': id else 'attendanceId': attendanceId,
    'lat': lat,
    'lng': lng,
    'offline': true,
    'capturedAtMs': capturedAtMs,
    'timeTrusted': timeTrusted,
    'syncedAtMs': ?syncedAtMs,
  };

  Map<String, dynamic> toJson() => {
    'id': id,
    'kind': kind,
    'delegateId': delegateId,
    'attendanceId': attendanceId,
    'lat': lat,
    'lng': lng,
    'capturedAtMs': capturedAtMs,
    'timeTrusted': timeTrusted,
    'syncedAtMs': ?syncedAtMs,
    'checkIn': checkIn,
  };

  static OfflineAttendanceAction? fromJson(Object? raw) {
    if (raw is! Map) return null;
    final id = raw['id'], kind = raw['kind'], delegateId = raw['delegateId'];
    final lat = raw['lat'], lng = raw['lng'], at = raw['capturedAtMs'];
    if (id is! String || kind is! String || delegateId is! String) return null;
    if (lat is! num || lng is! num || at is! int) return null;
    final checkIn = raw['checkIn'];
    return OfflineAttendanceAction(
      id: id,
      kind: kind,
      delegateId: delegateId,
      attendanceId: (raw['attendanceId'] as String?) ?? id,
      lat: lat.toDouble(),
      lng: lng.toDouble(),
      capturedAtMs: at,
      timeTrusted: raw['timeTrusted'] == true,
      syncedAtMs: raw['syncedAtMs'] as int?,
      checkIn: checkIn is Map ? Map<String, dynamic>.from(checkIn) : const {},
    );
  }
}

/// Attendance saved on the phone, one queue per delegate (TAS-363).
///
/// Kept on logout (the delegate is warned first) and sent when the same
/// delegate signs in again. An item leaves the queue only after the server
/// answered for it (written, already written, or refused).
abstract class AttendanceOfflineQueue {
  Future<void> add(OfflineAttendanceAction action);
  List<OfflineAttendanceAction> pending(String delegateId);
  Future<void> remove(String delegateId, String id);
  int pendingCount(String delegateId);

  /// Bumps on every change, for the "waiting to send" counter.
  ValueListenable<int> get changes;
}

/// The old single-device key of the unused queue (removed on start).
const String legacyOfflineQueueKey = 'cachedOfflineAttendanceQueue';

/// Prefix of the per-delegate keys. Must not start with any prefix that
/// `AuthLocalDataSource.clearAllUserCaches` removes on logout.
const String offlineAttendanceQueuePrefix = 'offline_attendance_queue_v1_';

class AttendanceOfflineQueueImpl implements AttendanceOfflineQueue {
  AttendanceOfflineQueueImpl({required this.sharedPreferences}) {
    try {
      sharedPreferences.remove(legacyOfflineQueueKey).ignore();
    } catch (_) {}
  }

  final SharedPreferences sharedPreferences;
  final ValueNotifier<int> _changes = ValueNotifier<int>(0);

  @override
  ValueListenable<int> get changes => _changes;

  String _key(String delegateId) =>
      '$offlineAttendanceQueuePrefix${delegateId.trim()}';

  @override
  List<OfflineAttendanceAction> pending(String delegateId) {
    if (delegateId.trim().isEmpty) return const [];
    try {
      final list =
          sharedPreferences.getStringList(_key(delegateId)) ?? const [];
      return [
        for (final raw in list) ?OfflineAttendanceAction.fromJson(_decode(raw)),
      ].where((a) => a.delegateId == delegateId.trim()).toList();
    } catch (_) {
      return const [];
    }
  }

  static Object? _decode(String raw) {
    try {
      return json.decode(raw);
    } catch (_) {
      return null;
    }
  }

  Future<void> _write(
    String delegateId,
    List<OfflineAttendanceAction> items,
  ) async {
    final key = _key(delegateId);
    if (items.isEmpty) {
      await sharedPreferences.remove(key);
    } else {
      await sharedPreferences.setStringList(
        key,
        items.map((a) => json.encode(a.toJson())).toList(),
      );
    }
    _changes.value++;
  }

  @override
  Future<void> add(OfflineAttendanceAction action) async {
    final items = pending(
      action.delegateId,
    ).where((a) => a.id != action.id).toList()..add(action);
    await _write(action.delegateId, items);
  }

  @override
  Future<void> remove(String delegateId, String id) async {
    final items = pending(delegateId);
    final kept = items.where((a) => a.id != id).toList();
    if (kept.length == items.length) return;
    await _write(delegateId, kept);
  }

  @override
  int pendingCount(String delegateId) => pending(delegateId).length;
}
