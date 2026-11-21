import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttendanceRemoteDataSourceImpl dataSource;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    dataSource = AttendanceRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  group('supervisor attendance alerts (TAS-71)', () {
    test('check-in writes one supervisor_<company> broadcast with createdBy, no users reads', () async {
      dataSource = AttendanceRemoteDataSourceImpl(
        firestore: fakeFirestore,
        auth: MockFirebaseAuth(signedIn: true, mockUser: MockUser(uid: 'auth_user1')),
      );
      await dataSource.checkIn(
        'user1',
        10.0,
        20.0,
        companyId: 'company1',
        organizationId: 'org1',
        deviceInfo: 'device1',
        branchName: 'branchA',
      );
      // The alert is fire-and-forget; let it finish.
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final notifs = await fakeFirestore.collection('notifications').get();
      expect(notifs.docs, hasLength(1));
      final n = notifs.docs.single.data();
      expect(n['delegateUid'], 'supervisor_company1');
      expect(n['createdBy'], 'auth_user1');
      expect(n['companyUID'], 'company1');
      expect(n['companyId'], 'company1');
      expect(n['organizationUID'], 'org1');
      expect(n['type'], 'attendance_check_in');
      expect(n['attendanceType'], 'check_in');
      expect(n['targetDelegateId'], 'user1');
      expect(n['senderRole'], 'delegate');
    });

    test('createdBy falls back to the delegate user id without auth', () async {
      await dataSource.checkIn(
        'user1',
        10.0,
        20.0,
        companyId: 'company1',
        organizationId: 'org1',
        deviceInfo: 'device1',
        branchName: 'branchA',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);

      final n = (await fakeFirestore.collection('notifications').get()).docs.single.data();
      expect(n['createdBy'], 'user1');
    });

    test('no company means no alert', () async {
      await dataSource.checkIn(
        'user1',
        10.0,
        20.0,
        companyId: '',
        organizationId: 'org1',
        deviceInfo: 'device1',
        branchName: 'branchA',
      );
      await Future<void>.delayed(Duration.zero);
      await Future<void>.delayed(Duration.zero);
      expect((await fakeFirestore.collection('notifications').get()).docs, isEmpty);
    });
  });

  test('checkIn should create a document', () async {
    // Act
    final result = await dataSource.checkIn(
      'user1',
      10.0,
      20.0,
      companyId: 'company1',
      organizationId: 'org1',
      deviceInfo: 'device1',
      branchName: 'branchA',
    );

    // Assert
    expect(result, isA<AttendanceModel>());
    expect(result.userId, 'user1');
    expect(result.latitude, 10.0);
    expect(result.longitude, 20.0);
    expect(result.branchName, 'branchA');

    // Verify document creation in fake firestore
    // Verify document creation in fake firestore
    final snapshot = await fakeFirestore
        .collection(kAttendanceCollection)
        .get();
    expect(snapshot.docs.length, 1);
    final doc = snapshot.docs.first;
    expect(doc.data()['delegateId'], 'user1');
    expect(doc.data()['branchName'], 'branchA');
    expect(doc.data()['location']['latitude'], 10.0);
    expect(doc.data()['location']['longitude'], 20.0);
    expect(doc.data()['timestamp'], isNotNull);
    expect(doc.data()['companyId'], 'company1');
    expect(doc.data()['organizationId'], 'org1');
    expect(doc.data()['deviceInfo'], 'device1');
    expect(doc.data()['type'], 'check_in');
  });

  test('checkIn denormalizes delegateName phone companyName personalPhotoURL', () async {
    final result = await dataSource.checkIn(
      'user_denorm',
      10.0,
      20.0,
      companyId: 'company1',
      organizationId: 'org1',
      deviceInfo: 'device1',
      branchName: 'branchA',
      delegateName: 'أحمد محمد',
      phoneNumber: '01012345678',
      companyName: 'شركة الاختبار',
      personalPhotoURL: 'https://example.com/photo.jpg',
    );
    expect(result.userId, 'user_denorm');
    final doc = await fakeFirestore
        .collection(kAttendanceCollection)
        .doc(result.id)
        .get();
    expect(doc.data()!['delegateName'], 'أحمد محمد');
    expect(doc.data()!['phoneNumber'], '01012345678');
    expect(doc.data()!['companyName'], 'شركة الاختبار');
    expect(doc.data()!['personalPhotoURL'], 'https://example.com/photo.jpg');
  });


  test('checkOut should create a check-out log and stamp checkOutTime on check-in', () async {
    // 1. Arrange - perform a check-in first
    final checkInResult = await dataSource.checkIn(
      'user1',
      10.0,
      20.0,
      companyId: 'company1',
      organizationId: 'org1',
      deviceInfo: 'device1',
      branchName: 'branchA',
    );

    // 2. Act - perform check-out
    final checkOutResult = await dataSource.checkOut(
      checkInResult.id,
      'org1',
      11.0,
      21.0,
    );

    // 3. Assert - check returned model
    expect(checkOutResult.id, checkInResult.id);
    expect(checkOutResult.checkOutTime, isNotNull);
    expect(
      checkOutResult.latitude,
      10.0,
    ); // Should return check-in lat by current impl

    // 4. Verify - check Firestore logs
    final snapshot = await fakeFirestore
        .collection(kAttendanceCollection)
        .where('type', isEqualTo: 'check_out')
        .get();

    expect(snapshot.docs.length, 1);
    final doc = snapshot.docs.first;
    expect(doc.data()['delegateId'], 'user1');
    expect(doc.data()['relatedCheckInId'], checkInResult.id);
    expect(doc.data()['location']['latitude'], 11.0);
    expect(doc.data()['location']['longitude'], 21.0);

    // 5. Fix2: check-in doc carries denormalized checkout fields
    final checkInDoc = await fakeFirestore
        .collection(kAttendanceCollection)
        .doc(checkInResult.id)
        .get();
    expect(checkInDoc.data()!['checkOutTime'], isNotNull);
    expect(checkInDoc.data()!['checkOutDocId'], doc.id);
    expect(checkInDoc.data()!['checkOutLocation']['latitude'], 11.0);
    expect(checkInDoc.data()!['checkOutLocation']['longitude'], 21.0);
  });

  test('getHistory should return merged check-in/out records', () async {
    // Arrange
    final checkIn = await dataSource.checkIn(
      'user1',
      10.0,
      20.0,
      companyId: 'company1',
      organizationId: 'org1',
      deviceInfo: 'device1',
    );
    await dataSource.checkOut(checkIn.id, 'org1', 11.0, 21.0);

    // Act
    final history = await dataSource.getHistory('user1', 'org1');

    // Assert
    expect(history.length, 1);
    expect(history[0].checkOutTime, isNotNull);
  });

  test(
    'findActiveAttendance should return most recent check-in if not checked out',
    () async {
      // Arrange
      await dataSource.checkIn(
        'user1',
        10.0,
        20.0,
        companyId: 'company1',
        organizationId: 'org1',
        deviceInfo: 'device1',
      );

      // Act
      final active = await dataSource.findActiveAttendance('user1', 'org1');

      // Assert
      expect(active, isNotNull);
      expect(active!.userId, 'user1');
    },
  );

  test(
    'findActiveAttendance should return null if most recent log is check-out',
    () async {
      // Arrange
      final checkIn = await dataSource.checkIn(
        'user1',
        10.0,
        20.0,
        companyId: 'company1',
        organizationId: 'org1',
        deviceInfo: 'device1',
      );
      // Small delay to ensure check-out timestamp is strictly after check-in
      await Future.delayed(const Duration(milliseconds: 10));
      await dataSource.checkOut(checkIn.id, 'org1', 11.0, 21.0);

      // Act
      final active = await dataSource.findActiveAttendance('user1', 'org1');

      // Assert
      expect(active, isNull);
    },
  );

  test(
    'findActiveAttendance returns null when check-in already has checkOutTime',
    () async {
      final checkIn = await dataSource.checkIn(
        'user1',
        10.0,
        20.0,
        companyId: 'company1',
        organizationId: 'org1',
        deviceInfo: 'device1',
      );
      // Simulate stamp-only close (no newer check_out log as latest).
      await fakeFirestore.collection(kAttendanceCollection).doc(checkIn.id).update({
        'checkOutTime': Timestamp.now(),
        'checkOutDocId': 'out1',
      });

      final active = await dataSource.findActiveAttendance('user1', 'org1');
      expect(active, isNull);
    },
  );
}
