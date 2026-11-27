import 'package:delegate_app/core/design/tokens.dart';
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
    // The list is lazy; a tall view builds every row (TAS-387 layout).
    setUp(() {
      final binding = TestWidgetsFlutterBinding.ensureInitialized();
      binding.platformDispatcher.views.first.physicalSize = const Size(800, 2600);
      binding.platformDispatcher.views.first.devicePixelRatio = 1;
    });
    tearDown(() {
      TestWidgetsFlutterBinding.ensureInitialized()
          .platformDispatcher
          .views
          .first
          .resetPhysicalSize();
    });

    testWidgets('renders settings screen with key elements', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      // TAS-387: language, theme mode, contrast and colour on the page.
      expect(find.byKey(const Key('settings_language')), findsOneWidget);
      expect(find.byKey(const Key('settings_theme_mode')), findsOneWidget);
      expect(find.byKey(const Key('settings_contrast')), findsOneWidget);
      expect(find.byKey(const Key('settings_colors')), findsOneWidget);
      // Logout tile is visible
      expect(find.byKey(const Key('settings_logout')), findsOneWidget);
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

    testWidgets('theme mode is chosen on the page (TAS-387)', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();
      final themeCubit = sl<ThemeCubit>();
      for (final (m, icon) in [
        (ThemeMode.dark, Symbols.dark_mode_rounded),
        (ThemeMode.light, Symbols.light_mode_rounded),
        (ThemeMode.system, Symbols.brightness_auto_rounded),
      ]) {
        final item = find.descendant(
          of: find.byKey(const Key('settings_theme_mode')),
          matching: find.byIcon(icon),
        );
        await tester.ensureVisible(item);
        await tester.tap(item);
        await tester.pumpAndSettle();
        expect(themeCubit.state.themeMode, m);
      }
      // No sheet or dialog any more.
      expect(find.byType(BottomSheet), findsNothing);
      expect(find.byType(Dialog), findsNothing);
    });

    testWidgets('contrast is saved on the cubit (TAS-387)', (tester) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();
      final themeCubit = sl<ThemeCubit>();
      final high = find.descendant(
        of: find.byKey(const Key('settings_contrast')),
        matching: find.text('High'),
      );
      await tester.ensureVisible(high);
      await tester.tap(high);
      await tester.pumpAndSettle();
      expect(themeCubit.state.contrast, TashilContrast.high);
      themeCubit.setContrast(TashilContrast.standard);
    });

    testWidgets('tapping logout shows confirmation dialog', (
      WidgetTester tester,
    ) async {
      await tester.pumpWidget(buildSettingsScreen());
      await tester.pumpAndSettle();

      final logoutTile = find.byKey(const Key('settings_logout'));
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

      final logoutTile = find.byKey(const Key('settings_logout'));
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

      final logoutTile = find.byKey(const Key('settings_logout'));
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

      // Five seed colours as 48dp icon buttons.
      expect(
        find.descendant(
          of: find.byKey(const Key('settings_colors')),
          matching: find.byType(IconButton),
        ),
        findsNWidgets(5),
      );
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
