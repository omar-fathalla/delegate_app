import 'dart:async';
import 'package:battery_plus/battery_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'delegate_tracking_service.dart';

/// محرك البث الميداني الحقيقي بهاتف المندوب (Real-time Field Telemetry & Tracking Engine)
/// يعمل بشكل تكيفي ذكي (Smart Adaptive Interval) بين فترتي الحضور والانصراف
class DelegateTrackingEngine {
  final DelegateTrackingService _trackingService;
  final Battery _battery;

  Timer? _periodicTimer;
  String? _activeDelegateId;
  Position? _lastRecordedPosition;
  DateTime? _lastPingTime;
  bool _isTracking = false;

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
  String? get activeDelegateId => _activeDelegateId;
  Position? get lastPosition => _lastRecordedPosition;

  /// 1. بدء جلسة التتبع الميداني في هاتف المندوب عند تسجيل الحضور
  Future<void> startTrackingSession({
    required String delegateId,
    Duration interval = const Duration(minutes: 5),
  }) async {
    if (_isTracking && _activeDelegateId == delegateId) return;

    _activeDelegateId = delegateId;
    _isTracking = true;

    debugPrint('🚀 [DelegateTrackingEngine] Starting tracking session for $delegateId');

    // إرسال أول نبضة قياس فوري
    await triggerTelemetryPing();

    // تشغيل المؤقت الدوري التكيفي الذكي
    _periodicTimer?.cancel();
    _periodicTimer = Timer.periodic(interval, (_) async {
      await triggerTelemetryPing();
    });
  }

  /// 2. إرسال نبضة قياس حي (GPS + Battery + Speed + Motion)
  Future<void> triggerTelemetryPing() async {
    final delegateId = _activeDelegateId;
    if (delegateId == null || !_isTracking) return;

    try {
      // أ. فحص إذن خدمات الموقع
      LocationPermission permission = await Geolocator.checkPermission();
      if (permission == LocationPermission.denied) {
        permission = await Geolocator.requestPermission();
        if (permission == LocationPermission.denied ||
            permission == LocationPermission.deniedForever) {
          debugPrint('⚠️ [DelegateTrackingEngine] Location permission denied.');
          return;
        }
      }

      // ب. قراءة الموقع الحالي بدقة عالية
      final position = await Geolocator.getCurrentPosition(
        locationSettings: const LocationSettings(
          accuracy: LocationAccuracy.high,
          timeLimit: Duration(seconds: 15),
        ),
      );

      // ج. قراءة نسبة البطارية الحقيقية
      int? batteryLevel;
      try {
        batteryLevel = await _battery.batteryLevel;
      } catch (err) {
        debugPrint('⚠️ [DelegateTrackingEngine] Battery read error: $err');
      }

      // د. احتساب السرعة وحالة الحركة
      double speedKmh = 0.0;
      if (position.speed > 0) {
        speedKmh = position.speed * 3.6; // تحويل من م/ث إلى كم/س
      } else if (_lastRecordedPosition != null && _lastPingTime != null) {
        final elapsedHours =
            DateTime.now().difference(_lastPingTime!).inSeconds / 3600.0;
        if (elapsedHours > 0) {
          final distanceMeters = Geolocator.distanceBetween(
            _lastRecordedPosition!.latitude,
            _lastRecordedPosition!.longitude,
            position.latitude,
            position.longitude,
          );
          speedKmh = (distanceMeters / 1000.0) / elapsedHours;
        }
      }

      final isMoving = speedKmh >= 2.0;

      _lastRecordedPosition = position;
      _lastPingTime = DateTime.now();

      // هـ. بث التحديث لقاعدة البيانات وتوثيق نقطة المسار (Breadcrumb)
      await _trackingService.updateLocationAndCheckGeofence(
        delegateId: delegateId,
        currentLat: position.latitude,
        currentLng: position.longitude,
        speed: speedKmh,
        batteryLevel: batteryLevel,
        isMoving: isMoving,
        isMocked: position.isMocked,
      );

      // و. مزامنة أي نقاط مسار سابقة تم حفظها أوفلاين أثناء انقطاع الاتصال
      await _trackingService.syncOfflineBreadcrumbsOnReconnect(
        delegateId: delegateId,
      );

      debugPrint(
        '📍 [DelegateTrackingEngine] Ping sent: Lat ${position.latitude.toStringAsFixed(4)}, '
        'Battery: $batteryLevel%, Speed: ${speedKmh.toStringAsFixed(1)} km/h, Moving: $isMoving',
      );
    } catch (e) {
      debugPrint('⚠️ [DelegateTrackingEngine] Telemetry ping error: $e');

      // عند انقطاع الإنترنت، تخزين إحداثيات المسار محلياً لحمايتها من الضياع
      if (_lastRecordedPosition != null) {
        await _trackingService.recordOfflineBreadcrumbLocally(
          delegateId: delegateId,
          lat: _lastRecordedPosition!.latitude,
          lng: _lastRecordedPosition!.longitude,
        );
      }
    }
  }

  /// 3. إيقاف جلسة التتبع عند تسجيل الانصراف (Check-Out)
  void stopTrackingSession() {
    debugPrint('🛑 [DelegateTrackingEngine] Stopping tracking session');
    _periodicTimer?.cancel();
    _periodicTimer = null;
    _isTracking = false;
    _activeDelegateId = null;
    _lastRecordedPosition = null;
    _lastPingTime = null;
  }
}
