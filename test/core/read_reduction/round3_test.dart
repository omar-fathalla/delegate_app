import 'package:battery_plus/battery_plus.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/config/read_reduction_flags.dart';
import 'package:delegate_app/features/marketing/data/datasources/today_attendance_query.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_live_refresh_controller.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:geolocator/geolocator.dart';
import 'package:mocktail/mocktail.dart';

class _MockTracking extends Mock implements DelegateTrackingService {}

class _MockBattery extends Mock implements Battery {}

Position _pos(double lat, double lng) => Position(
  latitude: lat,
  longitude: lng,
  timestamp: DateTime(2026, 11, 3),
  accuracy: 5,
  altitude: 0,
  altitudeAccuracy: 0,
  heading: 0,
  headingAccuracy: 0,
  speed: 0,
  speedAccuracy: 0,
);

/// Probe using the same mixin + controller wiring as BranchHomeScreen.
class _LiveProbe extends StatefulWidget {
  const _LiveProbe({required this.isActive, required this.log});
  final ValueListenable<bool>? isActive;
  final List<String> log;
  @override
  State<_LiveProbe> createState() => _LiveProbeState();
}

class _LiveProbeState extends State<_LiveProbe>
    with LiveTabVisibility<_LiveProbe> {
  BranchLiveRefreshController? live;

  @override
  ValueListenable<bool>? get liveActiveListenable => widget.isActive;

  @override
  void onLiveVisibilityChanged() => _sync();

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _sync();
  }

  void _sync() {
    if (liveTabVisible && live == null) {
      live = BranchLiveRefreshController(
        watch: () => const Stream<int>.empty(),
        onReload: ({required bool force}) {},
        onMidnight: () {},
        branchKeyBackfilled: () => false,
      )..start();
      widget.log.add('start');
    } else if (!liveTabVisible && live != null) {
      live!.stop();
      live = null;
      widget.log.add('stop');
    }
  }

  @override
  void dispose() {
    live?.stop();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => const SizedBox();
}

