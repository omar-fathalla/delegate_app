// HR web «مناديب الشركة» (MD3 Model 3), fake data only.
// Mobile keeps the original actions and the profile tap.
//
// Review screenshots: flutter test test/web/hr_delegates_tab_web_test.dart \
//   --dart-define=HR_DELEGATES_SHOTS=/absolute/output/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart' show Right;
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/admin/data/link_delegate_chains.dart';
import 'package:delegate_app/features/admin/domain/entities/chain_selection.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_delegates_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_add_chains_sheet.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_sidebar.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_desktop_top_bar.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/hr_web_account_button.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/rendering.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

const _shotsDir = String.fromEnvironment('HR_DELEGATES_SHOTS');
const _co = 'seed-fake-co';

Delegate _person({
  required String uid,
  required String fullName,
  String nid = '',
  String phone = '',
  String city = '',
  String orgUid = 'o-jomla',
  String orgName = 'جملة ماركت',
  List<String> allOrgs = const [],
  DelegateStatus status = DelegateStatus.active,
  UserRole role = UserRole.delegate,
  DelegatePosition position = DelegatePosition.promoter,
  bool annual = false,
}) =>
    Delegate(
      uid: uid,
      firstName: fullName.split(' ').first,
      middleName: '',
      lastName: '',
      fullName: fullName,
      nationalityID: nid,
      motherName: '',
      city: city,
      phoneNumber: phone,
      gender: DelegateGender.male,
      position: position,
      birthDate: DateTime(1995),
      organizationUID: orgUid,
      organizationName: orgName,
      companyUID: _co,
      companyName: 'شركة ألفا التجريبية',
      status: status,
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
      role: role,
      allOrganizationNames: allOrgs,
      isAnnualLeaveEnabled: annual,
    );

final _hr = _person(
  uid: 'seed-fake-hr',
  fullName: 'مشرف تجريبي',
  phone: '01000000000',
  role: UserRole.hr,
  position: DelegatePosition.supervisor,
);

const _names = [
  'أحمد سمير حسن', 'منى خالد إبراهيم', 'يوسف عادل مصطفى', 'ريم أشرف سالم',
  'كريم طارق فؤاد', 'نهى سامح عبد الله', 'عمر حازم رشاد', 'سلمى وليد شوقي',
  'حسام نبيل زكي', 'دينا مجدي صبري', 'مصطفى رامي جلال', 'هبة عصام نصر',
  'طارق أيمن فتحي', 'لمياء حسين بكر', 'شريف ماهر لطفي', 'إيمان رأفت سعيد',
];
const _cities = ['الإسكندرية', 'القاهرة', 'الجيزة', 'الغربية', 'البحيرة', 'دمياط'];

List<Delegate> _delegates() => [
  for (var i = 0; i < _names.length; i++)
    _person(
      uid: 'fake-d$i',
      fullName: _names[i],
      nid: '290000000000${(i + 1).toString().padLeft(2, '0')}',
      phone: '010000000${(i + 1).toString().padLeft(2, '0')}',
      city: _cities[i % _cities.length],
      allOrgs: i == 0
          ? const ['جملة ماركت', 'كارفور']
          : (i % 3 == 2 ? const ['جملة ماركت', 'كارفور', 'مترو'] : const ['جملة ماركت']),
      status: (i == 5 || i == 11) ? DelegateStatus.suspended : DelegateStatus.active,
      annual: i == 3,
    ),
];

const _orgs = {
  'o-jomla': 'جملة ماركت',
  'o-carrefour': 'كارفور',
  'o-zahran': 'زهران ماركت',
  'o-metro': 'مترو',
  'o-spinneys': 'سبينيس',
  'o-kheir': 'خير زمان',
  'o-beit': 'بيت الجملة',
};

Future<FakeFirebaseFirestore> _seed() async {
  final fs = FakeFirebaseFirestore();
  for (final e in _orgs.entries) {
    await fs.collection('organizations').doc(e.key).set({'name': e.value});
    await fs.collection('organizations').doc(e.key).collection('companies').doc(_co).set({'name': 'x'});
  }
  // A chain outside the company is never offered.
  await fs.collection('organizations').doc('o-other').set({'name': 'سلسلة شركة أخرى'});
  final first = _delegates().first;
  for (final org in ['o-jomla', 'o-carrefour']) {
    await fs
        .collection('organizations').doc(org)
        .collection('companies').doc(_co)
        .collection('delegates').doc(first.uid)
        .set({'uid': first.uid, 'nationalId': first.nationalityID, 'phoneNumber': first.phoneNumber});
  }
  await fs.collection('delegate_requests').doc('fake-req').set({
    'companyUID': _co,
    'nationalId': first.nationalityID,
    'status': 'pending',
    'organizationUID': 'o-spinneys',
    'organizationUIDs': ['o-spinneys'],
  });
  return fs;
}

