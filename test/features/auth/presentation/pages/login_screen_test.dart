import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/auth/presentation/pages/login_screen.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthBloc extends Mock implements AuthBloc {}
class MockPushNotificationService extends Mock implements PushNotificationService {}

void main() {
  late MockAuthBloc mockAuthBloc;
  late MockPushNotificationService mockPushNotificationService;

  setUpAll(() {
    registerFallbackValue(AuthInitial());
    registerFallbackValue(LoginRequested(phoneNumber: '', password: '', rememberMe: false));
  });

  setUp(() async {
    sl.allowReassignment = true;
    mockAuthBloc = MockAuthBloc();
    mockPushNotificationService = MockPushNotificationService();

    // Default stream for AuthBloc
    when(() => mockAuthBloc.state).thenReturn(AuthInitial());
    when(() => mockAuthBloc.stream).thenAnswer((_) => Stream.value(AuthInitial()));
    when(() => mockAuthBloc.close()).thenAnswer((_) async {});

    if (!sl.isRegistered<AuthBloc>()) {
      sl.registerFactory<AuthBloc>(() => mockAuthBloc);
    }

    if (!sl.isRegistered<PushNotificationService>()) {
      sl.registerLazySingleton<PushNotificationService>(() => mockPushNotificationService);
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
      home: BlocProvider<AuthBloc>.value(
        value: mockAuthBloc,
        child: const LoginScreen(),
      ),
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
    
    // Ensure all animations and controllers are disposed without errors
    await tester.pump();
  });

  testWidgets('LoginScreen toggles password visibility', (
    WidgetTester tester,
  ) async {
    await tester.pumpWidget(createWidgetUnderTest());

    final passwordFieldFinder = find.byType(TextFormField).at(1);
    
    // Verify initial state: obscured
    TextField passwordTextField = tester.widget(find.descendant(
      of: passwordFieldFinder,
      matching: find.byType(TextField),
    ));
    expect(passwordTextField.obscureText, isTrue);

    // Verify initial visibility off icon exists
    final visibilityOffIconFinder = find.byIcon(Icons.visibility_off_outlined);
    expect(visibilityOffIconFinder, findsOneWidget);

    // Tap the visibility toggle button (IconButton)
    await tester.tap(find.ancestor(
      of: visibilityOffIconFinder,
      matching: find.byType(IconButton),
    ));
    await tester.pump();

    // Verify state: visible
    passwordTextField = tester.widget(find.descendant(
      of: passwordFieldFinder,
      matching: find.byType(TextField),
    ));
    expect(passwordTextField.obscureText, isFalse);

    // Verify icon changed to visibility on
    final visibilityOnIconFinder = find.byIcon(Icons.visibility_outlined);
    expect(visibilityOnIconFinder, findsOneWidget);

    // Tap the visibility toggle button again
    await tester.tap(find.ancestor(
      of: visibilityOnIconFinder,
      matching: find.byType(IconButton),
    ));
    await tester.pump();

    // Verify state: obscured again
    passwordTextField = tester.widget(find.descendant(
      of: passwordFieldFinder,
      matching: find.byType(TextField),
    ));
    expect(passwordTextField.obscureText, isTrue);
  });
}