void main() {
  group('bug 2: generated legacy variants', () {
    test('cover «الابراهيميه» and every alef/ة/ى combination', () {
      final v = legacyBranchNameVariants('الإبراهيمية');
      expect(
        v,
        containsAll(<String>[
          'الإبراهيمية',
          'الابراهيميه', // previously missing
          'الابراهيمية',
          'الأبراهيميه',
          'الإبراهيميه',
        ]),
      );
      expect(
        legacyBranchNameVariants('فرع المعادي'),
        containsAll(['فرع المعادي', 'فرع المعادى']),
      );
      expect(
        legacyBranchNameVariants('أسيوط'),
        containsAll(['أسيوط', 'اسيوط', 'إسيوط', 'آسيوط']),
      );
      expect(legacyBranchNameVariants('  '), isEmpty);
    });

    test('variants are capped and chunked within whereIn limits', () {
      final long = List.filled(8, 'احمد').join(' ');
      expect(
        legacyBranchNameVariants(long).length,
        lessThanOrEqualTo(kMaxLegacyVariantsPerBranch + 2),
      );
      for (final c in chunkList(
        legacyBranchNameVariants(long).toList(),
        kBranchWhereInChunkSize,
      )) {
        expect(c.length, lessThanOrEqualTo(20));
      }
    });

    test('legacy-only path finds the «الابراهيميه» spelling', () async {
      final db = FakeFirebaseFirestore();
      await db.collection('rr3').doc('x').set({
        'organizationId': 'o',
        'branchName': 'الابراهيميه',
        'timestamp': Timestamp.fromDate(DateTime(2026, 11, 3, 9)),
      });
      final r = await fetchTodayAttendanceDocs(
        firestore: db,
        branchNames: const ['الإبراهيمية'],
        organizationId: 'o',
        dayStart: DateTime(2026, 11, 3),
        dayEnd: DateTime(2026, 11, 4),
        flags: ReadReductionFlags.fixed(),
        collection: 'rr3',
      );
      expect(r.docs.map((d) => d.id), ['x']);
    });
  });

  group('bug 3: every tracking write goes through the predicate', () {
    late _MockTracking svc;
    late DelegateTrackingEngine engine;

    setUp(() {
      svc = _MockTracking();
      final battery = _MockBattery();
      when(() => battery.batteryLevel).thenAnswer((_) async => 80);
      when(
        () => svc.updateLocationAndCheckGeofence(
          delegateId: any(named: 'delegateId'),
          currentLat: any(named: 'currentLat'),
          currentLng: any(named: 'currentLng'),
          speed: any(named: 'speed'),
          batteryLevel: any(named: 'batteryLevel'),
          isMoving: any(named: 'isMoving'),
          isMocked: any(named: 'isMocked'),
        ),
      ).thenAnswer((_) async {});
      when(
        () => svc.syncOfflineBreadcrumbsOnReconnect(
          delegateId: any(named: 'delegateId'),
        ),
      ).thenAnswer((_) async {});
      engine = DelegateTrackingEngine(trackingService: svc, battery: battery)
        ..debugActivate('d1');
    });

    test('heartbeat default is 90 s', () {
      expect(kTrackingHeartbeatInterval, const Duration(seconds: 90));
    });

    test('parked device: second ping within 90 s is skipped', () async {
      final now = DateTime.now();
      expect(await engine.handlePositionIfDue(_pos(30, 31), now: now), isTrue);
      expect(
        await engine.handlePositionIfDue(
          _pos(30, 31),
          now: now.add(const Duration(seconds: 30)),
        ),
        isFalse,
      );
      // Heartbeat tick a few ms early still counts (slack).
      expect(
        await engine.handlePositionIfDue(
          _pos(30, 31),
          now: now.add(const Duration(seconds: 89)),
        ),
        isTrue,
      );
    });

    test('moved >= 50 m sends immediately', () async {
      final now = DateTime.now();
      await engine.handlePositionIfDue(_pos(30, 31), now: now);
      expect(
        await engine.handlePositionIfDue(
          _pos(30.001, 31),
          now: now.add(const Duration(seconds: 5)),
        ),
        isTrue,
      );
    });
  });

  group('rollover', () {
    test('shouldRollOverToToday', () {
      final now = DateTime(2026, 11, 4, 0, 0, 2);
      expect(
        shouldRollOverToToday(
          followToday: true,
          selected: DateTime(2026, 11, 3, 22),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldRollOverToToday(
          followToday: false,
          selected: DateTime(2026, 11, 3, 22),
          now: now,
        ),
        isFalse,
        reason: 'browsing a past date stays put',
      );
      expect(
        shouldRollOverToToday(
          followToday: true,
          selected: DateTime(2026, 11, 4, 0),
          now: now,
        ),
        isFalse,
      );
    });
  });

  testWidgets('minor 3: safety net is skipped while error poll is active', (
    tester,
  ) async {
    final reloads = <bool>[];
    final c = BranchLiveRefreshController(
      watch: () => Stream<int>.error(
        FirebaseException(plugin: 'x', code: 'failed-precondition'),
      ),
      onReload: ({required bool force}) => reloads.add(force),
      onMidnight: () {},
      branchKeyBackfilled: () => false,
    )..start();
    await tester.pump();
    await tester.pump(const Duration(minutes: 15));
    expect(reloads.every((f) => f), isTrue, reason: 'no non-forced reloads');
    expect(reloads, hasLength(5));
    c.stop();
  });

  testWidgets('bug 1: hidden IndexedStack tab stops the live controller '
      '(no TickerMode from IndexedStack)', (tester) async {
    final log = <String>[];
    final active = ValueNotifier<bool>(true);
    Widget shell(int index) => MaterialApp(
      home: M3FadeThroughIndexedStack(
        index: index,
        lazy: false,
        children: [
          _LiveProbe(isActive: active, log: log),
          const Text('other tab'),
        ],
      ),
    );
    await tester.pumpWidget(shell(0));
    expect(log, ['start']);
    // Shell switches tab and flips isActive (as marketing/admin shells do).
    active.value = false;
    await tester.pumpWidget(shell(1));
    await tester.pumpAndSettle();
    expect(log, ['start', 'stop']);
    active.value = true;
    await tester.pumpWidget(shell(0));
    await tester.pumpAndSettle();
    expect(log, ['start', 'stop', 'start']);
    await tester.pumpWidget(const SizedBox());
    active.dispose();
  });
}
