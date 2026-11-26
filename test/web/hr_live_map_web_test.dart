// HR web «الخريطة الحية» (TAS-148), fake data only.
// One refresh (the shell's), the map opens on the company's branches with a
// message when nobody is checked in, an M3 SegmentedButton (height 40), and
// one KPI card style in the list. Mobile keeps the original controls.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:delegate_app/core/utils/google_maps_loader.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:delegate_app/features/tracking/presentation/pages/delegate_tracking_screen.dart';
import 'package:delegate_app/features/tracking/presentation/widgets/tracking_live_map_view.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

const _co = 'seed-fake-co';
const _org = 'seed-fake-org';

Delegate _hr() => Delegate(
  uid: 'seed-fake-hr',
  firstName: 'مسؤول',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'مسؤول تجريبي',
  nationalityID: '',
  motherName: '',
  city: '',
  phoneNumber: '',
  gender: DelegateGender.male,
  position: DelegatePosition.promoter,
  birthDate: DateTime(1990),
  organizationUID: _org,
  organizationName: 'سلسلة تجريبية',
  companyUID: _co,
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
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
  role: UserRole.hr,
);

/// A session from a past day: not live, but it carries the branch.
Map<String, dynamic> _pastSession(String id, String branch, double lat) => {
  'delegateId': id,
  'delegateName': 'مندوب $id',
  'companyUID': _co,
  'companyId': _co,
  'organizationId': _org,
  'branchName': branch,
  'branchLat': lat,
  'branchLng': 31.2,
  'geofenceRadius': 150,
  'currentStatus': 'checked_out',
  'checkInTime': Timestamp.fromDate(DateTime(2026, 1, 1, 9)),
  'checkOutTime': Timestamp.fromDate(DateTime(2026, 1, 1, 17)),
};

Map<String, dynamic> _liveSession(String id, String status) => {
  'delegateId': id,
  'delegateName': 'مندوب $id',
  'companyUID': _co,
  'companyId': _co,
  'organizationId': _org,
  'branchName': 'فرع المعادي',
  'branchLat': 29.96,
  'branchLng': 31.25,
  'currentStatus': status,
  'isTrackingEnabled': true,
  'checkInTime': Timestamp.fromDate(DateTime.now()),
};

Future<FakeFirebaseFirestore> _db(List<Map<String, dynamic>> docs) async {
  final db = FakeFirebaseFirestore();
  for (final d in docs) {
    await db.collection('delegate_tracking').doc(d['delegateId']).set(d);
  }
  return db;
}

Widget _app(Widget child, {HrWebHeaderBridge? bridge}) {
  final body = bridge == null
      ? child
      : HrWebHeaderBridgeScope(bridge: bridge, child: child);
  return MaterialApp(
    locale: const Locale('ar'),
    localizationsDelegates: appLocalizationsDelegates,
    supportedLocales: AppLocalizations.supportedLocales,
    home: body,
  );
}

Future<void> _setDesktop(WidgetTester tester) async {
  tester.view.physicalSize = const Size(1440, 900);
  tester.view.devicePixelRatio = 1.0;
  addTearDown(tester.view.resetPhysicalSize);
  addTearDown(tester.view.resetDevicePixelRatio);
}

/// Lets the stream deliver, then drains the maps-availability poll.
Future<void> _settle(WidgetTester tester) async {
  for (var i = 0; i < 5; i++) {
    await tester.pump(const Duration(milliseconds: 50));
  }
}

Future<void> _drain(WidgetTester tester) async {
  await tester.pumpWidget(const SizedBox.shrink());
  await tester.pump(const Duration(seconds: 30));
}

Finder _inScreen(Finder f) =>
    find.descendant(of: find.byType(DelegateTrackingScreen), matching: f);

