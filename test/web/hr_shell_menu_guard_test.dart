// Web HR shell: every supervisor-menu tool is in the sidebar and the compact
// menu, and opens the existing screen. /hr/home and /hr/delegate-attendance
// only admit company supervisors and HR. Mobile lists stay as they were.
import 'package:delegate_app/config/routes/app_router.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/features/admin/presentation/pages/subscription_renewal_screen.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/splash_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_access_gate.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_attendance_adjustments_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_device_unbind_requests_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_monthly_payroll_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_delegates_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_more_bottom_sheet.dart';
import 'package:delegate_app/features/penalties/presentation/pages/penalty_rules_catalog_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/features/tracking/presentation/pages/delegate_tracking_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/web_hr_system_redirect_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

const _supervisorMenu = [
  'الرئيسية',
  'الملف الشخصي',
  'طلبات الاشتراك',
  'تجديد المناديب',
  'سجل الحضور والانصراف',
  'مناديب الشركة',
  'Live Tracking',
  'الصور',
  'أذونات التصوير',
  'تعديلات الحضور',
  'طلبات الإجازات',
  'الرواتب',
  'تدقيق الأمان',
  'فك الأجهزة',
  'المهام',
  'لائحة الغرامات',
  'نظام الغرامات',
  'الإعدادات',
];

const _webOnlyTitles = [
  'الرئيسية',
  'طلبات اشتراك واعتماد المناديب',
  'المهام',
  'أذونات التصوير',
  'لائحة الغرامات والجزاءات',
  'نظام الغرامات والمخالفات',
];

Delegate _delegate(UserRole role, {String companyUID = 'seed-fake-co-alpha'}) =>
    Delegate(
      uid: 'seed-fake-${role.name}',
      firstName: 'مشرف',
      middleName: '',
      lastName: 'وهمي',
      fullName: 'مشرف وهمي',
      nationalityID: '__firebase_auth__:fake@example.com',
      motherName: '',
      city: '',
      phoneNumber: '01000000099',
      gender: DelegateGender.male,
      position: DelegatePosition.supervisor,
      birthDate: DateTime(1990),
      organizationUID: 'seed-fake-hr-org',
      organizationName: 'Fake Test Organization',
      companyUID: companyUID,
      companyName: companyUID.isEmpty ? '' : 'Fake Company Alpha',
      status: DelegateStatus.approved,
      delegatePublicId: '',
      allReceiptCodes: const [],
      createdAt: DateTime(2026),
      createdBy: 'system_admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: role,
      email: 'fake@example.com',
    );

List<String> _titles(Delegate delegate, HrShellPlacement placement) =>
    hrShellItems(
      delegate: delegate,
      isWeb: true,
      placement: placement,
    ).map((item) => item.menuLabel(isWeb: true)).toList();

