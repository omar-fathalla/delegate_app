import 'dart:async';
import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/features/feedback/data/datasources/feedback_remote_datasource.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFirebaseFirestore extends Mock implements FirebaseFirestore {}
class MockFirebaseStorage extends Mock implements FirebaseStorage {}
// ignore: subtype_of_sealed_class
class MockCollectionReference extends Mock implements CollectionReference<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockDocumentReference extends Mock implements DocumentReference<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQuerySnapshot extends Mock implements QuerySnapshot<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQueryDocumentSnapshot extends Mock implements QueryDocumentSnapshot<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockDocumentSnapshot extends Mock implements DocumentSnapshot<Map<String, dynamic>> {}
// ignore: subtype_of_sealed_class
class MockQuery extends Mock implements Query<Map<String, dynamic>> {}
class MockReference extends Mock implements Reference {}
class MockTaskSnapshot extends Mock implements TaskSnapshot {}
class FakeTaskSnapshot extends Fake implements TaskSnapshot {
  @override
  final Reference ref;
  
  FakeTaskSnapshot(this.ref);
}
class MockFile extends Mock implements File {}

class FakeUploadTask extends Fake implements UploadTask {
  final TaskSnapshot _snapshot;
  
  FakeUploadTask(this._snapshot);

  @override
  Future<S> then<S>(FutureOr<S> Function(TaskSnapshot) onValue, {Function? onError}) async {
    return await onValue(_snapshot);
  }

  @override
  Stream<TaskSnapshot> get snapshotEvents => Stream.value(_snapshot);

  @override
  TaskSnapshot get snapshot => _snapshot;
}

