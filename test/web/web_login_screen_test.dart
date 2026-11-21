// Web HR login is the staff form only. Delegate sign-in stays in the mobile
// app. Fake data only.
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/widgets/web_hr_login_map.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class _MockAuthBloc extends Mock implements AuthBloc {}

void main() {
  late _MockAuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(AuthInitial());
    registerFallbackValue(
      LoginRequested(phoneNumber: '', password: '', rememberMe: false),
    );
  });

  setUp(() async {
    sl.allowReassignment = true;
    bloc = _MockAuthBloc();
    when(() => bloc.state).thenReturn(AuthInitial());
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => bloc.close()).thenAnswer((_) async {});
    if (!sl.isRegistered<SharedPreferences>()) {
      SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
      final prefs = await SharedPreferences.getInstance();
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    await sl<SharedPreferences>().remove(kLoginModePrefKey);
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      localeProvider = sl<LocaleProvider>();
    }
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
  });

  tearDown(() {
    WebRuntimePolicy.debugIsWebOverride = null;
    final view = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    view.resetPhysicalSize();
    view.resetDevicePixelRatio();
  });

  Future<void> pump(
    WidgetTester t, {
    required bool web,
    Locale locale = const Locale('ar'),
    Size size = const Size(1280, 900),
    ThemeMode themeMode = ThemeMode.light,
  }) async {
    WebRuntimePolicy.debugIsWebOverride = web;
    t.view.physicalSize = size;
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(
      themeMode: themeMode,
      theme: ThemeData(colorSchemeSeed: const Color(0xFF6750A4)),
      darkTheme: ThemeData(
        colorSchemeSeed: const Color(0xFF6750A4),
        brightness: Brightness.dark,
      ),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: BlocProvider<AuthBloc>.value(value: bloc, child: const LoginScreen()),
    ));
    await t.pumpAndSettle();
  }

  Finder tab(LoginMode m) => find.byKey(ValueKey('group_item_$m'));

  testWidgets('web staff form has no delegate choice and can submit', (t) async {
    await pump(t, web: true);
    expect(find.text('مندوب'), findsNothing);
    expect(find.text('موظف إداري'), findsNothing);
    expect(tab(LoginMode.delegate), findsNothing);
    expect(find.byKey(const ValueKey('login_mode_switch')), findsNothing);
    expect(find.text('تسجيل الدخول للموظفين الإداريين'), findsOneWidget);
    expect(find.byKey(const ValueKey('login_national_id')), findsNothing);
    expect(find.byKey(const ValueKey('login_web_delegate_notice')), findsNothing);
    final submit = t.widget<FilledButton>(find.byKey(const ValueKey('login_submit')));
    expect(submit.onPressed, isNotNull);
    verifyNever(() => bloc.add(any()));
  });

  testWidgets('english web login uses the staff subtitle', (t) async {
    localeProvider.setLocale(const Locale('en'));
    addTearDown(() => localeProvider.setLocale(const Locale('ar')));
    await pump(t, web: true, locale: const Locale('en'));
    expect(find.text('Sign in for administrative staff'), findsOneWidget);
    expect(find.text('مندوب'), findsNothing);
    expect(find.text(WebRuntimePolicy.delegateLoginWebMessageEn), findsNothing);
    final submit = t.widget<FilledButton>(find.byKey(const ValueKey('login_submit')));
    expect(submit.onPressed, isNotNull);
  });

  testWidgets('web staff form signs in with LoginMode.staff', (t) async {
    await pump(t, web: true);
    await t.enterText(find.byKey(const ValueKey('login_phone')), '01000000000');
    await t.enterText(find.byKey(const ValueKey('login_staff_password')), 'fake-pass-123');
    await t.ensureVisible(find.byKey(const ValueKey('login_submit')));
    await t.tap(find.byKey(const ValueKey('login_submit')));
    await t.pump();
    final captured = verify(() => bloc.add(captureAny())).captured;
    final req = captured.whereType<LoginRequested>().single;
    expect(req.mode, LoginMode.staff);
  });

  testWidgets('web form column is 400dp on a 1280 window', (t) async {
    await pump(t, web: true);
    expect(t.getSize(find.byType(Scaffold).first).width, 1280);
    expect(
      t.getSize(find.byKey(const ValueKey('login_web_form_column'))).width,
      400,
    );
  });

  testWidgets('mobile (not web) is unchanged: delegate fields, no notice', (t) async {
    await pump(t, web: false);
    expect(find.byKey(const ValueKey('login_web_delegate_notice')), findsNothing);
    expect(find.byKey(const ValueKey('login_national_id')), findsOneWidget);
    expect(t.getSize(find.byType(Scaffold).first).width, 1280);
  });

  // TAS-188: brand hero with the branch map, form in a side sheet.
  testWidgets('wide web login shows the hero map, pins and side sheet', (t) async {
    await pump(t, web: true, size: const Size(1440, 900));
    expect(find.byKey(const ValueKey('login_web_map')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_web_brand_header')), findsOneWidget);
    expect(find.text('نظام الموارد البشرية'), findsOneWidget);
    expect(find.text('فريقك في الفروع في نظام واحد'), findsOneWidget);
    for (final pin in kHrLoginMapPins) {
      expect(find.text(pin.ar), findsOneWidget, reason: pin.ar);
    }
    expect(kHrLoginMapPins.first.ar, 'فتح الله ماركت');
    expect(kHrLoginMapPins.first.featured, isTrue);
    // RTL: the sheet is on the end (left) side, the headline on the start side.
    final sheet = t.getRect(find.byKey(const ValueKey('login_web_sheet')));
    expect(sheet.left, 16);
    expect(sheet.width, 520);
    final headline = t.getRect(find.byKey(const ValueKey('login_web_headline')));
    expect(headline.left, greaterThan(sheet.right));
  });

  testWidgets('form shows +20, the new remember label and support buttons', (t) async {
    await pump(t, web: true);
    expect(find.byKey(const ValueKey('login_phone_country_code')), findsOneWidget);
    expect(find.text('+20'), findsOneWidget);
    expect(find.text('البقاء متصلاً على هذا الجهاز'), findsOneWidget);
    expect(find.text('تذكرني'), findsNothing);
    expect(find.byKey(const ValueKey('login_support_whatsapp')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_support_button')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_caps_lock_hint')), findsNothing);
  });

  testWidgets('phone without the leading zero signs in', (t) async {
    await pump(t, web: true);
    await t.enterText(find.byKey(const ValueKey('login_phone')), '1000000000');
    await t.enterText(find.byKey(const ValueKey('login_staff_password')), 'fake-pass-123');
    await t.tap(find.byKey(const ValueKey('login_submit')));
    await t.pump();
    final captured = verify(() => bloc.add(captureAny())).captured;
    expect(captured.whereType<LoginRequested>(), hasLength(1));
  });

  testWidgets('dark hero and english copy render without overflow', (t) async {
    localeProvider.setLocale(const Locale('en'));
    addTearDown(() => localeProvider.setLocale(const Locale('ar')));
    await pump(
      t,
      web: true,
      locale: const Locale('en'),
      size: const Size(1024, 700),
      themeMode: ThemeMode.dark,
    );
    expect(t.takeException(), isNull);
    expect(find.text('Fathalla Market'), findsOneWidget);
    expect(find.text('Your branch teams, in one system'), findsOneWidget);
    // LTR: the sheet is on the end (right) side.
    final sheet = t.getRect(find.byKey(const ValueKey('login_web_sheet')));
    expect(sheet.right, 1024 - 16);
    expect(sheet.width, 440);
  });

  testWidgets('narrow web keeps the stacked layout with the support footer', (t) async {
    await pump(t, web: true, size: const Size(600, 1400));
    expect(t.takeException(), isNull);
    expect(find.byKey(const ValueKey('login_web_map')), findsNothing);
    expect(find.byKey(const ValueKey('login_support_whatsapp')), findsOneWidget);
    expect(find.byKey(const ValueKey('login_submit')), findsOneWidget);
  });
}
