import 'package:delegate_app/core/services/firestore_session_subscriptions.dart';
import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'delegate_tracking_service.dart';

/// محرك البث الميداني الحقيقي بهاتف المندوب (Real-time Field Telemetry & Tracking Engine)
/// يعمل بنظام البث المستمر في الخلفية (Background Location Stream + Foreground Service)
/// مع المزامنة اللحظية لأوامر المشرف والمؤقت الدوري الذكي
class DelegateTrackingEngine {
  final DelegateTrackingService _trackingService;
  final Battery _battery;

  StreamSubscription<Position>? _positionStreamSubscription;
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>?
      _remoteConfigSubscription;
  Timer? _periodicTimer;

  String? _activeDelegateId;
  Position? _lastRecordedPosition;
  DateTime? _lastPingTime;
  bool _isTracking = false;
  bool _remoteTrackingEnabled = true;

  // نمط المفرد (Singleton) للوصول الموحد عبر التطبيق
  static final DelegateTrackingEngine _instance =
      DelegateTrackingEngine._internal();
  factory DelegateTrackingEngine({
    DelegateTrackingService? trackingService,
    Battery? battery,
  }) {
    if (trackingService != null || battery != null) {
      return DelegateTrackingEngine._custom(
        trackingService: trackingService,
        battery: battery,
      );
    }
    return _instance;
  }

  DelegateTrackingEngine._internal()
      : _trackingService = DelegateTrackingService(),
        _battery = Battery();

  DelegateTrackingEngine._custom({
    DelegateTrackingService? trackingService,
    Battery? battery,
  })  : _trackingService = trackingService ?? DelegateTrackingService(),
        _battery = battery ?? Battery();

  bool get isTracking => _isTracking;
  bool get remoteTrackingEnabled => _remoteTrackingEnabled;
  String? get activeDelegateId => _activeDelegateId;
  Position? get lastPosition => _lastRecordedPosition;

