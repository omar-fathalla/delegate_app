// «إضافة مندوب لمنظمة جديدة» on desktop web (MD3 Model 1), fake data only.
// Mobile keeps the original single-column page.
//
// Review screenshots: flutter test test/web/add_delegate_form_web_test.dart \
//   --dart-define=ADD_DELEGATE_SHOTS=/absolute/output/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_delegate_form_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/add_delegate_desktop_layout.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/hr_shell_link.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shotsDir = String.fromEnvironment('ADD_DELEGATE_SHOTS');

Delegate _supervisor() => Delegate(
  uid: 'seed-fake-supervisor',
  firstName: 'مشرف',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مشرف تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-org',
  organizationName: 'Fake Org',
  companyUID: 'seed-fake-co',
  companyName: 'شركة ألفا التجريبية',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'test',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.admin,
);

const _fakeChains = [
  'زهران ماركت',
  'جملة ماركت',
  'كارفور',
  'خير زمان',
  'بيت الجملة',
  'أولاد رجب',
  'هايبر وان',
  'سعودي ماركت',
  'مترو ماركت',
  'سبينيس',
  'أوسكار',
  'بيم',
];

Future<List<Map<String, dynamic>>> _loader() async => [
  for (var i = 0; i < _fakeChains.length; i++)
    {'uid': 'fake-org-$i', 'name': _fakeChains[i]},
];

Future<void> _fonts() async {
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-SemiBold.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'));
  await cairo.load();
  final root = Platform.environment['FLUTTER_ROOT'];
  final mi = File('$root/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf');
  if (root != null && mi.existsSync()) {
    final loader = FontLoader('MaterialIcons')
      ..addFont(Future.value(ByteData.sublistView(mi.readAsBytesSync())));
    await loader.load();
  }
  final sym = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'));
  await sym.load();
}

final _shotKey = GlobalKey();

