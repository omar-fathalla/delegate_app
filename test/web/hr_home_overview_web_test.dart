// Web-only HR overview (/hr/home «الرئيسية») with fake data: every section,
// filters and search, the table states, the three window size classes, the
// shell wiring, and the mobile path staying as it was.
import 'dart:async';
import 'dart:io';

import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_tab.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_main_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/web/hr_system/delegate_subscription_requests_web.dart';
import 'package:delegate_app/web/hr_system/hr_home_overview_web.dart';
import 'package:delegate_app/web/hr_system/hr_home_side_cards_web.dart';
import 'package:firebase_core/firebase_core.dart';
// Transitive test helper of firebase_core (fake Firebase app, no network).
// ignore: depend_on_referenced_packages
import 'package:firebase_core_platform_interface/test.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:shared_preferences/shared_preferences.dart';

import 'web_golden.dart';

DateTime _at(int h, int m) => DateTime(2026, 11, 16, h, m);
var _clockNow = _at(13, 40);

Delegate _person(
  String uid,
  String name, {
  String org = 'فتح الله ماركت',
  String code = '',
  UserRole role = UserRole.delegate,
  String? email,
}) => Delegate(
  uid: uid,
  firstName: name.split(' ').first,
  middleName: '',
  lastName: '',
  fullName: name,
  nationalityID: '',
  motherName: '',
  city: 'Cairo',
  phoneNumber: '0100000$uid',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'fake-org',
  organizationName: org,
  companyUID: 'fake-company',
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
  delegatePublicId: code,
  allReceiptCodes: const [],
  createdAt: DateTime(2024),
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
  email: email,
);

final _supervisor = _person(
  'sup',
  'منى الشريف',
  role: UserRole.admin,
  code: 'SUP-1',
  email: 'mona@example.com',
);
final _hr = _person('hr', 'كريم عادل', role: UserRole.hr, code: 'HR-1');

const _chains = ['زهران ماركت', 'فتح الله ماركت', 'كارفور'];

/// 14 checked in (some still there), 3 absent, 1 on approved leave.
List<HRAttendanceRecord> _records() {
  HRAttendanceRecord row(
    String uid,
    String name,
    String org,
    String branch,
    DateTime inAt, [
    DateTime? outAt,
  ]) => HRAttendanceRecord(
    delegate: _person(uid, name, org: org, code: 'TS-$uid'),
    branchName: branch,
    checkInTime: inAt,
    checkOutTime: outAt,
  );
  return [
    row('1012', 'أحمد علي', 'فتح الله ماركت', 'فرع سموحة', _at(9, 2)),
    row('1003', 'محمد حسن', 'كارفور', 'فرع المعادي', _at(8, 15), _at(12, 30)),
    row('1007', 'سارة محمود', 'زهران ماركت', 'فرع سيدي بشر', _at(8, 41)),
    row('1001', 'يوسف إبراهيم', 'كارفور', 'فرع مدينة نصر', _at(7, 58)),
    row('1009', 'هالة فوزي', 'فتح الله ماركت', 'فرع ميامي', _at(8, 55)),
    row('1010', 'عمرو سعيد', 'زهران ماركت', 'فرع العجمي', _at(9, 10)),
    row('1005', 'نادين خالد', 'كارفور', 'فرع الدقي', _at(8, 30), _at(13, 5)),
    row('1011', 'إسلام طارق', 'فتح الله ماركت', 'فرع سموحة', _at(9, 25)),
    row('1002', 'دينا مصطفى', 'زهران ماركت', 'فرع المنشية', _at(8, 5)),
    row('1013', 'شريف ناصر', 'كارفور', 'فرع المعادي', _at(9, 40)),
    row('1004', 'ريم عبد الله', 'فتح الله ماركت', 'فرع ميامي', _at(8, 20)),
    row('1014', 'طارق سمير', 'زهران ماركت', 'فرع العجمي', _at(10, 5)),
    row('1006', 'مي جمال', 'كارفور', 'فرع الدقي', _at(8, 35)),
    row('1008', 'حسام رضا', 'فتح الله ماركت', 'فرع سموحة', _at(8, 50)),
    HRAttendanceRecord(delegate: _person('2001', 'وليد فتحي', code: 'TS-2001')),
    HRAttendanceRecord(
      delegate: _person('2002', 'أسماء رجب', org: 'كارفور', code: 'TS-2002'),
    ),
    HRAttendanceRecord(
      delegate: _person('2003', 'باسم عاطف', org: 'زهران ماركت'),
    ),
    HRAttendanceRecord(
      delegate: _person('2004', 'نهى سالم', code: 'TS-2004'),
      isOnApprovedLeave: true,
    ),
  ];
}

List<HRAttendanceRecord> _absentOnly() =>
    _records().where((r) => r.checkInTime == null).toList();

