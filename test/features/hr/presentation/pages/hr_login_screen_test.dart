import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
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
  late MockAuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(AuthInitial());
    registerFallbackValue(const LoginRequested(phoneNumber: '', password: ''));
  });

  setUp(() async {
    sl.allowReassignment = true;
    bloc = MockAuthBloc();
    when(() => bloc.state).thenReturn(AuthInitial());
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => bloc.close()).thenAnswer((_) async {});
    if (!sl.isRegistered<PushNotificationService>()) {
      sl.registerLazySingleton<PushNotificationService>(
        () => MockPushNotificationService(),
      );
    }
    if (!sl.isRegistered<SharedPreferences>()) {
      SharedPreferences.setMockInitialValues({'app_locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      // `localeProvider` is a late final global: assign it once per file.
      localeProvider = sl<LocaleProvider>();
    }
  });

  testWidgets('HR portal login dispatches LoginMode.staff', (tester) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    // The test font is wider than real Arabic/Latin glyphs, so a header Row
    // overflows here only. Ignore overflow; fail on anything else.
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('en'),
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const HrLoginScreen(),
        ),
      ),
    );
    await tester.pumpAndSettle();

    await tester.enterText(find.byType(TextFormField).at(0), '01000000000');
    await tester.enterText(find.byType(TextFormField).at(1), 'secret');
    final button = find.byType(FilledButton).first;
    await tester.ensureVisible(button);
    await tester.tap(button);
    await tester.pump();

    final event =
        verify(() => bloc.add(captureAny())).captured.single as LoginRequested;
    expect(event.mode, LoginMode.staff);
    expect(event.phoneNumber, '01000000000');
    expect(event.password, 'secret');
  });

  testWidgets('unknown phone shows the generic invalid-credentials snackbar', (
    tester,
  ) async {
    tester.view.physicalSize = const Size(1920, 1080);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final original = FlutterError.onError;
    FlutterError.onError = (details) {
      if (details.exceptionAsString().contains('overflowed')) return;
      original?.call(details);
    };
    addTearDown(() => FlutterError.onError = original);
    const error = AuthError(
      message: 'رقم الهاتف أو كلمة المرور غير صحيحة',
      code: 'invalid_credentials',
    );
    when(() => bloc.stream).thenAnswer((_) => Stream<AuthState>.value(error));

    await tester.pumpWidget(
      MaterialApp(
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        locale: const Locale('ar'),
        home: BlocProvider<AuthBloc>.value(
          value: bloc,
          child: const HrLoginScreen(),
        ),
      ),
    );
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 100));

    expect(find.byType(SnackBar), findsOneWidget);
    final l10n = await AppLocalizations.delegate.load(const Locale('ar'));
    expect(find.text(l10n.invalidLoginCredentials), findsOneWidget);
  });
}
