import 'dart:async';
import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/features/penalties/data/datasources/penalty_remote_data_source.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockFirebaseStorage extends Mock implements FirebaseStorage {}
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
class MockQuerySnapshot extends Mock implements QuerySnapshot<Map<String, dynamic>> {}
class MockQueryDocumentSnapshot extends Mock implements QueryDocumentSnapshot<Map<String, dynamic>> {}
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockReference extends Mock implements Reference {}
class MockTaskSnapshot extends Mock implements TaskSnapshot {}
class MockFile extends Mock implements File {}

class FakeUploadTask extends Fake implements UploadTask {
  @override
  final TaskSnapshot snapshot;
  final bool shouldThrow;

  FakeUploadTask(this.snapshot, {this.shouldThrow = false});

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot) onValue, {Function? onError}) async {
    if (shouldThrow) {
      if (onError != null) {
        return onError(Exception('Upload failed'));
      }
      throw Exception('Upload failed');
    }
    return await onValue(snapshot);
  }

  @override
  UploadTask catchError(Function onError, {bool Function(Object)? test}) {
    // Stub if needed
    return this;
  }
}

void main() {
  late PenaltyRemoteDataSourceImpl dataSource;
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseStorage mockStorage;
  late MockCollectionReference mockCollectionReference;
  late MockDocumentReference mockDocumentReference;
  late MockQuery mockQuery;
  late MockQuerySnapshot mockQuerySnapshot;
  late MockQueryDocumentSnapshot mockQueryDocumentSnapshot;

  final tDate = DateTime(2023, 1, 1);

  setUpAll(() {
    registerFallbackValue(const GetOptions());
    registerFallbackValue(PenaltyModel(
      penaltyId: 'test_id',
      companyId: 'company_123',
      companyName: 'Test Company',
      createdById: 'admin_123',
      createdByName: 'Admin Name',
      title: 'Test Penalty',
      category: ViolationCategory.dataMissing,
      incidentDescription: 'Missing data in form',
      fineAmount: 50.0,
      createdAt: tDate,
      updatedAt: tDate,
    ));
    registerFallbackValue(File('test.jpg'));
  });

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockStorage = MockFirebaseStorage();
    mockCollectionReference = MockCollectionReference();
    mockDocumentReference = MockDocumentReference();
    mockQuery = MockQuery();
    mockQuerySnapshot = MockQuerySnapshot();
    mockQueryDocumentSnapshot = MockQueryDocumentSnapshot();

    dataSource = PenaltyRemoteDataSourceImpl(
      firestore: mockFirestore,
      storage: mockStorage,
    );

    final emptySnap = MockQuerySnapshot();
    when(() => emptySnap.docs).thenReturn([]);
    final mockRulesRef = MockCollectionReference();
    final mockRulesQuery = MockQuery();
    when(() => mockFirestore.collection(any())).thenReturn(mockCollectionReference);
    when(() => mockFirestore.collection('penalty_rules')).thenReturn(mockRulesRef);
    when(() => mockRulesRef.where(any(), isEqualTo: any(named: 'isEqualTo'))).thenReturn(mockRulesQuery);
    when(() => mockRulesQuery.get(any())).thenAnswer((_) async => emptySnap);
    when(() => mockCollectionReference.doc(any())).thenReturn(mockDocumentReference);
    when(() => mockCollectionReference.get(any())).thenAnswer((_) async => emptySnap);
    when(() => mockQuery.get(any())).thenAnswer((_) async => emptySnap);
  });

  final tPenaltyModel = PenaltyModel(
    penaltyId: 'test_id',
    companyId: 'company_123',
    companyName: 'Test Company',
    createdById: 'admin_123',
    createdByName: 'Admin Name',
    title: 'Test Penalty',
    category: ViolationCategory.dataMissing,
    incidentDescription: 'Missing data in form',
    fineAmount: 50.0,
    currency: 'EGP',
    status: PenaltyStatus.issued,
    evidenceFiles: const [],
    createdAt: tDate,
    updatedAt: tDate,
  );

  group('createPenalty', () {
    test('should set penalty to firestore', () async {
      when(() => mockDocumentReference.id).thenReturn('test_id');
      when(() => mockDocumentReference.set(any())).thenAnswer((_) async {});

      await dataSource.createPenalty(tPenaltyModel);

      verify(() => mockFirestore.collection('penalties')).called(1);
      verify(() => mockCollectionReference.doc('test_id')).called(1);
      verify(() => mockDocumentReference.set(any())).called(1);
    });

    test('should throw ServerException on FirebaseException', () async {
      when(() => mockDocumentReference.id).thenReturn('test_id');
      when(() => mockDocumentReference.set(any()))
          .thenThrow(FirebaseException(plugin: 'firestore'));

      final call = dataSource.createPenalty;

      expect(() => call(tPenaltyModel), throwsA(isA<ServerException>()));
    });
  });

  group('getCompanyPenalties', () {
    test('should return list of PenaltyModel when successful', () async {
      when(() => mockCollectionReference.where('companyId', isEqualTo: 'company_123'))
          .thenReturn(mockQuery);
      when(() => mockQuery.get(any())).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockQueryDocumentSnapshot]);
      
      when(() => mockQueryDocumentSnapshot.id).thenReturn('test_id');
      when(() => mockQueryDocumentSnapshot.data()).thenReturn({
        'companyId': 'company_123',
        'companyName': 'Test Company',
        'createdById': 'admin_123',
        'createdByName': 'Admin Name',
        'title': 'Test Penalty',
        'category': 'DATA_MISSING',
        'incidentDescription': 'Missing data in form',
        'fineAmount': 50.0,
        'currency': 'EGP',
        'status': 'ISSUED',
        'evidenceFiles': [],
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      });

      final result = await dataSource.getCompanyPenalties('company_123');

      expect(result, equals([tPenaltyModel]));
    });

    test('should propagate generic exception', () async {
      when(() => mockCollectionReference.where('companyId', isEqualTo: 'company_123'))
          .thenReturn(mockQuery);
      when(() => mockQuery.get(any()))
          .thenThrow(Exception('generic'));

      expect(
        () => dataSource.getCompanyPenalties('company_123'),
        throwsA(isA<Exception>()),
      );
    });

    test('should throw ServerException on FirebaseException', () async {
      when(() => mockCollectionReference.where('companyId', isEqualTo: 'company_123'))
          .thenReturn(mockQuery);
      when(() => mockQuery.get(any()))
          .thenThrow(FirebaseException(plugin: 'firestore'));

      final call = dataSource.getCompanyPenalties;

      expect(() => call('company_123'), throwsA(isA<ServerException>()));
    });
  });

  group('getAllPenalties', () {
    test('should return list of PenaltyModel when successful', () async {
      when(() => mockCollectionReference.get(any())).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockQueryDocumentSnapshot]);
      
      when(() => mockQueryDocumentSnapshot.id).thenReturn('test_id');
      when(() => mockQueryDocumentSnapshot.data()).thenReturn({
        'companyId': 'company_123',
        'companyName': 'Test Company',
        'createdById': 'admin_123',
        'createdByName': 'Admin Name',
        'title': 'Test Penalty',
        'category': 'DATA_MISSING',
        'incidentDescription': 'Missing data in form',
        'fineAmount': 50.0,
        'currency': 'EGP',
        'status': 'ISSUED',
        'evidenceFiles': [],
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      });

      final result = await dataSource.getAllPenalties();

      expect(result, equals([tPenaltyModel]));
    });

    test('should return empty list on generic exception', () async {
      when(() => mockCollectionReference.get(any()))
          .thenThrow(Exception('generic'));

      final result = await dataSource.getAllPenalties();

      expect(result, equals([]));
    });

    test('should throw ServerException on FirebaseException', () async {
      when(() => mockCollectionReference.get(any()))
          .thenThrow(FirebaseException(plugin: 'firestore'));

      final call = dataSource.getAllPenalties;

      expect(() => call(), throwsA(isA<ServerException>()));
    });
  });

  group('updatePenaltyStatus', () {
    test('should update status successfully', () async {
      when(() => mockDocumentReference.update(any())).thenAnswer((_) async {});
      when(() => mockDocumentReference.get()).thenAnswer((_) async => mockQueryDocumentSnapshot);
      when(() => mockQueryDocumentSnapshot.exists).thenReturn(false);

      await dataSource.updatePenaltyStatus(penaltyId: 'test_id', status: PenaltyStatus.acknowledged);

      verify(() => mockFirestore.collection('penalties')).called(greaterThanOrEqualTo(1));
      verify(() => mockCollectionReference.doc('test_id')).called(greaterThanOrEqualTo(1));
      verify(() => mockDocumentReference.update(any())).called(1);
    });

    test('should throw ServerException on exception', () async {
      when(() => mockDocumentReference.update(any()))
          .thenThrow(FirebaseException(plugin: 'firestore'));

      expect(() => dataSource.updatePenaltyStatus(penaltyId: 'test_id', status: PenaltyStatus.acknowledged), throwsA(isA<ServerException>()));
    });
  });

  group('uploadEvidenceFile', () {
    late MockReference mockRootReference;
    late MockReference mockPenaltiesReference;
    late MockReference mockCompanyReference;
    late MockReference mockEvidenceReference;
    late MockReference mockIdReference;
    late MockReference mockFileReference;
    late MockTaskSnapshot mockTaskSnapshot;
    late MockFile mockFile;

    setUp(() {
      mockRootReference = MockReference();
      mockPenaltiesReference = MockReference();
      mockCompanyReference = MockReference();
      mockEvidenceReference = MockReference();
      mockIdReference = MockReference();
      mockFileReference = MockReference();
      mockTaskSnapshot = MockTaskSnapshot();
      mockFile = MockFile();

      when(() => mockStorage.ref()).thenReturn(mockRootReference);
      when(() => mockRootReference.child('penalties')).thenReturn(mockPenaltiesReference);
      when(() => mockPenaltiesReference.child('coA')).thenReturn(mockCompanyReference);
      when(() => mockCompanyReference.child('evidence')).thenReturn(mockEvidenceReference);
      when(() => mockEvidenceReference.child(any())).thenReturn(mockIdReference);
      when(() => mockIdReference.child(any())).thenReturn(mockFileReference);
      
      when(() => mockFile.path).thenReturn('/path/to/my_image.jpg');
    });

    test('should return EvidenceFile on success', () async {
      when(() => mockFileReference.putFile(any())).thenAnswer((_) => FakeUploadTask(mockTaskSnapshot));
      when(() => mockTaskSnapshot.ref).thenReturn(mockFileReference);
      when(() => mockFileReference.getDownloadURL()).thenAnswer((_) async => 'http://test.com/my_image.jpg');
      when(() => mockFileReference.fullPath)
          .thenReturn('penalties/coA/evidence/test_id/1_my_image.jpg');

      final result = await dataSource.uploadEvidenceFile(file: mockFile, penaltyId: 'test_id', companyId: 'coA');

      // TAS-42: the object path is kept; the URL only for old app versions.
      expect(result.fileUrl, equals('penalties/coA/evidence/test_id/1_my_image.jpg'));
      expect(result.legacyUrl, equals('http://test.com/my_image.jpg'));
      expect(result.toJson()['filePath'], result.fileUrl);
      expect(result.fileName, equals('my_image.jpg'));
      expect(result.fileType, equals('IMAGE'));
    });

    test('should throw ServerException on failure', () async {
      when(() => mockFileReference.putFile(any())).thenThrow(Exception());

      final call = dataSource.uploadEvidenceFile;

      expect(() => call(file: mockFile, penaltyId: 'test_id', companyId: 'coA'), throwsA(isA<ServerException>()));
    });

    test('should throw ServerException when companyId is empty', () async {
      final call = dataSource.uploadEvidenceFile;
      expect(() => call(file: mockFile, penaltyId: 'test_id', companyId: ''), throwsA(isA<ServerException>()));
    });
  });
}