HrHomeOverviewData _data({
  Delegate? delegate,
  bool loading = false,
  String? error,
  List<HRAttendanceRecord>? records,
}) => HrHomeOverviewData(
  delegate: delegate ?? _supervisor,
  isLoading: loading,
  errorMessage: error,
  records: records ?? _records(),
  chains: _chains,
  unreadNotifications: 3,
  isFreePromotion: true,
);

final _log = <String>[];
final _opened = <HRAttendanceRecord>[];

HrHomeOverviewActions _actions() => HrHomeOverviewActions(
  onReload: () async => _log.add('reload'),
  onOpenNotifications: () => _log.add('notifications'),
  onOpenProfile: () => _log.add('profile'),
  onOpenAttendanceLog: () => _log.add('attendance_log'),
  onOpenDelegates: () => _log.add('delegates'),
  onAddDelegate: () => _log.add('add_delegate'),
  onHowToLink: () => _log.add('how_to_link'),
  onOpenRecord: _opened.add,
);

Future<void> _fonts() async {
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'))
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Bold.ttf'));
  await cairo.load();
  final icons = FontLoader('MaterialIcons')
    ..addFont(
      Future.value(
        ByteData.sublistView(
          File(
            '${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf',
          ).readAsBytesSync(),
        ),
      ),
    );
  await icons.load();
}

ThemeData _theme() {
  final t = AppTheme.lightTheme();
  return t.copyWith(textTheme: t.textTheme.apply(fontFamily: 'Cairo'));
}

Widget _app(Widget home) => MaterialApp(
  debugShowCheckedModeBanner: false,
  theme: _theme(),
  localizationsDelegates: AppLocalizations.localizationsDelegates,
  supportedLocales: AppLocalizations.supportedLocales,
  locale: const Locale('ar'),
  home: home,
);

Future<void> _pumpView(
  WidgetTester t,
  Size size,
  HrHomeOverviewData data,
) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(
    _app(
      Scaffold(
        body: HrHomeOverviewView(
          data: data,
          actions: _actions(),
          clock: () => _clockNow,
        ),
      ),
    ),
  );
  await t.pump(const Duration(milliseconds: 400));
}

Future<void> _update(WidgetTester t, HrHomeOverviewData data) async {
  await t.pumpWidget(
    _app(
      Scaffold(
        body: HrHomeOverviewView(
          data: data,
          actions: _actions(),
          clock: () => _clockNow,
        ),
      ),
    ),
  );
  await t.pump();
}

List<String> _visibleRowUids(WidgetTester t) {
  final finder = find.byWidgetPredicate((w) {
    final k = w.key;
    return k is ValueKey<String> && k.value.startsWith('hr_home_row_');
  });
  final rows = finder.evaluate().map((e) => e.widget.key as ValueKey<String>);
  final list = rows.toList()
    ..sort(
      (a, b) => t
          .getTopLeft(find.byKey(a))
          .dy
          .compareTo(t.getTopLeft(find.byKey(b)).dy),
    );
  return list.map((k) => k.value.replaceFirst('hr_home_row_', '')).toList();
}

Color? _boxColor(WidgetTester t, Finder f) {
  final c = t.widget<Container>(f);
  final d = c.decoration;
  return d is BoxDecoration ? d.color : null;
}

/// The shell's own badge streams talk to Firestore directly; with no native
/// side they would throw once golden capture lets real async work run, so the
/// fake backend simply never answers (the same as an offline first load).
void _silenceFirestore() {
  const api =
      'dev.flutter.pigeon.cloud_firestore_platform_interface.FirebaseFirestoreHostApi';
  for (final method in const [
    'querySnapshot',
    'queryGet',
    'aggregateQuery',
    'documentReferenceSnapshot',
    'documentReferenceGet',
  ]) {
    TestDefaultBinaryMessengerBinding.instance.defaultBinaryMessenger
        .setMockMessageHandler(
          '$api.$method',
          (_) => Completer<ByteData?>().future,
        );
  }
}

