import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/presentation/widgets/add_delegate_subscription_section.dart';
import 'package:delegate_app/features/admin/presentation/widgets/company_exclusive_card_intro.dart';
import 'package:delegate_app/features/admin/presentation/widgets/subscription_request_status_widgets.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import '../../../support/promo_screenshot_harness.dart';

DelegateSubscriptionRequest _request({
  required SubscriptionPaymentMethod method,
  SubscriptionPaymentStatus paymentStatus = SubscriptionPaymentStatus.pending,
  SubscriptionRequestStatus status = SubscriptionRequestStatus.pending,
  String name = 'أحمد محمود',
  double fee = 500,
  int months = 6,
}) {
  return DelegateSubscriptionRequest(
    id: 'r1',
    supervisorUid: 's1',
    supervisorName: 'مشرف',
    supervisorPhone: '01000000000',
    companyUID: 'c1',
    companyName: 'شركة التجربة',
    organizationUID: 'o1',
    organizationName: 'لولو',
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
    subscriptionCycle: '2027_H1',
    cycleStartDate: DateTime(2027, 1, 1),
    cycleEndDate: DateTime(2027, 6, 30),
    fee: fee,
    remainingMonths: months,
    status: status,
    createdAt: DateTime(2027, 1, 2),
    paymentStatus: paymentStatus,
  );
}

