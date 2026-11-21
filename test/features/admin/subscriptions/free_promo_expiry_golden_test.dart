// Golden/screenshot tests (TAS-162, TAS-195). CI runs them in a separate
// step (`flutter test --tags golden`) on Linux; small host antialiasing
// differences are tolerated by test/flutter_test_config.dart.
// Run locally: flutter test --tags golden
// Re-record: flutter test --tags golden --update-goldens
@Tags(['golden'])
library;

import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/data/repositories/subscription_renewal_repository.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/services/subscription_payment_gateway.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/add_delegate_subscription_section.dart';
import 'package:delegate_app/features/admin/presentation/widgets/company_exclusive_card_intro.dart';
import 'package:delegate_app/features/admin/presentation/widgets/subscription_request_status_widgets.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/promo_screenshot_harness.dart';

import 'subscription_renewal_test.dart' as renewal;

const _goldenDir = '../../../goldens/free_promo_expiry';

DelegateSubscriptionRequest _request({
  required SubscriptionPaymentMethod method,
  SubscriptionPaymentStatus paymentStatus = SubscriptionPaymentStatus.pending,
  String name = 'أحمد محمود',
  double fee = 500,
  String companyName = 'شركة التجربة',
  String organizationName = 'لولو',
}) {
  return DelegateSubscriptionRequest(
    id: 'r1',
    supervisorUid: 's1',
    supervisorName: 'مشرف',
    supervisorPhone: '01000000000',
    companyUID: 'c1',
    companyName: companyName,
    organizationUID: 'o1',
    organizationName: organizationName,
    firstName: 'أحمد',
    secondName: 'محمود',
    thirdName: 'علي',
    fullName: name,
    phoneNumber: '01011111111',
    nationalId: '12345678901234',
    profileImageUrl: '',
    nationalIdFrontUrl: '',
    nationalIdBackUrl: '',
    paymentMethod: method,
    subscriptionCycle: method == SubscriptionPaymentMethod.freePromotion
        ? '2026_H2'
        : '2027_H1',
    cycleStartDate: DateTime(2026, 7, 1),
    cycleEndDate: DateTime(2026, 12, 31),
    fee: fee,
    remainingMonths: 6,
    status: SubscriptionRequestStatus.pending,
    createdAt: DateTime(2026, 8, 1),
    paymentStatus: paymentStatus,
  );
}

class _FakeGateway implements SubscriptionPaymentGateway {
  @override
  Future<Either<Failure, RenewalQuotePreview>> previewQuote({
    required String companyUID,
    String? organizationUID,
    required List<String> uids,
    String? periodCode,
  }) async {
    final now = SubscriptionCycleHelper.currentTime();
    final amount = SubscriptionCycleHelper.totalFor(uids.length, now);
    return Right(
      RenewalQuotePreview(
        amountCents: (amount * 100).round(),
        periodCode: periodCode ?? SubscriptionCycleHelper.getCycleCode(now),
        remainingMonths: SubscriptionCycleHelper.getRemainingMonthsInCycle(now),
        delegateCount: uids.length,
      ),
    );
  }

  @override
  Future<Either<Failure, PaymentCheckout>> startCheckout({
    required String requestId,
  }) async {
    return const Left(ServerFailure(PaymobNotConnectedGateway.message));
  }
}