void main() {
  setUpAll(() async {
    await _fonts();
    setupFirebaseCoreMocks();
    await Firebase.initializeApp();
    _silenceFirestore();
  });

  setUp(() async {
    _log.clear();
    _opened.clear();
    _clockNow = _at(13, 40);
    WebRuntimePolicy.debugIsWebOverride = true;
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
  });

  tearDown(() {
    WebRuntimePolicy.debugReset();
    HrHomeOverviewWeb.debugData = null;
    HrHomeOverviewWeb.debugClock = null;
    HrHomeOverviewWeb.debugOnReload = null;
    final v = TestWidgetsFlutterBinding.instance.platformDispatcher.views.first;
    v.resetPhysicalSize();
    v.resetDevicePixelRatio();
  });

  group('sections', () {
    testWidgets('body greeting is gone; reload stays in the header', (t) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      expect(find.textContaining('أهلاً بك'), findsNothing);
      expect(find.text('مشرف الشركة'), findsNothing);
      expect(find.textContaining('آخر تحديث'), findsNothing);
      expect(find.byKey(const ValueKey('hr_home_welcome')), findsNothing);
      expect(find.byKey(const ValueKey('hr_home_role_chip')), findsNothing);
      expect(find.byKey(const ValueKey('hr_home_last_updated')), findsNothing);
      for (final icon in [
        Icons.refresh_rounded,
        Icons.notifications_outlined,
        Icons.account_circle_outlined,
      ]) {
        expect(find.byIcon(icon), findsNothing, reason: icon.toString());
      }
      expect(find.byKey(const ValueKey('hr_home_refresh')), findsNothing);
      expect(find.byKey(const ValueKey('hr_home_account')), findsNothing);
      expect(_log, isEmpty);
      expect(find.textContaining('إجراءات سريعة'), findsNothing);
      expect(find.byType(AdminHomeHeroCard), findsNothing);
      expect(find.byType(AdminHomeQuickActions), findsNothing);
    });

    testWidgets('HR accounts have no body greeting or role chip', (t) async {
      await _pumpView(t, const Size(1440, 2000), _data(delegate: _hr));
      expect(find.textContaining('أهلاً بك'), findsNothing);
      expect(find.text('HR'), findsNothing);
      expect(find.byKey(const ValueKey('hr_home_role_chip')), findsNothing);
      expect(find.byKey(const ValueKey('hr_home_welcome')), findsNothing);
    });

    testWidgets('stats: total, present X of Y with progress, neutral absent', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      final total = find.byKey(const ValueKey('hr_home_stat_total'));
      expect(
        find.descendant(of: total, matching: find.text('18')),
        findsOneWidget,
      );
      final present = find.byKey(const ValueKey('hr_home_stat_present'));
      expect(
        find.descendant(of: present, matching: find.text('14')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: present, matching: find.text('من 18')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: present, matching: find.text('78%')),
        findsOneWidget,
      );
      final bar = t.widget<LinearProgressIndicator>(
        find.byKey(const ValueKey('hr_home_present_progress')),
      );
      expect(bar.value, closeTo(14 / 18, 1e-9));

      final absent = find.byKey(const ValueKey('hr_home_stat_absent'));
      final value = t.widget<Text>(
        find.descendant(of: absent, matching: find.text('3')),
      );
      final cs = _theme().colorScheme;
      expect(value.style!.color, isNot(cs.error));
      expect(value.style!.color, cs.onSurface);

      await t.tap(absent);
      await t.pumpAndSettle();
      final list = find.byKey(const ValueKey('hr_home_absent_list'));
      expect(list, findsOneWidget);
      expect(find.text('الغايبين النهاردة (3)'), findsOneWidget);
      for (final name in ['وليد فتحي', 'أسماء رجب', 'باسم عاطف']) {
        expect(
          find.descendant(of: list, matching: find.text(name)),
          findsOneWidget,
        );
      }
      expect(
        find.descendant(of: list, matching: find.text('نهى سالم')),
        findsNothing,
        reason: 'approved leave is not absent',
      );
      await t.tap(find.byKey(const ValueKey('hr_home_absent_close')));
      await t.pumpAndSettle();
      expect(list, findsNothing);
    });

    testWidgets('chains card: tinted letter chips that filter the table', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      final card = find.byKey(const ValueKey('hr_home_chains_card'));
      expect(
        find.descendant(of: card, matching: find.text(kHrHomeChainsTitle)),
        findsOneWidget,
      );
      for (final chain in _chains) {
        final chip = find.byKey(ValueKey('hr_home_chain_chip_$chain'));
        expect(chip, findsOneWidget);
        expect(
          find.descendant(of: chip, matching: find.byType(HrChainAvatar)),
          findsOneWidget,
        );
      }
      final tintA = HrChainTint.of('كارفور', Brightness.light);
      final tintB = HrChainTint.of('كارفور', Brightness.light);
      expect(tintA.background, tintB.background);
      expect(hrChainLetter('كارفور'), 'ك');

      await t.tap(find.byKey(const ValueKey('hr_home_chain_chip_كارفور')));
      await t.pump();
      final uids = _visibleRowUids(t);
      expect(uids, ['1001', '1003', '1005', '1006', '1013']);
      final chainChip = find.byKey(const ValueKey('hr_home_filter_chain'));
      expect(
        find.descendant(of: chainChip, matching: find.text('كارفور')),
        findsOneWidget,
      );

      await t.tap(find.byKey(const ValueKey('hr_home_chain_chip_كارفور')));
      await t.pump();
      expect(_visibleRowUids(t).length, 10);
    });

    testWidgets('feature card: side-card style, free chip, wired buttons', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      final card = find.byKey(const ValueKey('hr_home_feature_card'));
      final cs = _theme().colorScheme;
      expect(t.widget(card), isA<HrSideCard>());
      expect(
        find.descendant(of: card, matching: find.byIcon(Icons.hub_rounded)),
        findsOneWidget,
      );
      expect(
        find.descendant(of: card, matching: find.byType(HrExpressiveShape)),
        findsNothing,
      );
      expect(
        _boxColor(t, find.byKey(const ValueKey('hr_home_free_chip'))),
        cs.tertiaryContainer,
      );
      expect(find.text('مجاناً حتى 31/12'), findsOneWidget);
      expect(find.text('ميزة حصرية للشركات'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hr_home_add_delegate')));
      await t.tap(find.byKey(const ValueKey('hr_home_how_to_link')));
      expect(_log, ['add_delegate', 'how_to_link']);
    });

    testWidgets('duties guide: 4 collapsed items with the existing texts', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2400), _data());
      final card = find.byKey(const ValueKey('hr_home_duties_card'));
      expect(
        find.descendant(
          of: card,
          matching: find.text('دليل المهام والمسؤوليات'),
        ),
        findsOneWidget,
      );
      final duties = adminHomeDuties(_supervisor, isArabic: true);
      expect(duties, hasLength(4));
      expect(
        find.descendant(of: card, matching: find.byType(ExpansionTile)),
        findsNWidgets(4),
      );
      for (final duty in duties) {
        expect(find.text(duty.desc), findsNothing, reason: 'collapsed');
      }
      await t.tap(find.text('2. إدارة وتفعيل أذونات التصوير'));
      await t.pumpAndSettle();
      expect(find.text(duties[1].desc), findsOneWidget);
      expect(find.text(duties[0].desc), findsNothing);
    });
  });

  group('table, filters and search', () {
    testWidgets('rows are sorted by check-in and paginated by 10', (t) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      expect(
        find.byKey(const ValueKey('hr_home_attendance_table')),
        findsOneWidget,
      );
      for (final h in [
        'المندوب',
        'السلسلة والفرع',
        'الدخول',
        'الخروج',
        'المدة',
      ]) {
        expect(find.text(h), findsOneWidget, reason: h);
      }
      expect(_visibleRowUids(t), [
        '1001',
        '1002',
        '1003',
        '1004',
        '1005',
        '1006',
        '1007',
        '1008',
        '1009',
        '1012',
      ]);
      expect(find.text('1–10 من 14'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hr_home_page_next')));
      await t.pump();
      expect(_visibleRowUids(t), ['1010', '1011', '1013', '1014']);
      expect(find.text('11–14 من 14'), findsOneWidget);
      final next = t.widget<IconButton>(
        find.byKey(const ValueKey('hr_home_page_next')),
      );
      expect(next.onPressed, isNull);
      await t.tap(find.byKey(const ValueKey('hr_home_page_prev')));
      await t.pump();
      expect(find.text('1–10 من 14'), findsOneWidget);
    });

    testWidgets('open check-ins say «لسه موجود» and count up to now', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      final row = find.byKey(const ValueKey('hr_home_row_1001'));
      expect(
        find.descendant(of: row, matching: find.text('لسه موجود')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('7:58 ص')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: row, matching: find.text('5:42')),
        findsOneWidget,
      );
      final departed = find.byKey(const ValueKey('hr_home_row_1003'));
      expect(
        find.descendant(of: departed, matching: find.text('12:30 م')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: departed, matching: find.text('4:15')),
        findsOneWidget,
      );
      _clockNow = _at(14, 10);
      await t.pump(const Duration(seconds: 30));
      expect(
        find.descendant(of: row, matching: find.text('6:12')),
        findsOneWidget,
      );
      expect(
        find.descendant(of: departed, matching: find.text('4:15')),
        findsOneWidget,
      );
    });

    testWidgets('presence chips filter still-there and checked-out rows', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      expect(find.text('الكل  14'), findsOneWidget);
      expect(find.text('لسه موجود  12'), findsOneWidget);
      expect(find.text('انصرف  2'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hr_home_filter_departed')));
      await t.pump();
      expect(_visibleRowUids(t), ['1003', '1005']);
      await t.tap(find.byKey(const ValueKey('hr_home_filter_present')));
      await t.pump();
      expect(_visibleRowUids(t), isNot(contains('1003')));
      expect(find.text('1–10 من 12'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hr_home_filter_all')));
      await t.pump();
      expect(find.text('1–10 من 14'), findsOneWidget);
    });

    testWidgets('chain dropdown chip filters and resets', (t) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      await t.tap(find.byKey(const ValueKey('hr_home_filter_chain')));
      await t.pumpAndSettle();
      expect(find.text('كل السلاسل'), findsOneWidget);
      await t.tap(find.text('زهران ماركت').last);
      await t.pumpAndSettle();
      expect(_visibleRowUids(t), ['1002', '1007', '1010', '1014']);
      await t.tap(find.byKey(const ValueKey('hr_home_filter_chain')));
      await t.pumpAndSettle();
      await t.tap(find.text('كل السلاسل'));
      await t.pumpAndSettle();
      expect(find.text('1–10 من 14'), findsOneWidget);
    });

    testWidgets('search matches name or code; no match shows a message', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      await t.enterText(find.byKey(const ValueKey('hr_home_search')), 'سارة');
      await t.pump();
      expect(_visibleRowUids(t), ['1007']);
      await t.enterText(
        find.byKey(const ValueKey('hr_home_search')),
        'ts-1013',
      );
      await t.pump();
      expect(_visibleRowUids(t), ['1013']);
      await t.enterText(find.byKey(const ValueKey('hr_home_search')), 'zzz');
      await t.pump();
      expect(find.byKey(const ValueKey('hr_home_no_matches')), findsOneWidget);
    });

    testWidgets('row tap opens the delegate; link opens the attendance log', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data());
      await t.tap(find.byKey(const ValueKey('hr_home_row_1007')));
      expect(_opened.single.delegate.uid, '1007');
      await t.tap(find.byKey(const ValueKey('hr_home_attendance_log_link')));
      expect(_log, ['attendance_log']);
    });
  });

  group('table states', () {
    testWidgets('loading: skeleton and bar only after 300ms, inputs disabled', (
      t,
    ) async {
      t.view.physicalSize = const Size(1440, 2000);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        _app(
          Scaffold(
            body: HrHomeOverviewView(
              data: _data(loading: true, records: const []),
              actions: _actions(),
              clock: () => _clockNow,
            ),
          ),
        ),
      );
      await t.pump(const Duration(milliseconds: 200));
      expect(
        find.byKey(const ValueKey('hr_home_skeleton_row_0')),
        findsNothing,
      );
      expect(
        find.byType(LinearProgressIndicator),
        findsOneWidget,
        reason: 'only the stat bar, no loading bar yet',
      );
      await t.pump(const Duration(milliseconds: 150));
      for (var i = 0; i < 5; i++) {
        expect(find.byKey(ValueKey('hr_home_skeleton_row_$i')), findsOneWidget);
      }
      final bars = t.widgetList<LinearProgressIndicator>(
        find.byType(LinearProgressIndicator),
      );
      expect(bars.where((b) => b.value == null), hasLength(1));
      final total = find.byKey(const ValueKey('hr_home_stat_total'));
      expect(
        find.descendant(of: total, matching: find.text('—')),
        findsOneWidget,
      );
      for (final key in ['all', 'present', 'departed']) {
        final chip = t.widget<FilterChip>(
          find.byKey(ValueKey('hr_home_filter_$key')),
        );
        expect(chip.onSelected, isNull, reason: key);
      }
      final search = t.widget<TextField>(
        find.byKey(const ValueKey('hr_home_search')),
      );
      expect(search.enabled, isFalse);
      final chain = t.widget<PopupMenuButton<String>>(
        find.byKey(const ValueKey('hr_home_filter_chain')),
      );
      expect(chain.enabled, isFalse);
      // Captured mid fade-in: once the fade settles, the test harness drops the
      // retained opacity layer from full-page captures.
      await t.pump(const Duration(milliseconds: 100));
      await expectWebGolden(
        find.byType(MaterialApp),
        'goldens/hr_home_state_loading_1440.png',
      );

      _clockNow = _at(13, 41);
      await _update(t, _data());
      expect(
        find.byKey(const ValueKey('hr_home_skeleton_row_0')),
        findsNothing,
      );
      expect(find.textContaining('آخر تحديث'), findsNothing);
    });

    testWidgets('empty: cookie, message, tonal button, «لسه مسجلوش N»', (
      t,
    ) async {
      await _pumpView(t, const Size(1440, 2000), _data(records: _absentOnly()));
      final empty = find.byKey(const ValueKey('hr_home_empty'));
      expect(empty, findsOneWidget);
      expect(
        find.descendant(of: empty, matching: find.byType(HrExpressiveShape)),
        findsOneWidget,
      );
      final cookie = t.widget<HrExpressiveShape>(
        find.descendant(of: empty, matching: find.byType(HrExpressiveShape)),
      );
      final cs = _theme().colorScheme;
      expect(cookie.color, cs.primaryContainer);
      expect(
        find.descendant(
          of: empty,
          matching: find.byIcon(Icons.schedule_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('لسه محدش سجّل حضور النهاردة'), findsOneWidget);
      final absent = find.byKey(const ValueKey('hr_home_stat_absent'));
      expect(
        find.descendant(of: absent, matching: find.text('لسه مسجلوش')),
        findsOneWidget,
      );
      final n = t.widget<Text>(
        find.descendant(of: absent, matching: find.text('3')),
      );
      expect(n.style!.color, isNot(cs.error));
      expect(
        find.byKey(const ValueKey('hr_home_attendance_table')),
        findsNothing,
      );
      await t.tap(find.byKey(const ValueKey('hr_home_open_delegates')));
      expect(_log, ['delegates']);
      await expectWebGolden(
        find.byType(MaterialApp),
        'goldens/hr_home_state_empty_1440.png',
      );
    });

    testWidgets('error: error-container panel, retry, code, stats «—»', (
      t,
    ) async {
      await _pumpView(
        t,
        const Size(1440, 2000),
        _data(
          error: '[cloud_firestore/permission-denied] Missing permissions',
          records: const [],
        ),
      );
      final cs = _theme().colorScheme;
      final panel = find.byKey(const ValueKey('hr_home_error'));
      expect(_boxColor(t, panel), cs.errorContainer);
      expect(
        find.descendant(
          of: panel,
          matching: find.byIcon(Icons.cloud_off_rounded),
        ),
        findsOneWidget,
      );
      expect(find.text('مقدرناش نحمّل حضور النهاردة'), findsOneWidget);
      expect(find.text('رمز الخطأ: permission-denied'), findsOneWidget);
      for (final key in ['total', 'present', 'absent']) {
        final stat = find.byKey(ValueKey('hr_home_stat_$key'));
        expect(
          find.descendant(of: stat, matching: find.text('—')),
          findsWidgets,
          reason: key,
        );
      }
      await t.tap(find.byKey(const ValueKey('hr_home_retry')));
      expect(_log, ['reload']);
      await expectWebGolden(
        find.byType(MaterialApp),
        'goldens/hr_home_state_error_1440.png',
      );
    });

    testWidgets('error colours appear only in the error state', (t) async {
      final cs = _theme().colorScheme;
      bool usesErrorColour(WidgetTester t) => find
          .byWidgetPredicate((w) {
            if (w is Container) {
              final d = w.decoration;
              if (d is BoxDecoration &&
                  (d.color == cs.errorContainer || d.color == cs.error)) {
                return true;
              }
            }
            if (w is Text) {
              final c = w.style?.color;
              return c == cs.error || c == cs.onErrorContainer;
            }
            if (w is Icon) {
              return w.color == cs.error || w.color == cs.onErrorContainer;
            }
            return false;
          })
          .evaluate()
          .isNotEmpty;
      await _pumpView(t, const Size(1440, 2000), _data());
      expect(usesErrorColour(t), isFalse);
      await _update(t, _data(records: _absentOnly()));
      expect(usesErrorColour(t), isFalse);
      await _update(t, _data(error: 'boom', records: const []));
      expect(usesErrorColour(t), isTrue);
      expect(find.text('رمز الخطأ: HR-ATT-LOAD'), findsOneWidget);
    });
  });

  group('window size classes (web)', () {
    testWidgets('1440: table with the 352 side column beside it', (t) async {
      await _pumpView(t, const Size(1440, 1700), _data());
      final side = find.byKey(const ValueKey('hr_home_side_column'));
      expect(side, findsOneWidget);
      expect(t.getSize(side).width, kHrOverviewSideColumnWidth);
      final card = t.getRect(
        find.byKey(const ValueKey('hr_home_attendance_card')),
      );
      final sideRect = t.getRect(side);
      expect((card.top - sideRect.top).abs(), lessThan(1));
      expect(
        sideRect.right <= card.left,
        isTrue,
        reason: 'RTL: side on the left',
      );
      expect(
        find.byKey(const ValueKey('hr_home_attendance_table')),
        findsOneWidget,
      );
      final chains = t.getRect(
        find.byKey(const ValueKey('hr_home_chains_card')),
      );
      final feature = t.getRect(
        find.byKey(const ValueKey('hr_home_feature_card')),
      );
      final duties = t.getRect(
        find.byKey(const ValueKey('hr_home_duties_card')),
      );
      expect(chains.top < feature.top && feature.top < duties.top, isTrue);
      expect(t.takeException(), isNull);
      await expectWebGolden(
        find.byType(MaterialApp),
        'goldens/hr_home_view_1440.png',
      );
    });

    testWidgets('1000: table, side cards drop below', (t) async {
      await _pumpView(t, const Size(1000, 2200), _data());
      expect(find.byKey(const ValueKey('hr_home_side_column')), findsNothing);
      expect(
        find.byKey(const ValueKey('hr_home_attendance_table')),
        findsOneWidget,
      );
      final card = t.getRect(
        find.byKey(const ValueKey('hr_home_attendance_card')),
      );
      final chains = t.getRect(
        find.byKey(const ValueKey('hr_home_chains_card')),
      );
      expect(chains.top > card.bottom, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('800: one column, first 6 rows, «عرض كل الحاضرين (N)»', (
      t,
    ) async {
      await _pumpView(t, const Size(800, 2600), _data());
      expect(
        find.byKey(const ValueKey('hr_home_attendance_table')),
        findsNothing,
      );
      expect(
        find.byKey(const ValueKey('hr_home_attendance_list')),
        findsOneWidget,
      );
      expect(_visibleRowUids(t), hasLength(6));
      expect(_visibleRowUids(t).first, '1001');
      expect(find.text('عرض كل الحاضرين (14)'), findsOneWidget);
      await t.tap(find.byKey(const ValueKey('hr_home_show_all')));
      await t.pump();
      expect(_visibleRowUids(t), hasLength(14));
      expect(find.text('عرض أقل'), findsOneWidget);
      expect(find.byKey(const ValueKey('hr_home_chip_scroller')), findsNothing);
      final card = t.getRect(
        find.byKey(const ValueKey('hr_home_attendance_card')),
      );
      final chains = t.getRect(
        find.byKey(const ValueKey('hr_home_chains_card')),
      );
      expect(chains.top > card.bottom, isTrue);
      expect(t.takeException(), isNull);
    });

    testWidgets('412: compact stats and horizontally scrolling chips', (
      t,
    ) async {
      await _pumpView(t, const Size(412, 3000), _data());
      expect(
        find.byKey(const ValueKey('hr_home_chip_scroller')),
        findsOneWidget,
      );
      expect(
        find.byKey(const ValueKey('hr_home_attendance_list')),
        findsOneWidget,
      );
      expect(_visibleRowUids(t), hasLength(6));
      final total = find.byKey(const ValueKey('hr_home_stat_total'));
      final value = t.widget<Text>(
        find.descendant(of: total, matching: find.text('18')),
      );
      expect(value.style!.fontSize, 22);
      expect(t.takeException(), isNull);
    });
  });

  group('shell wiring (web)', () {
    test(
      'overview is the web home tab and first sidebar / bottom-bar item',
      () {
        expect(hrShellHomeTab(isWeb: true), kHrTabOverview);
        expect(hrBottomNavTabs(isWeb: true).first, kHrTabOverview);
        final sidebar = hrShellItems(
          delegate: _supervisor,
          isWeb: true,
          placement: HrShellPlacement.sidebar,
        );
        expect(sidebar.first.id, 'overview');
        expect(sidebar.first.title, 'الرئيسية');
        final more = hrShellItems(
          delegate: _supervisor,
          isWeb: true,
          placement: HrShellPlacement.moreSheet,
        ).map((i) => i.id);
        expect(more, isNot(contains('overview')));
        expect(more, contains('attendance'));
        final tab = hrShellTab(
          index: kHrTabOverview,
          delegate: _supervisor,
          onNavigateToTab: (_) {},
        );
        expect(tab, isA<HrHomeOverviewWeb>());
      },
    );

    testWidgets('live host renders the attendance tab through the overview', (
      t,
    ) async {
      t.view.physicalSize = const Size(1440, 2000);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(
        _app(
          Scaffold(
            body: HrHomeOverviewWeb(
              delegate: _supervisor,
              onNavigateToTab: (_) {},
            ),
          ),
        ),
      );
      for (var i = 0; i < 10; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HRAttendanceTab), findsOneWidget);
      expect(
        find.descendant(
          of: find.byType(HRAttendanceTab),
          matching: find.byType(HrHomeOverviewView),
        ),
        findsOneWidget,
      );
      // The fake Firebase app never answers, so the tab stays loading.
      expect(
        find.byKey(const ValueKey('hr_home_skeleton_row_0')),
        findsOneWidget,
      );
    });

    for (final c in <(Size, String)>[
      (const Size(1440, 1400), 'hr_home_shell_1440'),
      (const Size(800, 1400), 'hr_home_shell_800'),
      (const Size(412, 1400), 'hr_home_shell_412'),
    ]) {
      testWidgets('HRMainScreen lands on the overview at ${c.$1.width}', (
        t,
      ) async {
        HrHomeOverviewWeb.debugData = (_) => _data();
        HrHomeOverviewWeb.debugClock = () => _clockNow;
        t.view.physicalSize = c.$1;
        t.view.devicePixelRatio = 1;
        await t.pumpWidget(
          BlocProvider<ThemeCubit>.value(
            value: sl<ThemeCubit>(),
            child: _app(HRMainScreen(delegate: _supervisor)),
          ),
        );
        await t.pump(const Duration(milliseconds: 400));
        expect(find.byType(HrHomeOverviewView), findsOneWidget);
        expect(find.byType(HRAttendanceTab), findsNothing);
        if (c.$1.width <= 768) {
          final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
          expect(bar.selectedIndex, 0);
          expect(find.text('الرئيسية'), findsWidgets);
        } else {
          expect(find.text('الرئيسية'), findsWidgets);
        }
        await expectWebGolden(find.byType(MaterialApp), 'goldens/${c.$2}.png');
      });
    }
    testWidgets(
      'chains «عرض الكل» opens subscriptions on «طلبات السلاسل» (TAS-117)',
      (t) async {
        addTearDown(
          () => DelegateSubscriptionRequestsWeb.requestedTab.value = null,
        );
        HrHomeOverviewWeb.debugData = (_) => HrHomeOverviewData(
          delegate: _supervisor,
          isLoading: false,
          errorMessage: null,
          records: _records(),
          chains: _chains,
          pendingChainRequests: const ['Fake Pending Chain'],
        );
        HrHomeOverviewWeb.debugClock = () => _clockNow;
        t.view.physicalSize = const Size(1440, 900);
        t.view.devicePixelRatio = 1;
        final navigated = <(int, SubscriptionRequestsWebTab?)>[];
        await t.pumpWidget(
          _app(
            Scaffold(
              body: HrHomeOverviewWeb(
                delegate: _supervisor,
                // Record the requested tab at the moment the shell switches,
                // so a kept-alive page already sees it.
                onNavigateToTab: (i) => navigated.add(
                  (i, DelegateSubscriptionRequestsWeb.requestedTab.value),
                ),
              ),
            ),
          ),
        );
        await t.pump(const Duration(milliseconds: 400));

        final all = find.byKey(HrHomeChainsCard.pendingAllKey);
        await t.ensureVisible(all);
        await t.pump();
        await t.tap(all);
        await t.pump();

        expect(navigated, [
          (kHrTabSubscriptions, SubscriptionRequestsWebTab.chains),
        ]);
        expect(t.takeException(), isNull);
      },
    );
  });

  group('mobile path unchanged', () {
    setUp(() => WebRuntimePolicy.debugIsWebOverride = false);

    test('mobile home tab, bottom bar and menus have no overview', () {
      expect(hrShellHomeTab(isWeb: false), kHrTabAttendance);
      expect(hrBottomNavTabs(isWeb: false), [
        kHrTabAttendance,
        kHrTabDelegates,
        kHrTabTracking,
        kHrTabLeaves,
      ]);
      for (final placement in HrShellPlacement.values) {
        final ids = hrShellItems(
          delegate: _hr,
          isWeb: false,
          placement: placement,
        ).map((i) => i.id);
        expect(ids, isNot(contains('overview')), reason: placement.name);
      }
      final tab = hrShellTab(
        index: kHrTabOverview,
        delegate: _hr,
        onNavigateToTab: (_) {},
      );
      expect(tab, isA<SizedBox>());
      final attendance = hrShellTab(
        index: kHrTabAttendance,
        delegate: _hr,
        onNavigateToTab: (_) {},
      );
      expect(attendance, isA<HRAttendanceTab>());
      expect((attendance as HRAttendanceTab).viewBuilder, isNull);
    });

    testWidgets('mobile HRMainScreen opens on attendance, never the overview', (
      t,
    ) async {
      HrHomeOverviewWeb.debugData = (_) => _data();
      t.view.physicalSize = const Size(412, 900);
      t.view.devicePixelRatio = 1;
      await t.pumpWidget(_app(HRMainScreen(delegate: _hr)));
      for (var i = 0; i < 5; i++) {
        await t.pump(const Duration(milliseconds: 100));
      }
      expect(find.byType(HrHomeOverviewView), findsNothing);
      expect(find.byType(HrHomeOverviewWeb), findsNothing);
      expect(find.byType(HRAttendanceTab), findsOneWidget);
      final bar = t.widget<NavigationBar>(find.byType(NavigationBar));
      expect(bar.selectedIndex, 0);
      expect(bar.destinations, hasLength(5));
      expect(find.text('الحضور'), findsWidgets);
      expect(find.text('الرئيسية'), findsNothing);
    });

    test('duty texts keep the mobile guide wording', () {
      final sup = adminHomeDuties(_supervisor, isArabic: true);
      expect(sup.map((d) => d.title), [
        '1. متابعة حضور وانضباط مناديب الشركة:',
        '2. إدارة وتفعيل أذونات التصوير:',
        '3. متابعة وضبط المخالفات والغرامات:',
        '4. توجيه وتكليف مهام العمل:',
      ]);
      final org = adminHomeDuties(
        _person('o', 'مدير', role: UserRole.organizationAdmin),
        isArabic: true,
      );
      expect(org, hasLength(3));
      expect(org.first.title, '1. الإشراف العام على العمليات والفروع:');
    });
  });
}
