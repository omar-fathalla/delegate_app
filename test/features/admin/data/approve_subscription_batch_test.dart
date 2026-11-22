// r4 F2: the approval is one WriteBatch. If the batch fails partway, the
// request must stay 'pending' and no delegate doc is activated. Fake data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/core/error/failures.dart';

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

// r5: users/{uid} writes fail while [failUsers] is true (post-commit step 3).
class _UsersFailFirestore extends FakeFirebaseFirestore {
  bool failUsers = true;
  @override
  CollectionReference<Map<String, dynamic>> collection(String collectionPath) {
    final c = super.collection(collectionPath);
    if (collectionPath != 'users') return c;
    return _FailingUsers(c, this);
  }
}

class _FailingUsers extends Fake implements CollectionReference<Map<String, dynamic>> {
  _FailingUsers(this.inner, this.db);
  final CollectionReference<Map<String, dynamic>> inner;
  final _UsersFailFirestore db;
  @override
  DocumentReference<Map<String, dynamic>> doc([String? path]) => _FailingUserDoc(inner.doc(path), db);
}

class _FailingUserDoc extends Fake implements DocumentReference<Map<String, dynamic>> {
  _FailingUserDoc(this.inner, this.db);
  final DocumentReference<Map<String, dynamic>> inner;
  final _UsersFailFirestore db;
  @override
  String get id => inner.id;
  @override
  Future<DocumentSnapshot<Map<String, dynamic>>> get([GetOptions? options]) => inner.get(options);
  @override
  Future<void> set(Map<String, dynamic> data, [SetOptions? options]) async {
    if (db.failUsers) {
      throw FirebaseException(plugin: 'cloud_firestore', code: 'unavailable');
    }
    return inner.set(data, options);
  }
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
  'orgCompanyCheck': 'ok',
};

const _delegatePath = 'organizations/o1/companies/c1/delegates/r1';

Future<void> _seedCompany(FakeFirebaseFirestore db, {Iterable<String> orgs = const ['o1']}) async {
  for (final org in orgs) {
    await db.doc('organizations/$org').set({'name': 'chain $org'});
    await db.doc('organizations/$org/companies/c1').set({'name': 'C1', 'organizationUID': org});
  }
}

Future<void> _seed(FakeFirebaseFirestore db) async {
  await _seedCompany(db);
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
    expect(result.fold((f) => f.message, (_) => ''), approvalBatchDeniedMessage);
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

  test('new_delegate with no prior doc: request approved and delegate created in the same batch', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/sup').set({'role': 'supervisor', 'organizationUID': 'o1', 'companyUID': 'c1'});
    await _seedCompany(db);
    await db.doc('delegate_requests/r1').set(_req);
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
    expect(d['uid'], 'r1');
    expect(d['registeredVia'], 'mobile_app');
    expect(d['approvedRequestId'], 'r1');
    // TAS-230: server time, not the approving device's clock.
    expect(d['createdAt'], isA<Timestamp>());
    // Same-batch write: a trigger running after commit sees the approved
    // app request and cannot stamp the new doc as web.
  });

  test('newDelegateDocData adds a server createdAt only when missing (TAS-230)', () {
    final added = newDelegateDocData({'fullName': 'F'});
    expect(added['createdAt'], isA<FieldValue>());
    expect(added['fullName'], 'F');
    final kept = Timestamp.fromDate(DateTime(2025, 1, 1));
    expect(newDelegateDocData({'createdAt': kept})['createdAt'], same(kept));
    // The merge path for an existing doc never carries it.
    expect(profileMergeFields({'fullName': 'F'}).containsKey('createdAt'), isFalse);
  });

  test('new_delegate with two organizationUIDs writes both chain docs in the same batch, one fee', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('users/sup').set({'role': 'supervisor', 'organizationUID': 'o1', 'companyUID': 'c1'});
    await _seedCompany(db, orgs: ['o1', 'o2']);
    final req = {
      ..._req,
      'organizationUIDs': ['o1', 'o2'],
      'organizationNames': ['O1', 'O2'],
      'fee': 416.67,
    };
    await db.doc('delegate_requests/r1').set(req);
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(req, 'r1'),
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(result.isRight(), isTrue);
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'approved');
    for (final org in ['o1', 'o2']) {
      final d = (await db.doc('organizations/$org/companies/c1/delegates/r1').get()).data()!;
      expect(d['status'], 'active');
      expect(d['organizationUID'], org);
      expect(d['registeredVia'], 'mobile_app');
      expect(d['approvedRequestId'], 'r1');
      expect((d['subscription'] as Map)['amountDue'], 416.67);
      expect((d['subscription'] as Map)['registrationRequestId'], 'r1');
    }
  });

  test('r5: users/{uid} write fails after commit -> surfaced with a working retry', () async {
    final db = _UsersFailFirestore();
    await _seed(db);
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'ts',
      reviewerName: 'TS',
    );
    final Failure? f = result.fold((f) => f, (_) => null);
    expect(f, isA<ApprovalFollowUpFailure>());
    // Batch already committed.
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'approved');
    expect((await db.doc(_delegatePath).get()).data()!['status'], 'active');
    expect((await db.doc('users/r1').get()).exists, isFalse);

    // Still failing -> plain failure, retry can be offered again.
    expect((await (f! as ApprovalFollowUpFailure).retry()).isLeft(), isTrue);

    db.failUsers = false;
    final retried = await (f as ApprovalFollowUpFailure).retry();
    expect(retried.isRight(), isTrue);
    final u = (await db.doc('users/r1').get()).data()!;
    expect(u['role'], 'delegate');
    expect(u['status'], 'active');
    // The profile merge for the status-only activation also ran.
    expect((await db.doc(_delegatePath).get()).data()!['firstName'], 'Fake');
  });
}
