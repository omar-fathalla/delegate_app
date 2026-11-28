// TAS-363: the offline attendance queue (one per delegate).
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

OfflineAttendanceAction checkIn(String id, {String delegate = 'd1'}) =>
    OfflineAttendanceAction(
      id: id,
      kind: OfflineAttendanceAction.checkInKind,
      delegateId: delegate,
      attendanceId: id,
      lat: 30.04,
      lng: 31.23,
      capturedAtMs: 1000,
      timeTrusted: true,
      syncedAtMs: 500,
      checkIn: const {
        'organizationId': 'o1',
        'companyId': 'c1',
        'branchId': 'b1',
      },
    );

void main() {
  late SharedPreferences prefs;
  late AttendanceOfflineQueueImpl queue;

  setUp(() async {
    SharedPreferences.setMockInitialValues({
      legacyOfflineQueueKey: <String>['{}'],
    });
    prefs = await SharedPreferences.getInstance();
    queue = AttendanceOfflineQueueImpl(sharedPreferences: prefs);
  });

  test('add keeps the order; the same key is not added twice', () async {
    await queue.add(checkIn('k1'));
    await queue.add(checkIn('k2'));
    await queue.add(checkIn('k1'));
    expect(queue.pending('d1').map((a) => a.id), ['k2', 'k1']);
    expect(queue.pendingCount('d1'), 2);
  });

  test('remove takes out only that item', () async {
    await queue.add(checkIn('k1'));
    await queue.add(checkIn('k2'));
    await queue.remove('d1', 'k1');
    expect(queue.pending('d1').map((a) => a.id), ['k2']);
    await queue.remove('d1', 'k2');
    expect(
      prefs.getKeys().where((k) => k.startsWith(offlineAttendanceQueuePrefix)),
      isEmpty,
    );
  });

  test('one queue per delegate', () async {
    await queue.add(checkIn('k1', delegate: 'd1'));
    await queue.add(checkIn('k2', delegate: 'd2'));
    expect(queue.pending('d1').map((a) => a.id), ['k1']);
    expect(queue.pending('d2').map((a) => a.id), ['k2']);
    expect(queue.pending(''), isEmpty);
  });

  test('the counter notifier moves on every change', () async {
    final before = queue.changes.value;
    await queue.add(checkIn('k1'));
    await queue.remove('d1', 'k1');
    expect(queue.changes.value, before + 2);
  });

  test('callable data: key as requestId, offline time, no identity', () {
    final data = checkIn('k1').toCallableData();
    expect(data['requestId'], 'k1');
    expect(data['offline'], isTrue);
    expect(data['capturedAtMs'], 1000);
    expect(data['timeTrusted'], isTrue);
    expect(data['syncedAtMs'], 500);
    expect(data.containsKey('delegateId'), isFalse);
    final out = OfflineAttendanceAction(
      id: 'k1_out',
      kind: OfflineAttendanceAction.checkOutKind,
      delegateId: 'd1',
      attendanceId: 'k1',
      lat: 1,
      lng: 2,
      capturedAtMs: 2000,
      timeTrusted: false,
    ).toCallableData();
    expect(out['attendanceId'], 'k1');
    expect(out.containsKey('requestId'), isFalse);
    expect(out.containsKey('syncedAtMs'), isFalse);
  });

  test('the old single-device key is removed', () {
    expect(prefs.containsKey(legacyOfflineQueueKey), isFalse);
  });

  test('logout keeps the queue for the same delegate', () async {
    await queue.add(checkIn('k1'));
    await prefs.setStringList('cachedAttendance_d1', ['x']);
    await AuthLocalDataSourceImpl(sharedPreferences: prefs).clearCachedData();
    expect(prefs.containsKey('cachedAttendance_d1'), isFalse);
    expect(queue.pending('d1').map((a) => a.id), ['k1']);
  });
}
