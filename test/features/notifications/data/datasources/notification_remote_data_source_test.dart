import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockCollectionReference<T> extends Mock implements CollectionReference<T> {}
class MockDocumentReference<T> extends Mock implements DocumentReference<T> {}
class MockQuery<T> extends Mock implements Query<T> {}
class MockQuerySnapshot<T> extends Mock implements QuerySnapshot<T> {}
class MockQueryDocumentSnapshot<T> extends Mock implements QueryDocumentSnapshot<T> {}
class MockWriteBatch extends Mock implements WriteBatch {}

void main() {
  late NotificationRemoteDataSourceImpl dataSource;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference<Map<String, dynamic>> mockCollection;
  late MockDocumentReference<Map<String, dynamic>> mockDocument;
  late MockQuery<Map<String, dynamic>> mockQuery;
  late MockQuerySnapshot<Map<String, dynamic>> mockQuerySnapshot;
  late MockQueryDocumentSnapshot<Map<String, dynamic>> mockQueryDoc;
  late MockWriteBatch mockWriteBatch;

  setUpAll(() {
    registerFallbackValue(MockDocumentReference<Map<String, dynamic>>());
  });

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockCollection = MockCollectionReference();
    mockDocument = MockDocumentReference();
    mockQuery = MockQuery();
    mockQuerySnapshot = MockQuerySnapshot();
    mockQueryDoc = MockQueryDocumentSnapshot();
    mockWriteBatch = MockWriteBatch();

    dataSource = NotificationRemoteDataSourceImpl(firestore: mockFirestore);

    when(() => mockFirestore.collection(any())).thenReturn(mockCollection);
  });

  group('getNotifications', () {
    test('should return list of NotificationModel on success', () async {
      when(() => mockCollection.where('delegateUid', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.where('organizationId', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.limit(any())).thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      
      // Need a mutable list for sorting in the implementation
      final docsList = [mockQueryDoc];
      when(() => mockQuerySnapshot.docs).thenReturn(docsList);
      
      final data = {
        'delegateUid': 'delegate123',
        'organizationId': 'org123',
        'companyId': 'company123',
        'title': 'Title',
        'body': 'Body',
        'type': 'general',
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime(2023, 1, 1)),
      };
      when(() => mockQueryDoc.data()).thenReturn(data);
      when(() => mockQueryDoc.id).thenReturn('notif123');

      final result = await dataSource.getNotifications('delegate123', 'org123');

      expect(result, isA<List<NotificationModel>>());
      expect(result.length, 1);
      expect(result.first.id, 'notif123');
    });
  });

  group('getUnreadCount', () {
    test('should return stream of int representing unread notifications', () {
      when(() => mockCollection.where('delegateUid', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.limit(any())).thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockFirestore.collection(any())).thenReturn(mockCollection);
      when(() => mockCollection.doc(any())).thenReturn(mockDocument);
      when(() => mockDocument.get()).thenAnswer((_) async => mockQueryDoc);
      when(() => mockQueryDoc.exists).thenReturn(false);

      final data = {
        'delegateUid': 'delegate123',
        'organizationId': 'org123',
        'companyId': 'company123',
        'title': 'Title',
        'body': 'Body',
        'type': 'general',
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime(2023, 1, 1)),
      };
      when(() => mockQuerySnapshot.docs).thenReturn([mockQueryDoc, mockQueryDoc]);
      when(() => mockQueryDoc.data()).thenReturn(data);
      when(() => mockQueryDoc.id).thenReturn('notif123');

      final result = dataSource.getUnreadCount('delegate123', 'org123');

      expect(result, emits(1));
    });
  });

  group('markAsRead', () {
    test('should update isRead field to true', () async {
      when(() => mockCollection.doc(any())).thenReturn(mockDocument);
      when(() => mockDocument.update(any())).thenAnswer((_) async => {});

      await dataSource.markAsRead('notif123');

      verify(() => mockCollection.doc('notif123')).called(1);
      verify(() => mockDocument.update(any())).called(1);
    });
  });

  group('markAllAsRead', () {
    test('should update isRead to true for all unread notifications', () async {
      when(() => mockCollection.where('delegateUid', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.where('organizationId', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.where('isRead', isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockQueryDoc, mockQueryDoc]);
      when(() => mockQueryDoc.reference).thenReturn(mockDocument);

      when(() => mockFirestore.batch()).thenReturn(mockWriteBatch);
      when(() => mockWriteBatch.update(any(), any())).thenReturn(null);
      when(() => mockWriteBatch.commit()).thenAnswer((_) async => []);

      await dataSource.markAllAsRead('delegate123', 'org123');

      verify(() => mockFirestore.batch()).called(1);
      verify(() => mockWriteBatch.update<Object?>(mockDocument, any())).called(2);
      verify(() => mockWriteBatch.commit()).called(1);
    });
  });
}
