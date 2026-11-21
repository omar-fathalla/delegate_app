import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../../../../core/constants.dart';
import '../models/delegate_tracking_session_model.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import '../../domain/entities/tracking_breadcrumb.dart';
import '../models/tracking_breadcrumb_model.dart';

class DelegateTrackingService {
  final FirebaseFirestore _firestore;

  /// Signed-in user, for `createdBy` / `delegateUid` on alerts and audit
  /// logs (TAS-71). Null only in tests without Firebase; the session's
  /// delegate id is used then.
  final FirebaseAuth? _auth;

  DelegateTrackingService({FirebaseFirestore? firestore, FirebaseAuth? auth})
      : _firestore = firestore ?? FirebaseFirestore.instance,
        _auth = auth;

  String _writerUid(DelegateTrackingSession session) {
    try {
      return (_auth ?? FirebaseAuth.instance).currentUser?.uid ??
          session.delegateId;
    } catch (_) {
      // No Firebase app (unit tests).
      return session.delegateId;
    }
  }

  /// Audit log write that can never abort the location update around it.
  /// The rules need `delegateUid` (== auth uid) and company/org ids so the
  /// company's supervisors can read it (TAS-71).
  Future<void> _addAuditLog(
    DelegateTrackingSession session,
    Map<String, dynamic> fields,
  ) async {
    try {
      await _auditLogsCollection.add({
        ...fields,
        'delegateUid': _writerUid(session),
        'delegateId': session.delegateId,
        'companyUID': session.companyId,
        'companyId': session.companyId,
        'organizationUID': session.organizationId,
        'organizationId': session.organizationId,
      });
    } catch (e) {
      debugPrint('security audit log failed (${fields['action']}): $e');
    }
  }

  CollectionReference<Map<String, dynamic>> get _trackingCollection =>
      _firestore.collection('delegate_tracking');

  CollectionReference<Map<String, dynamic>> get _notificationsCollection =>
      _firestore.collection('notifications');

  CollectionReference<Map<String, dynamic>> get _auditLogsCollection =>
      _firestore.collection('security_audit_logs');

  /// 1. البث المباشر لجلسات تتبع المناديب للشركة أو المنظمة
  Stream<List<DelegateTrackingSession>> streamTrackingSessions({
    String? companyId,
    String? organizationId,
  }) {
    Query<Map<String, dynamic>> query = _trackingCollection;

    if (companyId != null && companyId.isNotEmpty) {
      query = query.where('companyUID', isEqualTo: companyId);
    } else if (organizationId != null && organizationId.isNotEmpty) {
      query = query.where('organizationId', isEqualTo: organizationId);
    }

    return query.snapshots().map((snapshot) {
      final sessions = snapshot.docs
          .map((doc) => DelegateTrackingSessionModel.fromFirestore(doc))
          .toList();
      // Dual-layer company isolation (AGENTS.md): query + in-memory guard.
      if (companyId != null && companyId.isNotEmpty) {
        return sessions
            .where((s) => s.companyId == companyId)
            .toList(growable: false);
      }
      if (organizationId != null && organizationId.isNotEmpty) {
        return sessions
            .where((s) => s.organizationId == organizationId)
            .toList(growable: false);
      }
      return sessions;
    });
  }

