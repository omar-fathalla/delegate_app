import 'dart:async';

import 'package:flutter/foundation.dart';

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
      _safetyNet = Timer.periodic(
        safetyNetInterval,
        (_) => onReload(force: false),
      );
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
