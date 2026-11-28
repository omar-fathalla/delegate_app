// TAS-366: «مرتبي» shows the same expected net as the HR payroll screen for
// the same data, labelled as an estimate. Fake data only.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/design/money.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:delegate_app/features/wallet/presentation/pages/delegate_my_salary_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_monthly_payroll_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

import '../../../hr/domain/services/payroll_fixtures.dart';

final _d1 = fakePayrollDelegate();
final _hr = fakePayrollDelegate(uid: 'seed-fake-hr', fullName: 'مشرف تجريبي', role: UserRole.hr);

class _FakeGetCompanyDelegates implements GetCompanyDelegates {
  @override
  AdminRepository get repository => throw UnimplementedError();

  @override
  Future<Either<Failure, CompanyDelegatesResult>> call(GetCompanyDelegatesParams params) async =>
      Right(CompanyDelegatesResult(delegates: [_d1]));
}

/// Data in the current month (relative to the real clock, as the HR screen
/// has no test clock): a 6h day on the 1st, an annual leave, penalties.
Future<FakeFirebaseFirestore> _seed({Map<String, dynamic>? wallet}) async {
  final fs = FakeFirebaseFirestore();
  final now = DateTime.now();
  final first = DateTime(now.year, now.month, 1, 0, 10);
  await fs.collection('company_payroll_configs').doc(kFakePayrollCompany).set({
    'calculationMode': 'monthly_with_deductions',
    'defaultDailyShiftHours': 8.0,
    'defaultMonthlyBaseSalary': 4200.0,
    'defaultMonthlyWorkingDays': 26,
  });
  await fs.collection('user_wallets').doc(_d1.uid).set(
        wallet ?? {'companyUID': kFakePayrollCompany, 'baseSalary': 5000},
      );
  await fs.collection('attendance_logs').add(checkIn(_d1.uid, first));
  await fs.collection('attendance_logs').add(checkOut(_d1.uid, first.add(const Duration(hours: 6))));
  await fs.collection('leave_requests').add({
    'delegateUid': _d1.uid, 'companyUID': kFakePayrollCompany, 'status': 'approved',
    'type': 'annual', 'daysCount': 1, 'startDate': Timestamp.fromDate(first),
  });
  await fs.collection('penalties').add({
    'targetDelegateId': _d1.uid, 'companyId': kFakePayrollCompany, 'status': 'ISSUED',
    'fineAmount': 120, 'createdAt': Timestamp.fromDate(first),
  });
  await fs.collection('penalties').add({
    'targetDelegateId': _d1.uid, 'companyId': kFakePayrollCompany, 'status': 'approved',
    'fineAmount': 30, 'createdAt': Timestamp.fromDate(first),
  });
  // Another company's penalty for the same id: never on «مرتبي».
  await fs.collection('penalties').add({
    'targetDelegateId': _d1.uid, 'companyId': 'other-co', 'status': 'ISSUED',
    'fineAmount': 999, 'createdAt': Timestamp.fromDate(first),
  });
  return fs;
}

Widget _app(Widget home) => MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(const Color(0xFF6750A4)),
      locale: const Locale('ar'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    );

String _text(WidgetTester t, Finder f) => t.widget<Text>(f).data ?? '';

/// `‎1,234.56 ج.م` / `1,235 ج.م` -> 1234.56 / 1235.
double _amount(String s) => double.parse(RegExp(r'-?[\d,]+(\.\d+)?').firstMatch(s)!.group(0)!.replaceAll(',', ''));

