import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/settings/presentation/pages/settings_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

Delegate _user(UserRole role) => Delegate(
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
  role: role,
);

final tDelegate = _user(UserRole.delegate);

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

/// TAS-358: the logout row stays for staff roles; the field delegate logs
/// out from the navigation menu instead. Tests that use the row run as HR.
final tStaff = _user(UserRole.hr);

Widget buildSettingsScreen({Delegate? who}) {
  return BlocProvider<ThemeCubit>.value(
    value: sl<ThemeCubit>(),
    child: MaterialApp(
      localizationsDelegates: appLocalizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      locale: const Locale('en'),
      home: SettingsScreen(delegate: who ?? tStaff),
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
      // Appearance (theme mode) tile is visible
      expect(find.byIcon(Symbols.dark_mode_rounded), findsOneWidget);
      // Logout tile is visible
      expect(find.byIcon(Icons.logout_rounded), findsAtLeastNWidgets(1));
    });

    testWidgets('renders AppBar with back button by default', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      expect(find.byType(AppBar), findsOneWidget);
      // TAS-358 (F-18): the official BackButton (named for screen readers).
      expect(find.byType(BackButton), findsOneWidget);
    });

    testWidgets('appearance sheet sets System/Light/Dark', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();
      final themeCubit = sl<ThemeCubit>();

      for (final m in [ThemeMode.dark, ThemeMode.light, ThemeMode.system]) {
        final tile = find.byIcon(Symbols.dark_mode_rounded).first;
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
        await tester.tap(find.byKey(ValueKey('theme_mode_${m.name}')));
        await tester.pumpAndSettle();
        expect(themeCubit.state.themeMode, m);
      }
    });

    group('appearance opens adaptively (TAS-158)', () {
      tearDown(WebRuntimePolicy.debugReset);

      Future<void> openAppearance(WidgetTester tester, {required bool web}) async {
        WebRuntimePolicy.debugIsWebOverride = web;
        tester.view.physicalSize =
            web ? const Size(1440, 900) : const Size(390, 844);
        tester.view.devicePixelRatio = 1;
        addTearDown(tester.view.reset);
        await tester.pumpWidget(buildSettingsScreen());
        await tester.pumpAndSettle();
        final tile = find.byIcon(Symbols.dark_mode_rounded).first;
        await tester.ensureVisible(tile);
        await tester.tap(tile);
        await tester.pumpAndSettle();
      }

      testWidgets('wide web opens a dialog, not a bottom sheet', (
        tester,
      ) async {
        await openAppearance(tester, web: true);
        expect(find.byType(Dialog), findsOneWidget);
        expect(find.byType(BottomSheet), findsNothing);
        expect(find.byKey(const ValueKey('hr_sheet_close')), findsOneWidget);

        final themeCubit = sl<ThemeCubit>();
        await tester.tap(find.byKey(const ValueKey('theme_mode_dark')));
        await tester.pumpAndSettle();
        expect(themeCubit.state.themeMode, ThemeMode.dark);
        expect(find.byType(Dialog), findsNothing);
        themeCubit.setThemeMode(ThemeMode.system);
      });

      testWidgets('mobile still opens a bottom sheet', (tester) async {
        await openAppearance(tester, web: false);
        expect(find.byType(BottomSheet), findsOneWidget);
        expect(find.byType(Dialog), findsNothing);
        expect(find.byKey(const ValueKey('theme_mode_light')), findsOneWidget);
      });
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

      // Confirmation modal should appear
      expect(find.textContaining('Log out?'), findsOneWidget);
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

      expect(find.text('Cancel'), findsOneWidget);
      expect(find.text('Log out'), findsWidgets);
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

      expect(find.textContaining('Log out?'), findsOneWidget);

      await tester.tap(find.text('Cancel'));
      await tester.pumpAndSettle();

      expect(find.textContaining('Log out?'), findsNothing);
    });

    testWidgets('color picker circles are rendered', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // Color option circles should be present
      expect(find.byType(GestureDetector), findsWidgets);
    });

    testWidgets('TAS-358: no logout row for the field delegate', (
      tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen(who: tDelegate));
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_logout')), findsNothing);
      expect(find.byIcon(Icons.logout_rounded), findsNothing);
    });

    testWidgets('TAS-358: staff roles keep the logout row', (tester) async {
      for (final role in [
        UserRole.hr,
        UserRole.admin,
        UserRole.accountant,
        UserRole.marketing,
        UserRole.superAdmin,
      ]) {
        await tester.pumpWidget(buildSettingsScreen(who: _user(role)));
        await tester.pumpAndSettle();
        expect(
          find.byKey(const Key('settings_logout')),
          findsOneWidget,
          reason: '$role',
        );
      }
    });

    testWidgets('TAS-358: language is a connected ButtonGroup and rows are '
        'ListTiles', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();
      expect(find.byKey(const Key('settings_language')), findsOneWidget);
      expect(find.byType(ListTile), findsWidgets);
    });
  });
}
