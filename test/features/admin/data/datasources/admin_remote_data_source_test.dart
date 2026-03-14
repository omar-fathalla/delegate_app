// ignore_for_file: subtype_of_sealed_class
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// We use an extended FakeFirebaseFirestore that forces throw on methods.
class ThrowingFakeFirebaseFirestore extends FakeFirebaseFirestore {
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    if (collectionPath == 'branches') {
      return ThrowingCollectionReference(super.collection(collectionPath));
    }
    return super.collection(collectionPath);
  }
}

class ThrowingCollectionReference implements CollectionReference<Map<String, dynamic>> {
  final CollectionReference<Map<String, dynamic>> delegate;

  ThrowingCollectionReference(this.delegate);

  @override
  Future<QuerySnapshot<Map<String, dynamic>>> get([GetOptions? options]) {
    throw FirebaseException(plugin: 'test', message: 'error');
  }

  @override
  Future<DocumentReference<Map<String, dynamic>>> add(Map<String, dynamic> data) {
    throw FirebaseException(plugin: 'test', message: 'error');
  }

  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) {
    return ThrowingDocumentReference(delegate.doc(path));
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

class ThrowingDocumentReference implements DocumentReference<Map<String, dynamic>> {
  final DocumentReference<Map<String, dynamic>> delegate;

  ThrowingDocumentReference(this.delegate);

  @override
  Future<void> update(Map<Object, Object?> data) {
    throw FirebaseException(plugin: 'test', message: 'error');
  }

  @override
  Future<void> delete() {
    throw FirebaseException(plugin: 'test', message: 'error');
  }

  @override
  dynamic noSuchMethod(Invocation invocation) => super.noSuchMethod(invocation);
}

void main() {
  late AdminRemoteDataSourceImpl dataSource;
  late ThrowingFakeFirebaseFirestore fakeFirestore;

  setUp(() {
    fakeFirestore = ThrowingFakeFirebaseFirestore();
    dataSource = AdminRemoteDataSourceImpl(firestore: fakeFirestore);
  });

  final tBranch = BranchModel(
    id: '1',
    branchName: 'test',
    latitude: 1.0,
    longitude: 1.0,
    geofenceRadius: 100,
  );

  group('FirebaseException handling', () {
    test('getBranches throws ServerFailure on FirebaseException', () async {
      expect(() => dataSource.getBranches(), throwsA(isA<ServerFailure>()));
    });

    test('addBranch throws ServerFailure on FirebaseException', () async {
      expect(() => dataSource.addBranch(tBranch), throwsA(isA<ServerFailure>()));
    });

    test('updateBranch throws ServerFailure on FirebaseException', () async {
      expect(() => dataSource.updateBranch(tBranch), throwsA(isA<ServerFailure>()));
    });

    test('deleteBranch throws ServerFailure on FirebaseException', () async {
      expect(() => dataSource.deleteBranch('1'), throwsA(isA<ServerFailure>()));
    });
  });
}
