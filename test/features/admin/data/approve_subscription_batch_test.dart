// r4 F2: the approval is one WriteBatch. If the batch fails partway, the
// request must stay 'pending' and no delegate doc is activated. Fake data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _FailingBatch implements WriteBatch {
  final WriteBatch inner;
  _FailingBatch(this.inner);
  @override
  Future<void> commit() async =>
      throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
  @override
  void delete(DocumentReference document) => inner.delete(document);
  @override
  void set<T>(DocumentReference<T> document, T data, [SetOptions? options]) =>
      inner.set(document, data, options);
  @override
  void update<T>(DocumentReference<T> document, T data) =>
      inner.update<T>(document, data);
}

class _FailingBatchFirestore extends FakeFirebaseFirestore {
  @override
  WriteBatch batch() => _FailingBatch(super.batch());
}

const _req = <String, dynamic>{
  'status': 'pending',
  'requestType': 'new_delegate',
  'supervisorUid': 'sup',
  'companyUID': 'c1',
  'companyName': 'C1',
  'organizationUID': 'o1',
  'organizationName': 'O1',
  'firstName': 'Fake',
  'secondName': 'Test',
  'thirdName': 'User',
  'phoneNumber': '0100000000',
  'nationalId': '',
  'profileImageUrl': 'p0',
  'nationalIdFrontUrl': 'f0',
  'nationalIdBackUrl': 'b0',
};

const _delegatePath = 'organizations/o1/companies/c1/delegates/r1';

Future<void> _seed(FakeFirebaseFirestore db) async {
  await db.doc('users/sup').set({'role': 'supervisor', 'organizationUID': 'o1', 'companyUID': 'c1'});
  await db.doc('delegate_requests/r1').set(_req);
  await db.doc(_delegatePath).set({
    'uid': 'r1',
    'status': 'pending',
    'profileImageUrl': 'p0',
    'documents': [
      {'documentKey': 'personalPhoto', 'documentStatus': 'pending', 'documentURL': 'p0'},
      {'documentKey': 'nationalityId', 'documentStatus': 'pending', 'documentURL': 'f0', 'secondaryURL': 'b0'},
    ],
  });
}

void main() {
  test('batch fails partway -> request stays pending, delegate stays pending', () async {
    final db = _FailingBatchFirestore();
    await _seed(db);
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'ts',
      reviewerName: 'TS',
    );
    expect(result.isLeft(), isTrue);
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'pending');
    final d = (await db.doc(_delegatePath).get()).data()!;
    expect(d['status'], 'pending');
    expect((d['documents'] as List).every((e) => e['documentStatus'] == 'pending'), isTrue);
  });

  test('batch commits -> request approved and existing doc activated status-only', () async {
    final db = FakeFirebaseFirestore();
    await _seed(db);
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(result.isRight(), isTrue);
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'approved');
    final d = (await db.doc(_delegatePath).get()).data()!;
    expect(d['status'], 'active');
    expect(d['approvedRequestId'], 'r1');
    final docs = d['documents'] as List;
    expect(docs.length, 2);
    expect(docs.every((e) => e['documentStatus'] == 'approved'), isTrue);
    expect(docs[1]['secondaryURL'], 'b0');
  });

  test('buildStatusOnlyActivation keeps size/order and flips only pending', () {
    final out = buildStatusOnlyActivation(
      existingDocuments: [
        {'documentKey': 'personalPhoto', 'documentStatus': 'pending', 'documentURL': 'p'},
        {'documentKey': 'x', 'documentStatus': 'rejected', 'documentURL': 'q'},
      ],
      reviewerName: 'R',
      reviewedAtIso: 't',
      approvedRequestId: 'r1',
    );
    final docs = out['documents'] as List;
    expect(docs.length, 2);
    expect(docs[0], {'documentKey': 'personalPhoto', 'documentStatus': 'approved', 'documentURL': 'p', 'reviewedBy': 'R', 'reviewedAt': 't'});
    expect(docs[1]['documentStatus'], 'rejected');
    expect(out.keys.toSet(), {'status', 'documents', 'reviewedBy', 'reviewedAt', 'approvedRequestId', 'updatedAt'});
  });

  test('profileMergeFields never carries status, documents or URLs', () {
    final m = profileMergeFields({'status': 'active', 'documents': [], 'profileImageUrl': 'p', 'fullName': 'F', 'approvedRequestId': 'r'});
    expect(m, {'fullName': 'F'});
  });
}