void main() {
  TestWidgetsFlutterBinding.ensureInitialized();
  setUp(SubscriptionCycleHelper.resetConfigForTest);
  tearDown(SubscriptionCycleHelper.resetConfigForTest);

  testWidgets('Paymob request uses a method chip and a separate amount chip', (tester) async {
    final theme = await promoTestTheme();
    final req = _request(
      method: SubscriptionPaymentMethod.paymob,
      paymentStatus: SubscriptionPaymentStatus.pending,
    );
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: SubscriptionRequestPaymentCard(
          request: req,
          role: UserRole.superAdmin,
        ),
      ),
    );
    expect(find.text('دفع إلكتروني عبر Paymob'), findsOneWidget);
    expect(find.textContaining('500 ج.م (6 أشهر)'), findsOneWidget);
    expect(find.text('بانتظار الدفع الإلكتروني'), findsOneWidget);
    expect(find.text('إيصال إلكتروني'), findsNothing);
    expect(find.text('اعتماد وتفعيل'), findsNothing);
    expect(
      find.text('بانتظار الدفع الإلكتروني. لا يمكن الاعتماد قبل تأكيد الدفع.'),
      findsOneWidget,
    );
    // Paymob and the amount must not share one string.
    final paymobTexts = tester.widgetList<Text>(find.byType(Text)).where((t) {
      final v = t.data ?? '';
      return v.contains('Paymob') && (v.contains('ج.م') || v.contains('500'));
    });
    expect(paymobTexts, isEmpty);
  });

  testWidgets('paid Paymob request shows approve for staff', (tester) async {
    final theme = await promoTestTheme();
    final req = _request(
      method: SubscriptionPaymentMethod.paymob,
      paymentStatus: SubscriptionPaymentStatus.paid,
    );
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: SubscriptionRequestPaymentCard(
          request: req,
          role: UserRole.superAdmin,
        ),
      ),
    );
    expect(find.text('مدفوع — بانتظار الاعتماد'), findsOneWidget);
    expect(find.text('اعتماد وتفعيل'), findsOneWidget);
  });

  testWidgets('historical free-promotion chip is archival, not a live green offer', (tester) async {
    final theme = await promoTestTheme();
    final req = _request(
      method: SubscriptionPaymentMethod.freePromotion,
      paymentStatus: SubscriptionPaymentStatus.waived,
      fee: 0,
    );
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: SubscriptionRequestPaymentCard(
          request: req,
          role: UserRole.superAdmin,
        ),
      ),
    );
    expect(find.text('مجاني (سجل 2026)'), findsWidgets);
    expect(find.text('عرض مجاني (0 ج.م)'), findsNothing);
    final chips = tester.widgetList<Container>(find.byType(Container));
    const liveGreen = Color(0xFF16A34A);
    const liveBg = Color(0xFFDCFCE7);
    final live = chips.where((c) {
      final d = c.decoration;
      if (d is! BoxDecoration) return false;
      return d.color == liveGreen || d.color == liveBg;
    });
    expect(live, isEmpty);
  });

  testWidgets('add-delegate after expiry shows Paymob and a short cycle title', (tester) async {
    final theme = await promoTestTheme();
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2027, 2, 10, 10);
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: const AddDelegateSubscriptionSection(isFree: false),
      ),
    );
    expect(find.text('الدفع إلكترونيًا عبر Paymob'), findsOneWidget);
    expect(find.textContaining('حتى نهاية النصف الأول 2027'), findsOneWidget);
    expect(find.textContaining('دورة النصف الأول (2027) •'), findsOneWidget); // banner only
    expect(find.text('إرسال طلب التسجيل'), findsOneWidget);
    expect(find.text('إرسال طلب التسجيل (مجاناً)'), findsNothing);
    final send = tester.widget<Icon>(find.byWidgetPredicate((w) =>
        w is Icon && w.icon?.codePoint == 0xe163));
    expect(send.icon?.matchTextDirection, isTrue);
    expect(tester.getSize(find.byType(FilledButton)).height, greaterThanOrEqualTo(48));
  });

  testWidgets('admin home intro hides the free badge after expiry', (tester) async {
    final theme = await promoTestTheme();
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: const CompanyExclusiveCardIntro(isArabic: true, isFreePromotion: false),
      ),
    );
    expect(find.text('مجاناً حتى 31/12'), findsNothing);
    expect(find.text('ميزة حصرية للشركات'), findsOneWidget);
    expect(find.textContaining('مجاناً بالكامل حتى 31/12'), findsNothing);
  });

  testWidgets('admin home intro keeps the free badge while the promo is live', (tester) async {
    final theme = await promoTestTheme();
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: const CompanyExclusiveCardIntro(isArabic: true, isFreePromotion: true),
      ),
    );
    expect(find.text('مجاناً حتى 31/12'), findsOneWidget);
  });

  testWidgets('F9: staff do not see approve on a pending Paymob renewal', (tester) async {
    final theme = await promoTestTheme();
    final req = _request(
      method: SubscriptionPaymentMethod.paymob,
      paymentStatus: SubscriptionPaymentStatus.pending,
      name: 'تجديد جماعي',
    );
    // _request defaults to new_delegate; copy with renewal type via constructor fields.
    final renewal = DelegateSubscriptionRequest(
      id: req.id,
      supervisorUid: req.supervisorUid,
      supervisorName: req.supervisorName,
      supervisorPhone: req.supervisorPhone,
      companyUID: req.companyUID,
      companyName: req.companyName,
      organizationUID: req.organizationUID,
      organizationName: req.organizationName,
      firstName: req.firstName,
      secondName: req.secondName,
      thirdName: req.thirdName,
      fullName: req.fullName,
      phoneNumber: req.phoneNumber,
      nationalId: req.nationalId,
      profileImageUrl: '',
      nationalIdFrontUrl: '',
      nationalIdBackUrl: '',
      paymentMethod: SubscriptionPaymentMethod.paymob,
      subscriptionCycle: '2027_H1',
      cycleStartDate: DateTime(2027, 1, 1),
      cycleEndDate: DateTime(2027, 6, 30),
      fee: 500,
      remainingMonths: 5,
      status: SubscriptionRequestStatus.pending,
      requestType: kRequestTypeRenewal,
      createdAt: DateTime(2027, 2, 1),
      paymentStatus: SubscriptionPaymentStatus.pending,
    );
    await tester.pumpWidget(
      promoTestApp(
        theme: theme,
        child: SubscriptionRequestPaymentCard(
          request: renewal,
          role: UserRole.superAdmin,
        ),
      ),
    );
    expect(find.text('اعتماد وتفعيل'), findsNothing);
    expect(find.text('رفض الطلب'), findsOneWidget);
    expect(find.textContaining('بانتظار الدفع الإلكتروني'), findsWidgets);
  });
}