void main() {
  setUpAll(() {
    registerFallbackValue(AuthInitial());
  });

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
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    WebHrSystemRedirect.debugHrSystemBuilder = null;
  });

  group('web menu', () {
    for (final role in [UserRole.admin, UserRole.hr]) {
      test('$role compact menu lists every supervisor tool once', () {
        final titles = _titles(_delegate(role), HrShellPlacement.compactMenu);
        expect(titles.toSet(), titles.toList().toSet());
        expect(titles, _supervisorMenu);
        expect(titles.last, 'الإعدادات');
        expect(titles[titles.length - 2], 'نظام الغرامات');
      });

      test('$role sidebar lists the same tools except the footer settings', () {
        final titles = _titles(_delegate(role), HrShellPlacement.sidebar);
        expect(
          titles,
          _supervisorMenu.where(
            (title) => title != 'الإعدادات' && title != 'الملف الشخصي',
          ),
        );
        expect(titles, isNot(contains('الملف الشخصي')));
      });
    }

    test('an account without a company does not get تجديد المناديب', () {
      final titles = _titles(
        _delegate(UserRole.admin, companyUID: ''),
        HrShellPlacement.compactMenu,
      );
      expect(titles, isNot(contains('تجديد المناديب')));
      expect(titles, contains('نظام الغرامات'));
      expect(titles.last, 'الإعدادات');
    });

    test('mobile catalog hides the tools the phone menu does not have', () {
      final titles = hrShellItems(
        delegate: _delegate(UserRole.hr),
        isWeb: false,
        placement: HrShellPlacement.compactMenu,
      ).map((item) => item.title);
      for (final title in _webOnlyTitles) {
        expect(titles, isNot(contains(title)));
      }
      expect(titles, contains('مناديب الشركة'));
      expect(titles, contains('سجل الحضور والانصراف'));
    });

    test(
      'each new tool builds the screen the supervisor menu already opens',
      () {
        final delegate = _delegate(UserRole.admin);
        Widget tab(int index) => hrShellTab(
          index: index,
          delegate: delegate,
          onNavigateToTab: (_) {},
        );

        expect(tab(kHrTabAttendance), isA<HRAttendanceTab>());
        expect(tab(kHrTabTracking), isA<DelegateTrackingScreen>());
        expect(tab(kHrTabDevices), isA<HRDeviceUnbindRequestsScreen>());
        expect(tab(kHrTabLeaves), isA<HRLeavesAndExcusesScreen>());
        expect(tab(kHrTabPayroll), isA<HRMonthlyPayrollScreen>());
        expect(tab(kHrTabDelegates), isA<HRDelegatesTab>());
        expect(tab(kHrTabPhotos), isA<HRPhotosTab>());
        expect(tab(kHrTabAdjustments), isA<HRAttendanceAdjustmentsScreen>());
        expect(
          tab(kHrTabSubscriptions),
          isA<DelegateSubscriptionRequestsPage>(),
        );
        expect(tab(kHrTabRenewal), isA<SubscriptionRenewalScreen>());
        expect(tab(kHrTabTasks), isA<AdminTasksScreen>());
        expect(tab(kHrTabPenaltyCatalog), isA<PenaltyRulesCatalogPage>());

        expect(tab(kHrTabPhotoPermissions), isA<HrSupervisorPermissionsHost>());
        expect(
          (tab(kHrTabPhotoPermissions) as HrSupervisorPermissionsHost)
              .supervisor,
          delegate,
        );
        expect(tab(kHrTabPenalties), isA<HrPenaltiesHost>());
        expect((tab(kHrTabPenalties) as HrPenaltiesHost).admin, delegate);
      },
    );
  });

  group('sidebar and compact sheet', () {
    Future<void> pumpSidebar(
      WidgetTester tester,
      Delegate delegate, {
      required bool web,
      required ValueChanged<int> onSelect,
    }) async {
      WebRuntimePolicy.debugIsWebOverride = web;
      tester.view.physicalSize = const Size(900, 2200);
      tester.view.devicePixelRatio = 1;
      addTearDown(tester.view.resetPhysicalSize);
      addTearDown(tester.view.resetDevicePixelRatio);
      await tester.pumpWidget(
        MaterialApp(
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Scaffold(
            body: HRDesktopSidebar(
              delegate: delegate,
              selectedIndex: 0,
              onItemSelected: onSelect,
              isExpanded: true,
              onToggleExpanded: () {},
              onOpenSettings: () {},
              onOpenProfile: () {},
            ),
          ),
        ),
      );
    }

    testWidgets('web sidebar shows every tool and selects its tab', (
      tester,
    ) async {
      int? selected;
      await pumpSidebar(
        tester,
        _delegate(UserRole.admin),
        web: true,
        onSelect: (index) => selected = index,
      );
      for (final title in _supervisorMenu.where(
        (t) => t != 'الإعدادات' && t != 'الملف الشخصي',
      )) {
        expect(find.text(title), findsWidgets, reason: title);
      }
      expect(find.text('الملف الشخصي'), findsNothing);
      expect(find.text('الإعدادات'), findsOneWidget);
      expect(find.byType(AppAvatar), findsNothing);
      expect(find.text('الحضور والانصراف'), findsNothing);
      await tester.tap(find.text('المهام'));
      expect(selected, kHrTabTasks);
      await tester.tap(find.text('أذونات التصوير'));
      expect(selected, kHrTabPhotoPermissions);
      await tester.tap(find.text('نظام الغرامات'));
      expect(selected, kHrTabPenalties);
    });

    testWidgets('mobile sidebar keeps its own labels and hides the new tools', (
      tester,
    ) async {
      await pumpSidebar(
        tester,
        _delegate(UserRole.hr),
        web: false,
        onSelect: (_) {},
      );
      expect(find.text('الحضور والانصراف'), findsOneWidget);
      expect(find.text('مناديب الشركة'), findsOneWidget);
      for (final title in _webOnlyTitles) {
        expect(find.text(title), findsNothing, reason: title);
      }
    });

    testWidgets(
      'web more sheet lists the tools that are not in the bottom bar',
      (tester) async {
        WebRuntimePolicy.debugIsWebOverride = true;
        tester.view.physicalSize = const Size(400, 1600);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.resetPhysicalSize);
        addTearDown(tester.view.resetDevicePixelRatio);
        await tester.pumpWidget(
          MaterialApp(
            home: Scaffold(
              body: HRMoreBottomSheet(
                hrDelegate: _delegate(UserRole.hr),
                currentIndex: 0,
                onSelectTab: (_) {},
              ),
            ),
          ),
        );
        expect(find.text('المهام'), findsOneWidget);
        expect(find.text('أذونات التصوير'), findsOneWidget);
        expect(find.text('لائحة الغرامات'), findsOneWidget);
        expect(find.text('نظام الغرامات'), findsOneWidget);
        expect(find.text('طلبات الاشتراك'), findsOneWidget);
        expect(find.text('سجل الحضور والانصراف'), findsOneWidget);
        expect(find.text('الرئيسية'), findsNothing);
      },
    );

    testWidgets('mobile more sheet stays the original five tools', (
      tester,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = false;
      await tester.pumpWidget(
        MaterialApp(
          home: Scaffold(
            body: HRMoreBottomSheet(
              hrDelegate: _delegate(UserRole.hr),
              currentIndex: 0,
              onSelectTab: (_) {},
            ),
          ),
        ),
      );
      expect(find.text('مسير الرواتب والعمولات'), findsOneWidget);
      expect(find.text('المهام'), findsNothing);
      expect(find.text('نظام الغرامات والمخالفات'), findsNothing);
    });
  });

  group('role guard', () {
    test('only supervisors and HR may stay; web delegates get the notice', () {
      for (final role in UserRole.values) {
        final web = hrShellDeniedLocation(role, isWeb: true);
        final mobile = hrShellDeniedLocation(role, isWeb: false);
        if (role == UserRole.admin || role == UserRole.hr) {
          expect(web, isNull, reason: role.name);
          expect(mobile, isNull, reason: role.name);
        } else if (role == UserRole.delegate) {
          expect(web, '/login?notice=delegate');
          expect(mobile, '/home');
        } else {
          expect(web, homePathForRole(role), reason: role.name);
          expect(mobile, homePathForRole(role), reason: role.name);
        }
      }
    });

    testWidgets('web delegate opening /hr/home sees the blocked notice', (
      tester,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      sl<SharedPreferences>().setString(
        kLoginModePrefKey,
        LoginMode.staff.name,
      );
      final bloc = _MockAuthBloc();
      when(() => bloc.state).thenReturn(AuthInitial());
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
      when(() => bloc.close()).thenAnswer((_) async {});
      final router = GoRouter(
        initialLocation: '/hr/home',
        initialExtra: _delegate(UserRole.delegate),
        routes: appRouter.configuration.routes,
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(
        BlocProvider<AuthBloc>.value(
          value: bloc,
          child: MaterialApp.router(
            routerConfig: router,
            locale: const Locale('ar'),
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
          ),
        ),
      );
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/login');
      expect(
        router.routeInformationProvider.value.uri.queryParameters['notice'],
        'delegate',
      );
      expect(
        find.byKey(const ValueKey('login_web_delegate_notice')),
        findsOneWidget,
      );
    });

    testWidgets('a marketing user is sent to the marketing home', (
      tester,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      final router = GoRouter(
        initialLocation: '/hr/home',
        initialExtra: _delegate(UserRole.marketing),
        routes: [
          GoRoute(
            path: '/hr/home',
            builder: (_, state) =>
                HrShellAccessGate(actor: state.extra! as Delegate),
          ),
          GoRoute(
            path: '/marketing/home',
            builder: (_, _) => const Text('marketing-home'),
          ),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/marketing/home');
      expect(find.text('marketing-home'), findsOneWidget);
    });

    testWidgets('mobile delegate is sent home, not to the web notice', (
      tester,
    ) async {
      WebRuntimePolicy.debugIsWebOverride = false;
      final router = GoRouter(
        initialLocation: '/hr/home',
        initialExtra: _delegate(UserRole.delegate),
        routes: [
          GoRoute(
            path: '/hr/home',
            builder: (_, state) =>
                HrShellAccessGate(actor: state.extra! as Delegate),
          ),
          GoRoute(
            path: '/home',
            builder: (_, _) => const Text('delegate-home'),
          ),
          GoRoute(path: '/login', builder: (_, _) => const Text('login')),
        ],
      );
      addTearDown(router.dispose);
      await tester.pumpWidget(MaterialApp.router(routerConfig: router));
      await tester.pumpAndSettle();
      expect(router.routeInformationProvider.value.uri.path, '/home');
      expect(find.text('delegate-home'), findsOneWidget);
      expect(find.text('login'), findsNothing);
    });

    testWidgets(
      'attendance detail follows the signed-in role, not the subject',
      (tester) async {
        final bloc = _MockAuthBloc();
        when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
        when(() => bloc.close()).thenAnswer((_) async {});
        final subject = _delegate(UserRole.delegate);

        when(() => bloc.state).thenReturn(AuthInitial());
        late Widget unsigned;
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: bloc,
            child: Builder(
              builder: (context) {
                unsigned = hrAttendanceDetailRouteChild(context, subject);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(unsigned, isA<SplashScreen>());

        when(() => bloc.state).thenReturn(
          AuthAuthenticated(delegate: _delegate(UserRole.marketing)),
        );
        late Widget denied;
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: bloc,
            child: Builder(
              builder: (context) {
                denied = hrAttendanceDetailRouteChild(context, subject);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(denied, isA<HrShellAccessGate>());

        when(
          () => bloc.state,
        ).thenReturn(AuthAuthenticated(delegate: _delegate(UserRole.hr)));
        late Widget allowed;
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: bloc,
            child: Builder(
              builder: (context) {
                allowed = hrAttendanceDetailRouteChild(context, subject);
                return const SizedBox();
              },
            ),
          ),
        );
        expect(allowed, isA<HRDelegateAttendanceDetailScreen>());
        final screen = allowed as HRDelegateAttendanceDetailScreen;
        expect(screen.delegate.role, UserRole.delegate);
        expect(screen.hrDelegate!.role, UserRole.hr);
      },
    );

    testWidgets('supervisor and HR stay on /hr/home', (tester) async {
      WebRuntimePolicy.debugIsWebOverride = true;
      WebHrSystemRedirect.debugHrSystemBuilder = (delegate) =>
          Text('kept ${delegate.role.name}');
      final bloc = _MockAuthBloc();
      when(() => bloc.state).thenReturn(AuthInitial());
      when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
      when(() => bloc.close()).thenAnswer((_) async {});
      for (final role in [UserRole.admin, UserRole.hr]) {
        final router = GoRouter(
          initialLocation: '/hr/home',
          initialExtra: _delegate(role),
          routes: appRouter.configuration.routes,
        );
        addTearDown(router.dispose);
        await tester.pumpWidget(
          BlocProvider<AuthBloc>.value(
            value: bloc,
            child: MaterialApp.router(
              routerConfig: router,
              locale: const Locale('ar'),
              localizationsDelegates: AppLocalizations.localizationsDelegates,
              supportedLocales: AppLocalizations.supportedLocales,
            ),
          ),
        );
        await tester.pumpAndSettle();
        expect(router.routeInformationProvider.value.uri.path, '/hr/home');
        expect(find.text('kept ${role.name}'), findsOneWidget);
      }
    });
  });
}
