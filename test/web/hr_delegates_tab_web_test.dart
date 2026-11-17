// HR web «مناديب الشركة» (MD3 Model 3), fake data only.
// Mobile keeps the original actions and the profile tap.
//
// Review screenshots: flutter test test/web/hr_delegates_tab_web_test.dart \
//   --dart-define=HR_DELEGATES_SHOTS=/absolute/output/dir
import 'dart:io';
import 'dart:ui' as ui;

import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/admin/data/chain_duplicate_lookup.dart';
import 'package:delegate_app/features/admin/data/link_delegate_chains.dart';
import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/web/hr_system/company_chain_requests_panel.dart';
import 'dart:async';
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
  // Chains the company is not in yet are offered with a «جديدة» hint.
  await fs.collection('organizations').doc('o-other').set({'name': 'أولاد رجب'});
  await fs.collection('organizations').doc('o-ragab').set({'name': 'هايبر وان'});
  // The hidden Fathalla chain is never offered.
  await fs.collection('organizations').doc('o-fathalla').set({'name': 'fathalla market'});
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


/// Fake chain names for the 38-chain screenshot (same count as prod).
const _moreChains = [
  'أبو زيد ماركت', 'الفرجاني', 'المحلاوي', 'بنده', 'تريد لاين', 'جاردن سيتي ماركت',
  'حلواني إخوان', 'خيرات مصر', 'رنين', 'زاد الخير', 'سعودي ماركت', 'صن مول',
  'طلبات', 'عبد الله ماركت', 'فارم بوكس', 'قطر الندى', 'لولو', 'ماي ماركت',
  'نيو سبينيس', 'هايبر الوكالة', 'وكالة المنصورة', 'أوسكار', 'اكس مارت', 'البدري',
  'التوحيد والنور', 'الراية', 'السلطان', 'العثيم', 'المصريين',
];

Future<FakeFirebaseFirestore> _seedMany() async {
  final fs = await _seed();
  for (var i = 0; i < _moreChains.length; i++) {
    await fs.collection('organizations').doc('o-more-$i').set({'name': _moreChains[i]});
  }
  await fs.collection(kCompanyChainRequestsCollection).doc('fake-ccr').set({
    'companyUID': _co, 'status': 'pending', 'organizationUID': 'o-more-3', 'organizationName': _moreChains[3],
  });
  return fs;
}

