// Web login keeps the delegate / staff tabs; the delegate tab never calls the
// device-binding delegate login on web. Fake data only.
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
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
  }) async {
    WebRuntimePolicy.debugIsWebOverride = web;
    t.view.physicalSize = const Size(1280, 900);
    t.view.devicePixelRatio = 1;
    await t.pumpWidget(MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: locale,
      home: BlocProvider<AuthBloc>.value(value: bloc, child: const LoginScreen()),
    ));
    await t.pumpAndSettle();
  }

  Finder tab(LoginMode m) => find.byKey(ValueKey('group_item_$m'));

  testWidgets('web keeps both tabs; delegate tab explains the app and never logs in', (t) async {
    await pump(t, web: true);
    expect(find.text('مندوب'), findsWidgets);
    expect(find.text('موظف إداري'), findsWidgets);
    expect(tab(LoginMode.delegate), findsOneWidget);
    expect(find.byKey(const ValueKey('login_web_delegate_notice')), findsOneWidget);
    expect(find.text(WebRuntimePolicy.delegateLoginWebMessage), findsOneWidget);
    expect(find.text(WebRuntimePolicy.delegateLoginWebMessageEn), findsNothing);
    expect(find.byKey(const ValueKey('login_national_id')), findsNothing);
    final submit = t.widget<FilledButton>(find.byKey(const ValueKey('login_submit')));
    expect(submit.onPressed, isNull);
    verifyNever(() => bloc.add(any()));
  });

  testWidgets('english delegate tab uses the policy message', (t) async {
    localeProvider.setLocale(const Locale('en'));
    addTearDown(() => localeProvider.setLocale(const Locale('ar')));
    await pump(t, web: true, locale: const Locale('en'));
    expect(find.text(WebRuntimePolicy.delegateLoginWebMessageEn), findsOneWidget);
    expect(find.text(WebRuntimePolicy.delegateLoginWebMessage), findsNothing);
    final submit = t.widget<FilledButton>(find.byKey(const ValueKey('login_submit')));
    expect(submit.onPressed, isNull);
  });

  testWidgets('web staff tab signs in with LoginMode.staff', (t) async {
    await pump(t, web: true);
    await t.tap(tab(LoginMode.staff));
    await t.pumpAndSettle();
    expect(find.byKey(const ValueKey('login_web_delegate_notice')), findsNothing);
    await t.enterText(find.byKey(const ValueKey('login_phone')), '01000000000');
    await t.enterText(find.byKey(const ValueKey('login_staff_password')), 'fake-pass-123');
    await t.ensureVisible(find.byKey(const ValueKey('login_submit')));
    await t.tap(find.byKey(const ValueKey('login_submit')));
    await t.pump();
    final captured = verify(() => bloc.add(captureAny())).captured;
    final req = captured.whereType<LoginRequested>().single;
    expect(req.mode, LoginMode.staff);
  });

  testWidgets('web centres the sheet at phone width on a wide window', (t) async {
    await pump(t, web: true);
    final size = t.getSize(find.byType(Scaffold).first);
    expect(size.width, LoginScreen.webMaxWidth);
  });

  testWidgets('mobile (not web) is unchanged: delegate fields, no notice', (t) async {
    await pump(t, web: false);
    expect(find.byKey(const ValueKey('login_web_delegate_notice')), findsNothing);
    expect(find.byKey(const ValueKey('login_national_id')), findsOneWidget);
    expect(t.getSize(find.byType(Scaffold).first).width, 1280);
  });
}
