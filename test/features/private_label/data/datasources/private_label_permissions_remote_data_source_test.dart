import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference<T> extends Mock implements CollectionReference<T> {}
class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}
class MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  late PrivateLabelPermissionsRemoteDataSourceImpl dataSource;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference<Map<String, dynamic>> mockPermissionsCollection;
  late MockCollectionReference<Map<String, dynamic>> mockNotificationsCollection;
  late MockDocumentReference<Map<String, dynamic>> mockDocRef;
  late MockWriteBatch mockBatch;

  setUpAll(() {
    registerFallbackValue(MockDocumentReference<Map<String, dynamic>>());
    registerFallbackValue(SetOptions(merge: true));
  });

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockPermissionsCollection = MockCollectionReference();
    mockNotificationsCollection = MockCollectionReference();
    mockDocRef = MockDocumentReference();
    mockBatch = MockWriteBatch();

    when(() => mockFirestore.collection('private_label_permissions'))
        .thenReturn(mockPermissionsCollection);
    when(() => mockFirestore.collection('notifications'))
        .thenReturn(mockNotificationsCollection);
    when(() => mockPermissionsCollection.doc(any())).thenReturn(mockDocRef);
    when(() => mockNotificationsCollection.doc(any())).thenReturn(mockDocRef);
    when(() => mockNotificationsCollection.doc()).thenReturn(mockDocRef);

    when(() => mockFirestore.batch()).thenReturn(mockBatch);
    when(() => mockBatch.set(any(), any(), any())).thenReturn(null);
    when(() => mockBatch.commit()).thenAnswer((_) async => []);

    dataSource = PrivateLabelPermissionsRemoteDataSourceImpl(firestore: mockFirestore);
  });

  group('bulkUpdatePermissions', () {
    test('does nothing when permissionsList is empty', () async {
      await dataSource.bulkUpdatePermissions(
        permissionsList: [],
        adminUid: 'admin_1',
        adminName: 'Admin Test',
      );

      verifyNever(() => mockFirestore.batch());
    });

    test('batches updates and commits for all users', () async {
      final permissionsList = [
        const PrivateLabelPermissions(
          userId: 'user_1',
          userName: 'User One',
          canCapture: true,
          canViewReports: false,
          canReviewAudit: false,
        ),
        const PrivateLabelPermissions(
          userId: 'user_2',
          userName: 'User Two',
          canCapture: true,
          canViewReports: true,
          canReviewAudit: false,
        ),
      ];

      await dataSource.bulkUpdatePermissions(
        permissionsList: permissionsList,
        adminUid: 'admin_1',
        adminName: 'Admin User',
        adminRole: 'superAdmin',
        notificationActionLabel: 'تفعيل التوثيق للجميع',
      );

      verify(() => mockFirestore.batch()).called(1);
      verify(() => mockBatch.set<Map<String, dynamic>>(any(), any(), any(that: isNotNull))).called(2);
      verify(() => mockBatch.set<Map<String, dynamic>>(any(), any(), any(that: isNull))).called(2);
      verify(() => mockBatch.commit()).called(1);
    });

    test('chunks updates properly when list exceeds chunk size', () async {
      final largeList = List.generate(
        250,
        (i) => PrivateLabelPermissions(
          userId: 'user_$i',
          userName: 'User $i',
          canCapture: true,
          canViewReports: false,
          canReviewAudit: false,
        ),
      );

      await dataSource.bulkUpdatePermissions(
        permissionsList: largeList,
        adminUid: 'admin_1',
        adminName: 'Admin User',
      );

      // 250 items chunked by 200 => 2 batches
      verify(() => mockFirestore.batch()).called(2);
      verify(() => mockBatch.commit()).called(2);
    });
  });
}