  /// 1. بدء جلسة التتبع الميداني في هاتف المندوب
  Future<void> startTrackingSession({
    required String delegateId,
    Duration interval = const Duration(minutes: 5),
  }) async {
    if (!WebRuntimePolicy.liveTrackingEnabled) return;
    if (_isTracking && _activeDelegateId == delegateId) return;

    _activeDelegateId = delegateId;
    _isTracking = true;
    _remoteTrackingEnabled = true;

    debugPrint(
        '🚀 [DelegateTrackingEngine] Starting background tracking session for $delegateId');

    // أ. الاستماع اللحظي لتغييرات إعدادات التتبع من المشرف (Remote Toggle)
    _listenToRemoteConfig(delegateId);

    // ب. بدء خدمة البث المستمر في الخلفية عبر Geolocator مع الإشعار الدائم
    await _startBackgroundPositionStream();

    // ج. إرسال أول نبضة قياس فوري
    await triggerTelemetryPing();

    // د. تشغيل المؤقت الدوري للحفاظ على تحديث حالة البطارية والاتصال أثناء التوقف
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) async {
      if (!_isTracking || !_remoteTrackingEnabled) return;
      await triggerTelemetryPing();
    });
  }

  /// الاستماع لتعديل حالة التتبع من المشرف (isTrackingEnabled)
  void _listenToRemoteConfig(String delegateId) {
    _remoteConfigSubscription?.cancel();
    try {
      _remoteConfigSubscription = FirebaseFirestore.instance
          .collection('delegate_tracking')
          .doc(delegateId)
          .snapshots()
          .listen((snap) {
        if (!snap.exists) return;
        final data = snap.data();
        if (data == null) return;

        final bool isEnabled = data['isTrackingEnabled'] ?? true;
        if (isEnabled != _remoteTrackingEnabled) {
          _remoteTrackingEnabled = isEnabled;
          debugPrint(
              '📡 [DelegateTrackingEngine] Remote tracking status changed to: $isEnabled');
          if (!isEnabled) {
            _positionStreamSubscription?.pause();
          } else {
            _positionStreamSubscription?.resume();
            unawaited(triggerTelemetryPing());
          }
        }
      }, onError: (err) {
        debugPrint(
            '⚠️ [DelegateTrackingEngine] Remote config subscription error: $err');
      });
      // TAS-76: logout cancels it with the other session listeners.
      final sub = _remoteConfigSubscription;
      if (sub != null) {
        FirestoreSessionSubscriptions.instance
            .register('tracking_remote_config', sub);
      }
    } catch (e) {
      debugPrint('⚠️ [DelegateTrackingEngine] Failed to listen to remote config: $e');
    }
  }

  /// إعداد وبدء تيار الموقع في الخلفية عبر Foreground Service
  Future<void> _startBackgroundPositionStream() async {
    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint('⚠️ [DelegateTrackingEngine] Location permission denied.');
          return;
        }
      }

      LocationSettings locationSettings;
      if (defaultTargetPlatform == TargetPlatform.android) {
        locationSettings = AndroidSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15, // إرسال تحديث عند التحرك 15 متراً
          intervalDuration: const Duration(seconds: 25),
          // TAS-364 (user decision 2026-11-26, message 4.1): a foreground
          // service with a fixed notification for the whole shift, so the
          // location keeps updating with the screen off. Started while the
          // app is open (check-in), so no ACCESS_BACKGROUND_LOCATION.
          foregroundNotificationConfig: trackingForegroundNotification(),
        );
      } else if (defaultTargetPlatform == TargetPlatform.iOS) {
        locationSettings = AppleSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
          activityType: ActivityType.other,
          pauseLocationUpdatesAutomatically: false,
          showBackgroundLocationIndicator: true,
          allowBackgroundLocationUpdates: true,
        );
      } else {
        locationSettings = const LocationSettings(
          accuracy: LocationAccuracy.high,
          distanceFilter: 15,
        );
      }

      _positionStreamSubscription?.cancel();
      _positionStreamSubscription = Geolocator.getPositionStream(
        locationSettings: locationSettings,
      ).listen(
        (position) async {
          if (!_isTracking || !_remoteTrackingEnabled) return;
          await _handleIncomingPosition(position);
        },
        onError: (err) {
          debugPrint('⚠️ [DelegateTrackingEngine] Position stream error: $err');
        },
      );
    } catch (e) {
      debugPrint('⚠️ [DelegateTrackingEngine] Failed to start background stream: $e');
    }
  }

  /// معالجة نقطة الموقع الواردة من تيار الـ GPS
  Future<void> _handleIncomingPosition(Position position) async {
    final delegateId = _activeDelegateId;
    if (delegateId == null || !_isTracking || !_remoteTrackingEnabled) return;

    try {
      // قراءة نسبة البطارية
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (err) {
        debugPrint('⚠️ [DelegateTrackingEngine] Battery read error: $err');
      }

      // احتساب السرعة وحالة الحركة
      double speedKmh = 0.0;
      if (position.speed > 0) {
        speedKmh = position.speed * 3.6;
      } else if (_lastRecordedPosition != null && _lastPingTime != null) {
        final elapsedSeconds =
            DateTime.now().difference(_lastPingTime!).inSeconds;
        if (elapsedSeconds > 0) {
          final distanceMeters = Geolocator.distanceBetween(
            _lastRecordedPosition!.latitude,
            _lastRecordedPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          speedKmh = (distanceMeters / 1000.0) / (elapsedSeconds / 3600.0);
        }
      }

      final isMoving = speedKmh >= 2.0;
      _lastRecordedPosition = position;
      _lastPingTime = DateTime.now();

      // بث التحديث لقاعدة البيانات وتوثيق نقطة المسار
      await _trackingService.updateLocationAndCheckGeofence(
        delegateId: delegateId,
        currentLat: position.latitude,
        currentLng: position.longitude,
        speed: speedKmh,
        batteryLevel: batteryLevel,
        isMoving: isMoving,
        isMocked: position.isMocked,
      );

      // مزامنة أي نقاط مسار سابقة محفوظة محلياً
      await _trackingService.syncOfflineBreadcrumbsOnReconnect(
        delegateId: delegateId,
      );

      debugPrint(
        '📍 [DelegateTrackingEngine] Stream ping: Lat ${position.latitude.toStringAsFixed(4)}, '
        'Battery: $batteryLevel%, Speed: ${speedKmh.toStringAsFixed(1)} km/h, Moving: $isMoving',
      );
    } catch (e) {
      debugPrint('⚠️ [DelegateTrackingEngine] Handle position error: $e');
      if (_lastRecordedPosition != null) {
        await _trackingService.recordOfflineBreadcrumbLocally(
          delegateId: delegateId,
          lat: _lastRecordedPosition!.latitude,
          lng: _lastRecordedPosition!.longitude,
        );
      }
    }
  }

  /// 2. إرسال نبضة قياس حي عند الطلب أو دورياً
  Future<void> triggerTelemetryPing() async {
    final delegateId = _activeDelegateId;
    if (delegateId == null || !_isTracking || !_remoteTrackingEnabled) return;

    try {
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint('⚠️ [DelegateTrackingEngine] Location permission denied.');
          return;
        }
      }

      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      await _handleIncomingPosition(position);
    } catch (e) {
      debugPrint('⚠️ [DelegateTrackingEngine] Telemetry ping error: $e');
    }
  }

  /// 3. إيقاف جلسة التتبع عند تسجيل الانصراف (Check-Out)
  void stopTrackingSession() {
    debugPrint('🛑 [DelegateTrackingEngine] Stopping tracking session');
    _positionStreamSubscription?.cancel();
    _positionStreamSubscription = null;
    _remoteConfigSubscription?.cancel();
    _remoteConfigSubscription = null;
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isTracking = false;
    _remoteTrackingEnabled = true;
    _activeDelegateId = null;
    _lastRecordedPosition = null;
    _lastPingTime = null;
  }
}

/// TAS-364: the shift notification (message 4.1 in
/// USER-SCENARIOS/01-delegate-messages.md). Shown while tracking runs and
/// removed when the session stops (check-out or logout).
ForegroundNotificationConfig trackingForegroundNotification() =>
    const ForegroundNotificationConfig(
      notificationTitle: 'تسهيل: الشيفت شغال',
      notificationText: 'موقعك بيتسجل لحد الانصراف',
      enableWakeLock: true,
      setOngoing: true,
    );
