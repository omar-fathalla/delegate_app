import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/data/repositories/subscription_renewal_repository.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/entities/subscription_renewal.dart';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

// 10 Feb 2027 noon Cairo: H1 2027, 5 months left -> 416.67 per delegate.
final feb2027 = DateTime.utc(2027, 2, 10, 10);
final nov2026 = DateTime.utc(2026, 11, 10, 10);
Key rowKey(String uid, String period) => Key('renewal_row_$uid|$period');

Delegate supervisor({
  String uid = 'sup1',
  DelegateStatus status = DelegateStatus.active,
  String organizationUID = 'o1',
  String companyUID = 'c1',
  UserRole role = UserRole.delegate,
}) => Delegate(
  uid: uid,
  firstName: 'مشرف',
  middleName: '',
  lastName: '',
  fullName: 'مشرف يوني',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: organizationUID,
  organizationName: 'لولو',
  companyUID: companyUID,
  companyName: 'يوني',
  status: status,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: '',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: role,
);

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  Future<void> reg(
    String id, {
    String company = 'c1',
    String type = 'new_delegate',
    String sup = 'sup1',
  }) => db.doc('delegate_requests/$id').set({
    'requestType': type,
    'status': 'approved',
    'supervisorUid': sup,
    'companyUID': company,
    'organizationUID': 'o1',
    'fullName': 'req $id',
  });
  Future<void> del(
    String id,
    String status, {
    String? reason,
    String company = 'c1',
  }) => db.doc('organizations/o1/companies/$company/delegates/$id').set({
    'uid': id,
    'fullName': 'مندوب $id',
    'phoneNumber': '010$id',
    'organizationName': 'لولو',
    'status': status,
    'statusReason': ?reason,
  });
  for (final id in ['a', 'b', 'c']) {
    await reg(id);
    await del(id, 'suspended', reason: kSubscriptionExpiredReason);
  }
  await reg('active1');
  await del('active1', 'active');
  await reg('manual');
  await del('manual', 'suspended', reason: 'manual');
  await reg('other', company: 'c2');
  await del(
    'other',
    'suspended',
    reason: kSubscriptionExpiredReason,
    company: 'c2',
  );
  // Web delegate: no app request at all.
  await del('web1', 'suspended', reason: kSubscriptionExpiredReason);
  return db;
}

class FakeGateway implements SubscriptionPaymentGateway {
  final List<String> started = [];
  DateTime Function() clock;

  FakeGateway({DateTime Function()? clock})
    : clock = clock ?? (() => DateTime(2027, 2, 10));

  @override
  Future<Either<Failure, RenewalQuotePreview>> previewQuote({
    required String companyUID,
    String? organizationUID,
    required List<String> uids,
    String? periodCode,
  }) async {
    final amount = SubscriptionCycleHelper.totalFor(uids.length, clock());
    final cents = (amount * 100).round();
    return Right(
      RenewalQuotePreview(
        amountCents: cents,
        periodCode: SubscriptionCycleHelper.getCycleCode(clock()),
        remainingMonths: SubscriptionCycleHelper.getRemainingMonthsInCycle(
          clock(),
        ),
        delegateCount: uids.length,
      ),
    );
  }

  @override
  Future<Either<Failure, PaymentCheckout>> startCheckout({
    required String requestId,
  }) async {
    started.add(requestId);
    return const Left(ServerFailure(PaymobNotConnectedGateway.message));
  }
}

