import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';

// Manual mock for AuthBloc to avoid complex dependency injection in smoke test
class MockAuthBloc extends Bloc<AuthEvent, AuthState> implements AuthBloc {
  MockAuthBloc() : super(AuthInitial());

  @override
  Login get loginUseCase => throw UnimplementedError();

  @override
  CheckAutoLogin get checkAutoLoginUseCase => throw UnimplementedError();

  @override
  Logout get logoutUseCase => throw UnimplementedError();
}

void main() {
  setUp(() async {
    // Configure GetIt to allow reassignment for testing
    sl.allowReassignment = true;
    sl.registerFactory<AuthBloc>(() => MockAuthBloc());

    // Register global providers and shared preferences
    SharedPreferences.setMockInitialValues({});
    final prefs = await SharedPreferences.getInstance();
    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerSingleton<SharedPreferences>(prefs);
    }

    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(prefs));
    }

    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(prefs));
    }

    // Initialize global variables required by MyApp/LoginScreen
    localeProvider = sl<LocaleProvider>();
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: localeProvider.locale,
      themeMode: sl<ThemeCubit>().state.themeMode,
      theme: ThemeData.light(), // Simple theme for test
      darkTheme: ThemeData.dark(), // Simple theme for test
      home: const Scaffold(body: LoginScreen()),
    );
  }

  testWidgets('Login screen smoke test', (WidgetTester tester) async {
    // Build our app and trigger a frame.
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Fetch localization strings
    final l10n = AppLocalizations.of(tester.element(find.byType(LoginScreen)))!;

    // Verify that the login screen elements are present
    expect(find.text(l10n.appTitle), findsOneWidget);
    expect(
      find.text(l10n.loginButton),
      findsAtLeast(1),
    ); // Might be same as title "login"
    expect(find.text(l10n.mobileNumber), findsOneWidget);
  });
}
