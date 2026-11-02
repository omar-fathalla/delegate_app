import 'dart:async';

import 'package:flutter/foundation.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';

/// Locks a check-in / check-out action from the tap until its result.
///
/// The lock is taken before the GPS fetch, so taps while the location is
/// being resolved are ignored. If the action dispatched an event to the bloc,
/// the lock is held until the bloc reports a result (or [resultTimeout]).
class AttendanceActionLock {
  AttendanceActionLock({this.resultTimeout = const Duration(seconds: 45)});

  final Duration resultTimeout;
  bool _busy = false;

  bool get isBusy => _busy;

  static bool _isResult(AttendanceState s) =>
      s is AttendanceCheckedIn ||
      s is AttendanceCheckedOut ||
      s is AttendanceError;

  /// Runs [action] unless another action is in flight. Returns false if the
  /// tap was ignored.
  Future<bool> run({
    required AttendanceBloc bloc,
    required Future<void> Function() action,
    required VoidCallback onChanged,
  }) async {
    if (_busy) return false;
    _busy = true;
    onChanged();

    var dispatched = false;
    final result = Completer<void>();
    final sub = bloc.stream.listen((s) {
      if (s is AttendanceLoading) dispatched = true;
      if (_isResult(s)) {
        dispatched = true;
        if (!result.isCompleted) result.complete();
      }
    });
    try {
      await action();
      // Let the bloc pick up an event added at the end of [action].
      await Future<void>.delayed(Duration.zero);
      if ((dispatched || bloc.state is AttendanceLoading) &&
          !result.isCompleted) {
        await result.future.timeout(resultTimeout, onTimeout: () {});
      }
    } finally {
      await sub.cancel();
      _busy = false;
      onChanged();
    }
    return true;
  }
}
