// TAS-139: every web HR shell page has its own URL (`/hr/<slug>`). The
// sidebar writes the URL, a URL (deep link, reload, browser back) selects the
// tab on the same mounted shell, inner pages add `?inner=<n>`, unknown slugs
// fall back to `/hr/home`. Mobile keeps `/hr/home` only. Fake data only.
// TAS-189: narrow web counts its full-screen inner pages in the URL too.
// TAS-190: the delegate attendance detail has its own address,
// `/hr/<tab>/delegate/<id>`.
import 'dart:async';

import 'package:delegate_app/config/routes/app_router.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/hr_shell_link.dart';
import 'package:firebase_core/firebase_core.dart';
// Transitive test helper of firebase_core (fake Firebase app, no network).
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:go_router/go_router.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

const _slugs = <int, String>{
  kHrTabOverview: '/hr/home',
  kHrTabAttendance: '/hr/attendance',
  kHrTabDelegates: '/hr/delegates',
  kHrTabTracking: '/hr/tracking',
  kHrTabPhotos: '/hr/photos',
  kHrTabAdjustments: '/hr/attendance/edits',
  kHrTabLeaves: '/hr/leaves',
  kHrTabPayroll: '/hr/payroll',
  kHrTabFraud: '/hr/security',
  kHrTabDevices: '/hr/devices',
  kHrTabTasks: '/hr/tasks',
  kHrTabPenaltyCatalog: '/hr/penalties/rules',
  kHrTabPenalties: '/hr/penalties',
  kHrTabSubscriptions: '/hr/subscriptions',
  kHrTabRenewal: '/hr/renewal',
};

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

/// Stand-in tab body with its own state (a tap counter) and a button that
/// opens an inner page.
class _StubTab extends StatefulWidget {
  const _StubTab(this.index);
  final int index;

  @override
  State<_StubTab> createState() => _StubTabState();
}

class _StubTabState extends State<_StubTab> {
  int taps = 0;

  @override
  Widget build(BuildContext context) => Column(
    children: [
      Text('tab ${widget.index} taps $taps'),
      TextButton(
        key: ValueKey('tap_${widget.index}'),
        onPressed: () => setState(() => taps++),
        child: const Text('tap'),
      ),
      TextButton(
        key: ValueKey('inner_${widget.index}'),
        onPressed: () => pushHrInnerPage<void>(
          context,
          title: 'صفحة داخلية',
          builder: (_, _) => const Text('inner body'),
        ),
        child: const Text('open inner'),
      ),
      TextButton(
        key: ValueKey('detail_${widget.index}'),
        onPressed: () => _pushFakeDetail(context, 'seed-fake-delegate-1'),
        child: const Text('open detail'),
      ),
      TextButton(
        key: ValueKey('profile_${widget.index}'),
        onPressed: () =>
            HrAccountPages.openProfile(context, _delegate(UserRole.admin)),
        child: const Text('open profile'),
      ),
    ],
  );
}

/// Stand-in for the delegate attendance detail page (TAS-190): an inner
/// page with the same address as the real one.
Future<void> _pushFakeDetail(BuildContext context, String delegateId) =>
    pushHrInnerPage<void>(
      context,
      title: 'مندوب وهمي',
      urlPath: hrDelegateDetailUrlPath(delegateId),
      builder: (_, _) => Text('detail $delegateId'),
    );

/// Delegate ids the shell opened from a URL.
final List<String> _openedFromUrl = [];

Future<void> _fakeOpenDetail(
  BuildContext context, {
  required String delegateId,
  required Delegate hrDelegate,
  bool Function()? shouldOpen,
}) async {
  _openedFromUrl.add(delegateId);
  if (!(shouldOpen?.call() ?? true)) return;
  await _pushFakeDetail(context, delegateId);
}

/// The shell's badge streams talk to Firestore directly; the fake backend
/// never answers (the same as an offline first load).
void _silenceFirestore() {
  const api =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  for (final method in const [
    'querySnapshot',
    'queryGet',
    'aggregateQuery',
    'documentReferenceSnapshot',
    'documentReferenceGet',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          '$api.$method',
          (_) => Completer<ByteData?>().future,
        );
  }
}

