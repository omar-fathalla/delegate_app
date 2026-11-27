import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_server_api.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-361 phase 2: check-in / check-out go through the server callables.
/// The fake server writes the record the way the real callable does.
class _FakeServer implements AttendanceServerApi {
  _FakeServer(this.fs, {this.error});

  final FakeFirebaseFirestore fs;
  Object? error;
  final calls = <String, Map<String, dynamic>>{};
  bool write = true;

  @override
  Future<Map<String, dynamic>> checkIn(Map<String, dynamic> data) async {
    calls['in'] = data;
    if (write) {
      await fs.collection(kAttendanceCollection).doc(data['requestId'] as String).set({
        'delegateId': 'user1',
        'type': 'check_in',
        'organizationId': data['organizationId'],
        'companyId': data['companyId'],
        'branchId': data['branchId'],
        'timestamp': Timestamp.now(),
        'location': {'latitude': data['lat'], 'longitude': data['lng']},
        'branchName': data['branchName'],
        'source': 'server',
      });
    }
    if (error != null) throw error!;
    return {'ok': true, 'attendanceId': data['requestId']};
  }

  @override
  Future<Map<String, dynamic>> checkOut(Map<String, dynamic> data) async {
    calls['out'] = data;
    if (error != null) throw error!;
    final id = data['attendanceId'] as String;
    await fs.collection(kAttendanceCollection).doc(id).update({
      'checkOutTime': Timestamp.now(),
      'checkOutDocId': '${id}_out',
    });
    return {'ok': true, 'outsideBranch': true};
  }
}

void main() {
  late FakeFirebaseFirestore fs;

  setUp(() => fs = FakeFirebaseFirestore());

  Future<String> checkIn(AttendanceRemoteDataSourceImpl ds, {String? branchId = 'b1'}) async {
    final m = await ds.checkIn(
      'user1',
      30.0449,
      31.2357,
      companyId: 'company1',
      organizationId: 'org1',
      deviceInfo: 'device1',
      branchName: 'Fake Alpha',
      branchId: branchId,
    );
    return m.id;
  }

  test('check-in goes to the server with the branch id and a stable request id', () async {
    final server = _FakeServer(fs);
    final ds = AttendanceRemoteDataSourceImpl(firestore: fs, serverApi: server);
    final id = await checkIn(ds);
    final sent = server.calls['in']!;
    expect(sent['requestId'], id);
    expect(sent['branchId'], 'b1');
    expect(sent['branchOrganizationUID'], 'org1');
    expect(sent['lat'], 30.0449);
    expect(sent.containsKey('delegateId'), isFalse, reason: 'identity comes from the token');
    final rec = (await fs.collection(kAttendanceCollection).doc(id).get()).data()!;
    expect(rec['source'], 'server', reason: 'no second, direct write');
  });

  test('a server refusal shows the server message and writes nothing', () async {
    final server = _FakeServer(fs, error: const ServerFailure('إنت برّه نطاق الفرع (222 متر). المسموح 150 متر.'))
      ..write = false;
    final ds = AttendanceRemoteDataSourceImpl(firestore: fs, serverApi: server);
    await expectLater(
      checkIn(ds),
      throwsA(isA<ServerFailure>().having((f) => f.message, 'message', contains('برّه نطاق الفرع'))),
    );
    expect((await fs.collection(kAttendanceCollection).get()).docs, isEmpty);
  });

  test('callable not deployed yet: old direct write', () async {
    final server = _FakeServer(fs, error: const AttendanceServerUnavailable())..write = false;
    final ds = AttendanceRemoteDataSourceImpl(firestore: fs, serverApi: server);
    final id = await checkIn(ds);
    final rec = (await fs.collection(kAttendanceCollection).doc(id).get()).data()!;
    expect(rec['type'], 'check_in');
    expect(rec.containsKey('source'), isFalse);
  });

  test('timeout but the record landed: success; did not land: unknown message', () async {
    final landed = _FakeServer(fs, error: const AttendanceServerUncertain());
    final id = await checkIn(AttendanceRemoteDataSourceImpl(firestore: fs, serverApi: landed));
    expect((await fs.collection(kAttendanceCollection).doc(id).get()).exists, isTrue);

    final fs2 = FakeFirebaseFirestore();
    final lost = _FakeServer(fs2, error: const AttendanceServerUncertain())..write = false;
    final ds2 = AttendanceRemoteDataSourceImpl(firestore: fs2, serverApi: lost);
    await expectLater(
      ds2.checkIn('user1', 30.0, 31.0,
          companyId: 'company1', organizationId: 'org1', deviceInfo: 'd', branchName: 'x', branchId: 'b1'),
      throwsA(isA<ServerFailure>().having((f) => f.message, 'message', kCheckInUnknownMessage)),
    );
  });

  test('legacy branch without id: old direct write, the server is not called', () async {
    final server = _FakeServer(fs);
    final ds = AttendanceRemoteDataSourceImpl(firestore: fs, serverApi: server);
    await checkIn(ds, branchId: null);
    expect(server.calls.containsKey('in'), isFalse);
  });

  test('check-out goes to the server; no direct batch', () async {
    final server = _FakeServer(fs);
    final ds = AttendanceRemoteDataSourceImpl(firestore: fs, serverApi: server);
    final id = await checkIn(ds);
    await ds.checkOut(id, 'org1', 30.06, 31.25);
    expect(server.calls['out'], {'attendanceId': id, 'lat': 30.06, 'lng': 31.25});
    expect((await fs.collection(kAttendanceCollection).doc('${id}_out').get()).exists, isFalse,
        reason: 'the fake server only stamps the check-in; the app wrote nothing itself');
  });

  test('attendanceServerError maps callable codes', () {
    expect(attendanceServerError('not-found', null, null), isA<AttendanceServerUnavailable>());
    expect(attendanceServerError('unavailable', null, null), isA<AttendanceServerUncertain>());
    final f = attendanceServerError('failed-precondition', {'reason': 'same_branch_today', 'message': 'رسالة'}, 'x');
    expect(f, isA<ServerFailure>().having((f) => f.message, 'message', 'رسالة'));
  });
}