Future<void> _pump(WidgetTester t, Size size) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final theme = AppTheme.lightTheme(const Color(0xFF6750A4));
  await t.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: MaterialApp(
        debugShowCheckedModeBanner: false,
        theme: theme.copyWith(
          textTheme: theme.textTheme.apply(fontFamily: 'Cairo'),
        ),
        locale: const Locale('ar'),
        localizationsDelegates: AppLocalizations.localizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: AddDelegateFormScreen(
          supervisor: _supervisor(),
          debugOrganizationsLoader: _loader,
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

Future<void> _fill(WidgetTester t) async {
  final fields = find.byType(TextFormField);
  await t.enterText(fields.at(0), 'أحمد');
  await t.enterText(fields.at(1), 'محمود');
  await t.enterText(fields.at(2), 'السيد');
  await t.enterText(fields.at(3), '01012345678');
  await t.pumpAndSettle();
}

Future<void> _shot(WidgetTester t, String name) async {
  if (_shotsDir.isEmpty) return;
  await t.runAsync(() async {
    final boundary =
        _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_shotsDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

void main() {
  setUpAll(_fonts);

  setUp(() async {
    sl.allowReassignment = true;
    SharedPreferences.setMockInitialValues({'app_locale': 'ar'});
    final prefs = await SharedPreferences.getInstance();
    if (!sl.isRegistered<SharedPreferences>()) {
      sl.registerLazySingleton<SharedPreferences>(() => prefs);
    }
    if (!sl.isRegistered<LocaleProvider>()) {
      sl.registerLazySingleton(() => LocaleProvider(sl<SharedPreferences>()));
      localeProvider = sl<LocaleProvider>();
    }
    if (!sl.isRegistered<ThemeCubit>()) {
      sl.registerLazySingleton(() => ThemeCubit(sl<SharedPreferences>()));
    }
    WebRuntimePolicy.debugReset();
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HrShellLink.debugReset();
  });

  /// Stand-in for the mounted HR shell so the header bell shows (2 unread).
  void attachFakeShell(List<int> tabs) {
    final bridge = HrWebHeaderBridge()
      ..attach(unread: 2, reloadHome: () async {}, openNotifications: () {});
    HrShellLink.attach(
      owner: Object(),
      selectTab: tabs.add,
      selectMenu: (_) {},
      bridge: bridge,
    );
  }

  test('desktop layout is web-only and wider than the shell breakpoint', () {
    expect(AddDelegateDesktopBreakpoints.useDesktop(isWeb: false, width: 1440), isFalse);
    expect(AddDelegateDesktopBreakpoints.useDesktop(isWeb: true, width: 768), isFalse);
    expect(AddDelegateDesktopBreakpoints.useDesktop(isWeb: true, width: 800), isTrue);
  });

  testWidgets('mobile keeps the original page (no summary, no sidebar)', (t) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await _pump(t, const Size(1440, 900));
    expect(find.byKey(const ValueKey('add_delegate_summary')), findsNothing);
    expect(find.byType(HRDesktopSidebar), findsNothing);
    expect(find.byType(AppBar), findsOneWidget);
  });

  testWidgets('1440: sidebar, header, two columns, live summary', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    attachFakeShell([]);
    await _pump(t, const Size(1440, 1000));
    expect(find.byKey(const ValueKey('hr_web_header_notifications')), findsOneWidget);
    expect(find.byType(HRDesktopSidebar), findsOneWidget);
    expect(find.text('إضافة مندوب لمنظمة جديدة'), findsOneWidget);
    expect(find.text('ملخص الطلب'), findsOneWidget);
    expect(find.byType(AppBar), findsNothing);
    await _fill(t);
    expect(find.text('أحمد محمود السيد'), findsOneWidget);
    // TAS-254: no chain picker; the base chain is chosen automatically.
    expect(find.byKey(const ValueKey('add_delegate_base_chain_note')), findsOneWidget);
    expect(find.byKey(AddDelegateChainGrid.optionKey('fake-org-0')), findsNothing);
    expect(find.text('السلسلة الأساسية'), findsOneWidget);
    expect(find.text(_fakeChains[0]), findsWidgets);
    await _shot(t, 'add-delegate-1440');
  });

  testWidgets('1024: rail navigation, still two columns', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    attachFakeShell([]);
    await _pump(t, const Size(1024, 900));
    expect(t.getSize(find.byType(HRDesktopSidebar)).width, lessThan(100));
    expect(find.byKey(const ValueKey('add_delegate_summary')), findsOneWidget);
    await _fill(t);
    await _shot(t, 'add-delegate-1024');
  });

  testWidgets('800: one column with a sticky bottom bar', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    attachFakeShell([]);
    await _pump(t, const Size(800, 900));
    expect(find.byKey(const ValueKey('add_delegate_summary')), findsNothing);
    expect(find.byKey(const ValueKey('add_delegate_bottom_bar')), findsOneWidget);
    await _fill(t);
    expect(find.byKey(const ValueKey('add_delegate_base_chain_note')), findsOneWidget);
    await _shot(t, 'add-delegate-800');
  });

  testWidgets('side navigation pops the page and switches the shell tab', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final tabs = <int>[];
    attachFakeShell(tabs);
    await _pump(t, const Size(1440, 1000));
    await t.tap(find.text('الرئيسية').first);
    await t.pumpAndSettle();
    expect(tabs, isNotEmpty);
  });

  testWidgets('duplicate chains are disabled with a neutral note', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    t.view.physicalSize = const Size(900, 520);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    addTearDown(t.view.resetDevicePixelRatio);
    final chains = [
      for (var i = 0; i < 9; i++) ChainOption(uid: 'c$i', name: _fakeChains[i]),
    ];
    final theme = AppTheme.lightTheme(const Color(0xFF6750A4));
    await t.pumpWidget(
      RepaintBoundary(
        key: _shotKey,
        child: MaterialApp(
          debugShowCheckedModeBanner: false,
          theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Cairo')),
          locale: const Locale('ar'),
          localizationsDelegates: AppLocalizations.localizationsDelegates,
          supportedLocales: AppLocalizations.supportedLocales,
          home: Directionality(
            textDirection: TextDirection.rtl,
            child: Scaffold(
              backgroundColor: theme.colorScheme.surfaceContainerLowest,
              body: Padding(
                padding: const EdgeInsets.all(24),
                child: AddDelegateChainGrid(
                  chains: chains,
                  selectedUids: const {'c0', 'c1', 'c3'},
                  duplicateUids: const {'c0'},
                  onChanged: (_) {},
                ),
              ),
            ),
          ),
        ),
      ),
    );
    await t.pumpAndSettle();
    final dup = t.widget<Checkbox>(find.descendant(
      of: find.byKey(AddDelegateChainGrid.optionKey('c0')),
      matching: find.byType(Checkbox),
    ));
    expect(dup.onChanged, isNull);
    final note = t.widget<Text>(find.byKey(AddDelegateChainGrid.warningKey));
    final cs = theme.colorScheme;
    expect(note.style?.color, cs.onSurfaceVariant);
    expect(find.text('2 مختارة'), findsOneWidget);
    await _shot(t, 'add-delegate-duplicate');
  });
}
