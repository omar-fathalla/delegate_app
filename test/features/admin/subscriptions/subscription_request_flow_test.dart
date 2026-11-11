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
      await db.doc('delegate_requests/r1').set(req().toMap());
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
}

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
    await db.doc('organizations/o1/companies/c1/delegates/$uid').set({
      'uid': uid,
      'status': 'active',
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'fullName': 'Delegate One',
      'subscription': {
        'periodCode': '2027_H1',
        'periodStart': '2027-01-01',
        'periodEnd': '2027-06-30',
        'amountDue': 416.67,
        'paymentStatus': 'paid',
        'renewalRequestId': 'ren-paid',
      },
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
    await db.doc('delegate_requests/add1').set(add.toMap());

    final r = await repo.approveSubscriptionRequest(
      request: add,
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isRight(), isTrue);
    final created = (await db.doc('organizations/o2/companies/c1/delegates/$uid').get()).data()!;
    expect(created['status'], 'active');
    expect(created['subscription']['periodCode'], '2027_H1');
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
    await db.doc('delegate_requests/add2').set(add.toMap());
    final r = await repo.approveSubscriptionRequest(
      request: add,
      reviewerUid: 'sa',
      reviewerName: 'SA',
    );
    expect(r.isLeft(), isTrue);
    expect((await db.doc('delegate_requests/add2').get()).data()!['status'], 'pending');
    expect((await db.doc('organizations/o2/companies/c1/delegates/$uid').get()).exists, isFalse);
  });

