import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late AttendanceRemoteDataSourceImpl dataSource;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = FakeFirebaseFirestore();
    dataSource = AttendanceRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  test('checkIn should create a document', () async {
    // Act
    final result = await dataSource.checkIn(
      'user1',
      10.0,
      20.0,
      branchName: 'branchA',
    );

    // Assert
    expect(result, isA<AttendanceModel>());
    expect(result.userId, 'user1');
    expect(result.latitude, 10.0);
    expect(result.longitude, 20.0);
    expect(result.branchName, 'branchA');

    // Verify document creation in fake firestore
    final snapshot = await fakeFirestore.collection('attendance').get();
    expect(snapshot.docs.length, 1);
    final doc = snapshot.docs.first;
    expect(doc.data()['userId'], 'user1');
    expect(doc.data()['branchName'], 'branchA');
    expect(doc.data()['latitude'], 10.0);
    expect(doc.data()['longitude'], 20.0);
    expect(doc.data()['checkInTime'], isNotNull);
  });
}