Widget _homeCard({required bool isFree}) {
  return Builder(
    builder: (context) {
      final cs = Theme.of(context).colorScheme;
      return Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: cs.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: cs.primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
        ),
        padding: const EdgeInsets.all(18),
        child: CompanyExclusiveCardIntro(
          isArabic: true,
          isFreePromotion: isFree,
        ),
      );
    },
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(SubscriptionCycleHelper.resetConfigForTest);
  tearDown(SubscriptionCycleHelper.resetConfigForTest);

  Future<void> prepare(WidgetTester tester) async {
    await tester.binding.setSurfaceSize(const Size(390, 844));
    tester.view.devicePixelRatio = 2.0;
    addTearDown(() async {
      await tester.binding.setSurfaceSize(null);
      tester.view.resetDevicePixelRatio();
    });
  }

  Future<void> shot(WidgetTester tester, String name) async {
    await tester.pumpAndSettle();
    await expectLater(
      find.byType(MaterialApp),
      matchesGoldenFile('$_goldenDir/$name.png'),
    );
  }

  testWidgets('admin_home_before', (tester) async {
    await prepare(tester);
    final theme = await promoTestTheme();
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2026, 11, 10, 10);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _homeCard(isFree: true),
        ),
      ),
    );
    await shot(tester, 'admin_home_before');
  });

  testWidgets('admin_home_after', (tester) async {
    await prepare(tester);
    final theme = await promoTestTheme();
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2027, 2, 10, 10);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: _homeCard(isFree: false),
        ),
      ),
    );
    await shot(tester, 'admin_home_after');
  });

  testWidgets('add_delegate_before', (tester) async {
    await prepare(tester);
    await tester.binding.setSurfaceSize(const Size(390, 1400));
    final theme = await promoTestTheme();
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2026, 11, 10, 10);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: AddDelegateSubscriptionSection(isFree: true, showSubmit: true),
        ),
      ),
    );
    await shot(tester, 'add_delegate_before');
  });

  testWidgets('add_delegate_after', (tester) async {
    await prepare(tester);
    await tester.binding.setSurfaceSize(const Size(390, 900));
    final theme = await promoTestTheme();
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2027, 2, 10, 10);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: const SingleChildScrollView(
          padding: EdgeInsets.all(16),
          child: AddDelegateSubscriptionSection(
            isFree: false,
            showSubmit: true,
          ),
        ),
      ),
    );
    await shot(tester, 'add_delegate_after');
  });

  testWidgets('subscription_requests_before', (tester) async {
    await prepare(tester);
    final theme = await promoTestTheme();
    final req = _request(
      method: SubscriptionPaymentMethod.freePromotion,
      paymentStatus: SubscriptionPaymentStatus.waived,
      fee: 0,
      name: 'محمد علي',
    );
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: SubscriptionRequestPaymentCard(
            request: req,
            role: UserRole.superAdmin,
          ),
        ),
      ),
    );
    await shot(tester, 'subscription_requests_before');
  });

  testWidgets('subscription_requests_after', (tester) async {
    await prepare(tester);
    final theme = await promoTestTheme();
    final pending = _request(
      method: SubscriptionPaymentMethod.paymob,
      paymentStatus: SubscriptionPaymentStatus.pending,
      organizationName: 'DEV منظمة تجريبية',
      companyName: 'DEV شركة تجريبية',
    );
    final archival = _request(
      method: SubscriptionPaymentMethod.freePromotion,
      paymentStatus: SubscriptionPaymentStatus.waived,
      fee: 0,
      name: 'سجل قديم',
    );
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Column(
            children: [
              SubscriptionRequestPaymentCard(
                request: pending,
                role: UserRole.superAdmin,
              ),
              const SizedBox(height: 12),
              SubscriptionRequestPaymentCard(
                request: archival,
                role: UserRole.superAdmin,
              ),
            ],
          ),
        ),
      ),
    );
    await shot(tester, 'subscription_requests_after');
  });

  testWidgets('subscription_renewal_before', (tester) async {
    await prepare(tester);
    final theme = await promoTestTheme();
    final db = await renewal.seed();
    final clock = () => renewal.nov2026;
    final repo = SubscriptionRenewalRepository(firestore: db, clock: clock);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: SubscriptionRenewalScreen(
          supervisor: renewal.supervisor(),
          repository: repo,
          paymentGateway: _FakeGateway(),
          clock: clock,
        ),
        wrapScaffold: false,
      ),
    );
    await tester.pumpAndSettle();
    await shot(tester, 'subscription_renewal_before');
  });

  testWidgets('subscription_renewal_after', (tester) async {
    await prepare(tester);
    final theme = await promoTestTheme();
    final db = await renewal.seed();
    final clock = () => renewal.feb2027;
    final repo = SubscriptionRenewalRepository(firestore: db, clock: clock);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: SubscriptionRenewalScreen(
          supervisor: renewal.supervisor(),
          repository: repo,
          paymentGateway: _FakeGateway(),
          clock: clock,
        ),
        wrapScaffold: false,
      ),
    );
    await tester.pumpAndSettle();
    await tester.tap(find.byKey(const Key('renewal_select_all')));
    await tester.pumpAndSettle();
    await shot(tester, 'subscription_renewal_after');
  });
}