void main() {
  late _MockAuthBloc bloc;

  setUpAll(() async {
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    _silenceFirestore();
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
    bloc = _MockAuthBloc();
    when(
      () => bloc.state,
    ).thenReturn(AuthAuthenticated(delegate: _delegate(UserRole.admin)));
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => bloc.close()).thenAnswer((_) async {});
    HRMainScreen.debugTabBuilder = (index) => _StubTab(index);
    HRMainScreen.debugOpenDelegateDetail = _fakeOpenDetail;
    HrAccountPages.debugProfileBuilder = (_, _) => const Text('profile body');
    _openedFromUrl.clear();
    WebRuntimePolicy.debugIsWebOverride = true;
  });

  tearDown(() {
    HRMainScreen.debugTabBuilder = null;
    HRMainScreen.debugOpenDelegateDetail = null;
    HrAccountPages.debugProfileBuilder = null;
    HrShellLink.debugReset();
    WebRuntimePolicy.debugReset();
  });

  group('slug table', () {
    test('each sidebar tab maps to its slug and back', () {
      for (final entry in _slugs.entries) {
        expect(hrShellPathForTab(entry.key), entry.value, reason: entry.value);
        expect(hrShellTabForPath(entry.value), entry.key, reason: entry.value);
      }
      expect(hrShellRoutePaths().toSet(), _slugs.values.toSet());
      expect(hrShellRoutePaths().first, kWebHrSystemPath);
      // Every tab of the catalog has a URL.
      for (final item in kHrShellCatalog) {
        if (item.tabIndex != null) {
          expect(item.webSlug, isNotNull, reason: item.id);
        }
      }
    });

    test('the retired permissions slot uses the «الصور» URL', () {
      expect(hrShellPathForTab(kHrTabPhotoPermissions), '/hr/photos');
    });

    test('unknown paths are not shell pages', () {
      for (final path in [
        '/hr/nope',
        '/hr/login',
        '/hr/delegate-attendance',
        '/hr/',
        '/admin/home',
        '/hr/attendance/edits/x',
      ]) {
        expect(hrShellTabForPath(path), isNull, reason: path);
      }
    });

    test('inner pages are a query count, never a name', () {
      expect(hrShellLocation(kHrTabAttendance), '/hr/attendance');
      expect(
        hrShellLocation(kHrTabAttendance, inner: 2),
        '/hr/attendance?inner=2',
      );
      expect(hrShellInnerDepth(Uri.parse('/hr/payroll?inner=1')), 1);
      expect(hrShellInnerDepth(Uri.parse('/hr/payroll?inner=-3')), 0);
      expect(hrShellInnerDepth(Uri.parse('/hr/payroll?inner=x')), 0);
      expect(hrShellInnerDepth(Uri.parse('/hr/payroll')), 0);
    });

    test('TAS-190: the delegate detail address carries the id only', () {
      const id = 'seed-fake-delegate-1';
      final url = hrDelegateDetailUrlPath(id);
      expect(url, 'delegate/$id');
      expect(hrDelegateIdFromUrlPath(url), id);
      expect(hrDelegateIdFromUrlPath('delegate/'), isNull);
      expect(hrDelegateIdFromUrlPath('delegate/a/b'), isNull);
      expect(hrDelegateIdFromUrlPath('other/x'), isNull);
      expect(hrDelegateIdFromUrlPath(null), isNull);

      expect(
        hrShellLocation(kHrTabAttendance, inner: 1, innerUrl: url),
        '/hr/attendance/delegate/$id',
      );
      expect(
        hrShellLocation(kHrTabDelegates, inner: 2, innerUrl: url),
        '/hr/delegates/delegate/$id?inner=1',
      );
      // No page open: the address is not written.
      expect(
        hrShellLocation(kHrTabAttendance, innerUrl: url),
        '/hr/attendance',
      );

      final path = '/hr/attendance/delegate/$id';
      expect(hrShellTabForPath(path), kHrTabAttendance);
      expect(
        hrShellTabForPath('/hr/attendance/edits/delegate/$id'),
        kHrTabAdjustments,
      );
      expect(hrShellInnerUrlForPath(path), url);
      expect(hrShellInnerDepth(Uri.parse(path)), 1);
      expect(hrShellInnerDepth(Uri.parse('$path?inner=1')), 2);
      for (final bad in [
        '/hr/attendance/delegate/',
        '/hr/nope/delegate/$id',
        '/hr/attendance/delegate/$id/x',
      ]) {
        expect(hrShellInnerUrlForPath(bad), isNull, reason: bad);
      }
      expect(hrShellTabForPath('/hr/nope/delegate/$id'), isNull);
      // A reload keeps the detail address.
      expect(
        hrShellRestoreLocation(kWebHrSystemPath, Uri.parse('$path?inner=1')),
        path,
      );
      expect(
        hrShellDelegateDetailRoutePaths(),
        contains('/hr/attendance/delegate/:delegateId'),
      );
    });

    test('a web reload of a shell URL stays on it after the splash', () {
      expect(
        hrShellRestoreLocation(
          kWebHrSystemPath,
          Uri.parse('/hr/payroll?inner=1'),
        ),
        '/hr/payroll',
      );
      expect(
        hrShellRestoreLocation(kWebHrSystemPath, Uri.parse('/')),
        kWebHrSystemPath,
      );
      expect(
        hrShellRestoreLocation(kWebHrSystemPath, Uri.parse('/hr/nope')),
        kWebHrSystemPath,
      );
      // Another role keeps its own home.
      expect(
        hrShellRestoreLocation('/marketing/home', Uri.parse('/hr/payroll')),
        '/marketing/home',
      );
      WebRuntimePolicy.debugIsWebOverride = false;
      expect(
        hrShellRestoreLocation(kWebHrSystemPath, Uri.parse('/hr/payroll')),
        kWebHrSystemPath,
      );
    });
  });

  group('router (production routes)', () {
    Future<GoRouter> pumpShell(
      WidgetTester t, {
      String initial = '/hr/home',
      Delegate? actor,
      Size size = const Size(1440, 1000),
    }) async {
      t.view.physicalSize = size;
      t.view.devicePixelRatio = 1;
      addTearDown(t.view.resetPhysicalSize);
      addTearDown(t.view.resetDevicePixelRatio);
      final router = GoRouter(
        initialLocation: initial,
        initialExtra: actor ?? _delegate(UserRole.admin),
        routes: appRouter.configuration.routes,
      );
      addTearDown(router.dispose);
      await t.pumpWidget(
        MultiBlocProvider(
          providers: [
            BlocProvider<AuthBloc>.value(value: bloc),
            BlocProvider<ThemeCubit>.value(value: sl<ThemeCubit>()),
          ],
          child: MaterialApp.router(
            routerConfig: router,
            localizationsDelegates: AppLocalizations.localizationsDelegates,
            supportedLocales: AppLocalizations.supportedLocales,
            locale: const Locale('ar'),
          ),
        ),
      );
      await settle(t);
      return router;
    }

    String location(GoRouter r) =>
        r.routerDelegate.currentConfiguration.uri.toString();

    int shownTab(WidgetTester t) => t
        .widget<IndexedStack>(
          find.descendant(
            of: find.byType(HRMainScreen, skipOffstage: false),
            matching: find.byType(IndexedStack, skipOffstage: false),
            skipOffstage: false,
          ),
        )
        .index!;

    Finder sidebarItem(String label) => find.descendant(
      of: find.byType(HRDesktopSidebar),
      matching: find.text(label),
    );

    testWidgets('/hr/payroll opens the payroll tab', (t) async {
      final r = await pumpShell(t, initial: '/hr/payroll');
      expect(location(r), '/hr/payroll');
      expect(shownTab(t), kHrTabPayroll);
      expect(
        t.widget<HRDesktopSidebar>(find.byType(HRDesktopSidebar)).selectedIndex,
        kHrTabPayroll,
      );
    });

    for (final entry in _slugs.entries) {
      testWidgets('${entry.value} opens tab ${entry.key}', (t) async {
        final r = await pumpShell(t, initial: entry.value);
        expect(location(r), entry.value);
        expect(shownTab(t), entry.key);
      });
    }

    testWidgets('a sidebar tap writes the URL', (t) async {
      final r = await pumpShell(t);
      expect(location(r), '/hr/home');
      expect(shownTab(t), kHrTabOverview);

      await t.tap(sidebarItem('الرواتب'));
      await settle(t);
      expect(location(r), '/hr/payroll');
      expect(shownTab(t), kHrTabPayroll);

      await t.tap(sidebarItem('تعديلات الحضور'));
      await settle(t);
      expect(location(r), '/hr/attendance/edits');

      await t.tap(sidebarItem('الرئيسية'));
      await settle(t);
      expect(location(r), '/hr/home');
    });

    testWidgets('HrShellLink.selectTab and selectMenu write the URL', (
      t,
    ) async {
      final r = await pumpShell(t);
      HrShellLink.selectTab(kHrTabLeaves);
      await settle(t);
      expect(location(r), '/hr/leaves');
      HrShellLink.selectMenu('tasks');
      await settle(t);
      expect(location(r), '/hr/tasks');
      expect(shownTab(t), kHrTabTasks);
    });

    testWidgets('an unknown slug falls back to /hr/home', (t) async {
      for (final path in ['/hr/nope', '/hr/attendance/nope']) {
        final r = await pumpShell(t, initial: path);
        expect(location(r), '/hr/home', reason: path);
        expect(shownTab(t), kHrTabOverview, reason: path);
      }
    });

    testWidgets('renewal without the permission falls back to /hr/home', (
      t,
    ) async {
      final r = await pumpShell(
        t,
        initial: '/hr/renewal',
        actor: _delegate(UserRole.admin, companyUID: ''),
      );
      expect(location(r), '/hr/home');
      expect(shownTab(t), kHrTabOverview);
    });

    testWidgets(
      'browser back (URL without extra) keeps one shell and its tab state',
      (t) async {
        final r = await pumpShell(t);
        final shell = t.state(find.byType(HRMainScreen));

        await t.tap(find.byKey(const ValueKey('tap_$kHrTabOverview')));
        await t.tap(find.byKey(const ValueKey('tap_$kHrTabOverview')));
        await t.pump();
        expect(find.text('tab $kHrTabOverview taps 2'), findsOneWidget);

        await t.tap(sidebarItem('الرواتب'));
        await settle(t);
        await t.tap(find.byKey(const ValueKey('tap_$kHrTabPayroll')));
        await t.pump();
        expect(location(r), '/hr/payroll');

        // The browser back/forward buttons drop `extra`; the session is used.
        r.go('/hr/home');
        await settle(t);
        expect(location(r), '/hr/home');
        expect(shownTab(t), kHrTabOverview);
        expect(t.state(find.byType(HRMainScreen)), same(shell));
        expect(
          find.text('tab $kHrTabOverview taps 2', skipOffstage: false),
          findsOneWidget,
        );

        r.go('/hr/payroll');
        await settle(t);
        expect(shownTab(t), kHrTabPayroll);
        expect(t.state(find.byType(HRMainScreen)), same(shell));
        expect(
          find.text('tab $kHrTabPayroll taps 1', skipOffstage: false),
          findsOneWidget,
        );
      },
    );

    testWidgets('inner pages add ?inner=1 and the browser back closes them', (
      t,
    ) async {
      final r = await pumpShell(t, initial: '/hr/attendance');
      await t.tap(find.byKey(const ValueKey('inner_$kHrTabAttendance')));
      await settle(t);
      expect(find.text('inner body'), findsOneWidget);
      expect(location(r), '/hr/attendance?inner=1');

      // Browser back.
      r.go('/hr/attendance');
      await settle(t);
      expect(find.text('inner body'), findsNothing);
      expect(shownTab(t), kHrTabAttendance);

      // The in-app back button takes the URL back too.
      await t.tap(find.byKey(const ValueKey('inner_$kHrTabAttendance')));
      await settle(t);
      expect(location(r), '/hr/attendance?inner=1');
      await t.tap(find.byKey(const ValueKey('hr_inner_page_back')));
      await settle(t);
      expect(find.text('inner body'), findsNothing);
      expect(location(r), '/hr/attendance');

      // A sidebar tap leaves the inner page for the new tab's URL.
      await t.tap(find.byKey(const ValueKey('inner_$kHrTabAttendance')));
      await settle(t);
      await t.tap(sidebarItem('الرواتب'));
      await settle(t);
      expect(find.text('inner body'), findsNothing);
      expect(location(r), '/hr/payroll');
    });

    testWidgets('a URL with ?inner= but no open page shows the tab', (t) async {
      final r = await pumpShell(t, initial: '/hr/leaves?inner=2');
      expect(shownTab(t), kHrTabLeaves);
      expect(find.byKey(const ValueKey('hr_inner_page_back')), findsNothing);
      expect(location(r), '/hr/leaves?inner=2');
    });

    testWidgets('narrow web bottom bar writes the URL too', (t) async {
      final r = await pumpShell(t, size: const Size(412, 900));
      await t.tap(find.text('المناديب'));
      await settle(t);
      expect(location(r), '/hr/delegates');
      expect(shownTab(t), kHrTabDelegates);
    });

    group('TAS-189: narrow web inner pages', () {
      const narrow = Size(412, 900);

      testWidgets('a full-screen inner page adds ?inner=1; back closes it', (
        t,
      ) async {
        final r = await pumpShell(t, initial: '/hr/home', size: narrow);
        expect(find.byType(HRDesktopSidebar), findsNothing);

        await t.tap(find.byKey(const ValueKey('inner_$kHrTabOverview')));
        await settleLong(t);
        expect(find.text('inner body'), findsOneWidget);
        // Full screen: no breadcrumb, the bottom bar is covered.
        expect(find.byKey(const ValueKey('hr_inner_page_back')), findsNothing);
        expect(location(r), '/hr/home?inner=1');

        // Browser back.
        r.go('/hr/home');
        await settleLong(t);
        expect(find.text('inner body'), findsNothing);
        expect(shownTab(t), kHrTabOverview);
        expect(location(r), '/hr/home');

        // The page's own back (app bar arrow) takes the URL back too.
        await t.tap(find.byKey(const ValueKey('inner_$kHrTabOverview')));
        await settleLong(t);
        expect(location(r), '/hr/home?inner=1');
        Navigator.of(t.element(find.text('inner body'))).pop();
        await settleLong(t);
        expect(find.text('inner body'), findsNothing);
        expect(location(r), '/hr/home');
      });

      testWidgets('two pages count 2 and the browser back closes one', (
        t,
      ) async {
        final r = await pumpShell(t, initial: '/hr/home', size: narrow);
        await t.tap(find.byKey(const ValueKey('inner_$kHrTabOverview')));
        await settleLong(t);
        final tab = t.element(
          find.byKey(
            const ValueKey('inner_$kHrTabOverview'),
            skipOffstage: false,
          ),
        );
        pushHrInnerPage<void>(
          tab,
          title: 'ثانية',
          builder: (_, _) => const Text('second body'),
        );
        await settleLong(t);
        expect(location(r), '/hr/home?inner=2');

        r.go('/hr/home?inner=1');
        await settleLong(t);
        expect(find.text('second body'), findsNothing);
        expect(find.text('inner body'), findsOneWidget);

        r.go('/hr/home');
        await settleLong(t);
        expect(find.text('inner body'), findsNothing);
        expect(find.byType(HRMainScreen), findsOneWidget);
      });

      testWidgets('account pages (profile) are counted too', (t) async {
        final r = await pumpShell(t, initial: '/hr/home', size: narrow);
        await t.tap(find.byKey(const ValueKey('profile_$kHrTabOverview')));
        await settleLong(t);
        expect(find.text('profile body'), findsOneWidget);
        expect(location(r), '/hr/home?inner=1');

        r.go('/hr/home');
        await settleLong(t);
        expect(find.text('profile body'), findsNothing);
      });

      testWidgets('mobile keeps the plain push and /hr/home', (t) async {
        WebRuntimePolicy.debugIsWebOverride = false;
        final r = await pumpShell(t, size: narrow);
        await t.tap(find.byKey(const ValueKey('inner_$kHrTabAttendance')));
        await settleLong(t);
        expect(find.text('inner body'), findsOneWidget);
        expect(location(r), '/hr/home');
        final route = ModalRoute.of(t.element(find.text('inner body')))!;
        expect(route.settings.name, isNull);
      });
    });

    group('TAS-190: delegate detail address', () {
      const path = '/hr/attendance/delegate/seed-fake-delegate-1';

      testWidgets('opening the detail writes its address; back closes it', (
        t,
      ) async {
        final r = await pumpShell(t, initial: '/hr/attendance');
        await t.tap(find.byKey(const ValueKey('detail_$kHrTabAttendance')));
        await settle(t);
        expect(find.text('detail seed-fake-delegate-1'), findsOneWidget);
        expect(location(r), path);
        expect(_openedFromUrl, isEmpty);

        // Browser back, then forward: the page opens again from the URL.
        r.go('/hr/attendance');
        await settle(t);
        expect(find.text('detail seed-fake-delegate-1'), findsNothing);
        r.go(path);
        await settle(t);
        expect(_openedFromUrl, ['seed-fake-delegate-1']);
        expect(find.text('detail seed-fake-delegate-1'), findsOneWidget);
        expect(location(r), path);

        // In-app back.
        await t.tap(find.byKey(const ValueKey('hr_inner_page_back')));
        await settle(t);
        expect(location(r), '/hr/attendance');
      });

      testWidgets('a direct visit opens the tab and the detail', (t) async {
        final r = await pumpShell(t, initial: path);
        expect(shownTab(t), kHrTabAttendance);
        expect(_openedFromUrl, ['seed-fake-delegate-1']);
        expect(find.text('detail seed-fake-delegate-1'), findsOneWidget);
        expect(location(r), path);
      });

      testWidgets('the address keeps the tab it was opened from', (t) async {
        final r = await pumpShell(t, initial: '/hr/delegates');
        await t.tap(find.byKey(const ValueKey('detail_$kHrTabDelegates')));
        await settle(t);
        expect(location(r), '/hr/delegates/delegate/seed-fake-delegate-1');
        expect(shownTab(t), kHrTabDelegates);
      });

      testWidgets('TAS-199: narrowing the window forgets the detail address', (
        t,
      ) async {
        final r = await pumpShell(t, initial: path);
        expect(find.text('detail seed-fake-delegate-1'), findsOneWidget);
        expect(location(r), path);

        // Wide to narrow drops the inner navigator and the detail page.
        t.view.physicalSize = const Size(412, 900);
        await settleLong(t);
        expect(location(r), '/hr/attendance');

        // The next inner page must not carry the old delegate id.
        r.go('/hr/delegates');
        await settleLong(t);
        await t.tap(find.byKey(const ValueKey('inner_$kHrTabDelegates')));
        await settleLong(t);
        expect(find.text('inner body'), findsOneWidget);
        expect(location(r), '/hr/delegates?inner=1');
      });

      testWidgets('narrow web: a direct visit opens it full screen', (t) async {
        final r = await pumpShell(t, initial: path, size: const Size(412, 900));
        expect(find.text('detail seed-fake-delegate-1'), findsOneWidget);
        expect(location(r), path);
        r.go('/hr/attendance');
        await settleLong(t);
        expect(find.text('detail seed-fake-delegate-1'), findsNothing);
        expect(shownTab(t), kHrTabAttendance);
      });
    });

    testWidgets('mobile stays on /hr/home while switching tabs', (t) async {
      WebRuntimePolicy.debugIsWebOverride = false;
      final r = await pumpShell(t, size: const Size(412, 900));
      expect(location(r), '/hr/home');
      expect(shownTab(t), kHrTabAttendance);
      final shell = t.widget<HRMainScreen>(find.byType(HRMainScreen));
      expect(shell.routeTab, isNull);

      await t.tap(find.text('المناديب'));
      await settle(t);
      expect(shownTab(t), kHrTabDelegates);
      expect(location(r), '/hr/home');

      await t.tap(find.text('الخريطة'));
      await settle(t);
      expect(shownTab(t), kHrTabTracking);
      expect(location(r), '/hr/home');
    });
  });
}

/// pumpAndSettle can hang on spinners; a few fixed frames are enough here.
Future<void> settle(WidgetTester t) async {
  for (var i = 0; i < 6; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

/// Full-screen routes (narrow web) take longer to leave than inner pages.
Future<void> settleLong(WidgetTester t) async {
  for (var i = 0; i < 15; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}
