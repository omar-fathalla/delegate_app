import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:flutter_test/flutter_test.dart';

// Manual mocks because mockito/mocktail are not available/reliable in this environment

class MockDocumentSnapshot extends Fake implements DocumentSnapshot<Map<String, dynamic>> {
  final String _id;
  final Map<String, dynamic>? _data;

  MockDocumentSnapshot(this._id, this._data);

  @override
  String get id => _id;

  @override
  Map<String, dynamic>? data() => _data;

  @override
  bool get exists => _data != null;
}

class MockDocumentReference extends Fake implements DocumentReference<Map<String, dynamic>> {
  final String _id;
  final Map<String, dynamic> _data;
  int getCallCount = 0;

  MockDocumentReference(this._id, this._data);

  @override
  String get id => _id;

  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) async {
    getCallCount++;
    return MockDocumentSnapshot(_id, _data);
  }
}

class MockCollectionReference extends Fake implements CollectionReference<Map<String, dynamic>> {
  final Map<String, MockDocumentReference> _docs = {};

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(Map<String, dynamic> data) async {
    final id = 'doc_${_docs.length + 1}';
    final docRef = MockDocumentReference(id, data);
    _docs[id] = docRef;
    return docRef;
  }

  // Helper to access created docs for verification
  MockDocumentReference? getLastCreatedDoc() {
    if (_docs.isEmpty) return null;
    return _docs.values.last;
  }
}

class MockFirebaseFirestore extends Fake implements FirebaseFirestore {
  final Map<String, MockCollectionReference> _collections = {};

  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (!_collections.containsKey(collectionPath)) {
      _collections[collectionPath] = MockCollectionReference();
    }
    return _collections[collectionPath]!;
  }

  MockCollectionReference? getCollection(String path) => _collections[path];
}

void main() {
  late AttendanceRemoteDataSourceImpl dataSource;
  late MockFirebaseFirestore mockFirestore;

  setUp(() {
    mockFirestore = MockFirebaseFirestore();
    dataSource = AttendanceRemoteDataSourceImpl(firestore: mockFirestore);
  });

  test('checkIn should create a document without redundant fetch', () async {
    final result = await dataSource.checkIn(
      'user1',
      10.0,
      20.0,
      branchName: 'branchA',
    );

    // Verify result is correct
    expect(result, isA<AttendanceModel>());
    expect(result.userId, 'user1');
    expect(result.latitude, 10.0);
    expect(result.longitude, 20.0);
    expect(result.branchName, 'branchA');

    // Verify redundant fetch happened
    final collection = mockFirestore.getCollection('attendance');
    expect(collection, isNotNull);
    final docRef = collection!.getLastCreatedDoc();
    expect(docRef, isNotNull);

    // This assertion confirms the optimization.
    // get() should NOT be called.
    expect(docRef!.getCallCount, 0, reason: 'Expected get() to NOT be called (optimized)');
  });
}
