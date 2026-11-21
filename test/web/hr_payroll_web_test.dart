// HR web «الرواتب» on M3 (TAS-119), fake data only.
// Web gets the toolbar, four summary cards and the shared HR table; mobile
// keeps the original layout.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_monthly_payroll_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

const _co = 'seed-fake-co';

Delegate _person({
  required String uid,
  required String fullName,
  String phone = '',
  UserRole role = UserRole.delegate,
  DelegatePosition position = DelegatePosition.promoter,
}) => Delegate(
  uid: uid,
  firstName: fullName.split(' ').first,
  middleName: '',
  lastName: '',
  fullName: fullName,
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: phone,
  gender: DelegateGender.male,
  position: position,
  birthDate: DateTime(1995),
  organizationUID: 'o-fake',
  organizationName: 'سلسلة تجريبية',
  companyUID: _co,
  companyName: 'شركة ألفا التجريبية',
  status: DelegateStatus.active,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'test',
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

final _hr = _person(
  uid: 'seed-fake-hr',
  fullName: 'مشرف تجريبي',
  phone: '01000000000',
  role: UserRole.hr,
  position: DelegatePosition.supervisor,
);

// fake-d1: monthly mode with a penalty, so deductions > 0.
// fake-d2: hourly mode with no penalty, so deductions are 0.
final _delegates = [
  _person(uid: 'fake-d1', fullName: 'أحمد سمير حسن', phone: '01000000001'),
  _person(uid: 'fake-d2', fullName: 'منى خالد إبراهيم', phone: '01000000002'),
];

class _FakeGetCompanyDelegates implements GetCompanyDelegates {
  @override
  AdminRepository get repository => throw UnimplementedError();

  @override
  Future<Either<Failure, CompanyDelegatesResult>> call(
    GetCompanyDelegatesParams params,
  ) async => Right(CompanyDelegatesResult(delegates: _delegates));
}

Future<FakeFirebaseFirestore> _seed() async {
  final fs = FakeFirebaseFirestore();
  await fs.collection('user_wallets').doc('fake-d1').set({
    'companyUID': _co,
    'baseSalary': 5000,
    'payrollCalculationMode': 'monthly_with_deductions',
  });
  await fs.collection('user_wallets').doc('fake-d2').set({
    'companyUID': _co,
    'baseSalary': 4000,
    'payrollCalculationMode': 'hourly_rate',
  });
  await fs.collection('penalties').add({
    'companyId': _co,
    'targetDelegateId': 'fake-d1',
    'status': 'approved',
    'fineAmount': 200,
    'createdAt': Timestamp.fromDate(DateTime.now()),
  });
  return fs;
}

Future<void> _pump(WidgetTester t) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final theme = AppTheme.lightTheme(const Color(0xFF6750A4));
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: theme,
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: HRMonthlyPayrollScreen(hrDelegate: _hr, showAppBar: false),
      ),
    ),
  );
  await t.pumpAndSettle();
}

String _textIn(WidgetTester t, Finder scope) => t
    .widgetList<Text>(find.descendant(of: scope, matching: find.byType(Text)))
    .map((w) => w.data ?? '')
    .join(' | ');

