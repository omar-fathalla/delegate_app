// TAS-140: «إضافة مندوب» from the HR home opens inside the web shell as an
// inner page (breadcrumb, no own sidebar or header), and the free offer is
// announced once, in the summary column. Fake data only.
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_delegate_form_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/add_delegate_subscription_section.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/hr_shell_link.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

Delegate _supervisor() => Delegate(
  uid: 'seed-fake-supervisor',
  firstName: 'مشرف',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مشرف تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-org',
  organizationName: 'Fake Org',
  companyUID: 'seed-fake-co',
  companyName: 'شركة ألفا التجريبية',
  status: DelegateStatus.approved,
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
  role: UserRole.admin,
);

Future<List<Map<String, dynamic>>> _loader() async => [
  {'uid': 'fake-org-0', 'name': 'زهران ماركت'},
  {'uid': 'fake-org-1', 'name': 'Fake Test Organization'},
];

const _openKey = ValueKey('test_open_add_delegate');

/// The home page's «إضافة مندوب» button, wired like the real overview.
Widget _homeButton() => Builder(
  builder: (context) => Center(
    child: FilledButton(
      key: _openKey,
      onPressed: () => openAdminHomeAddDelegate(
        context,
        _supervisor(),
        debugOrganizationsLoader: _loader,
      ),
      child: const Text('إضافة مندوب'),
    ),
  ),
);

/// Stand-in for the wide web shell: a 260 side rail and a content area with
/// a nested navigator published through [HrInnerPageHost].
Widget _fakeShell(GlobalKey<NavigatorState> inner) => Row(
  children: [
    const SizedBox(width: 260, key: ValueKey('fake_shell_sidebar')),
    Expanded(
      child: HrInnerPageHost(
        navigatorKey: inner,
        parentTitle: 'الرئيسية',
        child: Navigator(
          key: inner,
          pages: [MaterialPage<void>(child: Scaffold(body: _homeButton()))],
          onDidRemovePage: (_) {},
        ),
      ),
    ),
  ],
);

Future<void> _pump(WidgetTester t, Widget home) async {
  t.view.physicalSize = const Size(1440, 900);
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  await t.pumpWidget(
    MaterialApp(
      debugShowCheckedModeBanner: false,
      theme: AppTheme.lightTheme(const Color(0xFF6750A4)),
      locale: const Locale('ar'),
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Directionality(textDirection: TextDirection.rtl, child: home),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _open(WidgetTester t) async {
  await t.tap(find.byKey(_openKey));
  await t.pumpAndSettle();
}

void main() {
  setUp(() async {
    sl.allowReassignment = true;
    SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
    final prefs = await SharedPreferences.getInstance();
    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      localeProvider = sl<LocaleProvider>();
    }
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
    WebRuntimePolicy.debugReset();
    // Inside the free offer (it ends 31/12/2026).
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2026, 11, 21, 9);
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HrShellLink.debugReset();
    SubscriptionCycleHelper.nowOverride = null;
  });

  testWidgets('web 1440: opens inside the shell with a breadcrumb', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final inner = GlobalKey<NavigatorState>();
    await _pump(t, _fakeShell(inner));
    await _open(t);

    // The shell stays; the page sits in the content area.
    expect(find.byKey(const ValueKey('fake_shell_sidebar')), findsOneWidget);
    expect(find.byType(HrInnerPage), findsOneWidget);
    expect(find.byKey(const ValueKey('hr_inner_page_breadcrumb')), findsOneWidget);
    expect(
      t.widget<Text>(find.byKey(const ValueKey('hr_inner_page_title'))).data,
      'إضافة مندوب',
    );
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('hr_inner_page_parent')),
        matching: find.text('الرئيسية'),
      ),
      findsOneWidget,
    );
    final form = t.widget<AddDelegateFormScreen>(
      find.byType(AddDelegateFormScreen),
    );
    expect(form.inShell, isTrue);

    // No second sidebar, header, back button or app bar of its own.
    expect(find.byType(HRDesktopSidebar), findsNothing);
    expect(find.byKey(const ValueKey('add_delegate_back')), findsNothing);
    expect(find.text('إضافة مندوب لمنظمة جديدة'), findsNothing);
    expect(find.byType(AppBar), findsNothing);

    // Two columns in the 1180 content area.
    expect(find.byKey(const ValueKey('add_delegate_summary')), findsOneWidget);
    expect(t.takeException(), isNull);

    // Back returns to the home page in the same shell.
    await t.tap(find.byKey(const ValueKey('hr_inner_page_back')));
    await t.pumpAndSettle();
    expect(find.byType(AddDelegateFormScreen), findsNothing);
    expect(find.byKey(_openKey), findsOneWidget);
  });

  testWidgets('free offer is announced once, in the summary column', (
    t,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final inner = GlobalKey<NavigatorState>();
    await _pump(t, _fakeShell(inner));
    await _open(t);

    expect(find.byType(AddDelegateCycleBanner), findsOneWidget);
    expect(
      find.descendant(
        of: find.byKey(const ValueKey('add_delegate_summary_scroll')),
        matching: find.byType(AddDelegateCycleBanner),
      ),
      findsOneWidget,
    );
    expect(find.byType(AddDelegateFreePromotionCard), findsNothing);
    expect(find.text('عرض ترويجي مجاني ممتد لنهاية العام'), findsOneWidget);
    expect(
      find.byKey(const ValueKey('add_delegate_payment_section')),
      findsNothing,
    );
  });

  testWidgets('after the offer the paid plan keeps its own section', (t) async {
    SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2027, 2, 1, 9);
    WebRuntimePolicy.debugIsWebOverride = true;
    final inner = GlobalKey<NavigatorState>();
    await _pump(t, _fakeShell(inner));
    await _open(t);

    expect(
      find.byKey(const ValueKey('add_delegate_payment_section')),
      findsOneWidget,
    );
    expect(find.byType(AddDelegatePaymobCard), findsOneWidget);
    expect(find.byType(AddDelegateFreePromotionCard), findsNothing);
  });

  testWidgets('mobile: still a full-screen page with its own app bar', (
    t,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await _pump(t, Scaffold(body: _homeButton()));
    await _open(t);

    expect(find.byType(HrInnerPage), findsNothing);
    final form = t.widget<AddDelegateFormScreen>(
      find.byType(AddDelegateFormScreen),
    );
    expect(form.inShell, isFalse);
    expect(find.byType(AppBar), findsOneWidget);
    expect(find.text('إضافة مندوب لمنظمة جديدة'), findsOneWidget);
    // Mobile keeps its promotion card under the form.
    expect(find.byType(AddDelegateFreePromotionCard), findsOneWidget);
  });
}
