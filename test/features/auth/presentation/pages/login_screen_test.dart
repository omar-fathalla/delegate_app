import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';

// Manual mock for AuthBloc
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
    sl.allowReassignment = true;
    if (!sl.isRegistered<AuthBloc>()) {
      sl.registerFactory<AuthBloc>(() => MockAuthBloc());
    }

    if (!sl.isRegistered<SharedPreferences>()) {
      SharedPreferences.setMockInitialValues({'app_locale': 'en'});
      final prefs = await SharedPreferences.getInstance();
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }

    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      localeProvider = sl<LocaleProvider>();
    }

    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
  });

  Widget createWidgetUnderTest() {
    return MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: const LoginScreen(),
    );
  }

  testWidgets('LoginScreen disposes correctly', (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    // Interact with text fields to ensure controllers are active
    await tester.enterText(find.byType(TextFormField).at(0), '1234567890');
    await tester.enterText(find.byType(TextFormField).at(1), 'password123');

    // Verify text is entered
    expect(find.text('1234567890'), findsOneWidget);
    expect(find.text('password123'), findsOneWidget);

    // Pump another widget to trigger disposal of LoginScreen
    await tester.pumpWidget(const SizedBox());

    // No specific assertion for disposal here as we are relying on no exceptions being thrown.
  });

  testWidgets('LoginScreen toggles password visibility', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest());

    final passwordFieldFinder = find.byType(TextFormField).at(1);
    final passwordTextFieldFinder = find.descendant(
      of: passwordFieldFinder,
      matching: find.byType(TextField),
    );

    // Verify initial state: obscured
    TextField passwordTextField = tester.widget(passwordTextFieldFinder);
    expect(passwordTextField.obscureText, isTrue);

    // Verify initial visibility off icon exists (since _obscurePassword = true)
    final visibilityOffIconFinder = find.descendant(
      of: passwordFieldFinder,
      matching: find.byIcon(Icons.visibility_off_outlined),
    );
    expect(visibilityOffIconFinder, findsOneWidget);

    // Tap the visibility toggle button
    await tester.tap(visibilityOffIconFinder);
    await tester.pump();

    // Verify state: visible
    passwordTextField = tester.widget(passwordTextFieldFinder);
    expect(passwordTextField.obscureText, isFalse);

    // Verify icon changed to visibility on
    final visibilityOnIconFinder = find.descendant(
      of: passwordFieldFinder,
      matching: find.byIcon(Icons.visibility_outlined),
    );
    expect(visibilityOnIconFinder, findsOneWidget);

    // Tap the visibility toggle button again
    await tester.tap(visibilityOnIconFinder);
    await tester.pump();

    // Verify state: obscured again
    passwordTextField = tester.widget(passwordTextFieldFinder);
    expect(passwordTextField.obscureText, isTrue);

    // Verify icon changed back to visibility off
    expect(
      find.descendant(
        of: passwordFieldFinder,
        matching: find.byIcon(Icons.visibility_off_outlined),
      ),
      findsOneWidget,
    );
  });
}
