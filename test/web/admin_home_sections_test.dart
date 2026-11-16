import 'dart:io';
// Mobile home (unchanged order) + web-only desktop home grid, with fake data.
import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_state.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_home_web.dart';
import 'package:firebase_core/firebase_core.dart';
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'web_golden.dart';

class _MockBloc extends MockBloc<AdminDashboardEvent, AdminDashboardState>
    implements AdminDashboardBloc {}

class _MockRepo extends Mock implements DelegateSubscriptionRepository {}

final sup = Delegate(
  uid: 'test_sup', firstName: 'مشرف', middleName: '', lastName: 'تجريبي',
  fullName: 'مشرف تجريبي', nationalityID: '', motherName: '', city: 'Cairo',
  phoneNumber: '', gender: DelegateGender.male,
  position: DelegatePosition.supervisor, birthDate: DateTime(1990),
  organizationUID: 'org', organizationName: 'فتح الله ماركت', companyUID: '',
  companyName: 'energizer', status: DelegateStatus.active,
  delegatePublicId: 'X', allReceiptCodes: const [], createdAt: DateTime(2024),
  createdBy: 't', hasPendingUpdate: false, isDeductedFromCompany: false,
  isPrinted: false, isProfileComplete: true, numberOfDocuments: 0,
  paymentAmount: 0, version: 1, documents: const [], role: UserRole.admin
);

const _orgs = ['فتح الله ماركت', 'جملة ماركت', 'كارفور', 'زهران ماركت', 'سبينس'];

Future<void> _fonts() async {
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'));
  await cairo.load();
  final mi = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await mi.load();
  final sym = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'));
  await sym.load();
}

late _MockBloc bloc;

Widget _app(Widget home, {bool dark = false}) {
  final t = dark ? AppTheme.darkTheme() : AppTheme.lightTheme();
  return MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: t.copyWith(textTheme: t.textTheme.apply(fontFamily: 'Cairo')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ar'),
    home: Scaffold(body: home),
  );
}

void _size(WidgetTester t, Size s) {
  t.view.physicalSize = s;
  t.view.devicePixelRatio = 1;
}