class _MockBloc extends MockBloc<AdminDelegatesEvent, AdminDelegatesState>
    implements AdminDelegatesBloc {}

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

Future<void> _shot(WidgetTester t, String name) async {
  if (_shotsDir.isEmpty) return;
  await t.runAsync(() async {
    final boundary = _shotKey.currentContext!.findRenderObject()! as RenderRepaintBoundary;
    final image = await boundary.toImage();
    final bytes = await image.toByteData(format: ui.ImageByteFormat.png);
    File('$_shotsDir/$name.png').writeAsBytesSync(bytes!.buffer.asUint8List());
  });
}

/// Same shell layout as HRMainScreen on wide web: side nav (rail below
/// 1200 on this tab) + desktop header + the tab.
Future<void> _pump(WidgetTester t, Size size, {bool web = true}) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  addTearDown(t.view.resetPhysicalSize);
  addTearDown(t.view.resetDevicePixelRatio);
  final theme = AppTheme.lightTheme(const Color(0xFF6750A4));
  final tab = HRDelegatesTab(hrDelegate: _hr);
  final wide = size.width > 768;
  await t.pumpWidget(
    RepaintBoundary(
      key: _shotKey,
      child: BlocProvider<ThemeCubit>.value(
        value: sl<ThemeCubit>(),
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
              body: !wide
                  ? tab
                  : Row(
                      children: [
                        HRDelegatesShellNav(width: size.width),
                        Expanded(
                          child: Column(
                            children: [
                              HRDesktopTopBar(
                                delegate: _hr,
                                activeIndex: kHrTabDelegates,
                                onRefresh: () {},
                                onMenuSelected: (_) {},
                                menuItems: const [],
                                webBell: web ? HrWebHeaderBell(unread: 2, onPressed: () {}) : null,
                                webAccount: web
                                    ? (showName) => HrWebAccountButton(delegate: _hr, showName: showName)
                                    : null,
                              ),
                              Expanded(child: tab),
                            ],
                          ),
                        ),
                      ],
                    ),
            ),
          ),
        ),
      ),
    ),
  );
  await t.pumpAndSettle();
}

class HRDelegatesShellNav extends StatelessWidget {
  const HRDelegatesShellNav({super.key, required this.width});
  final double width;
  @override
  Widget build(BuildContext context) => HRDesktopSidebar(
        delegate: _hr,
        selectedIndex: kHrTabDelegates,
        isExpanded: !(WebRuntimePolicy.isWeb && width < 1200),
        onToggleExpanded: () {},
        onItemSelected: (_) {},
        onOpenSettings: () {},
        onOpenProfile: () {},
      );
}