void main() {
  late FakeFirebaseFirestore fs;

  setUp(() async {
    sl.allowReassignment = true;
    sl.registerLazySingleton<GetCompanyDelegates>(
      () => _FakeGetCompanyDelegates(),
    );
    fs = await _seed();
    HRMonthlyPayrollScreen.debugFirestore = () => fs;
    WebRuntimePolicy.debugReset();
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HRMonthlyPayrollScreen.debugFirestore = null;
  });

  group('web', () {
    setUp(() => WebRuntimePolicy.debugIsWebOverride = true);

    testWidgets('toolbar has month chip, search, rules and export', (t) async {
      await _pump(t);
      expect(find.byKey(const Key('payroll_web_body')), findsOneWidget);
      expect(find.byKey(const Key('payroll_web_month_chip')), findsOneWidget);
      expect(find.text('بحث باسم المندوب أو رقم الهاتف'), findsOneWidget);
      expect(
        find.descendant(
          of: find.byKey(const Key('payroll_web_rules')),
          matching: find.text('قواعد الرواتب'),
        ),
        findsOneWidget,
      );
      // Export is the primary FilledButton.
      expect(
        find.ancestor(
          of: find.text('تصدير Excel'),
          matching: find.byWidgetPredicate((w) => w is FilledButton),
        ),
        findsOneWidget,
      );
      // The old mobile KPI row is gone on web.
      expect(find.text('إجمالي الرواتب'), findsNothing);
    });

    testWidgets('four summary cards with headlineSmall tabular values', (
      t,
    ) async {
      await _pump(t);
      final ctx = t.element(find.byKey(const Key('payroll_web_body')));
      final scheme = Theme.of(ctx).colorScheme;
      final status = HrStatusColors.of(ctx);

      const cards = {
        'payroll_summary_count': 'عدد المناديب',
        'payroll_summary_gross': 'إجمالي الاستحقاق',
        'payroll_summary_deductions': 'إجمالي الخصومات',
        'payroll_summary_net': 'صافي الصرف',
      };
      for (final e in cards.entries) {
        final card = find.byKey(Key(e.key));
        expect(card, findsOneWidget, reason: e.key);
        expect(
          find.descendant(of: card, matching: find.text(e.value)),
          findsOneWidget,
        );
      }

      // Count card: two delegates.
      final count = find.descendant(
        of: find.byKey(const Key('payroll_summary_count')),
        matching: find.text('2'),
      );
      final countStyle = t.widget<Text>(count).style!;
      expect(
        countStyle.fontSize,
        Theme.of(ctx).textTheme.headlineSmall!.fontSize,
      );
      expect(
        countStyle.fontFeatures,
        contains(const FontFeature.tabularFigures()),
      );

      // Deductions value is red (there is a penalty).
      final deductions = t
          .widgetList<Text>(
            find.descendant(
              of: find.byKey(const Key('payroll_summary_deductions')),
              matching: find.byType(Text),
            ),
          )
          .last;
      expect(deductions.data, startsWith('-'));
      expect(deductions.style!.color, scheme.error);

      // Net card sits on the success container.
      final netCard = find.descendant(
        of: find.byKey(const Key('payroll_summary_net')),
        matching: find.byType(Container),
      );
      final colors = t
          .widgetList<Container>(netCard)
          .map((c) => (c.decoration as BoxDecoration?)?.color)
          .toList();
      expect(colors, contains(status.successContainer));
    });

    testWidgets('shared table with the agreed header columns', (t) async {
      await _pump(t);
      expect(find.byType(HrTableCard), findsOneWidget);
      expect(find.byType(HrTableHeader), findsOneWidget);
      for (final title in const [
        'المندوب',
        'الحضور',
        'الإجازات',
        'الغياب',
        'الأساسي',
        'الاستحقاق',
        'الخصومات',
        'الصافي',
      ]) {
        expect(find.byKey(Key('payroll_col_$title')), findsOneWidget,
            reason: title);
      }
      expect(find.byType(HrTableRow), findsNWidgets(2));
      // Name sub-line carries the role and the phone.
      final row = find.byKey(const Key('payroll_row_fake-d1'));
      final text = _textIn(t, row);
      expect(text, contains('أحمد سمير حسن'));
      expect(text, contains('مندوب / مروج'));
      expect(text, contains('01000000001'));
    });

    testWidgets('net is a success-container pill', (t) async {
      await _pump(t);
      final ctx = t.element(find.byKey(const Key('payroll_web_body')));
      final status = HrStatusColors.of(ctx);
      final pill = t.widget<Container>(
        find.byKey(const Key('payroll_net_fake-d1')),
      );
      expect((pill.decoration! as BoxDecoration).color,
          status.successContainer);
      final label = t.widget<Text>(
        find.descendant(
          of: find.byKey(const Key('payroll_net_fake-d1')),
          matching: find.byType(Text),
        ),
      );
      expect(label.style!.color, status.onSuccessContainer);
      expect(label.style!.fontFeatures,
          contains(const FontFeature.tabularFigures()));
      expect(label.data, endsWith('ج.م'));
    });

    testWidgets('deductions are red only when greater than 0', (t) async {
      await _pump(t);
      final ctx = t.element(find.byKey(const Key('payroll_web_body')));
      final scheme = Theme.of(ctx).colorScheme;

      final withPenalty = t.widget<Text>(
        find.byKey(const Key('payroll_deductions_fake-d1')),
      );
      expect(withPenalty.data, startsWith('-'));
      expect(withPenalty.style!.color, scheme.error);

      final none = t.widget<Text>(
        find.byKey(const Key('payroll_deductions_fake-d2')),
      );
      expect(none.data, '0 ج.م');
      expect(none.style!.color, isNot(scheme.error));
      expect(none.style!.color, scheme.onSurfaceVariant);
    });

    testWidgets('«⋮» menu offers edit salary and details', (t) async {
      await _pump(t);
      await t.tap(find.byKey(const Key('payroll_actions_fake-d1')));
      await t.pumpAndSettle();
      expect(find.text('تعديل الراتب'), findsOneWidget);
      expect(find.text('عرض التفاصيل'), findsOneWidget);
      await t.tap(find.text('عرض التفاصيل'));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('tapping a row opens the delegate details', (t) async {
      await _pump(t);
      await t.tap(find.text('منى خالد إبراهيم'));
      await t.pumpAndSettle();
      expect(find.byType(Dialog), findsOneWidget);
    });

    testWidgets('table scrolls sideways on a narrow window', (t) async {
      t.view.physicalSize = const Size(700, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final theme = AppTheme.lightTheme(const Color(0xFF6750A4));
      await t.pumpWidget(
        MaterialApp(
          theme: theme,
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: HRMonthlyPayrollScreen(hrDelegate: _hr, showAppBar: false),
          ),
        ),
      );
      await t.pumpAndSettle();
      expect(t.takeException(), isNull);
      expect(
        find.descendant(
          of: find.byType(HrTableCard),
          matching: find.byWidgetPredicate(
            (w) =>
                w is SingleChildScrollView &&
                w.scrollDirection == Axis.horizontal,
          ),
        ),
        findsOneWidget,
      );
    });
  });

  testWidgets('mobile keeps the original layout', (t) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await _pump(t);
    expect(find.byKey(const Key('payroll_web_body')), findsNothing);
    expect(find.byType(HrTableCard), findsNothing);
    expect(find.text('إجمالي الرواتب'), findsOneWidget);
    expect(find.text('صافي المستحق للصرف'), findsOneWidget);
    expect(find.text('صافي الصرف'), findsOneWidget); // old table header
    expect(find.text('عدد المناديب'), findsNothing);
  });
}
