import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:flutter/widgets.dart';

/// Read-reduction Phase 1 (review fixes): timers around the branch screen's
/// today-only attendance listener, kept out of the widget so they can be
/// tested with fake time.
///
/// While [start]ed it:
/// * listens to [watch] and debounces change bursts into one
///   `onReload(force: true)` after [debounce];
/// * on a listener error (e.g. missing index) drops the listener and falls
///   back to `onReload(force: true)` every [errorFallbackInterval];
/// * while [branchKeyBackfilled] is false, also runs a slow safety-net
///   `onReload(force: false)` every [safetyNetInterval] so check-ins from old
///   app versions (no `branchKey`, invisible to the listener) still appear;
/// * fires [onMidnight] once at the next local midnight, then reschedules.
class BranchLiveRefreshController {
  BranchLiveRefreshController({
    required this.watch,
    required this.onReload,
    required this.onMidnight,
    required this.branchKeyBackfilled,
    this.debounce = const Duration(seconds: 10),
    this.errorFallbackInterval = const Duration(minutes: 3),
    this.safetyNetInterval = const Duration(minutes: 5),
    DateTime Function()? clock,
  }) : _clock = clock ?? DateTime.now;

  final Stream<int> Function() watch;
  final void Function({required bool force}) onReload;
  final VoidCallback onMidnight;
  final bool Function() branchKeyBackfilled;
  final Duration debounce;
  final Duration errorFallbackInterval;
  final Duration safetyNetInterval;
  final DateTime Function() _clock;

  StreamSubscription<int>? _sub;
  Timer? _debounce;
  Timer? _errorFallback;
  Timer? _safetyNet;
  Timer? _midnight;

  bool get isRunning => _midnight != null;
  @visibleForTesting
  bool get inErrorFallback => _errorFallback != null;
  @visibleForTesting
  bool get hasSafetyNet => _safetyNet != null;

  static Duration untilNextMidnight(DateTime now) {
    final next = DateTime(now.year, now.month, now.day + 1);
    return next.difference(now);
  }

  void start() {
    stop();
    _sub = watch().listen(
      (_) {
        _debounce?.cancel();
        _debounce = Timer(debounce, () => onReload(force: true));
      },
      onError: (Object e) {
        debugPrint('branch live listener failed, polling instead: $e');
        _sub?.cancel();
        _sub = null;
        _debounce?.cancel();
        _errorFallback ??= Timer.periodic(
          errorFallbackInterval,
          (_) => onReload(force: true),
        );
      },
    );
    if (!branchKeyBackfilled()) {
      _safetyNet = Timer.periodic(safetyNetInterval, (_) {
        // The 3 min error poll already reloads (forced); don't double up.
        if (_errorFallback != null) return;
        onReload(force: false);
      });
    }
    _scheduleMidnight();
  }

  void _scheduleMidnight() {
    _midnight?.cancel();
    // +1 s so "today" has definitely rolled over when the callback runs.
    _midnight = Timer(
      untilNextMidnight(_clock()) + const Duration(seconds: 1),
      () {
        _midnight = null;
        onMidnight();
        // onMidnight usually restarts us; if not, keep the day roll-over.
        if (_midnight == null && _sub != null) _scheduleMidnight();
      },
    );
  }

  void stop() {
    _sub?.cancel();
    _sub = null;
    _debounce?.cancel();
    _debounce = null;
    _errorFallback?.cancel();
    _errorFallback = null;
    _safetyNet?.cancel();
    _safetyNet = null;
    _midnight?.cancel();
    _midnight = null;
  }
}

/// True when a screen that was following "today" should jump to the new day
/// (midnight passed while open, or the app resumes on a later day).
bool shouldRollOverToToday({
  required bool followToday,
  required DateTime selected,
  required DateTime now,
}) =>
    followToday &&
    (selected.year != now.year ||
        selected.month != now.month ||
        selected.day != now.day);

/// Tab-visibility for screens hosted in an `IndexedStack`.
///
/// `TickerMode` alone is not enough: Flutter's `IndexedStack` hides children
/// with `Visibility(maintainAnimation: true)`, which inserts no `TickerMode`,
/// so an offstage tab still reports "enabled". Hosting shells therefore pass
/// an explicit [liveActiveListenable] (true only while the tab is selected);
/// `TickerMode` is still honoured for routes/offstage widgets that set it.
mixin LiveTabVisibility<T extends StatefulWidget> on State<T> {
  ValueListenable<bool>? _attached;
  bool _tickerEnabled = true;

  /// Supplied by the hosting shell; null means "always active" (e.g. pushed
  /// as its own route).
  ValueListenable<bool>? get liveActiveListenable;

  /// Called whenever [liveTabVisible] may have changed.
  void onLiveVisibilityChanged();

  bool get liveTabVisible => (_attached?.value ?? true) && _tickerEnabled;

  void _attach() {
    final next = liveActiveListenable;
    if (identical(next, _attached)) return;
    _attached?.removeListener(onLiveVisibilityChanged);
    _attached = next;
    _attached?.addListener(onLiveVisibilityChanged);
  }

  @override
  void initState() {
    super.initState();
    _attach();
  }

  @override
  void didUpdateWidget(covariant T oldWidget) {
    super.didUpdateWidget(oldWidget);
    final before = liveTabVisible;
    _attach();
    if (before != liveTabVisible) onLiveVisibilityChanged();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _tickerEnabled = TickerMode.valuesOf(context).enabled;
  }

  @override
  void dispose() {
    _attached?.removeListener(onLiveVisibilityChanged);
    _attached = null;
    super.dispose();
  }
}