void main() {
  late FeedbackRemoteDataSourceImpl dataSource;
  late MockFirebaseFirestore mockFirestore;
  late MockFirebaseStorage mockStorage;
  late MockCollectionReference mockCollectionReference;
  late MockDocumentReference mockDocumentReference;
  late MockQuery mockQuery;
  late MockQuerySnapshot mockQuerySnapshot;
  late MockQueryDocumentSnapshot mockQueryDocumentSnapshot;
  late MockDocumentSnapshot mockDocumentSnapshot;

  final tDate = DateTime(2023, 1, 1);

  setUpAll(() {
    registerFallbackValue(File('test.jpg'));
    registerFallbackValue(SettableMetadata());
  });

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    mockStorage = MockFirebaseStorage();
    mockCollectionReference = MockCollectionReference();
    mockDocumentReference = MockDocumentReference();
    mockQuery = MockQuery();
    mockQuerySnapshot = MockQuerySnapshot();
    mockQueryDocumentSnapshot = MockQueryDocumentSnapshot();
    mockDocumentSnapshot = MockDocumentSnapshot();

    dataSource = FeedbackRemoteDataSourceImpl(
      firestore: mockFirestore,
      storage: mockStorage,
    );

    when(() => mockFirestore.collection(any())).thenReturn(mockCollectionReference);
    when(() => mockCollectionReference.doc(any())).thenReturn(mockDocumentReference);
  });

  final tFeedbackModel = FeedbackModel(
    id: 'test_id',
    userId: 'user_123',
    userName: 'Test User',
    userEmail: 'test@example.com',
    type: FeedbackType.featureRequest,
    content: 'Please add a dark mode feature',
    screenshotUrl: 'http://test.com/my_image.jpg',
    status: FeedbackStatus.pending,
    createdAt: tDate,
    updatedAt: tDate,
  );

  group('submitFeedback', () {
    test('should add feedback to firestore without screenshot', () async {
      when(() => mockCollectionReference.add(any())).thenAnswer((_) async => mockDocumentReference);

      await dataSource.submitFeedback(tFeedbackModel, null);

      verify(() => mockFirestore.collection('feedbacks')).called(1);
      verify(() => mockCollectionReference.add(any())).called(1);
    });

    test('should upload screenshot and add feedback to firestore', () async {
      final mockFile = MockFile();
      final mockRootReference = MockReference();
      final mockChildReference = MockReference();
      final mockTaskSnapshot = FakeTaskSnapshot(mockChildReference);

      when(() => mockStorage.ref()).thenReturn(mockRootReference);
      when(() => mockRootReference.child(any())).thenReturn(mockChildReference);
      
      when(() => mockChildReference.putFile(any(), any())).thenAnswer((_) => FakeUploadTask(mockTaskSnapshot));
      when(() => mockChildReference.getDownloadURL()).thenAnswer((_) async => 'http://test.com/my_image.jpg');
      when(() => mockChildReference.fullPath).thenReturn('feedback_screenshots/f.jpg');
      when(() => mockCollectionReference.add(any())).thenAnswer((_) async => mockDocumentReference);

      await dataSource.submitFeedback(tFeedbackModel, mockFile);

      verify(() => mockStorage.ref()).called(1);
      verify(() => mockChildReference.putFile(any(), any())).called(1);
      verify(() => mockFirestore.collection('feedbacks')).called(1);
      final written = verify(() => mockCollectionReference.add(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      // TAS-42: the path is stored; the URL stays only for old app versions.
      expect(written['screenshotPath'], 'feedback_screenshots/f.jpg');
      expect(written['screenshotUrl'], 'http://test.com/my_image.jpg');
    });

    test('TAS-42: with legacy URLs off only the path is stored', () async {
      LegacyStorageUrls.debugOverride = false;
      addTearDown(() => LegacyStorageUrls.debugOverride = null);
      final mockFile = MockFile();
      final mockRootReference = MockReference();
      final mockChildReference = MockReference();
      final mockTaskSnapshot = FakeTaskSnapshot(mockChildReference);
      when(() => mockStorage.ref()).thenReturn(mockRootReference);
      when(() => mockRootReference.child(any())).thenReturn(mockChildReference);
      when(() => mockChildReference.putFile(any(), any()))
          .thenAnswer((_) => FakeUploadTask(mockTaskSnapshot));
      when(() => mockChildReference.fullPath).thenReturn('feedback_screenshots/f.jpg');
      when(() => mockCollectionReference.add(any()))
          .thenAnswer((_) async => mockDocumentReference);

      await dataSource.submitFeedback(tFeedbackModel, mockFile);

      verifyNever(() => mockChildReference.getDownloadURL());
      final written = verify(() => mockCollectionReference.add(captureAny()))
          .captured
          .single as Map<String, dynamic>;
      expect(written['screenshotPath'], 'feedback_screenshots/f.jpg');
      expect(written.containsKey('screenshotUrl'), isFalse);
    });
  });

  group('getUserFeedbacks', () {
    test('should return list of FeedbackModel when successful', () async {
      when(() => mockCollectionReference.where('userId', isEqualTo: 'user_123'))
          .thenReturn(mockQuery);
      when(() => mockQuery.orderBy('createdAt', descending: true)).thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockQueryDocumentSnapshot]);
      
      when(() => mockQueryDocumentSnapshot.id).thenReturn('test_id');
      when(() => mockQueryDocumentSnapshot.data()).thenReturn({
        'userId': 'user_123',
        'userName': 'Test User',
        'userEmail': 'test@example.com',
        'type': 'feature_request',
        'content': 'Please add a dark mode feature',
        'screenshotUrl': 'http://test.com/my_image.jpg',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      });

      final result = await dataSource.getUserFeedbacks('user_123');

      expect(result, equals([tFeedbackModel]));
    });
  });

  group('getFeedbackById', () {
    test('should return FeedbackModel when successful', () async {
      when(() => mockDocumentReference.get()).thenAnswer((_) async => mockDocumentSnapshot);
      when(() => mockDocumentSnapshot.exists).thenReturn(true);
      when(() => mockDocumentSnapshot.id).thenReturn('test_id');
      when(() => mockDocumentSnapshot.data()).thenReturn({
        'userId': 'user_123',
        'userName': 'Test User',
        'userEmail': 'test@example.com',
        'type': 'feature_request',
        'content': 'Please add a dark mode feature',
        'screenshotUrl': 'http://test.com/my_image.jpg',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      });

      final result = await dataSource.getFeedbackById('test_id');

      expect(result, equals(tFeedbackModel));
    });

    test('should throw Exception when not found', () async {
      when(() => mockDocumentReference.get()).thenAnswer((_) async => mockDocumentSnapshot);
      when(() => mockDocumentSnapshot.exists).thenReturn(false);

      final call = dataSource.getFeedbackById;

      expect(() => call('test_id'), throwsA(isA<Exception>()));
    });
  });

  group('getAllFeedbacks', () {
    test('should return list of FeedbackModel when successful', () async {
      when(() => mockCollectionReference.orderBy('createdAt', descending: true)).thenReturn(mockQuery);
      when(() => mockQuery.get()).thenAnswer((_) async => mockQuerySnapshot);
      when(() => mockQuerySnapshot.docs).thenReturn([mockQueryDocumentSnapshot]);
      
      when(() => mockQueryDocumentSnapshot.id).thenReturn('test_id');
      when(() => mockQueryDocumentSnapshot.data()).thenReturn({
        'userId': 'user_123',
        'userName': 'Test User',
        'userEmail': 'test@example.com',
        'type': 'feature_request',
        'content': 'Please add a dark mode feature',
        'screenshotUrl': 'http://test.com/my_image.jpg',
        'status': 'pending',
        'createdAt': Timestamp.fromDate(tDate),
        'updatedAt': Timestamp.fromDate(tDate),
      });

      final result = await dataSource.getAllFeedbacks();

      expect(result, equals([tFeedbackModel]));
    });
  });

  group('updateFeedbackStatus', () {
    test('should update status successfully', () async {
      when(() => mockDocumentReference.update(any())).thenAnswer((_) async {});

      await dataSource.updateFeedbackStatus(feedbackId: 'test_id', status: FeedbackStatus.resolved, adminResponse: 'Fixed');

      verify(() => mockFirestore.collection('feedbacks')).called(1);
      verify(() => mockCollectionReference.doc('test_id')).called(1);
      verify(() => mockDocumentReference.update(any())).called(1);
    });
  });

  group('deleteFeedback', () {
    test('should delete feedback successfully', () async {
      when(() => mockDocumentReference.delete()).thenAnswer((_) async {});

      await dataSource.deleteFeedback('test_id');

      verify(() => mockFirestore.collection('feedbacks')).called(1);
      verify(() => mockCollectionReference.doc('test_id')).called(1);
      verify(() => mockDocumentReference.delete()).called(1);
    });
  });
}
