import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/changelog/data/datasources/changelog_remote_datasource.dart';
import 'package:delegate_app/features/changelog/data/models/app_update_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

// ignore: subtype_of_sealed_class
class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}

// ignore: subtype_of_sealed_class
class MockCollectionReference extends Mock
    implements CollectionReference<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockQuerySnapshot extends Mock
    implements QuerySnapshot<Map<String, dynamic>> {}

// ignore: subtype_of_sealed_class
class MockQueryDocumentSnapshot extends Mock
    implements QueryDocumentSnapshot<Map<String, dynamic>> {}

void main() {
  late ChangelogRemoteDataSourceImpl dataSource;
  late MockFirebaseFirestore mockFirestore;
  late MockCollectionReference mockCollectionReference;
  late MockQuery mockQuery;
  late MockQuerySnapshot mockQuerySnapshot;
  late MockQueryDocumentSnapshot mockDocSnapshot;

  setUpAll(() {
    registerFallbackValue(DateTime.now());
  });

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockCollectionReference = MockCollectionReference();
    mockQuery = MockQuery();
    mockQuerySnapshot = MockQuerySnapshot();
    mockDocSnapshot = MockQueryDocumentSnapshot();
    dataSource = ChangelogRemoteDataSourceImpl(firestore: mockFirestore);
  });

  final tDate = DateTime(2023, 1, 1);
  final tJson = {
    'title': 'Test Update',
    'titleEn': 'Test Update EN',
    'description': 'Test Description',
    'descriptionEn': 'Test Description EN',
    'version': '1.0.0',
    'type': 'feature',
    'priority': 'normal',
    'createdAt': Timestamp.fromDate(tDate),
    'isActive': true,
    'highlights': ['H1'],
    'highlightsEn': ['H1 EN'],
  };

  group('getUpdates', () {
    test('should return list of AppUpdateModel when successful', () async {
      when(() => mockFirestore.collection('app_updates'))
          .thenReturn(mockCollectionReference);
      when(() => mockCollectionReference.where('isActive', isEqualTo: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.orderBy('createdAt', descending: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockDocSnapshot]);
      when(() => mockDocSnapshot.data()).thenReturn(tJson);
      when(() => mockDocSnapshot.id).thenReturn('test_id');

      final result = await dataSource.getUpdates();

      expect(result, isA<List<AppUpdateModel>>());
      expect(result.length, 1);
      expect(result.first.id, 'test_id');
      expect(result.first.title, 'Test Update');
    });

    test('should throw ServerFailure on exception', () async {
      when(() => mockFirestore.collection('app_updates'))
          .thenReturn(mockCollectionReference);
      when(() => mockCollectionReference.where('isActive', isEqualTo: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.orderBy('createdAt', descending: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.get()).thenThrow(Exception('test error'));

      expect(() => dataSource.getUpdates(), throwsA(isA<ServerFailure>()));
    });
  });

  group('getUpdatesSince', () {
    test('should return list of AppUpdateModel when successful', () async {
      when(() => mockFirestore.collection('app_updates'))
          .thenReturn(mockCollectionReference);
      when(() => mockCollectionReference.where('isActive', isEqualTo: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.where('createdAt',
              isGreaterThan: any(named: 'isGreaterThan')))
          .thenReturn(mockQuery);
      when(() => mockQuery.orderBy('createdAt', descending: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockDocSnapshot]);
      when(() => mockDocSnapshot.data()).thenReturn(tJson);
      when(() => mockDocSnapshot.id).thenReturn('test_id');

      final result = await dataSource.getUpdatesSince(DateTime(2022, 1, 1));

      expect(result, isA<List<AppUpdateModel>>());
      expect(result.length, 1);
      expect(result.first.id, 'test_id');
    });

    test('should throw ServerFailure on exception', () async {
      when(() => mockFirestore.collection('app_updates'))
          .thenReturn(mockCollectionReference);
      when(() => mockCollectionReference.where('isActive', isEqualTo: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.where('createdAt',
              isGreaterThan: any(named: 'isGreaterThan')))
          .thenReturn(mockQuery);
      when(() => mockQuery.orderBy('createdAt', descending: true))
          .thenReturn(mockQuery);
      when(() => mockQuery.get()).thenThrow(Exception('test error'));

      expect(() => dataSource.getUpdatesSince(DateTime.now()),
          throwsA(isA<ServerFailure>()));
    });
  });
}