void main() {
  setUpAll(_fonts);

  late List<List<CompanyChainOption>> submitted;
  late FakeFirebaseFirestore fs;

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
    fs = await _seedMany();
    submitted = [];
    CompanyChainCatalog.clear();
    HrAddChainsSheet.debugFirestore = () => fs;
    HrAddChainsSheet.debugSubmit = (selected) async {
      submitted.add(selected);
    };
    WebRuntimePolicy.debugReset();
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HrAddChainsSheet.debugReset();
    CompanyChainCatalog.clear();
  });

  testWidgets('mobile keeps the original actions, no company button', (t) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await _pump(t, const Size(1440, 900), web: false);
    expect(find.text('الملف'), findsWidgets);
    expect(find.byKey(const Key('hr_add_company_chains')), findsNothing);
  });

  testWidgets('1440: compact table, no per-delegate «إضافة سلاسل», page button', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(1440, 900));
    expect(find.text('السلاسل'), findsOneWidget);
    expect(find.text('الملف'), findsNothing);
    expect(find.byKey(const Key('hr_delegate_add_chains_fake-d0')), findsNothing);
    expect(find.byKey(const Key('hr_delegate_attendance_fake-d0')), findsOneWidget);
    expect(find.byKey(const Key('hr_add_company_chains')), findsOneWidget);
    expect(find.text('إضافة سلاسل للشركة'), findsOneWidget);
    expect(find.descendant(of: find.byKey(const Key('hr_delegate_chains_fake-d0')), matching: find.text('2')), findsOneWidget);
    await _shot(t, 'hr-delegates-1440');
  });

  testWidgets('sheet loading state: skeleton, no lone spinner', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    final never = Completer<List<CompanyChainOption>>();
    HrAddChainsSheet.debugCatalog = () => never.future;
    await _pump(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('hr_add_company_chains')));
    await t.pump();
    await t.pump(const Duration(milliseconds: 300));
    await t.pump(const Duration(milliseconds: 300));
    expect(find.byKey(HrAddChainsSheet.skeletonKey), findsOneWidget);
    expect(find.byType(CircularProgressIndicator), findsNothing);
    expect(t.widget<FilledButton>(find.byKey(HrAddChainsSheet.submitKey)).onPressed, isNull);
    await _shot(t, 'chains-sheet-loading-1440');
  });

  testWidgets('sheet: sections, joined disabled, pending, search, select all (no cap), send', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('hr_add_company_chains')));
    await t.pumpAndSettle();
    expect(find.byKey(HrAddChainsSheet.titleKey), findsOneWidget);
    expect(find.text('سلاسل الشركة (7)'), findsOneWidget);
    expect(find.text('سلاسل أخرى (تحتاج موافقة) (31)'), findsOneWidget);
    expect(find.textContaining('· جديدة'), findsNothing);
    expect(find.byKey(HrAddChainsSheet.chipKey('o-fathalla')), findsNothing);
    expect(find.text('طلب قيد المراجعة'), findsOneWidget);
    await _shot(t, 'chains-sheet-loaded-1440');

    // Joined chains cannot be picked.
    await t.tap(find.byKey(HrAddChainsSheet.chipKey('o-jomla')));
    await t.pumpAndSettle();
    expect(find.text('0 مختارة'), findsOneWidget);

    // «اختيار الكل» follows the search filter.
    await t.enterText(find.byKey(HrAddChainsSheet.searchKey), 'ماركت');
    await t.pumpAndSettle();
    await t.tap(find.byKey(HrAddChainsSheet.selectAllKey));
    await t.pumpAndSettle();
    final filtered = _moreChains.where((n) => n.contains('ماركت')).length;
    expect(find.text('$filtered مختارة'), findsOneWidget);

    // No cap: every selectable chain (30 = 31 minus the pending one).
    await t.enterText(find.byKey(HrAddChainsSheet.searchKey), '');
    await t.pumpAndSettle();
    await t.tap(find.byKey(HrAddChainsSheet.selectAllKey));
    await t.pumpAndSettle();
    expect(find.text('30 مختارة'), findsOneWidget);
    await _shot(t, 'chains-sheet-selected-1440');
    await t.tap(find.byKey(HrAddChainsSheet.submitKey));
    await t.pumpAndSettle();
    expect(submitted.single.length, 30);
    expect(submitted.single.any((c) => c.joined), isFalse);
    expect(submitted.single.any((c) => c.uid == 'o-more-3'), isFalse);
    expect(find.byKey(HrAddChainsSheet.titleKey), findsNothing);
    expect(find.textContaining('تم إرسال طلب ضم 30 سلسلة'), findsOneWidget);
  });

  testWidgets('800: cards, full-screen sheet', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    await _pump(t, const Size(800, 900));
    await t.tap(find.byKey(const Key('hr_add_company_chains')));
    await t.pumpAndSettle();
    expect(t.getSize(find.byType(HrAddChainsSheet)).width, 800);
    await _shot(t, 'chains-sheet-800');
  });

  testWidgets('pending check fails: chains still show with a neutral note', (t) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    HrAddChainsSheet.debugPending = () async => throw Exception('offline');
    await _pump(t, const Size(1440, 900));
    await t.tap(find.byKey(const Key('hr_add_company_chains')));
    await t.pumpAndSettle();
    expect(find.byKey(HrAddChainsSheet.chipKey('o-other')), findsOneWidget);
    expect(find.textContaining('تعذر التحقق من الطلبات السابقة'), findsOneWidget);
  });

  test('catalog: joined flags, alphabetical, hidden chain left out, cached', () async {
    final list = await CompanyChainCatalog.fetch(firestore: fs, companyUID: _co);
    expect(list.where((c) => c.joined).map((c) => c.uid).toSet(), _orgs.keys.toSet());
    expect(list.any((c) => c.uid == 'o-fathalla'), isFalse);
    final names = list.map((c) => c.name.toLowerCase()).toList();
    expect(names, [...names]..sort());
    await fs.collection('organizations').doc('o-new').set({'name': 'جديدة تماماً'});
    final again = await CompanyChainCatalog.fetch(firestore: fs, companyUID: _co);
    expect(again.length, list.length); // served from the cache
    final fresh = await CompanyChainCatalog.fetch(firestore: fs, companyUID: _co, forceRefresh: true);
    expect(fresh.length, list.length + 1);
  });

  test('submit: one pending doc per chain, 40 chains, no delegate on it', () async {
    final chains = [
      for (var i = 0; i < 40; i++) CompanyChainOption(uid: 'c$i', name: 'سلسلة $i', joined: false),
    ];
    await submitCompanyChainRequests(
      firestore: fs, supervisor: _hr, companyUID: _co, companyName: 'شركة تجريبية', chains: chains,
    );
    final docs = (await fs.collection(kCompanyChainRequestsCollection)
            .where('companyUID', isEqualTo: _co).where('requestType', isEqualTo: 'company_join_chain').get())
        .docs;
    expect(docs.length, 40);
    expect(docs.map((d) => d['batchId']).toSet().length, 1);
    expect(docs.every((d) => d['batchSize'] == 40 && d['status'] == 'pending'), isTrue);
    expect(docs.any((d) => d.data().containsKey('existingDelegateUid')), isFalse);
    final pending = await fetchPendingCompanyChainUids(firestore: fs, companyUID: _co);
    expect(pending.length, 41); // 40 + the seeded one
  });

  testWidgets('approval panel: company, chains, approve/reject buttons', (t) async {
    t.view.physicalSize = const Size(700, 600);
    t.view.devicePixelRatio = 1;
    addTearDown(t.view.resetPhysicalSize);
    final reqs = [
      for (final (i, n) in ['كارفور', 'مترو', 'زهران ماركت'].indexed)
        CompanyChainRequest(
          id: 'r$i', status: 'pending', companyUID: _co, companyName: 'شركة تجريبية',
          organizationUID: 'o$i', organizationName: n, supervisorUid: _hr.uid,
          supervisorName: _hr.fullName, batchId: 'b1',
        ),
    ];
    await t.pumpWidget(MaterialApp(
      home: Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: CompanyChainRequestsPanel(reviewer: _hr, requestsOverride: reqs)),
      ),
    ));
    expect(find.text('طلبات ضم سلاسل (3)'), findsOneWidget);
    expect(find.text('شركة تجريبية'), findsOneWidget);
    expect(find.text('موافقة على الكل'), findsOneWidget);
    expect(find.byKey(CompanyChainRequestsPanel.approveKey('r1')), findsOneWidget);
  });

  test('link pre-check (mobile sheet / add-delegate): own doc / same ID = linked, request = pending', () async {
    final d = _delegates().first;
    await fs
        .collection('organizations').doc('o-metro')
        .collection('companies').doc(_co)
        .collection('delegates').doc('other-doc')
        .set({'nationalityID': d.nationalityID});
    final r = await lookupLinkChainStates(
      firestore: fs,
      companyUID: _co,
      delegateUid: d.uid,
      nationalId: d.nationalityID,
      phoneNumber: d.phoneNumber,
      organizationUIDs: const ['o-jomla', 'o-metro', 'o-spinneys', 'o-zahran'],
    );
    expect(r.delegateOrgUids, {'o-jomla', 'o-metro'});
    expect(r.pendingOrgUids, {'o-spinneys'});
  });

  test('mobile sheet still hides linked chains (shared fetch default)', () async {
    final d = _delegates().first;
    final chains = await fetchLinkableChains(firestore: fs, delegate: d, supervisor: _hr);
    expect(chains.map((c) => c.uid), isNot(contains('o-jomla')));
    expect(chains.firstWhere((c) => c.uid == 'o-other').companyRegistered, isFalse);
    final all = await fetchLinkableChains(firestore: fs, delegate: d, supervisor: _hr, includeLinked: true);
    expect(all.where((c) => c.alreadyLinked).map((c) => c.uid).toSet(), {'o-jomla', 'o-carrefour'});
  });
}
