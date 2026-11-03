import 'package:delegate_app/features/marketing/presentation/pages/branch_live_refresh_controller.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Probe mirroring BranchHomeScreen's visibility wiring, including the
/// route-cover path in didChangeDependencies.
class _RouteProbe extends StatefulWidget {
  const _RouteProbe({required this.isActive, required this.db});
  final ValueListenable<bool> isActive;
  final FakeFirebaseFirestore db;
  @override
  State<_RouteProbe> createState() => _RouteProbeState();
}

class _RouteProbeState extends State<_RouteProbe>
    with LiveTabVisibility<_RouteProbe> {
  int loads = 0;
  int records = 0;
  DateTime? lastSync;
  bool _lastVisible = true;
  final List<bool> tickerHistory = [];
  DateTime Function() clock = DateTime.now;

  @override
  ValueListenable<bool>? get liveActiveListenable => widget.isActive;

  @override
  void initState() {
    super.initState();
    _load();
  }

  Future<void> _load() async {
    loads++;
    final snap = await widget.db.collection('attendance').get();
    lastSync = clock();
    if (mounted) setState(() => records = snap.docs.length);
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    tickerHistory.add(TickerMode.valuesOf(context).enabled);
    if (liveTabVisible != _lastVisible) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (mounted) onLiveVisibilityChanged();
      });
    }
  }

  @override
  void onLiveVisibilityChanged() {
    final visible = liveTabVisible;
    if (visible == _lastVisible) return;
    final reload = shouldReloadOnShow(
      wasVisible: _lastVisible,
      isVisible: visible,
      lastSync: lastSync,
      now: clock(),
    );
    _lastVisible = visible;
    if (reload) _load();
  }

  @override
  Widget build(BuildContext context) => Text('records:$records');
}

void main() {
  testWidgets('TickerMode turns off under a pushed MaterialPageRoute; '
      'pop after 45 s reloads', (tester) async {
    final db = FakeFirebaseFirestore();
    final active = ValueNotifier<bool>(true);
    final navKey = GlobalKey<NavigatorState>();
    await tester.pumpWidget(
      MaterialApp(
        navigatorKey: navKey,
        home: Scaffold(
          body: _RouteProbe(isActive: active, db: db),
        ),
      ),
    );
    await tester.pump();
    final state = tester.state<_RouteProbeState>(find.byType(_RouteProbe));
    expect(state.loads, 1);
    expect(find.text('records:0'), findsOneWidget);

    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('details')),
    );
    await tester.pumpAndSettle();
    // Verification: TickerMode is disabled for the covered screen.
    expect(state.tickerHistory.last, isFalse);
    expect(state.liveTabVisible, isFalse);

    await db.collection('attendance').add({'branchName': 'x'});
    var fakeNow = DateTime.now().add(const Duration(seconds: 45));
    state.clock = () => fakeNow;

    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(state.tickerHistory.last, isTrue);
    expect(state.loads, 2);
    expect(find.text('records:1', skipOffstage: false), findsOneWidget);

    // Quick push/pop within 30 s → no extra reload.
    navKey.currentState!.push(
      MaterialPageRoute<void>(builder: (_) => const Text('details')),
    );
    await tester.pumpAndSettle();
    fakeNow = fakeNow.add(const Duration(seconds: 5));
    navKey.currentState!.pop();
    await tester.pumpAndSettle();
    expect(state.loads, 2);
  });
}
