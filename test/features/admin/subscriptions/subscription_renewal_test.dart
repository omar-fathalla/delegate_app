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

Delegate supervisor({
  String uid = 'sup1',
  DelegateStatus status = DelegateStatus.active,
  String organizationUID = 'o1',
  String companyUID = 'c1',
}) =>
    Delegate(
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
    );

Future<FakeFirebaseFirestore> seed() async {
  final db = FakeFirebaseFirestore();
  Future<void> reg(String id, {String company = 'c1', String type = 'new_delegate', String sup = 'sup1'}) =>
      db.doc('delegate_requests/$id').set({
        'requestType': type,
        'status': 'approved',
        'supervisorUid': sup,
        'companyUID': company,
        'organizationUID': 'o1',
        'fullName': 'req $id',
      });
  Future<void> del(String id, String status, {String? reason, String company = 'c1'}) =>
      db.doc('organizations/o1/companies/$company/delegates/$id').set({
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
  await del('other', 'suspended', reason: kSubscriptionExpiredReason, company: 'c2');
  // Web delegate: no app request at all.
  await del('web1', 'suspended', reason: kSubscriptionExpiredReason);
  return db;
}

class FakeGateway implements SubscriptionPaymentGateway {
  final List<String> started = [];
  @override
  Future<Either<Failure, PaymentCheckout>> startCheckout({required String requestId}) async {
    started.add(requestId);
    return const Left(ServerFailure(PaymobNotConnectedGateway.message));
  }
}

void main() {
  group('RenewalSelection', () {
    const ds = [
      RenewableDelegate(uid: 'a', fullName: 'A', phoneNumber: '', organizationName: ''),
      RenewableDelegate(uid: 'b', fullName: 'B', phoneNumber: '', organizationName: ''),
      RenewableDelegate(uid: 'c', fullName: 'C', phoneNumber: '', organizationName: '', pendingRenewalRequestId: 'r0'),
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
      expect(RenewalSelection.single('a').total(DateTime.utc(2027, 6, 10, 10)), 83.33);
    });

    test('select all skips delegates already awaiting payment; retainOnly drops stale uids', () {
      final all = const RenewalSelection().selectAll(ds);
      expect(all.selectedUids, {'a', 'b'});
      expect(all.total(DateTime.utc(2027, 1, 5, 10)), 1000);
      expect(RenewalSelection(const {'a', 'zzz', 'c'}).retainOnly(ds).selectedUids, {'a'});
    });

    test('total is recomputed when the calendar month changes in the same period', () {
      const sel = RenewalSelection({'a', 'b'});
      expect(sel.total(DateTime(2027, 1, 15)), 1000.0);
      expect(sel.feePerDelegate(DateTime(2027, 1, 15)), 500.0);
      expect(sel.total(DateTime(2027, 2, 1)), 833.34);
      expect(sel.feePerDelegate(DateTime(2027, 2, 1)), 416.67);
    });

    test('nothing to pay during the free promotion', () {
      expect(const RenewalSelection().selectAll(ds).total(nov2026), 0);
    });

    test('selectAll and toggle respect maxDelegatesPerRenewal', () {
      final many = List.generate(
        SubscriptionCycleHelper.maxDelegatesPerRenewal + 5,
        (i) => RenewableDelegate(uid: 'u$i', fullName: '$i', phoneNumber: '', organizationName: ''),
      );
      final all = const RenewalSelection().selectAll(many);
      expect(all.count, SubscriptionCycleHelper.maxDelegatesPerRenewal);
      var s = RenewalSelection(
        {for (var i = 0; i < SubscriptionCycleHelper.maxDelegatesPerRenewal; i++) 'u$i'},
      );
      s = s.toggle('extra');
      expect(s.count, SubscriptionCycleHelper.maxDelegatesPerRenewal);
      expect(s.isSelected('extra'), isFalse);
    });
  });

  group('SubscriptionRenewalRepository', () {
    test('lists only this company\'s app-added delegates suspended for expiry', () async {
      final repo = SubscriptionRenewalRepository(firestore: await seed(), clock: () => feb2027);
      final list = (await repo.loadRenewableDelegates(companyUID: 'c1')).getOrElse(() => []);
      expect(list.map((d) => d.uid), ['a', 'b', 'c']);
    });

    test('partial renewal: one request, one payment, only the selected delegates', () async {
      final db = await seed();
      final repo = SubscriptionRenewalRepository(firestore: db, clock: () => feb2027);
      final list = (await repo.loadRenewableDelegates(companyUID: 'c1')).getOrElse(() => []);
      final s = supervisor();
      final id = (await repo.submitRenewal(
        supervisorUid: s.uid,
        supervisorName: s.fullName,
        supervisorPhone: s.phoneNumber,
        companyUID: s.companyUID,
        companyName: s.companyName,
        organizationUID: s.organizationUID,
        organizationName: s.organizationName,
        delegates: list.where((d) => d.uid != 'c').toList(),
      ))
          .getOrElse(() => '');
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
      expect((await db.doc('organizations/o1/companies/c1/delegates/a').get()).data()!['status'], 'suspended');

      // a and b are now awaiting payment; c can still be renewed later.
      final again = (await repo.loadRenewableDelegates(companyUID: 'c1')).getOrElse(() => []);
      expect(again.where((d) => d.isAwaitingPayment).map((d) => d.uid), ['a', 'b']);
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
      await db.doc('delegate_requests/$id').update({'paymentStatus': 'failed'});
      final afterFail = (await repo.loadRenewableDelegates(companyUID: 'c1')).getOrElse(() => []);
      expect(afterFail.where((d) => d.isAwaitingPayment), isEmpty);
    });

    test('cancel an unpaid renewal; a paid one cannot be cancelled', () async {
      final db = await seed();
      final repo = SubscriptionRenewalRepository(firestore: db, clock: () => feb2027);
      await db.doc('delegate_requests/r1').set({'paymentStatus': 'pending', 'status': 'pending'});
      await db.doc('delegate_requests/r2').set({'paymentStatus': 'paid', 'status': 'approved'});
      expect((await repo.cancelRenewal('r1')).isRight(), isTrue);
      expect((await db.doc('delegate_requests/r1').get()).data()!['status'], 'cancelled');
      expect((await repo.cancelRenewal('r2')).isLeft(), isTrue);
    });

    test('rejects more than maxDelegatesPerRenewal in one renewal', () async {
      final repo = SubscriptionRenewalRepository(firestore: await seed(), clock: () => feb2027);
      final s = supervisor();
      final tooMany = List.generate(
        SubscriptionCycleHelper.maxDelegatesPerRenewal + 1,
        (i) => RenewableDelegate(uid: 'x$i', fullName: 'x', phoneNumber: '', organizationName: ''),
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

    test('no renewal during the free promotion, and empty selection is refused', () async {
      final repo = SubscriptionRenewalRepository(firestore: await seed(), clock: () => nov2026);
      final s = supervisor();
      Future<Either<Failure, String>> submit(List<RenewableDelegate> ds) => repo.submitRenewal(
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
        (await submit(const [RenewableDelegate(uid: 'a', fullName: 'A', phoneNumber: '', organizationName: '')]))
            .isLeft(),
        isTrue,
      );
    });

    test('watchPaymentStatus follows the server-written status', () async {
      final db = FakeFirebaseFirestore();
      await db.doc('delegate_requests/r').set({'paymentStatus': 'pending'});
      final repo = SubscriptionRenewalRepository(firestore: db, clock: () => feb2027);
      final expectation = expectLater(
        repo.watchPaymentStatus('r'),
        emitsThrough(SubscriptionPaymentStatus.paid),
      );
      await Future<void>.delayed(Duration.zero);
      await db.doc('delegate_requests/r').update({'paymentStatus': 'paid'});
      await expectation;
    });
  });

  group('SubscriptionRenewalScreen', () {
    testWidgets('multi-select, live total, one Paymob checkout for the selection', (tester) async {
      final db = await seed();
      final gateway = FakeGateway();
      final repo = SubscriptionRenewalRepository(firestore: db, clock: () => feb2027);
      await tester.pumpWidget(MaterialApp(
        home: SubscriptionRenewalScreen(
          supervisor: supervisor(),
          repository: repo,
          paymentGateway: gateway,
          clock: () => feb2027,
        ),
      ));
      await tester.pumpAndSettle();

      expect(find.text('تجديد المناديب'), findsOneWidget);
      expect(find.byKey(const Key('renewal_row_a')), findsOneWidget);
      expect(find.byKey(const Key('renewal_row_c')), findsOneWidget);
      expect(find.byKey(const Key('renewal_row_web1')), findsNothing);
      expect(find.byKey(const Key('renewal_row_manual')), findsNothing);

      String total() => tester.widget<Text>(find.byKey(const Key('renewal_total'))).data!;
      expect(total(), 'الإجمالي: 0 ج.م');
      FilledButton pay() => tester.widget<FilledButton>(find.byKey(const Key('renewal_pay_button')));
      expect(pay().onPressed, isNull);

      await tester.tap(find.byKey(const Key('renewal_row_a')));
      await tester.pump();
      expect(total(), 'الإجمالي: 416.67 ج.م');
      await tester.tap(find.byKey(const Key('renewal_row_b')));
      await tester.pump();
      expect(total(), 'الإجمالي: 833.34 ج.م');

      await tester.tap(find.byKey(const Key('renewal_select_all')));
      await tester.pump();
      expect(total(), 'الإجمالي: 1250.01 ج.م');
      await tester.tap(find.byKey(const Key('renewal_select_all')));
      await tester.pump();
      expect(total(), 'الإجمالي: 0 ج.م');

      await tester.tap(find.byKey(const Key('renewal_row_b')));
      await tester.pump();
      await tester.tap(find.byKey(const Key('renewal_pay_button')));
      await tester.pumpAndSettle();

      expect(gateway.started, hasLength(1));
      final req = (await db.doc('delegate_requests/${gateway.started.single}').get()).data()!;
      expect(req['coveredDelegateUids'], ['b']);
      expect(req['amountDue'], 416.67);
      expect(find.byKey(const Key('renewal_payment_status')), findsOneWidget);

      // b now shows as awaiting payment; a and c remain selectable for later.
      expect(find.text('إلغاء الطلب'), findsOneWidget);
      expect(tester.widget<CheckboxListTile>(find.byKey(const Key('renewal_row_a'))).value, isFalse);
    });

    testWidgets('during the free promotion the pay button is disabled', (tester) async {
      final repo = SubscriptionRenewalRepository(firestore: await seed(), clock: () => nov2026);
      await tester.pumpWidget(MaterialApp(
        home: SubscriptionRenewalScreen(
          supervisor: supervisor(),
          repository: repo,
          paymentGateway: FakeGateway(),
          clock: () => nov2026,
        ),
      ));
      await tester.pumpAndSettle();
      await tester.tap(find.byKey(const Key('renewal_row_a')));
      await tester.pump();
      expect(tester.widget<FilledButton>(find.byKey(const Key('renewal_pay_button'))).onPressed, isNull);
      expect(find.textContaining('مجاني حتى 31/12/2026'), findsOneWidget);
    });
  });

    test('a uid passed twice (two chains) is charged once', () async {
      final db = FakeFirebaseFirestore();
      final repo = SubscriptionRenewalRepository(firestore: db, clock: () => DateTime.utc(2027, 2, 10));
      const twice = [
        RenewableDelegate(uid: 'app1', fullName: 'A', phoneNumber: '', organizationName: 'O1'),
        RenewableDelegate(uid: 'app1', fullName: 'A', phoneNumber: '', organizationName: 'O2'),
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
      expect(m['fee'], SubscriptionCycleHelper.totalFor(1, DateTime.utc(2027, 2, 10)));
    });
}
