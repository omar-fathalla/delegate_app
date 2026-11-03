// Desktop attendance table (web-only) with fake data + mobile tab unchanged.
import 'dart:io';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/admin_desktop/admin_desktop_attendance_web.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:intl/date_symbol_data_local.dart';

Delegate _d(String uid, String name) => Delegate(
      uid: uid, firstName: name, middleName: '', lastName: '',
      fullName: name, nationalityID: '', motherName: '', city: 'Cairo',
      phoneNumber: '010$uid', gender: DelegateGender.male,
      position: DelegatePosition.supervisor, birthDate: DateTime(1990),
      organizationUID: 'org', organizationName: 'energizer', companyUID: 'c',
      companyName: 'energizer', status: DelegateStatus.active,
      delegatePublicId: 'X$uid', allReceiptCodes: const [], createdAt: DateTime(2024),
      createdBy: 't', hasPendingUpdate: false, isDeductedFromCompany: false,
      isPrinted: false, isProfileComplete: true, numberOfDocuments: 0,
      paymentAmount: 0, version: 1, documents: const [], role: UserRole.delegate,
    );

final _day = DateTime(2026, 11, 2);
final _records = [
  HRAttendanceRecord(delegate: _d('1', 'أحمد علي'), branchName: 'فرع المعادي',
      checkInTime: _day.add(const Duration(hours: 9, minutes: 2))),
  HRAttendanceRecord(delegate: _d('2', 'محمد حسن'), branchName: 'فرع مدينة نصر',
      checkInTime: _day.add(const Duration(hours: 8, minutes: 55)),
      checkOutTime: _day.add(const Duration(hours: 17, minutes: 10))),
  HRAttendanceRecord(delegate: _d('3', 'سارة محمود'), branchName: 'فرع الدقي'),
  HRAttendanceRecord(delegate: _d('4', 'منى سعيد'), branchName: 'فرع الزمالك',
      isOnApprovedLeave: true),
];

final _log = <String>[];
HRAttendanceViewData _data() => HRAttendanceViewData(
      isLoading: false, errorMessage: null, selectedDate: _day, isToday: false,
      statusFilter: 'all', selectedChain: 'all', selectedBranch: 'all',
      chains: {'energizer'}, branches: {'فرع المعادي', 'فرع الدقي'},
      records: _records, searchController: TextEditingController(),
      onSearchChanged: () => _log.add('search'),
      onDateChanged: (d) => _log.add('date:${d.day}'),
      onStatusChanged: (v) => _log.add('status:$v'),
      onChainChanged: (v) => _log.add('chain:$v'),
      onBranchChanged: (v) => _log.add('branch:$v'),
      onRefresh: () async => _log.add('refresh'),
    );

Future<void> _fonts() async {
  final cairo = FontLoader('Cairo')
    ..addFont(rootBundle.load('assets/fonts/Cairo/Cairo-Regular.ttf'));
  await cairo.load();
  final mi = FontLoader('MaterialIcons')
    ..addFont(Future.value(ByteData.sublistView(File('${Platform.environment['FLUTTER_ROOT']}/bin/cache/artifacts/material_fonts/MaterialIcons-Regular.otf').readAsBytesSync())));
  await mi.load();
  final sym = FontLoader('packages/material_symbols_icons/MaterialSymbolsRounded')
    ..addFont(rootBundle.load('packages/material_symbols_icons/lib/fonts/MaterialSymbolsRounded.ttf'));
  await sym.load();
  await initializeDateFormatting('ar');
}

Future<void> _pump(WidgetTester t, Size size, ThemeData theme, Widget home) async {
  t.view.physicalSize = size;
  t.view.devicePixelRatio = 1;
  await t.pumpWidget(MaterialApp(
    debugShowCheckedModeBanner: false,
    theme: theme.copyWith(textTheme: theme.textTheme.apply(fontFamily: 'Cairo')),
    localizationsDelegates: AppLocalizations.localizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    locale: const Locale('ar'),
    home: Scaffold(body: home),
  ));
  for (var i = 0; i < 10; i++) {
    await t.pump(const Duration(milliseconds: 100));
  }
}

void main() {
  setUpAll(_fonts);
  tearDown(() {
    final b = TestWidgetsFlutterBinding.instance;
    b.platformDispatcher.views.first.resetPhysicalSize();
    b.platformDispatcher.views.first.resetDevicePixelRatio();
  });

  testWidgets('mobile tab (no viewBuilder) renders as before', (t) async {
    await _pump(t, const Size(390, 844), AppTheme.lightTheme(),
        HRAttendanceTab(hrDelegate: _d('sup', 'مشرف')));
    expect(find.byType(AttendanceDesktopTableWeb), findsNothing);
    await expectLater(find.byType(HRAttendanceTab),
        matchesGoldenFile('goldens/attendance_mobile_390_light.png'));
  });

  testWidgets('viewBuilder receives the tab state read-only', (t) async {
    HRAttendanceViewData? got;
    await _pump(t, const Size(1280, 800), AppTheme.lightTheme(),
        HRAttendanceTab(hrDelegate: _d('sup', 'مشرف'), viewBuilder: (c, d) {
          got = d;
          return const SizedBox();
        }));
    expect(got, isNotNull);
    expect(got!.statusFilter, 'all');
    expect(got!.selectedChain, 'all');
    expect(got!.selectedBranch, 'all');
  });

  testWidgets('desktop table 1280 light', (t) async {
    _log.clear();
    await _pump(t, const Size(1280, 800), AppTheme.lightTheme(),
        AttendanceDesktopTableWeb(data: _data()));
    for (final h in ['المندوب', 'الدخول', 'الخروج', 'الحالة']) {
      expect(find.text(h), findsOneWidget);
    }
    expect(find.byType(DataRow), findsNothing); // DataRow isn't a widget
    expect(find.text('سارة محمود'), findsOneWidget);
    final absent = t.widget<Container>(find.ancestor(
        of: find.text('غائب').last, matching: find.byType(Container)).first);
    expect((absent.decoration as BoxDecoration).color,
        AppTheme.lightTheme().colorScheme.errorContainer);
    await expectLater(find.byType(AttendanceDesktopTableWeb),
        matchesGoldenFile('goldens/attendance_desktop_1280_light.png'));
    await t.tap(find.text('حاضر').first);
    await t.pump();
    expect(_log, contains('status:present'));
    await t.tap(find.byTooltip('اليوم السابق'));
    expect(_log, contains('date:1'));
  });

  testWidgets('date button has a fixed width (I-11: no header reflow)', (t) async {
    await _pump(t, const Size(1280, 800), AppTheme.lightTheme(),
        AttendanceDesktopTableWeb(data: _data()));
    final r = t.getSize(find.byKey(const ValueKey('attendance_date_button')));
    expect(r.width, 230);
  });

  testWidgets('desktop table 1600 dark', (t) async {
    await _pump(t, const Size(1600, 900), AppTheme.darkTheme(),
        AttendanceDesktopTableWeb(data: _data()));
    await expectLater(find.byType(AttendanceDesktopTableWeb),
        matchesGoldenFile('goldens/attendance_desktop_1600_dark.png'));
  });
}
