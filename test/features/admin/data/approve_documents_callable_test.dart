// TAS-336: technical support approves through approveDelegateDocuments when
// every bound delegate doc is 'pending'. Fake data only.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/core/constants/cloud_functions.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

class _MockFunctions extends Mock implements FirebaseFunctions {}

class _MockCallable extends Mock implements HttpsCallable {}

class _MockResult extends Mock implements HttpsCallableResult<dynamic> {}

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

const _path = 'organizations/o1/companies/c1/delegates/r1';

List<Map<String, dynamic>> _pendingDocs(int n) => [
      for (var i = 0; i < n; i++)
        {'documentKey': 'personalPhoto', 'documentStatus': 'pending', 'documentURL': 'p0'},
    ];

Future<void> _seed(FakeFirebaseFirestore db, {bool delegateDoc = true}) async {
  await db.doc('organizations/o1').set({'name': 'O1'});
  await db.doc('organizations/o1/companies/c1').set({'name': 'C1', 'organizationUID': 'o1'});
  await db.doc('users/sup').set({'role': 'supervisor', 'organizationUID': 'o1', 'companyUID': 'c1'});
  await db.doc('delegate_requests/r1').set(_req);
  if (delegateDoc) {
    await db.doc(_path).set({
      'uid': 'r1',
      'status': 'pending',
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'documents': _pendingDocs(6),
    });
  }
}

void main() {
  late _MockFunctions functions;
  late _MockCallable callable;

  setUpAll(() => registerFallbackValue(<String, dynamic>{}));

  setUp(() {
    functions = _MockFunctions();
    callable = _MockCallable();
    when(() => functions.httpsCallable(CloudCallableNames.approveDelegateDocuments))
        .thenReturn(callable);
  });

  test('tech support + pending doc: calls the callable, no client batch on status', () async {
    final db = FakeFirebaseFirestore();
    await _seed(db);
    when(() => callable.call<dynamic>(any())).thenAnswer((_) async => _MockResult());
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage(), functions: functions);
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'ts',
      reviewerName: 'TS',
      reviewerRole: 'technicalSupport',
    );
    expect(result.isRight(), isTrue);
    final payload = verify(() => callable.call<dynamic>(captureAny())).captured.single as Map;
    expect(payload, {'requestId': 'r1', 'organizationUIDs': ['o1'], 'reviewerName': 'TS'});
    // The client wrote neither the approval nor the flips (the mock wrote nothing).
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'pending');
    final d = (await db.doc(_path).get()).data()!;
    expect(d['status'], 'pending');
    expect((d['documents'] as List).every((e) => e['documentStatus'] == 'pending'), isTrue);
    // Profile follow-up merge and the login record still run.
    expect(d['fullName'], 'Fake Test User');
    expect((await db.doc('users/r1').get()).data()!['role'], 'delegate');
  });

  test('callable error: server message shown, follow-ups skipped', () async {
    final db = FakeFirebaseFirestore();
    await _seed(db);
    when(() => callable.call<dynamic>(any())).thenThrow(FirebaseFunctionsException(
      code: 'failed-precondition',
      message: 'الطلب لم يعد قيد المراجعة.',
      details: {'reason': 'request_not_pending'},
    ));
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage(), functions: functions);
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'ts',
      reviewerName: 'TS',
      reviewerRole: 'technicalSupport',
    );
    expect(result.fold((f) => f.message, (_) => ''), 'الطلب لم يعد قيد المراجعة.');
    expect((await db.doc('users/r1').get()).exists, isFalse);
    expect((await db.doc(_path).get()).data()!['fullName'], isNull);
  });

  test('function not deployed: generic unavailable message, no fallback write', () async {
    final db = FakeFirebaseFirestore();
    await _seed(db);
    when(() => callable.call<dynamic>(any()))
        .thenThrow(FirebaseFunctionsException(code: 'not-found', message: 'NOT_FOUND'));
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage(), functions: functions);
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'ts',
      reviewerName: 'TS',
      reviewerRole: 'technicalSupport',
    );
    expect(result.fold((f) => f.message, (_) => ''), contains('غير متاحة'));
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'pending');
    expect((await db.doc(_path).get()).data()!['status'], 'pending');
  });

  test('super-admin keeps the client batch (no callable)', () async {
    final db = FakeFirebaseFirestore();
    await _seed(db);
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage(), functions: functions);
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'sa',
      reviewerName: 'SA',
      reviewerRole: 'superAdmin',
    );
    expect(result.isRight(), isTrue);
    verifyNever(() => functions.httpsCallable(any()));
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'approved');
    expect((await db.doc(_path).get()).data()!['status'], 'active');
  });

  test('tech support with no prior doc (create): client batch as before', () async {
    final db = FakeFirebaseFirestore();
    await _seed(db, delegateDoc: false);
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage(), functions: functions);
    final result = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(_req, 'r1'),
      reviewerUid: 'ts',
      reviewerName: 'TS',
      reviewerRole: 'technicalSupport',
    );
    expect(result.isRight(), isTrue);
    verifyNever(() => functions.httpsCallable(any()));
    expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'approved');
  });

  test('isTechSupportReviewer spellings', () {
    expect(isTechSupportReviewer('technicalSupport'), isTrue);
    expect(isTechSupportReviewer('technical_support'), isTrue);
    expect(isTechSupportReviewer('tech-support'), isTrue);
    expect(isTechSupportReviewer('superAdmin'), isFalse);
    expect(isTechSupportReviewer(null), isFalse);
  });

  test('approveDocumentsCallableMessage', () {
    expect(
      approveDocumentsCallableMessage(FirebaseFunctionsException(
          code: 'permission-denied', message: 'م', details: {'reason': 'not_approver'})),
      'م',
    );
    expect(
      approveDocumentsCallableMessage(FirebaseFunctionsException(code: 'internal', message: 'INTERNAL')),
      contains('حاول مرة أخرى'),
    );
  });
}
