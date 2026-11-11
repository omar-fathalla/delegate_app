import 'dart:async';

import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:flutter/widgets.dart';

/// Rebuilds a promo-gated screen when the app resumes or when Cairo midnight
/// (or a short fallback tick) is crossed, so Paymob takes over without a restart.
///
/// The app assigns [onResumeRefresh] at startup (TrustedTime sync + config
/// reload). This file must not import `injection_container.dart`.
mixin PromoClockBinding<T extends StatefulWidget> on State<T>, WidgetsBindingObserver {
  /// App-level hook set from DI. Tests may leave this null.
  static Future<void> Function()? onResumeRefresh;

  Timer? _promoMidnightTimer;
  String _promoDayStamp = '';

  /// Called after the clock or config may have changed. Default is [setState].
  void onPromoClockTick() {
    if (mounted) setState(() {});
  }

  @override
  void initState() {
    super.initState();
    WidgetsBinding.instance.addObserver(this);
    _promoDayStamp = _cairoDayStamp();
    _schedulePromoTimer();
  }

  @override
  void dispose() {
    _promoMidnightTimer?.cancel();
    WidgetsBinding.instance.removeObserver(this);
    super.dispose();
  }

  @override
  void didChangeAppLifecycleState(AppLifecycleState state) {
    if (state == AppLifecycleState.resumed) {
      unawaited(_refreshOnResume());
    }
  }

  Future<void> _refreshOnResume() async {
    try {
      await onResumeRefresh?.call();
    } catch (_) {}
    if (!mounted) return;
    _promoDayStamp = _cairoDayStamp();
    _schedulePromoTimer();
    onPromoClockTick();
  }

  void _schedulePromoTimer() {
    _promoMidnightTimer?.cancel();
    final now = SubscriptionCycleHelper.currentTime();
    final cairo = SubscriptionCycleHelper.cairoTime(now);
    final nextMidnight = DateTime(cairo.year, cairo.month, cairo.day).add(const Duration(days: 1));
    var wait = nextMidnight.difference(cairo) + const Duration(seconds: 1);
    if (wait.isNegative || wait.inMilliseconds < 1) {
      wait = const Duration(seconds: 1);
    }
    if (wait > const Duration(minutes: 15)) {
      wait = const Duration(minutes: 15);
    }
    _promoMidnightTimer = Timer(wait, () {
      if (!mounted) return;
      final stamp = _cairoDayStamp();
      if (stamp != _promoDayStamp) {
        _promoDayStamp = stamp;
        onPromoClockTick();
      }
      _schedulePromoTimer();
    });
  }

  String _cairoDayStamp() {
    final d = SubscriptionCycleHelper.cairoTime();
    return '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';
  }
}