  /// 2. تفعيل / إلغاء تتبع المندوب بواسطة المشرف
  Future<void> toggleTracking({
    required String delegateId,
    required bool enabled,
    required String supervisorId,
    required String supervisorName,
  }) async {
    try {
      await _trackingCollection.doc(delegateId).set({
        'isTrackingEnabled': enabled,
        'trackingUpdatedBy': supervisorId,
        'trackingUpdatedByName': supervisorName,
        'trackingUpdatedAt': FieldValue.serverTimestamp(),
      }, SetOptions(merge: true));

      // توثيق العملية في سجل الأمان
      await _auditLogsCollection.add({
        'action': enabled ? 'enable_delegate_tracking' : 'disable_delegate_tracking',
        'type': 'geofence_tracking_toggle',
        'delegateId': delegateId,
        'supervisorId': supervisorId,
        'supervisorName': supervisorName,
        'enabled': enabled,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error toggling tracking: $e');
      rethrow;
    }
  }

  /// 2.1 تفعيل / إلغاء تتبع جماعي لجميع المناديب بنقرة واحدة (Bulk Toggle)
  Future<void> bulkToggleTracking({
    required List<String> delegateIds,
    required bool enabled,
    required String supervisorId,
    required String supervisorName,
  }) async {
    if (delegateIds.isEmpty) return;
    try {
      final batch = _firestore.batch();
      for (final id in delegateIds) {
        final docRef = _trackingCollection.doc(id);
        batch.set(docRef, {
          'isTrackingEnabled': enabled,
          'trackingUpdatedBy': supervisorId,
          'trackingUpdatedByName': supervisorName,
          'trackingUpdatedAt': FieldValue.serverTimestamp(),
        }, SetOptions(merge: true));
      }
      await batch.commit();

      await _auditLogsCollection.add({
        'action': enabled ? 'bulk_enable_delegate_tracking' : 'bulk_disable_delegate_tracking',
        'type': 'geofence_tracking_bulk_toggle',
        'delegateCount': delegateIds.length,
        'supervisorId': supervisorId,
        'supervisorName': supervisorName,
        'enabled': enabled,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().toIso8601String(),
      });
    } catch (e) {
      debugPrint('Error in bulkToggleTracking: $e');
      rethrow;
    }
  }

  /// 3. تهيئة أو تحديث جلسة التتبع عند تسجيل الحضور
  Future<void> initializeTrackingSession({
    required String delegateId,
    required String delegateName,
    required String delegatePhone,
    String? avatarUrl,
    required String companyId,
    required String organizationId,
    required String branchId,
    required String branchName,
    required double branchLat,
    required double branchLng,
    required double geofenceRadius,
    required double currentLat,
    required double currentLng,
    DateTime? checkInTime,
    double? speed,
    int? batteryLevel,
    bool? isMoving,
  }) async {
    try {
      final distance = Geolocator.distanceBetween(
        currentLat,
        currentLng,
        branchLat,
        branchLng,
      );

      final isInside = distance <= (geofenceRadius + 50.0);

      final sessionDoc = await _trackingCollection.doc(delegateId).get();
      final bool previousEnabled =
          sessionDoc.exists ? (sessionDoc.data()?['isTrackingEnabled'] == true) : false;
      final existingAvatar = sessionDoc.data()?['avatarUrl']?.toString();
      final effectiveAvatar = (avatarUrl != null && avatarUrl.isNotEmpty)
          ? avatarUrl
          : (existingAvatar != null && existingAvatar.isNotEmpty ? existingAvatar : null);

      final session = DelegateTrackingSessionModel(
        delegateId: delegateId,
        delegateName: delegateName,
        delegatePhone: delegatePhone,
        avatarUrl: effectiveAvatar,
        companyId: companyId,
        organizationId: organizationId,
        branchId: branchId,
        branchName: branchName,
        branchLat: branchLat,
        branchLng: branchLng,
        geofenceRadius: geofenceRadius,
        isTrackingEnabled: previousEnabled,
        currentStatus: isInside ? TrackingStatus.insideZone : TrackingStatus.outsideZone,
        currentDistanceMeters: distance,
        lastLatitude: currentLat,
        lastLongitude: currentLng,
        lastUpdated: DateTime.now(),
        checkInTime: checkInTime ?? DateTime.now(),
        isOnline: true,
        isMockLocationDetected: false,
        offlineBreadcrumbsCount: 0,
        speed: speed ?? 0.0,
        batteryLevel: batteryLevel,
        isMoving: isMoving ?? false,
      );

      await _trackingCollection.doc(delegateId).set({
        ...session.toJson(),
        'companyId': companyId,
        'companyUID': companyId,
        'organizationId': organizationId,
        'organizationUID': organizationId,
        'checkOutTime': FieldValue.delete(),
      }, SetOptions(merge: true));

      // تسجيل أول نقطة مسار (First Breadcrumb)
      try {
        await _trackingCollection
            .doc(delegateId)
            .collection('breadcrumbs')
            .add({
          'latitude': currentLat,
          'longitude': currentLng,
          'timestamp': FieldValue.serverTimestamp(),
          'speed': speed ?? 0.0,
          'batteryLevel': ?batteryLevel,
          'distanceMeters': distance,
          'isInside': isInside,
        });
      } catch (e, st) {
        debugPrint(
          'DelegateTrackingService: failed writing first breadcrumb: $e\n$st',
        );
      }
    } catch (e, st) {
      debugPrint('DelegateTrackingService: error initializing session: $e\n$st');
    }
  }

  /// 4. فحص موقع المندوب وتحديث النطاق الجغرافي مع التيليميتري الحية ومسار الحركة
  Future<void> updateLocationAndCheckGeofence({
    required String delegateId,
    required double currentLat,
    required double currentLng,
    double? speed,
    int? batteryLevel,
    bool? isMoving,
    bool isMocked = false,
  }) async {
    try {
      final doc = await _trackingCollection.doc(delegateId).get();
      if (!doc.exists) return;

      final session = DelegateTrackingSessionModel.fromFirestore(doc);

      // رصد مكافحة برامج الـ Fake GPS والمواقع الوهمية
      if (isMocked && !session.isMockLocationDetected) {
        await _trackingCollection.doc(delegateId).update({
          'isMockLocationDetected': true,
          'mockDetectedAt': FieldValue.serverTimestamp(),
        });

        await _sendGeofenceNotification(
          title: '🚨 تحذير أمني: رصد موقع وهمي (Mock Location)',
          body:
              'تم رصد استخدام برنامج تزييف موقع (Fake GPS) بواسطة المندوب ${session.delegateName} في فرع (${BranchDisplayCache.instance.displayName(session.branchName)}).',
          type: 'mock_location_alert',
          session: session,
          breachDistance: 0,
        );

        await _addAuditLog(session, {
          'action': 'mock_location_detected_during_tracking',
          'type': 'security_violation',
          'delegateName': session.delegateName,
          'delegatePhone': session.delegatePhone,
          'branchName': session.branchName,
          'latitude': currentLat,
          'longitude': currentLng,
          'timestamp': FieldValue.serverTimestamp(),
          'createdAt': DateTime.now().toIso8601String(),
        });
      }

      if (!session.isTrackingEnabled) {
        await _trackingCollection.doc(delegateId).update({
          'lastLatitude': currentLat,
          'lastLongitude': currentLng,
          'speed': ?speed,
          'batteryLevel': ?batteryLevel,
          'isMoving': ?isMoving,
          'lastUpdated': FieldValue.serverTimestamp(),
          'isOnline': true,
        });
        return;
      }

      final distance = Geolocator.distanceBetween(
        currentLat,
        currentLng,
        session.branchLat,
        session.branchLng,
      );

      final allowedThreshold = session.geofenceRadius + 50.0;
      final bool isNowInside = distance <= allowedThreshold;

      final bool wasOutside = session.currentStatus == TrackingStatus.outsideZone;

      final now = DateTime.now();
      final timeStr = DateFormat('hh:mm a', 'ar').format(now);

      // سيناريو 1: خارج النطاق مع فترة سماح ذكية 3 دقائق لمنع الإنذارات المزعجة
      if (!isNowInside) {
        DateTime firstExit = session.firstExitedAt ?? now;
        final bool isFirstRecordedExit = session.firstExitedAt == null;
        final elapsedSeconds = now.difference(firstExit).inSeconds;

        final bool gracePeriodExceeded = elapsedSeconds >= 180; // 3 دقائق
        final bool shouldNotifyBreach = gracePeriodExceeded &&
            (session.lastBreachAt == null ||
                now.difference(session.lastBreachAt!).inMinutes >= 15);

        final breachMeters = (distance - session.geofenceRadius).toInt();

        await _trackingCollection.doc(delegateId).update({
          'currentStatus': 'outside',
          'currentDistanceMeters': distance,
          'lastLatitude': currentLat,
          'lastLongitude': currentLng,
          'speed': ?speed,
          'batteryLevel': ?batteryLevel,
          'isMoving': ?isMoving,
          'lastUpdated': FieldValue.serverTimestamp(),
          if (isFirstRecordedExit) 'firstExitedAt': FieldValue.serverTimestamp(),
          if (shouldNotifyBreach) 'lastBreachAt': FieldValue.serverTimestamp(),
          'isOnline': true,
        });

        // إرسال الإشعار فقط إذا استمر الخروج وتجاوز فترة السماح (3 دقائق)
        if (shouldNotifyBreach) {
          await _sendGeofenceNotification(
            title: '⚠️ تنبيه خروج مؤكد عن نطاق الفرع',
            body:
                'المندوب ${session.delegateName} تجاوز نطاق فرع (${BranchDisplayCache.instance.displayName(session.branchName)}) بـ $breachMeters متر ومستمر خارج النطاق منذ $timeStr.',
            type: 'geofence_breach',
            session: session,
            breachDistance: breachMeters,
          );

          await _addAuditLog(session, {
            'action': 'confirmed_geofence_breach_after_grace',
            'type': 'geofence_violation',
            'delegateName': session.delegateName,
            'delegatePhone': session.delegatePhone,
            'branchName': session.branchName,
            'geofenceRadius': session.geofenceRadius,
            'breachDistanceMeters': breachMeters,
            'totalDistanceMeters': distance,
            'latitude': currentLat,
            'longitude': currentLng,
            'gracePeriodSeconds': elapsedSeconds,
            'timestamp': FieldValue.serverTimestamp(),
            'timeString': timeStr,
          });
        }
      }
      // سيناريو 2: عودة المندوب لنطاق الفرع (إلغاء فترة السماح والإنذار)
      else if (isNowInside && (wasOutside || session.firstExitedAt != null)) {
        final bool hadConfirmedBreach = session.lastBreachAt != null && wasOutside;

        await _trackingCollection.doc(delegateId).update({
          'currentStatus': 'inside',
          'currentDistanceMeters': distance,
          'lastLatitude': currentLat,
          'lastLongitude': currentLng,
          'speed': ?speed,
          'batteryLevel': ?batteryLevel,
          'isMoving': ?isMoving,
          'lastUpdated': FieldValue.serverTimestamp(),
          'firstExitedAt': FieldValue.delete(),
          'isOnline': true,
        });

        if (hadConfirmedBreach) {
          await _sendGeofenceNotification(
            title: '🟢 عودة المندوب لنطاق الفرع',
            body:
                'عاد المندوب ${session.delegateName} إلى داخل نطاق فرع (${BranchDisplayCache.instance.displayName(session.branchName)}) في تمام الساعة $timeStr.',
            type: 'geofence_return',
            session: session,
            breachDistance: 0,
          );
        }
      }
      // سيناريو 3: التحديث العادي وهو داخل النطاق
      else {
        await _trackingCollection.doc(delegateId).update({
          'currentDistanceMeters': distance,
          'lastLatitude': currentLat,
          'lastLongitude': currentLng,
          'speed': ?speed,
          'batteryLevel': ?batteryLevel,
          'isMoving': ?isMoving,
          'lastUpdated': FieldValue.serverTimestamp(),
          'isOnline': true,
          'currentStatus': 'inside',
        });
      }

      // تسجيل نقطة مسار في سجل التحركات (Breadcrumb trail)
      try {
        await _trackingCollection
            .doc(delegateId)
            .collection('breadcrumbs')
            .add({
          'latitude': currentLat,
          'longitude': currentLng,
          'timestamp': FieldValue.serverTimestamp(),
          'speed': speed ?? 0.0,
          'batteryLevel': ?batteryLevel,
          'distanceMeters': distance,
          'isInside': isNowInside,
        });
      } catch (err) {
        debugPrint('Error recording breadcrumb: $err');
      }
    } catch (e) {
      debugPrint('Error updating location and checking geofence: $e');
    }
  }

  /// 4.1 البث المباشر لمسار المندوب (Breadcrumb Trail) لرسم خط السير على الخريطة
  Stream<List<TrackingBreadcrumb>> streamBreadcrumbs({
    required String delegateId,
    int limit = 200,
  }) {
    return _trackingCollection
        .doc(delegateId)
        .collection('breadcrumbs')
        .orderBy('timestamp', descending: false)
        .limit(limit)
        .snapshots()
        .map((snap) => snap.docs
            .map((doc) => TrackingBreadcrumbModel.fromFirestore(doc))
            .toList());
  }

  /// 4.2 جلب مسار تحرك المندوب لليوم
  Future<List<TrackingBreadcrumb>> getTodayBreadcrumbs({
    required String delegateId,
    int limit = 300,
  }) async {
    try {
      final snap = await _trackingCollection
          .doc(delegateId)
          .collection('breadcrumbs')
          .orderBy('timestamp', descending: false)
          .limit(limit)
          .get();

      return snap.docs
          .map((doc) => TrackingBreadcrumbModel.fromFirestore(doc))
          .toList();
    } catch (e) {
      debugPrint('Error fetching breadcrumbs: $e');
      return [];
    }
  }

  /// 4.3 محاكاة وتوليد مسار تحرك ميداني حي للمندوب (لأغراض المعاينة والاختبار على لوحة الويب)
  Future<void> simulateDelegateMovement({
    required String delegateId,
    required double baseLat,
    required double baseLng,
    int? batteryLevel,
    double? speed,
  }) async {
    try {
      final now = DateTime.now();
      final batch = _firestore.batch();
      final crumbsRef =
          _trackingCollection.doc(delegateId).collection('breadcrumbs');

      // مسار تحرك واقعي مكون من 6 نقاط متتالية تنطلق من الفرع إلى الشارع الرئيسي
      final offsets = [
        {'dLat': 0.0000, 'dLng': 0.0000, 'speed': 0.0, 'battery': 88, 'dist': 0.0, 'inside': true},
        {'dLat': 0.0008, 'dLng': 0.0006, 'speed': 12.5, 'battery': 87, 'dist': 95.0, 'inside': true},
        {'dLat': 0.0021, 'dLng': 0.0016, 'speed': 24.0, 'battery': 86, 'dist': 260.0, 'inside': false},
        {'dLat': 0.0039, 'dLng': 0.0031, 'speed': 32.5, 'battery': 85, 'dist': 510.0, 'inside': false},
        {'dLat': 0.0055, 'dLng': 0.0048, 'speed': 28.0, 'battery': 84, 'dist': 780.0, 'inside': false},
        {'dLat': 0.0072, 'dLng': 0.0065, 'speed': 19.5, 'battery': 83, 'dist': 1120.0, 'inside': false},
      ];

      for (int i = 0; i < offsets.length; i++) {
        final off = offsets[i];
        final pointLat = baseLat + (off['dLat'] as double);
        final pointLng = baseLng + (off['dLng'] as double);
        final pointTime = now.subtract(Duration(minutes: (offsets.length - 1 - i) * 3));

        final crumbDoc = crumbsRef.doc();
        batch.set(crumbDoc, {
          'latitude': pointLat,
          'longitude': pointLng,
          'timestamp': Timestamp.fromDate(pointTime),
          'speed': off['speed'],
          'batteryLevel': off['battery'],
          'distanceMeters': off['dist'],
          'isInside': off['inside'],
        });
      }

      final lastOff = offsets.last;
      final currentLat = baseLat + (lastOff['dLat'] as double);
      final currentLng = baseLng + (lastOff['dLng'] as double);

      final sessionDocRef = _trackingCollection.doc(delegateId);
      batch.update(sessionDocRef, {
        'lastLatitude': currentLat,
        'lastLongitude': currentLng,
        'speed': speed ?? (lastOff['speed'] as double),
        'batteryLevel': batteryLevel ?? (lastOff['battery'] as int),
        'isMoving': true,
        'currentStatus': 'outside',
        'currentDistanceMeters': lastOff['dist'],
        'lastUpdated': FieldValue.serverTimestamp(),
        'isOnline': true,
      });

      await batch.commit();
    } catch (e) {
      debugPrint('Error simulating delegate movement: $e');
    }
  }

  /// 5. معالجة حالة انقطاع الاتصال (Offline) دون إرسال إنذار كاذب
  Future<void> markDelegateOffline(String delegateId) async {
    try {
      await _trackingCollection.doc(delegateId).update({
        'isOnline': false,
        'currentStatus': 'offline',
        'lastOfflineAt': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      debugPrint(
        'DelegateTrackingService: failed marking delegate offline: $e\n$st',
      );
    }
  }

  /// 6. تخزين مسارات الـ GPS محلياً أثناء انقطاع الإنترنت (Offline Breadcrumbs)
  Future<void> recordOfflineBreadcrumbLocally({
    required String delegateId,
    required double lat,
    required double lng,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'offline_tracking_crumbs_$delegateId';
      final existing = prefs.getStringList(key) ?? [];
      final item = '${DateTime.now().toIso8601String()},$lat,$lng';
      existing.add(item);
      // الاحتفاظ بآخر 100 نقطة فقط
      if (existing.length > 100) {
        existing.removeRange(0, existing.length - 100);
      }
      await prefs.setStringList(key, existing);
    } catch (e, st) {
      debugPrint(
        'DelegateTrackingService: failed recording offline breadcrumb: $e\n$st',
      );
    }
  }

  /// 7. مزامنة البيانات والمسار المسجل أثناء انقطاع النت فور استعادة الاتصال
  Future<void> syncOfflineBreadcrumbsOnReconnect({
    required String delegateId,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final key = 'offline_tracking_crumbs_$delegateId';
      final crumbs = prefs.getStringList(key);
      if (crumbs == null || crumbs.isEmpty) return;

      final doc = await _trackingCollection.doc(delegateId).get();
      if (!doc.exists) return;

      final session = DelegateTrackingSessionModel.fromFirestore(doc);
      final allowedThreshold = session.geofenceRadius + 50.0;

      bool breachOccurredWhileOffline = false;
      DateTime? firstBreachTime;
      double maxBreachDistance = 0.0;

      for (final crumb in crumbs) {
        final parts = crumb.split(',');
        if (parts.length >= 3) {
          final time = DateTime.tryParse(parts[0]);
          final lat = double.tryParse(parts[1]);
          final lng = double.tryParse(parts[2]);
          if (lat != null && lng != null) {
            final dist = Geolocator.distanceBetween(
              lat,
              lng,
              session.branchLat,
              session.branchLng,
            );
            if (dist > allowedThreshold) {
              breachOccurredWhileOffline = true;
              firstBreachTime ??= time;
              if (dist > maxBreachDistance) maxBreachDistance = dist;
            }
          }
        }
      }

      // مسح الكاش المحلي بعد الفحص
      await prefs.remove(key);

      // إذا حدث خروج فعلي أثناء فترة الأوفلاين، نبلغ المشرف بتوثيق دقيق
      if (breachOccurredWhileOffline && session.isTrackingEnabled) {
        final breachTimeStr = firstBreachTime != null
            ? DateFormat('hh:mm a', 'ar').format(firstBreachTime)
            : 'أثناء انقطاع الاتصال';

        await _sendGeofenceNotification(
          title: '⚠️ تنبيه خروج موثق (أثناء انقطاع الاتصال)',
          body:
              'تم رصد مغادرة المندوب ${session.delegateName} لنطاق فرع (${BranchDisplayCache.instance.displayName(session.branchName)}) أثناء انقطاع النت (وقت الخروج: $breachTimeStr).',
          type: 'geofence_breach_offline_sync',
          session: session,
          breachDistance: (maxBreachDistance - session.geofenceRadius).toInt(),
        );
      }
    } catch (e) {
      debugPrint('Error syncing offline breadcrumbs: $e');
    }
  }

  /// 8. إرسال إشعار للمشرفين في مجموعة notifications
  Future<void> _sendGeofenceNotification({
    required String title,
    required String body,
    required String type,
    required DelegateTrackingSession session,
    required int breachDistance,
  }) async {
    try {
      final now = DateTime.now();
      // TAS-71: a delegate cannot list `users` under the rules, so the
      // per-supervisor fan-out is gone. One `supervisor_<companyUID>`
      // broadcast is what the supervisor inbox reads; the create rule needs
      // `createdBy` == auth uid and the delegate's own company.
      if (session.companyId.isEmpty) {
        debugPrint('geofence alert skipped ($type): session has no company');
        return;
      }

      await _notificationsCollection.add({
        'title': title,
        'body': body,
        'type': type,
        'delegateUid': 'supervisor_${session.companyId}',
        'createdBy': _writerUid(session),
        'companyId': session.companyId,
        'companyUID': session.companyId,
        'organizationId': session.organizationId,
        'organizationUID': session.organizationId,
        'targetDelegateId': session.delegateId,
        'targetDelegateName': session.delegateName,
        'targetDelegatePhone': session.delegatePhone,
        'branchName': session.branchName,
        'breachDistanceMeters': breachDistance,
        'isRead': false,
        'read': false,
        'createdAt': Timestamp.fromDate(now),
        'deletedBy': <String>[],
      });
    } catch (e) {
      debugPrint('Error sending geofence notification: $e');
    }
  }

  /// 9. مزامنة الحاضرين اليوم تلقائياً إلى جلسات التتبع
  Future<void> populateTodayAttendanceToTracking({
    required String? companyId,
    required String? organizationId,
  }) async {
    try {
      CairoClock.ensureInitialized();
      final nowUtc = DateTime.now().toUtc();

      // جلب الفروع للحصول على إحداثياتها ونصف قطر الزون
      final branchesSnap = await _firestore.collection('branches').get();
      final Map<String, Map<String, dynamic>> branchesByName = {};
      for (final doc in branchesSnap.docs) {
        final data = doc.data();
        final name = (data['branchName'] ?? data['name'] ?? '').toString().trim().toLowerCase();
        if (name.isNotEmpty) {
          branchesByName[name] = {...data, 'id': doc.id};
        }
      }

      // جلب سجلات الحضور المعتمدة لليوم
      List<QueryDocumentSnapshot<Map<String, dynamic>>> attendanceDocs = [];
      if (companyId != null && companyId.isNotEmpty) {
        final snap = await _firestore
            .collection(kAttendanceCollection)
            .where('companyId', isEqualTo: companyId)
            .get();
        attendanceDocs = snap.docs;
        if (attendanceDocs.isEmpty) {
          final snapUid = await _firestore
              .collection(kAttendanceCollection)
              .where('companyUID', isEqualTo: companyId)
              .get();
          attendanceDocs = snapUid.docs;
        }
      } else if (organizationId != null && organizationId.isNotEmpty) {
        final snap = await _firestore
            .collection(kAttendanceCollection)
            .where('organizationId', isEqualTo: organizationId)
            .get();
        attendanceDocs = snap.docs;
        if (attendanceDocs.isEmpty) {
          final snapOrgUid = await _firestore
              .collection(kAttendanceCollection)
              .where('organizationUID', isEqualTo: organizationId)
              .get();
          attendanceDocs = snapOrgUid.docs;
        }
      } else {
        final snap = await _firestore.collection(kAttendanceCollection).get();
        attendanceDocs = snap.docs;
      }

      // تجميع أحدث تسجيل حضور اليوم لكل مندوب مع تتبع الانصرافات
      final Map<String, Map<String, dynamic>> latestCheckIns = {};
      final Map<String, DateTime> latestCheckOuts = {};

      for (final doc in attendanceDocs) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString();
        final delegateId = (data['delegateId'] ?? data['userId'] ?? '').toString().trim();
        if (delegateId.isEmpty) continue;

        DateTime? logTime;
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          logTime = ts.toDate();
        } else if (data['realTimestamp'] != null) {
          logTime = DateTime.tryParse(data['realTimestamp'].toString());
        } else if (data['createdAt'] != null) {
          logTime = DateTime.tryParse(data['createdAt'].toString());
        }

        if (logTime != null &&
            !CairoClock.isSameCairoCalendarDay(logTime, nowUtc)) {
          continue;
        }

        if (type == 'check_out') {
          if (logTime != null) {
            final prevOut = latestCheckOuts[delegateId];
            if (prevOut == null || logTime.isAfter(prevOut)) {
              latestCheckOuts[delegateId] = logTime;
            }
          }
        } else if (type.isEmpty || type == 'check_in') {
          final existing = latestCheckIns[delegateId];
          if (existing == null) {
            latestCheckIns[delegateId] = data;
          } else {
            final existingTs = existing['timestamp'] is Timestamp
                ? (existing['timestamp'] as Timestamp).toDate()
                : null;
            if (logTime != null && (existingTs == null || logTime.isAfter(existingTs))) {
              latestCheckIns[delegateId] = data;
            }
          }
        }
      }

      for (final entry in latestCheckIns.entries) {
        final delegateId = entry.key;
        final data = entry.value;

        final branchName = (data['branchName'] ?? '').toString().trim();
        final branchData = branchesByName[branchName.toLowerCase()] ?? {};

        // استخراج إحداثيات الموقع المسجل
        double? currentLat;
        double? currentLng;
        if (data['location'] is Map) {
          final loc = data['location'] as Map;
          currentLat = (loc['latitude'] as num?)?.toDouble() ??
              double.tryParse(loc['latitude']?.toString() ?? '');
          currentLng = (loc['longitude'] as num?)?.toDouble() ??
              double.tryParse(loc['longitude']?.toString() ?? '');
        }
        currentLat ??= (data['latitude'] as num?)?.toDouble() ??
            double.tryParse(data['latitude']?.toString() ?? '');
        currentLng ??= (data['longitude'] as num?)?.toDouble() ??
            double.tryParse(data['longitude']?.toString() ?? '');

        final double branchLat = (branchData['latitude'] as num?)?.toDouble() ??
            double.tryParse(branchData['latitude']?.toString() ?? '') ??
            (currentLat ?? 0.0);
        final double branchLng = (branchData['longitude'] as num?)?.toDouble() ??
            double.tryParse(branchData['longitude']?.toString() ?? '') ??
            (currentLng ?? 0.0);
        final double geofenceRadius =
            (branchData['geofenceRadius'] as num?)?.toDouble() ??
                double.tryParse(branchData['geofenceRadius']?.toString() ?? '') ??
                100.0;

        currentLat ??= branchLat;
        currentLng ??= branchLng;

        // جلب بيانات المندوب للاسم ورقم الهاتف والصورة
        String name = (data['delegateName'] ?? data['userName'] ?? '').toString().trim();
        String phone = (data['delegatePhone'] ?? data['userPhone'] ?? '').toString().trim();
        String avatarUrl = extractPhotoUrl(data);

        if (name.isEmpty || phone.isEmpty || avatarUrl.isEmpty) {
          try {
            if (organizationId != null &&
                organizationId.isNotEmpty &&
                companyId != null &&
                companyId.isNotEmpty) {
              final nestedDelDoc = await _firestore
                  .collection('organizations')
                  .doc(organizationId)
                  .collection('companies')
                  .doc(companyId)
                  .collection('delegates')
                  .doc(delegateId)
                  .get();
              if (nestedDelDoc.exists) {
                final dData = nestedDelDoc.data() ?? {};
                if (name.isEmpty) {
                  final rawFull = (dData['fullName'] ?? dData['name'])?.toString().trim();
                  final combined = '${dData['firstName'] ?? ''} ${dData['lastName'] ?? ''}'.trim();
                  name = (rawFull != null && rawFull.isNotEmpty) ? rawFull : combined;
                }
                if (phone.isEmpty) {
                  phone = (dData['phoneNumber'] ?? dData['phone'] ?? '').toString().trim();
                }
                if (avatarUrl.isEmpty) {
                  avatarUrl = extractPhotoUrl(dData);
                }
              }
            }

            if (name.isEmpty || phone.isEmpty || avatarUrl.isEmpty) {
              final delDoc = await _firestore.collection('delegates').doc(delegateId).get();
              if (delDoc.exists) {
                final dData = delDoc.data() ?? {};
                if (name.isEmpty) {
                  final rawFull = (dData['fullName'] ?? dData['name'])?.toString().trim();
                  final combined = '${dData['firstName'] ?? ''} ${dData['lastName'] ?? ''}'.trim();
                  name = (rawFull != null && rawFull.isNotEmpty) ? rawFull : combined;
                }
                if (phone.isEmpty) {
                  phone = (dData['phoneNumber'] ?? dData['phone'] ?? '').toString().trim();
                }
                if (avatarUrl.isEmpty) {
                  avatarUrl = extractPhotoUrl(dData);
                }
              }
            }
          } catch (e, st) {
            debugPrint(
              'DelegateTrackingService: populate nested delegate lookup failed: $e\n$st',
            );
          }

          if (name.isEmpty || phone.isEmpty || avatarUrl.isEmpty) {
            try {
              final userDoc = await _firestore.collection('users').doc(delegateId).get();
              final userData = userDoc.data() ?? {};
              if (name.isEmpty) {
                name = (userData['fullName'] ?? userData['name'] ?? userData['displayName'] ?? '').toString().trim();
              }
              if (phone.isEmpty) {
                phone = (userData['phoneNumber'] ?? userData['phone'] ?? '').toString().trim();
              }
              if (avatarUrl.isEmpty) {
                avatarUrl = extractPhotoUrl(userData);
              }
            } catch (e, st) {
              debugPrint(
                'DelegateTrackingService: populate users lookup failed: $e\n$st',
              );
            }
          }
        }
        if (name.isEmpty) name = 'مندوب';

        final checkInTs = data['timestamp'];
        final checkInTime = checkInTs is Timestamp
            ? checkInTs.toDate()
            : (checkInTs is String ? DateTime.tryParse(checkInTs) : null);

        // إذا كان المندوب قد انصرف أو انتهت ورديته (11.5 ساعة كاملة)، لا نضيفه للمتابعة الحية
        final outTime = latestCheckOuts[delegateId];
        if (checkInTime != null) {
          if (outTime != null && outTime.isAfter(checkInTime)) continue;
          if (nowUtc.difference(checkInTime.toUtc()) >= kAttendanceAutoCloseAfter) {
            continue;
          }
        }

        await initializeTrackingSession(
          delegateId: delegateId,
          delegateName: name,
          delegatePhone: phone,
          avatarUrl: avatarUrl.isNotEmpty ? avatarUrl : null,
          companyId: companyId ?? (data['companyId'] ?? '').toString(),
          organizationId: organizationId ?? (data['organizationId'] ?? '').toString(),
          branchId: (branchData['id'] ?? '').toString(),
          branchName: branchName.isNotEmpty ? branchName : 'الفرع الميداني',
          branchLat: branchLat,
          branchLng: branchLng,
          geofenceRadius: geofenceRadius,
          currentLat: currentLat,
          currentLng: currentLng,
          checkInTime: checkInTime ?? nowUtc,
        );
      }
    } catch (e, st) {
      debugPrint(
        'DelegateTrackingService: error populating today attendance: $e\n$st',
      );
    }
  }

  /// أداة استخراج رابط الصورة الشخصية للمندوب بمرونة من وثائق فايرستور
  static String extractPhotoUrl(Map<String, dynamic> data) {
    final direct = (data['avatarUrl'] ??
            data['photoURL'] ??
            data['photoUrl'] ??
            data['profileImageUrl'] ??
            data['personalPhotoURL'] ??
            data['personalPhotoUrl'] ??
            data['imageUrl'] ??
            data['userPhoto'])
        ?.toString()
        .trim();
    if (direct != null && direct.isNotEmpty && direct.startsWith('http')) {
      return direct;
    }
    final docs = data['documents'];
    if (docs is List) {
      for (final doc in docs) {
        if (doc is Map &&
            (doc['documentKey'] == 'personalPhoto' ||
                doc['key'] == 'personalPhoto' ||
                doc['type'] == 'personalPhoto')) {
          final url = (doc['documentURL'] ?? doc['url'] ?? doc['downloadUrl'])
              ?.toString()
              .trim();
          if (url != null && url.isNotEmpty && url.startsWith('http')) {
            return url;
          }
        }
      }
    }
    return '';
  }
}
