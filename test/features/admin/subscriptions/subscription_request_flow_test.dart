import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'subscription_renewal_test.dart' show supervisor;

class _MockStorage extends Mock implements FirebaseStorage {}

DelegateSubscriptionRequest req({
  String type = kRequestTypeNewDelegate,
  SubscriptionPaymentStatus pay = SubscriptionPaymentStatus.pending,
}) =>
    DelegateSubscriptionRequest(
      id: 'r1',
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      organizationUID: 'o1',
      organizationName: 'O',
      firstName: 'a',
      secondName: 'b',
      thirdName: 'c',
      fullName: 'a b c',
      phoneNumber: '010',
      nationalId: '',
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.paymob,
      subscriptionCycle: '2027_H1',
      cycleStartDate: DateTime(2027, 1, 1),
      cycleEndDate: DateTime(2027, 6, 30, 23, 59, 59),
      fee: 416.67,
      remainingMonths: 5,
      requestType: type,
      createdAt: DateTime(2027, 2, 10),
      paymentStatus: pay,
    );



Map<String, dynamic> paidSubNow({
  double amountDue = 416.67,
  String? renewalRequestId = 'ren-paid',
}) {
  final at = DateTime.now().toUtc();
  return {
    'periodCode': SubscriptionCycleHelper.getCycleCode(at),
    'periodStart': SubscriptionCycleHelper.periodStartDay(at),
    'periodEnd': SubscriptionCycleHelper.periodEndDay(at),
    'amountDue': amountDue,
    'paymentStatus': 'paid',
    if (renewalRequestId != null) 'renewalRequestId': renewalRequestId,
  };
}

Future<void> seedPaidAddOrgContext(
  FakeFirebaseFirestore db, {
  String uid = 'sup1',
  List<String> orgs = const ['o1', 'o2'],
}) async {
  for (final org in orgs) {
    await db.doc('organizations/$org').set({'name': 'chain $org'});
    await db.doc('organizations/$org/companies/c1').set({'name': 'C'});
  }
  await db.doc('organizations/o1/companies/c1/delegates/$uid').set({
    'uid': uid,
    'status': 'active',
    'companyUID': 'c1',
    'organizationUID': 'o1',
    'subscription': paidSubNow(renewalRequestId: null),
  });
}