void main() {
  setUpAll(CairoClock.ensureInitialized);
  setUp(() {
    googleMapsAvailabilityOverride = () => false;
    googleMapsReloadOverride = () {};
  });
  tearDown(() {
    googleMapsAvailabilityOverride = null;
    googleMapsReloadOverride = null;
    WebRuntimePolicy.debugReset();
  });

  group('HR web shell', () {
    setUp(() => WebRuntimePolicy.debugIsWebOverride = true);

    testWidgets(
      'no refresh in the page, segmented switch 40 high, empty map message '
      'with the company branches',
      (tester) async {
        await _setDesktop(tester);
        final db = await _db([
          _pastSession('a', 'فرع مدينة نصر', 30.05),
          _pastSession('b', 'فرع الدقي', 30.03),
        ]);
        await tester.pumpWidget(
          _app(
            DelegateTrackingScreen(
              adminDelegate: _hr(),
              initialMapView: true,
              showAppBar: false,
              hrWebShell: true,
              trackingService: DelegateTrackingService(firestore: db),
            ),
          ),
        );
        await _settle(tester);

        expect(
          find.byKey(const ValueKey('tracking_hr_web_bar')),
          findsOneWidget,
        );
        expect(_inScreen(find.byIcon(Icons.sync_rounded)), findsNothing);
        expect(_inScreen(find.byIcon(Icons.refresh_rounded)), findsNothing);
        expect(find.byType(TashilConnectedButtonGroup<bool>), findsNothing);

        final segmented = find.byKey(const ValueKey('tracking_view_switch'));
        expect(segmented, findsOneWidget);
        expect(tester.getSize(segmented).height, 40);

        final empty = find.byKey(const ValueKey('tracking_map_empty'));
        expect(empty, findsOneWidget);
        expect(find.text('لا يوجد مناديب حاضرون الآن'), findsOneWidget);
        expect(
          find.textContaining('تظهر فروع الشركة على الخريطة'),
          findsOneWidget,
        );

        final map = tester.widget<TrackingLiveMapView>(
          find.byType(TrackingLiveMapView),
        );
        expect(map.showRefreshControls, isFalse);
        expect(
          map.branches.map((b) => b.branchName),
          unorderedEquals(['فرع مدينة نصر', 'فرع الدقي']),
        );
        await _drain(tester);
      },
    );

    testWidgets('the shell refresh reaches the page through the bridge', (
      tester,
    ) async {
      await _setDesktop(tester);
      final bridge = HrWebHeaderBridge();
      addTearDown(bridge.dispose);
      final db = await _db(const []);
      await tester.pumpWidget(
        _app(
          DelegateTrackingScreen(
            adminDelegate: _hr(),
            initialMapView: true,
            showAppBar: false,
            hrWebShell: true,
            trackingService: DelegateTrackingService(firestore: db),
          ),
          bridge: bridge,
        ),
      );
      await _settle(tester);

      final reload = bridge.pageReload(kHrTabTracking);
      expect(reload, isNotNull);
      await tester.runAsync(reload!);
      await _settle(tester);
      expect(find.byKey(const ValueKey('tracking_syncing')), findsNothing);

      await _drain(tester);
      expect(bridge.pageReload(kHrTabTracking), isNull);
    });

    testWidgets('list KPI cards share one style; status chips in the bar', (
      tester,
    ) async {
      await _setDesktop(tester);
      final db = await _db([
        _liveSession('a', 'inside'),
        _liveSession('b', 'outside'),
      ]);
      await tester.pumpWidget(
        _app(
          DelegateTrackingScreen(
            adminDelegate: _hr(),
            initialMapView: true,
            showAppBar: false,
            hrWebShell: true,
            trackingService: DelegateTrackingService(firestore: db),
          ),
        ),
      );
      await _settle(tester);

      expect(find.byKey(const ValueKey('tracking_map_empty')), findsNothing);
      expect(find.byType(HrStatusChip), findsNWidgets(2));

      await tester.tap(find.text('قائمة تفصيلية (2)'));
      await _settle(tester);

      // «الإجمالي» is the selected filter; the other four are unselected.
      const keys = ['tracking_active', 'inside', 'outside', 'offline'];
      final cards = [
        for (final k in keys)
          tester.widget<Material>(find.byKey(ValueKey('tracking_kpi_$k'))),
      ];
      final colors = cards.map((m) => m.color).toSet();
      final borders = cards
          .map((m) => (m.shape! as RoundedRectangleBorder).side.color)
          .toSet();
      expect(colors, hasLength(1));
      expect(borders, hasLength(1));
      expect(_inScreen(find.byIcon(Icons.sync_rounded)), findsNothing);
      await _drain(tester);
    });
  });

  testWidgets('mobile keeps its own switch and refresh buttons', (
    tester,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    await _setDesktop(tester);
    final db = await _db(const []);
    await tester.pumpWidget(
      _app(
        DelegateTrackingScreen(
          adminDelegate: _hr(),
          initialMapView: true,
          showAppBar: false,
          hrWebShell: true,
          trackingService: DelegateTrackingService(firestore: db),
        ),
      ),
    );
    await _settle(tester);

    expect(find.byType(TashilConnectedButtonGroup<bool>), findsOneWidget);
    expect(find.byKey(const ValueKey('tracking_hr_web_bar')), findsNothing);
    expect(find.byKey(const ValueKey('tracking_map_empty')), findsNothing);
    final map = tester.widget<TrackingLiveMapView>(
      find.byType(TrackingLiveMapView),
    );
    expect(map.showRefreshControls, isTrue);
    expect(map.branches, isEmpty);
    await _drain(tester);
  });

  test('TrackingMapBranch.fromSessions keeps one pin per named branch', () {
    DelegateTrackingSession s(String branch, double lat) =>
        DelegateTrackingSession(
          delegateId: '$branch$lat',
          delegateName: 'x',
          delegatePhone: '',
          companyId: _co,
          organizationId: _org,
          branchId: '',
          branchName: branch,
          branchLat: lat,
          branchLng: lat == 0 ? 0 : 31.2,
          geofenceRadius: 100,
          isTrackingEnabled: false,
          currentStatus: TrackingStatus.offline,
          currentDistanceMeters: 0,
          lastUpdated: DateTime(2026),
        );
    final branches = TrackingMapBranch.fromSessions([
      s('فرع أ', 30.0),
      s('فرع أ', 30.1),
      s('فرع ب', 0),
      s('', 30.2),
      s('فرع ج', 30.3),
    ]);
    expect(branches.map((b) => b.branchName), ['فرع أ', 'فرع ج']);
    expect(branches.first.latitude, 30.0);
  });
}