void main() {
  setUpAll(() async {
    await _fonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    // Silence firebase_auth listener registration (no native side in tests).
    for (final m in ['registerIdTokenListener', 'registerAuthStateListener']) {
      TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
          .setMockMessageHandler(
        'dev.flutter.pigeon.firebase_auth_platform_interface.FirebaseAuthHostApi.$m',
        (_) async => const StandardMessageCodec().encodeMessage(<Object?>['noop']),
      );
    }
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMethodCallHandler(const MethodChannel('noop'), (_) async => null);
    SharedPreferences.setMockInitialValues({'supervisor_orgs_energizer': _orgs});
    final prefs = await SharedPreferences.getInstance();
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerSingleton<LocaleProvider>(LocaleProvider(prefs));
    }
    final repo = _MockRepo();
    when(() => repo.getSubscriptionRequestsStream(
          statusFilter: any(named: 'statusFilter'),
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
        )).thenAnswer((_) => Stream.value(<DelegateSubscriptionRequest>[]));
    if (!sl.isRegistered<DelegateSubscriptionRepository>()) {
      sl.registerSingleton<DelegateSubscriptionRepository>(repo);
    }
    registerFallbackValue(const LoadDashboard(organizationUID: '', companyUID: ''));
  });

  setUp(() {
    bloc = _MockBloc();
    whenListen(
      bloc,
      const Stream<AdminDashboardState>.empty(),
      initialState: const AdminDashboardLoaded(
        summary: DashboardSummary(totalDelegates: 12, checkedInToday: 9, absentToday: 3),
      ),
    );
    if (sl.isRegistered<AdminDashboardBloc>()) sl.unregister<AdminDashboardBloc>();
    sl.registerFactory<AdminDashboardBloc>(() => bloc);
  });

  tearDown(() {
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.resetPhysicalSize();
    v.resetDevicePixelRatio();
  });

  for (final dark in [false, true]) {
    testWidgets('mobile home renders all sections in order (dark=$dark)', (t) async {
      _size(t, const Size(390, 1600));
      await t.pumpWidget(_app(AdminHomeScreen(adminDelegate: sup), dark: dark));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      final order = [
        find.byType(AdminHomeHeroCard),
        find.byType(AdminHomeChainChips),
        find.byType(AdminHomeDutiesGuide),
        find.byType(AdminHomePromoCard),
        find.byType(AdminHomeTodayOverview),
        find.byType(AdminHomeQuickActions),
      ];
      for (final f in order) {
        expect(f, findsOneWidget);
      }
      double y(Finder f) => t.getTopLeft(f).dy;
      expect(y(order[0]) < y(order[3]), isTrue);
      expect(y(order[1]) < y(order[2]), isTrue); // chips, then duties inside hero
      expect(y(order[2]) < y(order[3]), isTrue);
      expect(y(order[3]) < y(order[4]), isTrue);
      expect(y(order[4]) < y(order[5]), isTrue);
      // chips + duties are embedded inside the hero on mobile
      expect(find.descendant(of: order[0], matching: order[2]), findsOneWidget);
      await expectWebGolden(find.byType(MaterialApp), 'goldens/home_mobile_390_${dark ? 'dark' : 'light'}.png');
    });
  }

  testWidgets('hero card dark mode uses primaryContainer with readable contrast', (t) async {
    _size(t, const Size(390, 1600));
    await t.pumpWidget(_app(AdminHomeScreen(adminDelegate: sup), dark: true));
    for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    final cs = AppTheme.darkTheme().colorScheme;
    final box = t.widget<Container>(find.descendant(
            of: find.byType(AdminHomeHeroCard), matching: find.byType(Container))
        .first);
    final deco = box.decoration as BoxDecoration;
    expect(deco.color, cs.primaryContainer);
    expect(deco.gradient, isNull);
    final title = t.widget<Text>(find.textContaining('أهلاً بك'));
    expect(title.style!.color, cs.onPrimaryContainer);
    double lum(Color c) => c.computeLuminance();
    final a = lum(cs.onPrimaryContainer), b = lum(cs.primaryContainer);
    final ratio = (a > b ? a + .05 : b + .05) / (a > b ? b + .05 : a + .05);
    expect(ratio, greaterThanOrEqualTo(4.5));
  });

  testWidgets('hero card light mode keeps primary gradient + white', (t) async {
    _size(t, const Size(390, 1600));
    await t.pumpWidget(_app(AdminHomeScreen(adminDelegate: sup)));
    for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
    final box = t.widget<Container>(find.descendant(
            of: find.byType(AdminHomeHeroCard), matching: find.byType(Container))
        .first);
    expect((box.decoration as BoxDecoration).gradient, isNotNull);
    expect(t.widget<Text>(find.textContaining('أهلاً بك')).style!.color, Colors.white);
  });

  final cases = <(Size, bool, String)>[
    (const Size(1280, 1100), false, 'home_desktop_1280_light'),
    (const Size(1600, 1100), true, 'home_desktop_1600_dark'),
    (const Size(1000, 1700), false, 'home_desktop_1000_light'),
  ];
  for (final c in cases) {
    testWidgets('desktop home grid ${c.$3}', (t) async {
      _size(t, c.$1);
      await t.pumpWidget(_app(AdminDesktopHomeWeb(delegate: sup), dark: c.$2));
      for (var i = 0; i < 20; i++) {
        await t.pump(const Duration(milliseconds: 200));
      }
      expect(find.byType(AdminDesktopHomeGridWeb), findsOneWidget);
      expect(find.byType(AdminHomeChainChips), findsOneWidget);
      final hero = t.getRect(find.byType(AdminHomeHeroCard));
      final ov = t.getRect(find.byType(AdminHomeTodayOverview));
      if (c.$1.width >= 1200) {
        expect((hero.top - ov.top).abs() < 30, isTrue, reason: 'same row');
      } else {
        expect(ov.top > hero.bottom, isTrue, reason: 'overview below');
      }
      await expectWebGolden(find.byType(MaterialApp), 'goldens/${c.$3}.png');
    });
  }
}