void main() {
  setUp(() {
    MissingCheckOutRule.debugReset();
    sl.allowReassignment = true;
    sl.registerLazySingleton<GetCompanyDelegates>(() => _FakeGetCompanyDelegates());
    WebRuntimePolicy.debugReset();
  });
  tearDown(() {
    DelegateMySalaryScreen.debugFirestore = null;
    DelegateMySalaryScreen.debugNow = null;
    HRMonthlyPayrollScreen.debugFirestore = null;
    WebRuntimePolicy.debugReset();
    MissingCheckOutRule.debugReset();
  });

  testWidgets('shows both months, the estimate notes and the expected net', (t) async {
    final fs = await _seed();
    DelegateMySalaryScreen.debugFirestore = () => fs;
    await t.pumpWidget(_app(DelegateMySalaryScreen(delegate: _d1)));
    await t.pumpAndSettle();

    expect(find.text('مرتبي'), findsOneWidget);
    expect(find.byKey(const Key('my_salary_current')), findsOneWidget);
    expect(find.byKey(const Key('my_salary_previous')), findsOneWidget);
    expect(find.text(kSalaryEstimateNote), findsNWidgets(2));
    expect(
      find.descendant(of: find.byKey(const Key('my_salary_previous')), matching: find.text(kPreviousMonthNote)),
      findsOneWidget,
    );
    expect(
      find.descendant(of: find.byKey(const Key('my_salary_current')), matching: find.text(kPreviousMonthNote)),
      findsNothing,
    );
    // ISSUED 120 + legacy approved 30; the other company's 999 is not shown.
    final penalties = find.descendant(
      of: find.byKey(const Key('my_salary_current')),
      matching: find.byKey(const Key('my_salary_penalties')),
    );
    expect(_text(t, penalties), contains(Money.formatEgp(150)));
  });

  testWidgets('a read error shows the retry state, not a zero salary', (t) async {
    DelegateMySalaryScreen.debugFirestore = () => throw FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied');
    await t.pumpWidget(_app(DelegateMySalaryScreen(delegate: _d1)));
    await t.pumpAndSettle();
    expect(find.text('فيه مشكلة عندنا'), findsOneWidget);
    expect(find.text('جرّب تاني'), findsOneWidget);
    expect(find.byKey(const Key('my_salary_net')), findsNothing);
  });

  testWidgets('forgotten session: shown as waiting for HR (message 3.17)', (t) async {
    final fs = await _seed();
    final now = DateTime.now();
    MissingCheckOutRule.debugSet(DateTime(now.year, now.month - 1, 1));
    await fs.collection('attendance_logs').add(
          checkIn(_d1.uid, DateTime(now.year, now.month - 1, 3, 8), extra: {'missingCheckOut': true}),
        );
    DelegateMySalaryScreen.debugFirestore = () => fs;
    await t.pumpWidget(_app(DelegateMySalaryScreen(delegate: _d1)));
    await t.pumpAndSettle();
    expect(
      find.descendant(of: find.byKey(const Key('my_salary_previous')), matching: find.byKey(const Key('my_salary_forgotten'))),
      findsOneWidget,
    );
  });

  for (final mode in ['monthly_with_deductions', 'hourly_rate']) {
    testWidgets('same net as the HR payroll screen ($mode)', (t) async {
      final wallet = {
        'companyUID': kFakePayrollCompany,
        'monthlyAllocation': 5200,
        'payrollCalculationMode': mode,
      };
      final fs = await _seed(wallet: wallet);

      // HR (web layout, one delegate: the net card is this delegate's net).
      t.view.physicalSize = const Size(1440, 900);
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      WebRuntimePolicy.debugIsWebOverride = true;
      HRMonthlyPayrollScreen.debugFirestore = () => fs;
      await t.pumpWidget(_app(HRMonthlyPayrollScreen(hrDelegate: _hr, showAppBar: false)));
      await t.pumpAndSettle();
      final hrNetText = t
          .widgetList<Text>(find.descendant(
            of: find.byKey(const Key('payroll_summary_net')),
            matching: find.byType(Text),
          ))
          .last
          .data!;
      final hrNet = _amount(hrNetText);

      // Delegate.
      WebRuntimePolicy.debugReset();
      t.view.physicalSize = const Size(400, 900);
      DelegateMySalaryScreen.debugFirestore = () => fs;
      await t.pumpWidget(_app(DelegateMySalaryScreen(delegate: _d1)));
      await t.pumpAndSettle();
      final net = _amount(_text(
        t,
        find.descendant(of: find.byKey(const Key('my_salary_current')), matching: find.byKey(const Key('my_salary_net'))),
      ));

      expect(net, greaterThan(0));
      // HR web rounds to whole pounds.
      expect(net.round(), hrNet.round(), reason: 'HR "$hrNetText" vs «مرتبي» $net');
    });
  }
}
