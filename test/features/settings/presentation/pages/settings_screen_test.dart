import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';

final tDelegate = Delegate(
  uid: '1',
  firstName: 'Ahmed',
  middleName: 'Ali',
  lastName: 'Hassan',
  fullName: 'Ahmed Ali Hassan',
  nationalityID: '12345',
  motherName: 'Mother',
  city: 'Cairo',
  phoneNumber: '01234567890',
  gender: DelegateGender.male,
  position: DelegatePosition.promoter,
  birthDate: DateTime(1990, 1, 1),
  organizationUID: 'org1',
  organizationName: 'Org',
  companyUID: 'comp1',
  companyName: 'Comp',
  status: DelegateStatus.active,
  delegatePublicId: 'DEL-1',
  allReceiptCodes: const [],
  createdAt: DateTime(2024, 1, 1),
  createdBy: 'admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
);

Future<void> setupDI() async {
  sl.allowReassignment = true;
  if (!sl.isRegistered<SharedPreferences>()) {
    SharedPreferences.setMockInitialValues({});
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
}

Widget buildSettingsScreen() {
  return BlocProvider<ThemeCubit>.value(
    value: sl<ThemeCubit>(),
    child: MaterialApp(
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: SettingsScreen(delegate: tDelegate),
    ),
  );
}

void main() {
  setUpAll(() async {
    await setupDI();
  });

  group('SettingsScreen', () {
    testWidgets('renders settings screen with key elements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Language tile is visible
      expect(find.byIcon(Icons.translate_rounded), findsOneWidget);
      // Dark mode switch is visible
      expect(find.byType(Switch), findsOneWidget);
      // Logout tile is visible
      expect(find.byIcon(Icons.logout_rounded), findsAtLeastNWidgets(1));
    });

    testWidgets('dark mode switch toggles theme', (WidgetTester tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      final themeCubit = sl<ThemeCubit>();
      final initialDark = themeCubit.state.isDarkMode;

      await tester.tap(find.byType(Switch));
      await tester.pumpAndSettle();

      expect(themeCubit.state.isDarkMode, !initialDark);
    });

    testWidgets('tapping logout shows confirmation dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      final logoutTile = find.byIcon(Icons.logout_rounded).last;
      await tester.ensureVisible(logoutTile);
      await tester.pumpAndSettle();

      // Tap the logout tile
      await tester.tap(logoutTile);
      await tester.pumpAndSettle();

      // Dialog should appear
      expect(find.byType(AlertDialog), findsOneWidget);
    });

    testWidgets('logout dialog has cancel and confirm buttons', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      final logoutTile = find.byIcon(Icons.logout_rounded).last;
      await tester.ensureVisible(logoutTile);
      await tester.pumpAndSettle();

      await tester.tap(logoutTile);
      await tester.pumpAndSettle();

      expect(find.byType(TextButton), findsOneWidget);
      expect(find.byType(FilledButton), findsOneWidget);
    });

    testWidgets('tapping cancel closes logout dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      final logoutTile = find.byIcon(Icons.logout_rounded).last;
      await tester.ensureVisible(logoutTile);
      await tester.pumpAndSettle();

      await tester.tap(logoutTile);
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsOneWidget);

      await tester.tap(find.byType(TextButton));
      await tester.pumpAndSettle();

      expect(find.byType(AlertDialog), findsNothing);
    });

    testWidgets('color picker circles are rendered', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Color option circles should be present
      expect(find.byType(GestureDetector), findsWidgets);
    });
  });
}