void main() {
  test('request round-trips subscription fields; legacy docs read as waived', () {
    final r = req().copyWith(
      requestType: kRequestTypeRenewal,
      coveredDelegateUids: ['a', 'b'],
      items: const [RenewalItem(uid: 'a', fullName: 'A', fee: 416.67)],
    );
    final m = r.toMap();
    expect(m['periodCode'], '2027_H1');
    expect(m['amountDue'], 416.67);
    expect(m['paymentStatus'], 'pending');
    expect(m['paymentMethod'], 'paymob');
    final back = DelegateSubscriptionRequest.fromMap({...m, 'paymob': {'transactionId': 'tx1'}}, 'r1');
    expect(back.isRenewalRequest, isTrue);
    expect(back.coveredDelegateUids, ['a', 'b']);
    expect(back.items.single.fee, 416.67);
    expect(back.paymobTransactionId, 'tx1');
    final legacy = DelegateSubscriptionRequest.fromMap({'requestType': 'new_delegate'}, 'x');
    expect(legacy.paymentStatus, SubscriptionPaymentStatus.waived);
    expect(legacy.isPaymentSettled, isTrue);
  });

  group('approval path', () {
    late FakeFirebaseFirestore db;
    late DelegateSubscriptionRepositoryImpl repo;
    setUp(() async {
      db = FakeFirebaseFirestore();
      repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
      await db.doc('organizations/o1').set({'name': 'chain o1'});
      await db.doc('organizations/o1/companies/c1').set({'name': 'C'});
      await db.doc('delegate_requests/r1').set({
        ...req().toMap(),
        'orgCompanyCheck': 'ok',
      });
    });

    test('staff cannot approve a renewal by hand (server approves on verified payment)', () async {
      final r = await repo.approveSubscriptionRequest(
          request: req(type: kRequestTypeRenewal), reviewerUid: 'sa', reviewerName: 'SA');
      expect(r.isLeft(), isTrue);
      expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'pending');
    });

    test('a paid-period new delegate cannot be activated before payment is verified', () async {
      final r = await repo.approveSubscriptionRequest(request: req(), reviewerUid: 'sa', reviewerName: 'SA');
      expect(r.isLeft(), isTrue);
      expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'pending');
      for (final p in [SubscriptionPaymentStatus.failed]) {
        expect((await repo.approveSubscriptionRequest(
                request: req(pay: p), reviewerUid: 'sa', reviewerName: 'SA'))
            .isLeft(), isTrue);
      }
    });

    test('once paid (or waived in 2026) the existing approval flow activates the delegate', () async {
      final r = await repo.approveSubscriptionRequest(
          request: req(pay: SubscriptionPaymentStatus.paid), reviewerUid: 'sa', reviewerName: 'SA');
      expect(r.isRight(), isTrue);
      final d = (await db.doc('organizations/o1/companies/c1/delegates/r1').get()).data()!;
      expect(d['status'], 'active');
      expect(d['subscription']['periodCode'], '2027_H1');
      expect(d['subscription']['periodEnd'], '2027-06-30');
      expect(d['subscription']['paymentStatus'], 'paid');
      expect(d['subscription']['registrationRequestId'], 'r1');
    });
  });

  test('adding a chain is never charged, whatever the caller passes', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    await seedPaidAddOrgContext(db);
    final r = await repo.submitAddOrganizationRequest(
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      targetOrganizationUID: 'o2',
      targetOrganizationName: 'O2',
      existingDelegate: supervisor(),
      paymentMethod: SubscriptionPaymentMethod.instaPay,
      fee: 500,
      remainingMonths: 6,
    );
    final id = r.getOrElse(() => '');
    final m = (await db.doc('delegate_requests/$id').get()).data()!;
    expect(m['requestType'], kRequestTypeAddOrganization);
    expect(m['fee'], 0.0);
    expect(m['amountDue'], 0.0);
    expect(m['paymentMethod'], 'not_required');
    expect(m['paymentStatus'], 'not_required');
  });

  test('submit refuses a suspended delegate or a chain they are already on', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    final suspended = await repo.submitAddOrganizationRequest(
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      targetOrganizationUID: 'o2',
      targetOrganizationName: 'O2',
      existingDelegate: supervisor(uid: 'd1', status: DelegateStatus.suspended),
      paymentMethod: SubscriptionPaymentMethod.notRequired,
    );
    expect(suspended.isLeft(), isTrue);

    final sameChain = await repo.submitAddOrganizationRequest(
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      targetOrganizationUID: 'o1',
      targetOrganizationName: 'O1',
      existingDelegate: supervisor(uid: 'd1'),
      paymentMethod: SubscriptionPaymentMethod.paymob,
      fee: 500,
    );
    expect(sameChain.isLeft(), isTrue);
  });

  test('paid add-to-another-chain copies the existing subscription and is not charged', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    const uid = 'd1';
    await db.doc('organizations/o1').set({'name': 'chain o1'});
    await db.doc('organizations/o1/companies/c1').set({'name': 'C'});
    await db.doc('organizations/o2').set({'name': 'chain o2'});
    await db.doc('organizations/o2/companies/c1').set({'name': 'C'});
    await db.doc('organizations/o3').set({'name': 'chain o3'});
    await db.doc('organizations/o3/companies/c1').set({'name': 'C'});
    await db.doc('organizations/o1/companies/c1/delegates/$uid').set({
      'uid': uid,
      'status': 'active',
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'fullName': 'Delegate One',
      'subscription': paidSubNow(),
    });
    final add = DelegateSubscriptionRequest(
      id: 'add1',
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      organizationUID: 'o2',
      organizationName: 'O2',
      firstName: 'D',
      secondName: '',
      thirdName: '',
      fullName: 'Delegate One',
      phoneNumber: '010',
      nationalId: '',
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.notRequired,
      subscriptionCycle: '2027_H1',
      cycleStartDate: DateTime(2027, 1, 1),
      cycleEndDate: DateTime(2027, 6, 30, 23, 59, 59),
      fee: 0,
      remainingMonths: 0,
      requestType: kRequestTypeAddOrganization,
      existingDelegateUid: uid,
      currentOrganizationName: 'O1',
      createdAt: DateTime(2027, 2, 10),
      paymentStatus: SubscriptionPaymentStatus.notRequired,
    );
    await db.doc('delegate_requests/add1').set({...add.toMap(), 'orgCompanyCheck': 'ok'});

    final r = await repo.approveSubscriptionRequest(
      request: add,
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isRight(), isTrue);
    final created = (await db.doc('organizations/o2/companies/c1/delegates/$uid').get()).data()!;
    expect(created['status'], 'active');
    expect(created['subscription']['periodCode'], paidSubNow()['periodCode']);
    expect(created['subscription']['paymentStatus'], 'paid');
    expect(created['subscription']['amountDue'], 416.67);
    expect(created['subscription']['renewalRequestId'], 'ren-paid');
    final request = (await db.doc('delegate_requests/add1').get()).data()!;
    expect(request['status'], 'approved');
    expect(request['paymentStatus'], 'not_required');
    expect(request['fee'], 0);
  });

  test('approval refuses add-to-another-chain when the delegate is not already active', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    const uid = 'd2';
    await db.doc('organizations/o1/companies/c1/delegates/$uid').set({
      'uid': uid,
      'status': 'suspended',
      'statusReason': 'subscription_expired',
      'companyUID': 'c1',
      'organizationUID': 'o1',
    });
    final add = DelegateSubscriptionRequest(
      id: 'add2',
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      organizationUID: 'o2',
      organizationName: 'O2',
      firstName: 'D',
      secondName: '',
      thirdName: '',
      fullName: 'Delegate Two',
      phoneNumber: '010',
      nationalId: '',
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.notRequired,
      subscriptionCycle: '2027_H1',
      cycleStartDate: DateTime(2027, 1, 1),
      cycleEndDate: DateTime(2027, 6, 30, 23, 59, 59),
      fee: 0,
      remainingMonths: 0,
      requestType: kRequestTypeAddOrganization,
      existingDelegateUid: uid,
      createdAt: DateTime(2027, 2, 10),
      paymentStatus: SubscriptionPaymentStatus.notRequired,
    );
    await db.doc('delegate_requests/add2').set({...add.toMap(), 'orgCompanyCheck': 'ok'});
    final r = await repo.approveSubscriptionRequest(
      request: add,
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isLeft(), isTrue);
    expect((await db.doc('delegate_requests/add2').get()).data()!['status'], 'pending');
    expect((await db.doc('organizations/o2/companies/c1/delegates/$uid').get()).exists, isFalse);
  });

  test('approval refuses add-to-another-chain when the delegate is active but unpaid', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    const uid = 'd-unpaid';
    await db.doc('organizations/o1/companies/c1/delegates/$uid').set({
      'uid': uid,
      'status': 'active',
      'companyUID': 'c1',
      'organizationUID': 'o1',
    });
    final add = DelegateSubscriptionRequest(
      id: 'add-unpaid',
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      organizationUID: 'o2',
      organizationName: 'O2',
      firstName: 'D',
      secondName: '',
      thirdName: '',
      fullName: 'Delegate Unpaid',
      phoneNumber: '010',
      nationalId: '',
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.notRequired,
      subscriptionCycle: '2027_H1',
      cycleStartDate: DateTime(2027, 1, 1),
      cycleEndDate: DateTime(2027, 6, 30, 23, 59, 59),
      fee: 0,
      remainingMonths: 0,
      requestType: kRequestTypeAddOrganization,
      existingDelegateUid: uid,
      createdAt: DateTime(2027, 2, 10),
      paymentStatus: SubscriptionPaymentStatus.notRequired,
    );
    await db.doc('delegate_requests/add-unpaid').set({...add.toMap(), 'orgCompanyCheck': 'ok'});
    final r = await repo.approveSubscriptionRequest(
      request: add,
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isLeft(), isTrue);
    expect((await db.doc('delegate_requests/add-unpaid').get()).data()!['status'], 'pending');
    expect((await db.doc('organizations/o2/companies/c1/delegates/$uid').get()).exists, isFalse);
  });

  test('partial-duplicate remaining chains attach to the existing uid with no new fee', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    const uid = 'd-exist';
    await seedPaidAddOrgContext(db, uid: uid, orgs: const ['o1', 'o2', 'o3']);
    await db.doc('organizations/o1/companies/c1/delegates/$uid').set({
      'uid': uid,
      'status': 'active',
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'organizationName': 'O1',
      'fullName': 'Existing Delegate',
      'firstName': 'Existing',
      'nationalId': '20000000000099',
      'nationalityID': '20000000000099',
      'phoneNumber': '01000000099',
      'subscription': paidSubNow(renewalRequestId: 'ren-exist'),
    });

    final loaded = await repo.loadCompanyDelegate(
      companyUID: 'c1',
      organizationUID: 'o1',
      uid: uid,
    );
    final existing = loaded.getOrElse(() => throw StateError('missing delegate'));
    expect(existing.uid, uid);
    expect(existing.status, DelegateStatus.active);

    final submitted = await repo.submitAddOrganizationRequest(
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      targetOrganizationUID: 'o2',
      targetOrganizationName: 'O2',
      organizationUIDs: const ['o2', 'o3'],
      organizationNames: const ['O2', 'O3'],
      existingDelegate: existing,
      paymentMethod: SubscriptionPaymentMethod.paymob,
      fee: 500,
      remainingMonths: 5,
    );
    expect(submitted.isRight(), isTrue);
    final requestId = submitted.getOrElse(() => '');
    final written = (await db.doc('delegate_requests/$requestId').get()).data()!;
    expect(written['requestType'], kRequestTypeAddOrganization);
    expect(written['existingDelegateUid'], uid);
    expect(written['fee'], 0.0);
    expect(written['amountDue'], 0.0);
    expect(written['paymentStatus'], 'not_required');
    expect(written['organizationUIDs'], ['o2', 'o3']);
    expect(written['id'] ?? requestId, isNot(uid));

    await db.doc('delegate_requests/$requestId').update({'orgCompanyCheck': 'ok'});
    final stamped = (await db.doc('delegate_requests/$requestId').get()).data()!;
    final add = DelegateSubscriptionRequest.fromMap(stamped, requestId);
    final approved = await repo.approveSubscriptionRequest(
      request: add,
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(approved.isRight(), isTrue);
    for (final org in ['o2', 'o3']) {
      final created = (await db.doc('organizations/$org/companies/c1/delegates/$uid').get()).data()!;
      expect(created['uid'], uid);
      expect(created['status'], 'active');
      expect(created['subscription']['paymentStatus'], 'paid');
      expect(created['subscription']['renewalRequestId'], 'ren-exist');
      expect(created['subscription']['amountDue'], 416.67);
    }
  });

  test('approval refuses new_delegate and add_organization when orgCompanyCheck is not ok', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    await db.doc('organizations/o1').set({'name': 'chain o1'});
    await db.doc('organizations/o1/companies/c1').set({'name': 'C'});
    await db.doc('delegate_requests/r-failed').set({
      ...req(pay: SubscriptionPaymentStatus.paid).toMap(),
      'orgCompanyCheck': 'failed',
    });
    final failed = await repo.approveSubscriptionRequest(
      request: req(pay: SubscriptionPaymentStatus.paid).copyWith(id: 'r-failed'),
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(failed.isLeft(), isTrue);
    expect((await db.doc('delegate_requests/r-failed').get()).data()!['status'], isNot('approved'));
    expect((await db.doc('organizations/o1/companies/c1/delegates/r-failed').get()).exists, isFalse);

    // No stamp (auditDelegateRequestOrgs not deployed, e.g. prod today):
    // falls back to the client re-check and approves.
    await db.doc('delegate_requests/r-missing').set(req(pay: SubscriptionPaymentStatus.paid).toMap());
    final missing = await repo.approveSubscriptionRequest(
      request: req(pay: SubscriptionPaymentStatus.paid).copyWith(id: 'r-missing'),
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(missing.isRight(), isTrue);
  });

  test('approval registers the company in a chain it is not in (copied record, admin, no overwrite)', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    await db.doc('organizations/o1').set({'name': 'chain o1', 'code': 'O1'});
    await db.doc('organizations/o2').set({'name': 'chain o2', 'code': 'O2'});
    await db.doc('organizations/o3').set({'name': 'chain o3', 'code': 'O3'});
    await db.doc('organizations/o1/companies/c1').set({
      'name': 'C', 'type': 'distributor', 'companyCodeInOrg': '1048',
      'organizationUID': 'o1', 'organizationName': 'chain o1', 'organizationCode': 'O1',
      'commercialRegisterNumber': 'CR-1', 'taxCardNumber': 'TX-1',
      'hasDeferredPayment': true, 'deferredPayment': 900, 'status': 'Approved',
      'delegatesCount': 12, 'totalApprovedDelegates': 12,
      'documentUrls': {'commercialRegister': 'u1', 'taxCard': 'u2'},
    });
    // o3 already has another company with code 1048 -> code left pending.
    await db.doc('organizations/o3/companies/other').set({'name': 'X', 'companyCodeInOrg': '1048'});
    await db.doc('delegate_requests/r-new').set({
      ...req(pay: SubscriptionPaymentStatus.paid).toMap(),
      'organizationUID': 'o2',
      'organizationName': 'chain o2',
      'organizationUIDs': ['o2', 'o3'],
      'organizationNames': ['chain o2', 'chain o3'],
      // Old stamp from before the product decision is tolerated.
      'orgCompanyCheck': 'failed',
      'orgCompanyCheckReason': 'org_not_in_company',
    });
    final r = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(
        (await db.doc('delegate_requests/r-new').get()).data()!,
        'r-new',
      ),
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isRight(), isTrue, reason: r.fold((f) => f.message, (_) => ''));
    final o2 = (await db.doc('organizations/o2/companies/c1').get()).data()!;
    expect(o2['organizationUID'], 'o2');
    expect(o2['organizationName'], 'chain o2');
    expect(o2['organizationCode'], 'O2');
    expect(o2['companyCodeInOrg'], '1048');
    expect(o2['commercialRegisterNumber'], 'CR-1');
    expect(o2['taxCardNumber'], 'TX-1');
    expect(o2['type'], 'distributor');
    expect(o2['hasDeferredPayment'], isTrue);
    expect(o2['deferredPayment'], 0);
    expect(o2['status'], 'Approved');
    expect(o2['delegatesCount'], 0);
    expect(o2['registeredVia'], 'add_organization_approval');
    expect(o2['registeredFromRequestId'], 'r-new');
    expect(o2['registeredFromOrganizationUID'], 'o1');
    final o3 = (await db.doc('organizations/o3/companies/c1').get()).data()!;
    expect(o3['companyCodeInOrg'], '');
    expect(o3['companyCodeInOrgPending'], isTrue);
    expect((await db.doc('organizations/o2/companies/c1/admins/sup1').get()).exists, isTrue);
    expect((await db.doc('organizations/o2/companies/c1/delegates/r-new').get()).exists, isTrue);
    expect((await db.doc('organizations/o3/companies/c1/delegates/r-new').get()).exists, isTrue);
    // The existing record in o1 is untouched.
    final o1 = (await db.doc('organizations/o1/companies/c1').get()).data()!;
    expect(o1['deferredPayment'], 900);
    expect(o1['delegatesCount'], 12);
  });

  test('approval refuses a secondary chain that does not exist even if the mark is ok', () async {
    final db = FakeFirebaseFirestore();
    final repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    await db.doc('organizations/o1').set({'name': 'chain o1'});
    await db.doc('organizations/o1/companies/c1').set({'name': 'C'});
    await db.doc('delegate_requests/r-ox').set({
      ...req(pay: SubscriptionPaymentStatus.paid).toMap(),
      'organizationUID': 'o1',
      'organizationUIDs': ['o1', 'oX'],
      'orgCompanyCheck': 'ok',
    });
    final r = await repo.approveSubscriptionRequest(
      request: DelegateSubscriptionRequest.fromMap(
        (await db.doc('delegate_requests/r-ox').get()).data()!,
        'r-ox',
      ),
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isLeft(), isTrue);
    expect((await db.doc('organizations/oX/companies/c1/delegates/r-ox').get()).exists, isFalse);
  });
}
