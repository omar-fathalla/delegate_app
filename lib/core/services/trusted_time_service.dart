import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';

import 'clock/boot_clock.dart';
import 'trusted_time_anchor.dart';

/// Service providing tamper-proof, synchronized time across the application.
/// Uses server time synchronization and a monotonic stopwatch to prevent
/// fraudulent clock manipulation by users on their local devices.
///
/// TAS-363: every successful sync also saves (server time, boot clock) on the
/// phone ([TrustedTimeAnchorStore]), so an offline check-in made after the
/// app was closed still gets a time the user can't move by changing the
/// phone's clock ([captureOfflineTime]).
class TrustedTimeService {
  final FirebaseFirestore? _firestore;
  final TrustedTimeAnchorStore? _anchorStore;
  final BootClock _bootClock;
  final Stopwatch _monotonicStopwatch = Stopwatch();

  DateTime _baseServerTime = DateTime.now();
  Duration _serverOffset = Duration.zero;
  bool _isSynced = false;

  Timer? _tickerTimer;
  final StreamController<DateTime> _liveClockController =
      StreamController<DateTime>.broadcast();

  TrustedTimeService({
    FirebaseFirestore? firestore,
    TrustedTimeAnchorStore? anchorStore,
    BootClock? bootClock,
    bool autoSync = true,
  }) : _firestore = firestore,
       _anchorStore = anchorStore,
       _bootClock = bootClock ?? BootClock.system() {
    _init(autoSync: autoSync);
  }

  void _init({bool autoSync = true}) {
    _monotonicStopwatch.start();
    _baseServerTime = DateTime.now();
    _startLiveTicker();
    // Proactively sync with Firebase server time
    if (autoSync) syncServerTime().ignore();
  }

  /// TAS-363: the time an offline check-in / check-out is saved with. Trusted
  /// when the phone has synced since its last boot; otherwise the server
  /// counts the record from the time it arrives (user decision 27 Nov).
  OfflineTimeCapture captureOfflineTime() => decideOfflineCapture(
    anchor: _anchorStore?.read(),
    bootNowMs: _bootClock.elapsedMs(),
    wallNowMs: DateTime.now().millisecondsSinceEpoch,
  );

  /// Saves the anchor of a sync (exposed for tests).
  @visibleForTesting
  Future<void> recordServerTime(DateTime serverTime) => _saveAnchor(serverTime);

  Future<void> _saveAnchor(DateTime serverTime) async {
    final store = _anchorStore;
    final boot = _bootClock.elapsedMs();
    if (store == null || boot == null) return;
    await store.write(
      TrustedTimeAnchor(
        serverMs: serverTime.millisecondsSinceEpoch,
        bootMs: boot,
        wallMs: DateTime.now().millisecondsSinceEpoch,
      ),
    );
  }

  /// True if network/server time has been successfully calibrated.
  bool get isSynced => _isSynced;

  /// Returns the current trusted, tamper-proof [DateTime].
  /// Accounts for server time offset and monotonic time elapsed since calibration.
  DateTime get now {
    if (_isSynced) {
      return _baseServerTime.add(_monotonicStopwatch.elapsed);
    }
    // Not synced in this run (offline since launch): the saved anchor still
    // gives the server time if the phone has not rebooted (TAS-363).
    if (_anchorStore != null) {
      final offline = captureOfflineTime();
      if (offline.trusted) return offline.at;
    }
    return DateTime.now().add(_serverOffset);
  }

  /// Stream of trusted [DateTime] that ticks every second for UI live clocks.
  Stream<DateTime> get liveClockStream => _liveClockController.stream;

  void _startLiveTicker() {
    _tickerTimer?.cancel();
    _tickerTimer = Timer.periodic(const Duration(seconds: 1), (_) {
      if (!_liveClockController.isClosed) {
        _liveClockController.add(now);
      }
    });
  }

  /// Calibrates local time with Firebase server time.
  Future<void> syncServerTime() async {
    try {
      FirebaseFirestore? firestore = _firestore;
      if (firestore == null) {
        try {
          firestore = FirebaseFirestore.instance;
        } catch (_) {
          return;
        }
      }

      final startTime = DateTime.now();
      
      // Perform a lightweight server timestamp probe
      final docRef = firestore.collection('_system_metadata').doc('time_probe');
      await docRef.set({
        'probe': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true)).timeout(const Duration(seconds: 5));

      final snapshot = await docRef.get(const GetOptions(source: Source.server)).timeout(const Duration(seconds: 5));
      final endTime = DateTime.now();

      if (snapshot.exists) {
        final data = snapshot.data();
        final serverTs = data?['probe'] as Timestamp?;
        if (serverTs != null) {
          // Half of the round-trip latency
          final latency = Duration(
            milliseconds: (endTime.difference(startTime).inMilliseconds / 2).round(),
          );
          final calibratedServerTime = serverTs.toDate().add(latency);

          _baseServerTime = calibratedServerTime;
          _monotonicStopwatch.reset();
          _monotonicStopwatch.start();
          _serverOffset = calibratedServerTime.difference(DateTime.now());
          _isSynced = true;
          await _saveAnchor(calibratedServerTime);
          debugPrint(
            '[TrustedTimeService] Server time synced successfully: $_baseServerTime (Offset: ${_serverOffset.inMilliseconds}ms)',
          );
        }
      }
    } catch (e) {
      // Fallback: Continue using device time + previous offset
      debugPrint('[TrustedTimeService] Time probe fallback: $e');
    }
  }

  void dispose() {
    _tickerTimer?.cancel();
    _liveClockController.close();
    _monotonicStopwatch.stop();
  }
}
