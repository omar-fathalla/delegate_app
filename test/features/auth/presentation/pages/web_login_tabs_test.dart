import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_login_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

class MockPushNotificationService extends Mock
    implements PushNotificationService {}

void main() {
  late MockAuthBloc authBloc;

  setUpAll(() {
    registerFallbackValue(AuthInitial());
    registerFallbackValue(
      LoginRequested(phoneNumber: '', password: '', rememberMe: false),
    );
  });

  setUp(() async {
    WebRuntimePolicy.debugIsWebOverride = true;
    authBloc = MockAuthBloc();
    when(() => authBloc.state).thenReturn(AuthInitial());
    when(() => authBloc.stream).thenAnswer((_) => Stream.value(AuthInitial()));
    when(() => authBloc.close()).thenAnswer((_) async {});
    when(() => authBloc.add(any())).thenAnswer((_) {});

    if (!sl.isRegistered<AuthBloc>()) {
      sl.registerFactory<AuthBloc>(() => authBloc);
    }
    if (!sl.isRegistered<PushNotificationService>()) {
      sl.registerLazySingleton<PushNotificationService>(
        () => MockPushNotificationService(),
      );
    }
    if (!sl.isRegistered<SharedPreferences>()) {
      SharedPreferences.setMockInitialValues({
        'app_locale': 'ar',
        'app_locale_explicit': true,
      });
      final prefs = await SharedPreferences.getInstance();
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      // late final: assign once for the whole file.
      localeProvider = sl<LocaleProvider>();
    }
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
  });

  tearDown(WebRuntimePolicy.debugReset);

  Widget app(Widget home, {Locale locale = const Locale('ar')}) {
    return MaterialApp(
      locale: locale,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: BlocProvider<AuthBloc>.value(value: authBloc, child: home),
    );
  }

  testWidgets('web login has no مندوب or موظف إداري choice', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();

    expect(find.byType(HrLoginScreen), findsNothing);
    expect(find.text('مندوب'), findsNothing);
    expect(find.text('موظف إداري'), findsNothing);
    expect(find.byKey(const ValueKey('login_mode_switch')), findsNothing);
    expect(find.text('لحسابات الموظفين والإدارة'), findsOneWidget);
  });

  testWidgets('web staff form submits LoginMode.staff', (tester) async {
    tester.view.physicalSize = const Size(1200, 2000);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    await tester.pumpWidget(app(const LoginScreen()));
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '01012345678');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret-pass');
    final button = find.widgetWithText(FilledButton, 'تسجيل الدخول');
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    final captured =
        verify(() => authBloc.add(captureAny())).captured.single
            as LoginRequested;
    expect(captured.mode, LoginMode.staff);
    expect(captured.phoneNumber, '01012345678');
    expect(captured.password, 'secret-pass');
  });

  testWidgets('hr login screen submits LoginMode.staff', (tester) async {
    tester.view.physicalSize = const Size(1400, 1600);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    // Match the provider to the English MaterialApp so the badge uses the
    // short "HR Portal" label instead of the long Arabic string in LTR.
    localeProvider.setLocale(const Locale('en'));
    await tester.pumpWidget(
      app(const HrLoginScreen(), locale: const Locale('en')),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '01012345678');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret-pass');
    await tester.tap(find.widgetWithText(FilledButton, 'Login'));
    await tester.pump();

    final captured =
        verify(() => authBloc.add(captureAny())).captured.single
            as LoginRequested;
    expect(captured.mode, LoginMode.staff);
    expect(captured.phoneNumber, '01012345678');
    expect(captured.password, 'secret-pass');
  });
}