void main() {
  setUpAll(_fonts);

  late List<List<ChainOption>> submitted;

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
    final bloc = _MockBloc();
    whenListen(
      bloc,
      const Stream<AdminDelegatesState>.empty(),
      initialState: AdminDelegatesLoaded(delegates: _delegates()),
    );
    sl.registerFactory<AdminDelegatesBloc>(() => bloc);
    final fs = await _seed();
    submitted = [];
    HrAddChainsSheet.debugFirestore = () => fs;
    HrAddChainsSheet.debugSubmit = (selected) async {
      submitted.add(selected);
      return const Right('fake-request');
    };
    WebRuntimePolicy.debugReset();
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HrAddChainsSheet.debugReset();
  });

  testWidgets('mobile keeps the original actions', (t) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await _pump(t, const Size(1440, 900), web: false);
    expect(find.text('الملف'), findsWidgets);
    expect(find.byKey(const Key('hr_delegate_add_chains_fake-d0')), findsNothing);
  });

  testWidgets('1440: compact table, chain counts, icon actions, no profile/call/WhatsApp', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(1440, 900));
    expect(find.text('دليل كوادر ومناديب الشركة'), findsOneWidget);
    expect(find.text('السلاسل'), findsOneWidget);
    expect(find.text('الملف'), findsNothing);
    expect(find.byTooltip('مراسلة عبر واتساب (01000000001)'), findsNothing);
    expect(find.byTooltip('اتصال هاتفي (01000000001)'), findsNothing);
    var rowsVisible = 0;
    for (var i = 0; i < _names.length; i++) {
      final f = find.byKey(Key('hr_delegate_row_fake-d$i'));
      if (f.evaluate().isNotEmpty && t.getRect(f).bottom <= 900) rowsVisible++;
    }
    expect(rowsVisible, greaterThanOrEqualTo(13));
    final add = find.byKey(const Key('hr_delegate_add_chains_fake-d0'));
    expect(t.getSize(add).height, greaterThanOrEqualTo(48));
    expect(find.descendant(of: find.byKey(const Key('hr_delegate_chains_fake-d0')), matching: find.text('2')), findsOneWidget);
    await _shot(t, 'hr-delegates-1440');
    // Row tap (on the # / name side) does not open the profile.
    final row = find.byKey(const Key('hr_delegate_row_fake-d1'));
    await t.tapAt(t.getTopRight(row) + const Offset(-30, 25));
    await t.pumpAndSettle();
    expect(find.byType(HRDelegatesTab), findsOneWidget);
    expect(find.byKey(const Key('hr_delegate_row_fake-d1')).hitTestable(), findsOneWidget);
    expect(find.byType(SnackBar), findsNothing);
  });

  testWidgets('suspended delegate: «إضافة سلاسل» disabled with a tooltip', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(1440, 900));
    final btn = t.widget<IconButton>(find.byKey(const Key('hr_delegate_add_chains_fake-d5')));
    expect(btn.onPressed, isNull);
    expect(find.byTooltip(kHrAddChainsSuspendedTooltip), findsWidgets);
    expect(kHrAllowAddChainsForSuspended, isFalse);
  });

  testWidgets('side sheet: linked, pending, search, send', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('hr_delegate_add_chains_fake-d0')));
    await t.pumpAndSettle();
    expect(find.byKey(HrAddChainsSheet.titleKey), findsOneWidget);
    expect(t.getSize(find.byType(HrAddChainsSheet)).width, 1440); // overlay
    expect(find.text('مرتبط حالياً (2)'), findsOneWidget);
    expect(find.text('سلسلة شركة أخرى'), findsNothing);
    final spinneys = t.widget<FilterChip>(find.byKey(HrAddChainsSheet.chipKey('o-spinneys')));
    expect(spinneys.onSelected, isNull);
    final carrefour = t.widget<FilterChip>(find.byKey(HrAddChainsSheet.chipKey('o-carrefour')));
    expect(carrefour.onSelected, isNull);
    await t.tap(find.byKey(HrAddChainsSheet.chipKey('o-zahran')));
    await t.tap(find.byKey(HrAddChainsSheet.chipKey('o-metro')));
    await t.pumpAndSettle();
    expect(find.text('2/$kMaxOrganizationsPerRequest مختارة'), findsOneWidget);
    expect(find.text('إرسال الطلب (2)'), findsOneWidget);
    await _shot(t, 'hr-delegates-picker-1440');

    await t.enterText(find.byKey(HrAddChainsSheet.searchKey), 'خير');
    await t.pumpAndSettle();
    expect(find.byKey(HrAddChainsSheet.chipKey('o-beit')), findsNothing);
    expect(find.byKey(HrAddChainsSheet.chipKey('o-kheir')), findsOneWidget);

    await t.tap(find.byKey(HrAddChainsSheet.submitKey));
    await t.pumpAndSettle();
    expect(submitted.single.map((c) => c.uid), ['o-zahran', 'o-metro']);
    expect(find.byKey(HrAddChainsSheet.titleKey), findsNothing);
    expect(find.text(linkChainsSuccessMessage(['زهران ماركت', 'مترو'])), findsOneWidget);
    await _shot(t, 'hr-delegates-sent-1440');
  });

  testWidgets('1024: rail navigation and merged columns', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(1024, 800));
    expect(t.getSize(find.byType(HRDesktopSidebar)).width, lessThan(100));
    expect(find.text('الرقم القومي / الهاتف'), findsOneWidget);
    expect(find.text('السلاسل'), findsOneWidget);
    await _shot(t, 'hr-delegates-1024');
  });

  testWidgets('800: cards, full-screen sheet', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(800, 900));
    expect(find.text('المندوب / المروج'), findsNothing);
    expect(find.byKey(const Key('hr_delegate_add_chains_fake-d0')), findsOneWidget);
    await _shot(t, 'hr-delegates-800');
    await t.tap(find.byKey(const Key('hr_delegate_add_chains_fake-d0')));
    await t.pumpAndSettle();
    expect(t.getSize(find.byKey(HrAddChainsSheet.titleKey)).width, greaterThan(500));
    await _shot(t, 'hr-delegates-picker-800');
  });

  test('mobile sheet still hides linked chains (shared fetch default)', () async {
    final fs = await _seed();
    final d = _delegates().first;
    final chains = await fetchLinkableChains(firestore: fs, delegate: d, supervisor: _hr);
    expect(chains.map((c) => c.uid), isNot(contains('o-jomla')));
    expect(chains.map((c) => c.uid), isNot(contains('o-carrefour')));
    expect(chains.map((c) => c.uid), isNot(contains('o-other')));
    final all = await fetchLinkableChains(firestore: fs, delegate: d, supervisor: _hr, includeLinked: true);
    expect(all.where((c) => c.alreadyLinked).map((c) => c.uid).toSet(), {'o-jomla', 'o-carrefour'});
  });
}

