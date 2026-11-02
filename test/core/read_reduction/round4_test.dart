import 'package:delegate_app/features/marketing/presentation/pages/branch_live_refresh_controller.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

/// Probe mirroring BranchHomeScreen.onLiveVisibilityChanged: reload on a
/// hidden → visible flip when the last load is older than 30 s.
class _ReloadProbe extends StatefulWidget {
  const _ReloadProbe({required this.isActive, required this.db});
  final ValueListenable<bool> isActive;
  final FakeFirebaseFirestore db;
  @override
  State<_ReloadProbe> createState() => _ReloadProbeState();
}

class _ReloadProbeState extends State<_ReloadProbe>
    with LiveTabVisibility<_ReloadProbe> {
  int loads = 0;
  int records = 0;
  DateTime? lastSync;
  bool _lastVisible = true;
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
  void onLiveVisibilityChanged() {
    final visible = liveTabVisible;
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
  Widget build(BuildContext context) =>
      Text('records:$records', textDirection: TextDirection.ltr);
}

void main() {
  group('shouldReloadOnShow', () {
    final now = DateTime(2026, 11, 3, 12);
    test('reloads on flip when stale or never loaded', () {
      expect(
        shouldReloadOnShow(
          wasVisible: false,
          isVisible: true,
          lastSync: now.subtract(const Duration(seconds: 31)),
          now: now,
        ),
        isTrue,
      );
      expect(
        shouldReloadOnShow(
          wasVisible: false,
          isVisible: true,
          lastSync: null,
          now: now,
        ),
        isTrue,
      );
    });
    test('no reload when fresh, hiding, or already visible', () {
      final fresh = now.subtract(const Duration(seconds: 10));
      expect(
        shouldReloadOnShow(
          wasVisible: false,
          isVisible: true,
          lastSync: fresh,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldReloadOnShow(
          wasVisible: true,
          isVisible: false,
          lastSync: null,
          now: now,
        ),
        isFalse,
      );
      expect(
        shouldReloadOnShow(
          wasVisible: true,
          isVisible: true,
          lastSync: null,
          now: now,
        ),
        isFalse,
      );
    });
  });

  testWidgets('hide, add record, show after 30 s → reload shows it', (
    tester,
  ) async {
    final db = FakeFirebaseFirestore();
    final active = ValueNotifier<bool>(true);
    await tester.pumpWidget(_ReloadProbe(isActive: active, db: db));
    await tester.pump();
    final state = tester.state<_ReloadProbeState>(find.byType(_ReloadProbe));
    expect(state.loads, 1);
    expect(find.text('records:0'), findsOneWidget);

    active.value = false;
    await tester.pump();
    await db.collection('attendance').add({'branchName': 'x'});
    var fakeNow = DateTime.now().add(const Duration(seconds: 45));
    state.clock = () => fakeNow;

    active.value = true;
    await tester.pump();
    await tester.pump();
    expect(state.loads, 2);
    expect(find.text('records:1'), findsOneWidget);

    // Quick hide/show within 30 s → no extra reload.
    active.value = false;
    await tester.pump();
    fakeNow = fakeNow.add(const Duration(seconds: 5));
    active.value = true;
    await tester.pump();
    expect(state.loads, 2);
  });
}
