import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

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
  setUp(() {
    sl.allowReassignment = true;
    if (!sl.isRegistered<AuthBloc>()) {
      sl.registerFactory<AuthBloc>(() => MockAuthBloc());
    }
  });

  Widget createWidgetUnderTest() {
    return const MaterialApp(
      localizationsDelegates: [
        AppLocalizations.delegate,
        GlobalMaterialLocalizations.delegate,
        GlobalWidgetsLocalizations.delegate,
        GlobalCupertinoLocalizations.delegate,
      ],
      supportedLocales: [Locale('en')],
      home: LoginScreen(),
    );
  }

  testWidgets('LoginScreen disposes correctly', (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());

    // Interact with text fields to ensure controllers are active
    await tester.enterText(find.byType(TextFormField).at(0), '1234567890');
    await tester.enterText(find.byType(TextFormField).at(1), 'MotherName');

    // Verify text is entered
    expect(find.text('1234567890'), findsOneWidget);
    expect(find.text('MotherName'), findsOneWidget);

    // Pump another widget to trigger disposal of LoginScreen
    await tester.pumpWidget(const SizedBox());

    // No specific assertion for disposal here as we are relying on no exceptions being thrown.
  });

  testWidgets('LoginScreen toggles password visibility',
      (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle(); // Wait for animations

    // Find the Password text field (it's the second TextFormField)
    final passwordFieldFinder = find.byType(TextFormField).at(1);
    final passwordTextFieldFinder =
        find.descendant(of: passwordFieldFinder, matching: find.byType(TextField));

    // Verify initial state: obscured
    TextField passwordTextField = tester.widget(passwordTextFieldFinder);
    expect(passwordTextField.obscureText, isTrue);

    // Verify initial tooltip "Show password"
    final showPasswordTooltip = find.byTooltip('Show password');
    expect(showPasswordTooltip, findsOneWidget);

    // Tap the visibility toggle button (found via tooltip)
    await tester.tap(showPasswordTooltip);
    await tester.pump();

    // Verify state: visible
    passwordTextField = tester.widget(passwordTextFieldFinder);
    expect(passwordTextField.obscureText, isFalse);

    // Verify tooltip changed to "Hide password"
    final hidePasswordTooltip = find.byTooltip('Hide password');
    expect(hidePasswordTooltip, findsOneWidget);

    // Tap the visibility toggle button again (found via new tooltip)
    await tester.tap(hidePasswordTooltip);
    await tester.pump();

    // Verify state: obscured again
    passwordTextField = tester.widget(passwordTextFieldFinder);
    expect(passwordTextField.obscureText, isTrue);

    // Verify tooltip changed back to "Show password"
    expect(find.byTooltip('Show password'), findsOneWidget);
  });

  testWidgets('Tapping "Remember Me" text toggles checkbox',
      (WidgetTester tester) async {
    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pumpAndSettle();

    // Find the checkbox
    final checkboxFinder = find.byType(Checkbox);
    expect(checkboxFinder, findsOneWidget);

    // Check initial state (should be unchecked by default in LoginScreen)
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);

    // Find the text "Remember Me"
    final rememberMeTextFinder = find.text('Remember Me');
    expect(rememberMeTextFinder, findsOneWidget);

    // Tap the text
    await tester.tap(rememberMeTextFinder);
    await tester.pump();

    // Check state (should be checked)
    expect(tester.widget<Checkbox>(checkboxFinder).value, isTrue);

    // Tap the text again
    await tester.tap(rememberMeTextFinder);
    await tester.pump();

    // Check state (should be unchecked)
    expect(tester.widget<Checkbox>(checkboxFinder).value, isFalse);
  });
}
