// ignore_for_file: avoid_print
import 'dart:convert';

import 'package:flutter/scheduler.dart';

/// Scoped branch-screen timing for REAL_TEST profile runs.
/// Enabled only when REAL_TEST_METRICS dart-define is true.
class RealTestMetrics {
  RealTestMetrics._();

  static const enabled = bool.fromEnvironment('REAL_TEST_METRICS', defaultValue: false);
  static const clearCold = bool.fromEnvironment('REAL_TEST_COLD', defaultValue: false);

  static int? t0Ms;
  static int? t1Ms;
  static int? t2Ms;
  static int? t3Ms;
  static int? loginDoneMs;
  static int? runAppMs;

  static int attendanceQueryMs = 0;
  static int attendanceDocs = 0;
  static int attendanceChunks = 0;
  static int checkoutFallbackMs = 0;
  static int checkoutMissingDelegates = 0;
  static int checkoutChunks = 0;
  static int companyPrePaintMs = 0;
  static int companyPrePaintIds = 0;
  static int companyPostEnrichMs = 0;
  static int companyPostEnrichIds = 0;
  static int enrichMs = 0;
  static int enrichMissingCount = 0;
  static int enrichBatches = 0;
  static int uniqueDelegates = 0;
  static int localCacheHits = 0;
  static int branchCount = 0;
  static String mode = 'unknown';

  static final List<int> _buildMs = [];
  static final List<int> _rasterMs = [];
  static final List<int> _totalMs = [];
  static bool _frameCb = false;

  static void markLoginDone() {
    if (!enabled) return;
    loginDoneMs = DateTime.now().millisecondsSinceEpoch;
    print('[REAL_TEST] loginDone msSinceEpoch=$loginDoneMs');
  }

  static void markRunApp() {
    if (!enabled) return;
    runAppMs = DateTime.now().millisecondsSinceEpoch;
    print('[REAL_TEST] runApp msSinceEpoch=$runAppMs');
  }

  static void markT0({required String runMode, required int branches}) {
    if (!enabled) return;
    mode = runMode;
    branchCount = branches;
    t0Ms = DateTime.now().millisecondsSinceEpoch;
    t1Ms = t2Ms = t3Ms = null;
    attendanceQueryMs = attendanceDocs = attendanceChunks = 0;
    checkoutFallbackMs = checkoutMissingDelegates = checkoutChunks = 0;
    companyPrePaintMs = companyPrePaintIds = 0;
    companyPostEnrichMs = companyPostEnrichIds = 0;
    enrichMs = enrichMissingCount = enrichBatches = 0;
    uniqueDelegates = localCacheHits = 0;
    _buildMs.clear();
    _rasterMs.clear();
    _totalMs.clear();
    _ensureFrameCallback();
    print('[REAL_TEST] t0_loadDispatch msSinceEpoch=$t0Ms mode=$mode branches=$branches');
  }

  static void markT1() {
    if (!enabled) return;
    t1Ms = DateTime.now().millisecondsSinceEpoch;
    print('[REAL_TEST] t1_queryComplete msSinceEpoch=$t1Ms deltaFromT0=${t1Ms! - (t0Ms ?? t1Ms!)}');
  }

  static void markT2() {
    if (!enabled) return;
    t2Ms = DateTime.now().millisecondsSinceEpoch;
    print('[REAL_TEST] t2_firstPaint msSinceEpoch=$t2Ms deltaFromT0=${t2Ms! - (t0Ms ?? t2Ms!)}');
  }

  static void markT3() {
    if (!enabled) return;
    t3Ms = DateTime.now().millisecondsSinceEpoch;
    print('[REAL_TEST] t3_enrichComplete msSinceEpoch=$t3Ms deltaFromT0=${t3Ms! - (t0Ms ?? t3Ms!)}');
    // Allow a couple frames after enrich emit before dumping.
    Future<void>.delayed(const Duration(milliseconds: 400), dump);
  }

  static void _ensureFrameCallback() {
    if (_frameCb) return;
    _frameCb = true;
    SchedulerBinding.instance.addTimingsCallback((timings) {
      if (!enabled || t0Ms == null || t3Ms != null && DateTime.now().millisecondsSinceEpoch - t3Ms! > 500) {
        return;
      }
      for (final t in timings) {
        _buildMs.add(t.buildDuration.inMilliseconds);
        _rasterMs.add(t.rasterDuration.inMilliseconds);
        _totalMs.add(t.totalSpan.inMilliseconds);
      }
    });
  }

  static int _sum(List<int> xs) => xs.fold(0, (a, b) => a + b);
  static int _max(List<int> xs) => xs.isEmpty ? 0 : xs.reduce((a, b) => a > b ? a : b);
  static double _avg(List<int> xs) => xs.isEmpty ? 0 : _sum(xs) / xs.length;

  static void dump() {
    if (!enabled || t0Ms == null) return;
    final t0 = t0Ms!;
    final map = <String, Object?>{
      'mode': mode,
      'branchCount': branchCount,
      'loginDoneMs': loginDoneMs,
      'runAppMs': runAppMs,
      't0': t0,
      't1_queryComplete_ms': t1Ms == null ? null : (t1Ms! - t0),
      't2_firstPaint_ms': t2Ms == null ? null : (t2Ms! - t0),
      't3_enrichComplete_ms': t3Ms == null ? null : (t3Ms! - t0),
      'phases': {
        'attendanceQueryMs': attendanceQueryMs,
        'attendanceDocs': attendanceDocs,
        'attendanceChunks': attendanceChunks,
        'checkoutFallbackMs': checkoutFallbackMs,
        'checkoutMissingDelegates': checkoutMissingDelegates,
        'checkoutChunks': checkoutChunks,
        'companyPrePaintMs': companyPrePaintMs,
        'companyPrePaintIds': companyPrePaintIds,
        'enrichMs': enrichMs,
        'enrichMissingCount': enrichMissingCount,
        'enrichBatches': enrichBatches,
        'companyPostEnrichMs': companyPostEnrichMs,
        'companyPostEnrichIds': companyPostEnrichIds,
        'uniqueDelegates': uniqueDelegates,
        'localCacheHits': localCacheHits,
      },
      'frames': {
        'count': _buildMs.length,
        'buildSumMs': _sum(_buildMs),
        'buildAvgMs': double.parse(_avg(_buildMs).toStringAsFixed(1)),
        'buildMaxMs': _max(_buildMs),
        'rasterSumMs': _sum(_rasterMs),
        'rasterAvgMs': double.parse(_avg(_rasterMs).toStringAsFixed(1)),
        'rasterMaxMs': _max(_rasterMs),
        'totalMaxMs': _max(_totalMs),
      },
    };
    print('[REAL_TEST_METRICS] ${json.encode(map)}');
  }
}