void main() {
  group('RenewalSelection', () {
    const ds = [
      RenewableDelegate(
        uid: 'a',
        fullName: 'A',
        phoneNumber: '',
        organizationName: '',
      ),
      RenewableDelegate(
        uid: 'b',
        fullName: 'B',
        phoneNumber: '',
        organizationName: '',
      ),
      RenewableDelegate(
        uid: 'c',
        fullName: 'C',
        phoneNumber: '',
        organizationName: '',
        pendingRenewalRequestId: 'r0',
      ),
    ];

    test('any subset; total is the sum of prorated fees', () {
      var s = const RenewalSelection();
      expect(s.total(feb2027), 0);
      s = s.toggle('a');
      expect(s.count, 1);
      expect(s.total(feb2027), 416.67);
      s = s.toggle('b');
      expect(s.total(feb2027), 833.34);
      s = s.toggle('a');
      expect(s.selectedUids, {'b'});
      expect(
        RenewalSelection.single('a').total(DateTime.utc(2027, 6, 10, 10)),
        83.33,
      );
    });

    test(
      'select all skips delegates already awaiting payment; retainOnly drops stale uids',
      () {
        final all = const RenewalSelection().selectAll(ds);
        expect(all.selectedUids, {'a', 'b'});
        expect(all.total(DateTime.utc(2027, 1, 5, 10)), 1000);
        expect(
          RenewalSelection(const {'a', 'zzz', 'c'}).retainOnly(ds).selectedUids,
          {'a'},
        );
      },
    );

    test(
      'total is recomputed when the calendar month changes in the same period',
      () {
        const sel = RenewalSelection({'a', 'b'});
        expect(sel.total(DateTime(2027, 1, 15)), 1000.0);
        expect(sel.feePerDelegate(DateTime(2027, 1, 15)), 500.0);
        expect(sel.total(DateTime(2027, 2, 1)), 833.34);
        expect(sel.feePerDelegate(DateTime(2027, 2, 1)), 416.67);
      },
    );

    test('nothing to pay during the free promotion', () {
      expect(const RenewalSelection().selectAll(ds).total(nov2026), 0);
    });

    test(
      'advance selection uses the next period full fee, not today\'s promo zero',
      () {
        const sel = RenewalSelection({'a', 'b'});
        final dec = DateTime.utc(2026, 12, 15, 10);
        expect(sel.feePerDelegate(dec, null, '2027_H1'), 500.0);
        expect(sel.total(dec, null, '2027_H1'), 1000.0);
        expect(sel.total(dec), 0); // current period still free
      },
    );

    test('selectAll and toggle respect maxDelegatesPerRenewal', () {
      final many = List.generate(
        SubscriptionCycleHelper.maxDelegatesPerRenewal + 5,
        (i) => RenewableDelegate(
          uid: 'u$i',
          fullName: '$i',
          phoneNumber: '',
          organizationName: '',
        ),
      );
      final all = const RenewalSelection().selectAll(many);
      expect(all.count, SubscriptionCycleHelper.maxDelegatesPerRenewal);
      var s = RenewalSelection({
        for (var i = 0; i < SubscriptionCycleHelper.maxDelegatesPerRenewal; i++)
          'u$i',
      });
      s = s.toggle('extra');
      expect(s.count, SubscriptionCycleHelper.maxDelegatesPerRenewal);
      expect(s.isSelected('extra'), isFalse);
    });
  });

  group('SubscriptionRenewalRepository', () {
    test(
      'lists only this company\'s app-added delegates suspended for expiry',
      () async {
        final repo = SubscriptionRenewalRepository(
          firestore: await seed(),
          clock: () => feb2027,
        );
        final list = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        expect(list.map((d) => d.uid).toSet(), {
          'a',
          'b',
          'c',
          'active1',
          'manual',
        });
        expect(list.where((d) => d.isSelectable).map((d) => d.uid).toSet(), {
          'a',
          'b',
          'c',
          'active1',
          'manual',
        });
        expect(list.where((d) => d.isCovered), isEmpty);
      },
    );

    test(
      'org-admin list query is scoped to organizationUID; HR sees every chain',
      () async {
        final db = await seed();
        await db.doc('delegate_requests/o2d').set({
          'requestType': kRequestTypeNewDelegate,
          'status': 'approved',
          'supervisorUid': 'sup1',
          'companyUID': 'c1',
          'organizationUID': 'o2',
          'fullName': 'req o2d',
        });
        await db.doc('organizations/o2/companies/c1/delegates/o2d').set({
          'uid': 'o2d',
          'fullName': 'مندوب o2d',
          'phoneNumber': '010o2d',
          'organizationName': 'سلسلة 2',
          'status': 'suspended',
          'statusReason': kSubscriptionExpiredReason,
        });
        final repo = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => feb2027,
        );
        final hr = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        expect(hr.map((d) => d.uid), containsAll(['a', 'b', 'c', 'o2d']));
        final orgAdmin = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
          organizationUID: 'o1',
        )).getOrElse(() => []);
        expect(orgAdmin.map((d) => d.uid).toSet(), {
          'a',
          'b',
          'c',
          'active1',
          'manual',
        });
        expect(orgAdmin.map((d) => d.uid), isNot(contains('o2d')));
      },
    );

    test(
      'partial renewal: one request, one payment, only the selected delegates',
      () async {
        final db = await seed();
        final repo = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => feb2027,
        );
        final list = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        final s = supervisor();
        final id = (await repo.submitRenewal(
          supervisorUid: s.uid,
          supervisorName: s.fullName,
          supervisorPhone: s.phoneNumber,
          companyUID: s.companyUID,
          companyName: s.companyName,
          organizationUID: s.organizationUID,
          organizationName: s.organizationName,
          delegates: list.where((d) => d.uid == 'a' || d.uid == 'b').toList(),
        )).getOrElse(() => '');
        final data = (await db.doc('delegate_requests/$id').get()).data()!;
        expect(data['requestType'], kRequestTypeRenewal);
        expect(data['status'], 'pending');
        expect(data['paymentStatus'], 'pending');
        expect(data['paymentMethod'], 'paymob');
        expect(data['periodCode'], '2027_H1');
        expect(data['coveredDelegateUids'], ['a', 'b']);
        expect(data['amountDue'], 833.34);
        expect((data['items'] as List).map((e) => e['fee']), [416.67, 416.67]);
        // Delegates stay suspended until the server applies a verified payment.
        expect(
          (await db.doc('organizations/o1/companies/c1/delegates/a').get())
              .data()!['status'],
          'suspended',
        );

        // a and b are now awaiting payment; c can still be renewed later.
        final again = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        expect(again.where((d) => d.isAwaitingPayment).map((d) => d.uid), [
          'a',
          'b',
        ]);
        final dup = await repo.submitRenewal(
          supervisorUid: s.uid,
          supervisorName: s.fullName,
          supervisorPhone: s.phoneNumber,
          companyUID: s.companyUID,
          companyName: s.companyName,
          organizationUID: s.organizationUID,
          organizationName: s.organizationName,
          delegates: again.where((d) => d.uid == 'a').toList(),
        );
        expect(dup.isLeft(), isTrue);

        // A failed payment frees them for a new attempt.
        await db.doc('delegate_requests/$id').update({
          'paymentStatus': 'failed',
        });
        final afterFail = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        expect(afterFail.where((d) => d.isAwaitingPayment), isEmpty);
      },
    );

    test('cancel an unpaid renewal; a paid one cannot be cancelled', () async {
      final db = await seed();
      final repo = SubscriptionRenewalRepository(
        firestore: db,
        clock: () => feb2027,
      );
      await db.doc('delegate_requests/r1').set({
        'paymentStatus': 'pending',
        'status': 'pending',
      });
      await db.doc('delegate_requests/r2').set({
        'paymentStatus': 'paid',
        'status': 'approved',
      });
      expect((await repo.cancelRenewal('r1')).isRight(), isTrue);
      expect(
        (await db.doc('delegate_requests/r1').get()).data()!['status'],
        'cancelled',
      );
      expect((await repo.cancelRenewal('r2')).isLeft(), isTrue);
    });

    test('rejects more than maxDelegatesPerRenewal in one renewal', () async {
      final repo = SubscriptionRenewalRepository(
        firestore: await seed(),
        clock: () => feb2027,
      );
      final s = supervisor();
      final tooMany = List.generate(
        SubscriptionCycleHelper.maxDelegatesPerRenewal + 1,
        (i) => RenewableDelegate(
          uid: 'x$i',
          fullName: 'x',
          phoneNumber: '',
          organizationName: '',
        ),
      );
      final r = await repo.submitRenewal(
        supervisorUid: s.uid,
        supervisorName: s.fullName,
        supervisorPhone: s.phoneNumber,
        companyUID: s.companyUID,
        companyName: s.companyName,
        organizationUID: s.organizationUID,
        organizationName: s.organizationName,
        delegates: tooMany,
      );
      expect(r.isLeft(), isTrue);
    });

    test(
      'no renewal during the free promotion, and empty selection is refused',
      () async {
        final repo = SubscriptionRenewalRepository(
          firestore: await seed(),
          clock: () => nov2026,
        );
        final s = supervisor();
        Future<Either<Failure, String>> submit(List<RenewableDelegate> ds) =>
            repo.submitRenewal(
              supervisorUid: s.uid,
              supervisorName: s.fullName,
              supervisorPhone: s.phoneNumber,
              companyUID: s.companyUID,
              companyName: s.companyName,
              organizationUID: s.organizationUID,
              organizationName: s.organizationName,
              delegates: ds,
            );
        expect((await submit(const [])).isLeft(), isTrue);
        expect(
          (await submit(const [
            RenewableDelegate(
              uid: 'a',
              fullName: 'A',
              phoneNumber: '',
              organizationName: '',
            ),
          ])).isLeft(),
          isTrue,
        );
      },
    );

    test(
      'advance window lists uncovered app-added delegates and submits the next period at full fee',
      () async {
        final db = await seed();
        await db.doc('organizations/o1/companies/c1/delegates/a').update({
          'subscription': {'periodCode': '2027_H1', 'paymentStatus': 'paid'},
        });
        final dec = DateTime.utc(2026, 12, 15, 10);
        final repo = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => dec,
          advanceRenewalEnabled: true,
          advanceRenewalDays: 30,
        );
        final list = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        expect(
          list
              .where((d) => d.periodCode == '2026_H2')
              .map((d) => d.uid)
              .toSet(),
          {'a', 'b', 'c', 'active1', 'manual'},
        );
        expect(
          list
              .where((d) => d.periodCode == '2027_H1' && d.isSelectable)
              .map((d) => d.uid)
              .toSet(),
          {'b', 'c', 'active1', 'manual'},
        );
        expect(
          list
              .where((d) => d.periodCode == '2027_H1' && d.uid == 'a')
              .single
              .isCovered,
          isTrue,
        );

        final s = supervisor();
        final id = (await repo.submitRenewal(
          supervisorUid: s.uid,
          supervisorName: s.fullName,
          supervisorPhone: s.phoneNumber,
          companyUID: s.companyUID,
          companyName: s.companyName,
          organizationUID: s.organizationUID,
          organizationName: s.organizationName,
          delegates: list
              .where((d) => d.uid == 'active1' && d.periodCode == '2027_H1')
              .toList(),
        )).getOrElse(() => '');
        expect(id, isNotEmpty);
        final data = (await db.doc('delegate_requests/$id').get()).data()!;
        expect(data['periodCode'], '2027_H1');
        expect(data['periodStart'], '2027-01-01');
        expect(data['periodEnd'], '2027-06-30');
        expect(data['amountDue'] ?? data['fee'], 500.0);
        expect(data['remainingMonths'], 6);
        expect(data['coveredDelegateUids'], ['active1']);
      },
    );

    test(
      'pending current-period renewals stay visible and cancellable during the advance window',
      () async {
        final db = await seed();
        await db.doc('delegate_requests/pendH2').set({
          'requestType': kRequestTypeRenewal,
          'status': 'pending',
          'paymentStatus': 'pending',
          'companyUID': 'c1',
          'organizationUID': 'o1',
          'periodCode': '2026_H2',
          'coveredDelegateUids': ['a', 'b'],
        });
        final dec = DateTime.utc(2026, 12, 15, 10);
        final repo = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => dec,
          advanceRenewalEnabled: true,
          advanceRenewalDays: 30,
        );
        final list = (await repo.loadRenewableDelegates(
          companyUID: 'c1',
        )).getOrElse(() => []);
        final currentA = list.singleWhere(
          (d) => d.uid == 'a' && d.periodCode == '2026_H2',
        );
        expect(currentA.pendingRenewalRequestId, 'pendH2');
        expect(currentA.isAwaitingPayment, isTrue);
        expect((await repo.cancelRenewal('pendH2')).isRight(), isTrue);
        expect(
          (await db.doc('delegate_requests/pendH2').get()).data()!['status'],
          'cancelled',
        );
      },
    );

    test(
      'reads advance flags from config/subscriptions with constructor override still winning',
      () async {
        final db = await seed();
        final dec = DateTime.utc(2026, 12, 15, 10);
        await db.doc('config/subscriptions').set({
          'advanceRenewalEnabled': false,
          'advanceRenewalDays': 30,
        });
        final closed = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => dec,
        );
        await closed.refreshAdvanceConfig();
        expect(closed.isAdvanceRenewalOpen(dec), isFalse);
        await db.doc('config/subscriptions').set({
          'advanceRenewalEnabled': true,
          'advanceRenewalDays': 30,
        });
        final opened = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => dec,
        );
        await opened.refreshAdvanceConfig();
        expect(opened.isAdvanceRenewalOpen(dec), isTrue);
        final forcedOff = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => dec,
          advanceRenewalEnabled: false,
          advanceRenewalDays: 30,
        );
        await forcedOff.refreshAdvanceConfig();
        expect(forcedOff.isAdvanceRenewalOpen(dec), isFalse);
      },
    );

    test('watchPaymentStatus follows the server-written status', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('delegate_requests/r').set({'paymentStatus': 'pending'});
      final repo = SubscriptionRenewalRepository(
        firestore: db,
        clock: () => feb2027,
      );
      final expectation = expectLater(
        repo.watchPaymentStatus('r'),
        emitsThrough(SubscriptionPaymentStatus.paid),
      );
      await Future<void>.delayed(Duration.zero);
      await db.doc('delegate_requests/r').update({'paymentStatus': 'paid'});
      await expectation;
    });
  });

  test('covered delegates are excluded from selection with a reason', () async {
    final db = await seed();
    await db.doc('organizations/o1/companies/c1/delegates/c').update({
      'subscription': {'periodCode': '2027_H1', 'paymentStatus': 'paid'},
    });
    final repo = SubscriptionRenewalRepository(
      firestore: db,
      clock: () => feb2027,
    );
    final list = (await repo.loadRenewableDelegates(
      companyUID: 'c1',
    )).getOrElse(() => []);
    final covered = list.where((d) => d.uid == 'c').single;
    expect(covered.isCovered, isTrue);
    expect(covered.isSelectable, isFalse);
    expect(covered.exclusionReason, 'مغطى بالفعل لهذه الفترة');
    expect(
      const RenewalSelection().selectAll(list).isSelected(covered.selectionKey),
      isFalse,
    );
  });

  test('loadPaidRenewals returns one receipt listing the delegates', () async {
    final db = await seed();
    final repo = SubscriptionRenewalRepository(
      firestore: db,
      clock: () => feb2027,
    );
    await db.doc('delegate_requests/paid1').set({
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'requestType': kRequestTypeRenewal,
      'paymentStatus': 'paid',
      'periodCode': '2027_H1',
      'amountPaid': 833.34,
      'remainingMonths': 5,
      'companyName': 'يوني',
      'items': [
        {'uid': 'a', 'fullName': 'مندوب a', 'fee': 416.67},
        {'uid': 'b', 'fullName': 'مندوب b', 'fee': 416.67},
      ],
      'paymob': {'transactionId': 'tx-1'},
      'paidAt': '2027-02-10T10:00:00.000Z',
    });
    final list = (await repo.loadPaidRenewals(
      companyUID: 'c1',
    )).getOrElse(() => []);
    expect(list, hasLength(1));
    expect(list.single.delegateCount, 2);
    expect(list.single.transactionId, 'tx-1');
    expect(list.single.amount, 833.34);
  });

  group('SubscriptionRenewalScreen', () {
    testWidgets(
      'multi-select, live total, one Paymob checkout for the selection',
      (tester) async {
        final db = await seed();
        final gateway = FakeGateway();
        final repo = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => feb2027,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SubscriptionRenewalScreen(
              supervisor: supervisor(),
              repository: repo,
              paymentGateway: gateway,
              clock: () => feb2027,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.text('تجديد المناديب'), findsOneWidget);
        expect(find.byKey(rowKey('a', '2027_H1')), findsOneWidget);
        expect(find.byKey(rowKey('c', '2027_H1')), findsOneWidget);
        expect(find.byKey(rowKey('web1', '2027_H1')), findsNothing);
        expect(find.byKey(rowKey('manual', '2027_H1')), findsOneWidget);

        String total() =>
            tester.widget<Text>(find.byKey(const Key('renewal_total'))).data!;
        expect(total(), 'الإجمالي: 0 ج.م');
        FilledButton pay() => tester.widget<FilledButton>(
          find.byKey(const Key('renewal_pay_button')),
        );
        expect(pay().onPressed, isNull);

        await tester.tap(find.byKey(rowKey('a', '2027_H1')));
        await tester.pump();
        expect(total(), 'الإجمالي: 416.67 ج.م');
        await tester.tap(find.byKey(rowKey('b', '2027_H1')));
        await tester.pump();
        expect(total(), 'الإجمالي: 833.34 ج.م');

        await tester.tap(find.byKey(const Key('renewal_select_all')));
        await tester.pump();
        // a, b, c, active1, manual — 5 × 416.67
        expect(total(), 'الإجمالي: 2083.35 ج.م');
        await tester.tap(find.byKey(const Key('renewal_select_all')));
        await tester.pump();
        expect(total(), 'الإجمالي: 0 ج.م');

        await tester.tap(find.byKey(rowKey('b', '2027_H1')));
        await tester.pump();
        await tester.tap(find.byKey(const Key('renewal_pay_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('renewal_confirm_sheet')), findsOneWidget);
        expect(
          tester
              .widget<Text>(find.byKey(const Key('renewal_confirm_summary')))
              .data,
          'عدد المناديب: 1 × 416.67 ج.م = 416.67 ج.م',
        );
        await tester.tap(find.byKey(const Key('renewal_confirm_pay')));
        await tester.pumpAndSettle();

        expect(gateway.started, hasLength(1));
        final req =
            (await db.doc('delegate_requests/${gateway.started.single}').get())
                .data()!;
        expect(req['coveredDelegateUids'], ['b']);
        expect(req['amountDue'], 416.67);
        expect(find.byKey(const Key('renewal_payment_status')), findsOneWidget);

        // b now shows as awaiting payment; a and c remain selectable for later.
        expect(find.text('إلغاء الطلب'), findsOneWidget);
        expect(
          tester
              .widget<CheckboxListTile>(find.byKey(rowKey('a', '2027_H1')))
              .value,
          isFalse,
        );

        final cancelBtn = find.widgetWithText(TextButton, 'إلغاء الطلب');
        await tester.ensureVisible(cancelBtn);
        await tester.pumpAndSettle();
        await tester.tap(cancelBtn);
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('renewal_cancel_confirm')), findsOneWidget);
        await tester.tap(find.byKey(const Key('renewal_cancel_confirm_yes')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('renewal_payment_status')), findsNothing);
        expect(find.text('إلغاء الطلب'), findsNothing);
      },
    );

    testWidgets('during the free promotion the pay button is disabled', (
      tester,
    ) async {
      final repo = SubscriptionRenewalRepository(
        firestore: await seed(),
        clock: () => nov2026,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionRenewalScreen(
            supervisor: supervisor(),
            repository: repo,
            paymentGateway: FakeGateway(),
            clock: () => nov2026,
          ),
        ),
      );
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(rowKey('a', '2026_H2')));
      await tester.pump();
      expect(
        tester
            .widget<FilledButton>(find.byKey(const Key('renewal_pay_button')))
            .onPressed,
        isNull,
      );
      expect(find.textContaining('مجاني حتى 31/12/2026'), findsOneWidget);
    });

    testWidgets(
      'advance window enables pay during the free promotion at the next-period fee',
      (tester) async {
        final db = await seed();
        final dec = DateTime.utc(2026, 12, 15, 10);
        final gateway = FakeGateway(clock: () => dec);
        final repo = SubscriptionRenewalRepository(
          firestore: db,
          clock: () => dec,
          advanceRenewalEnabled: true,
          advanceRenewalDays: 30,
        );
        await tester.pumpWidget(
          MaterialApp(
            home: SubscriptionRenewalScreen(
              supervisor: supervisor(),
              repository: repo,
              paymentGateway: gateway,
              clock: () => dec,
            ),
          ),
        );
        await tester.pumpAndSettle();

        expect(find.byKey(rowKey('active1', '2027_H1')), findsOneWidget);
        expect(find.textContaining('التجديد المقدَّم'), findsAtLeast(1));
        expect(find.textContaining('مجاني حتى 31/12/2026'), findsNothing);

        await tester.ensureVisible(find.byKey(rowKey('active1', '2027_H1')));
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(rowKey('active1', '2027_H1')));
        await tester.pump();
        expect(
          tester.widget<Text>(find.byKey(const Key('renewal_total'))).data,
          'الإجمالي: 500 ج.م',
        );
        expect(
          tester
              .widget<FilledButton>(find.byKey(const Key('renewal_pay_button')))
              .onPressed,
          isNotNull,
        );

        await tester.tap(find.byKey(const Key('renewal_pay_button')));
        await tester.pumpAndSettle();
        expect(find.byKey(const Key('renewal_confirm_sheet')), findsOneWidget);
        await tester.tap(find.byKey(const Key('renewal_confirm_pay')));
        await tester.pumpAndSettle();
        expect(gateway.started, hasLength(1));
        final req =
            (await db.doc('delegate_requests/${gateway.started.single}').get())
                .data()!;
        expect(req['periodCode'], '2027_H1');
        expect(req['amountDue'] ?? req['fee'], 500.0);
      },
    );

    testWidgets('suspended filter hides active delegates', (tester) async {
      final repo = SubscriptionRenewalRepository(
        firestore: await seed(),
        clock: () => feb2027,
      );
      await tester.pumpWidget(
        MaterialApp(
          home: SubscriptionRenewalScreen(
            supervisor: supervisor(),
            repository: repo,
            paymentGateway: FakeGateway(),
            clock: () => feb2027,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(find.byKey(rowKey('active1', '2027_H1')), findsOneWidget);
      await tester.tap(find.byKey(const Key('renewal_filter_suspended')));
      await tester.pumpAndSettle();
      expect(find.byKey(rowKey('a', '2027_H1')), findsOneWidget);
      expect(find.byKey(rowKey('active1', '2027_H1')), findsNothing);
    });
  });

  test('a uid passed twice (two chains) is charged once', () async {
    final db = FakeFirebaseFirestore();
    final repo = SubscriptionRenewalRepository(
      firestore: db,
      clock: () => DateTime.utc(2027, 2, 10),
    );
    const twice = [
      RenewableDelegate(
        uid: 'app1',
        fullName: 'A',
        phoneNumber: '',
        organizationName: 'O1',
      ),
      RenewableDelegate(
        uid: 'app1',
        fullName: 'A',
        phoneNumber: '',
        organizationName: 'O2',
      ),
    ];
    final r = await repo.submitRenewal(
      supervisorUid: 'sup1',
      supervisorName: 'S',
      supervisorPhone: '',
      companyUID: 'c1',
      companyName: 'C',
      organizationUID: 'o1',
      organizationName: 'O1',
      delegates: twice,
    );
    expect(r.isRight(), isTrue);
    final id = r.getOrElse(() => '');
    final m = (await db.doc('delegate_requests/$id').get()).data()!;
    expect(m['coveredDelegateUids'], ['app1']);
    expect((m['items'] as List).length, 1);
    expect(
      m['fee'],
      SubscriptionCycleHelper.totalFor(1, DateTime.utc(2027, 2, 10)),
    );
  });
}
