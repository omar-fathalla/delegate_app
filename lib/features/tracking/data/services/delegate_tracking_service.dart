import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import '../models/delegate_tracking_session_model.dart';
import '../../domain/entities/delegate_tracking_session.dart';

class DelegateTrackingService {
  final FirebaseFirestore _firestore;

  DelegateTrackingService({FirebaseFirestore? firestore})
      : _firestore = firestore ?? FirebaseFirestore.instance;

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
      query = query.where('companyId', isEqualTo: companyId);
    } else if (organizationId != null && organizationId.isNotEmpty) {
      query = query.where('organizationId', isEqualTo: organizationId);
    }

    return query.snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => DelegateTrackingSessionModel.fromFirestore(doc))
          .toList();
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

      final session = DelegateTrackingSessionModel(
        delegateId: delegateId,
        delegateName: delegateName,
        delegatePhone: delegatePhone,
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
      );

      await _trackingCollection.doc(delegateId).set(session.toJson(), SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error initializing tracking session: $e');
    }
  }

  /// 4. فحص موقع المندوب وتحديث النطاق الجغرافي مع فترة سماح ذكية ورصد التزييف
  Future<void> updateLocationAndCheckGeofence({
    required String delegateId,
    required double currentLat,
    required double currentLng,
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
              'تم رصد استخدام برنامج تزييف موقع (Fake GPS) بواسطة المندوب ${session.delegateName} في فرع (${session.branchName}).',
          type: 'mock_location_alert',
          session: session,
          breachDistance: 0,
        );

        await _auditLogsCollection.add({
          'action': 'mock_location_detected_during_tracking',
          'type': 'security_violation',
          'delegateId': session.delegateId,
          'delegateName': session.delegateName,
          'delegatePhone': session.delegatePhone,
          'companyId': session.companyId,
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
                'المندوب ${session.delegateName} تجاوز نطاق فرع (${session.branchName}) بـ $breachMeters متر ومستمر خارج النطاق منذ $timeStr.',
            type: 'geofence_breach',
            session: session,
            breachDistance: breachMeters,
          );

          await _auditLogsCollection.add({
            'action': 'confirmed_geofence_breach_after_grace',
            'type': 'geofence_violation',
            'delegateId': session.delegateId,
            'delegateName': session.delegateName,
            'delegatePhone': session.delegatePhone,
            'companyId': session.companyId,
            'organizationId': session.organizationId,
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
          'lastUpdated': FieldValue.serverTimestamp(),
          'firstExitedAt': FieldValue.delete(),
          'isOnline': true,
        });

        if (hadConfirmedBreach) {
          await _sendGeofenceNotification(
            title: '🟢 عودة المندوب لنطاق الفرع',
            body:
                'عاد المندوب ${session.delegateName} إلى داخل نطاق فرع (${session.branchName}) في تمام الساعة $timeStr.',
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
          'lastUpdated': FieldValue.serverTimestamp(),
          'isOnline': true,
          'currentStatus': 'inside',
        });
      }
    } catch (e) {
      debugPrint('Error updating location and checking geofence: $e');
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
    } catch (_) {}
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
    } catch (_) {}
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
              'تم رصد مغادرة المندوب ${session.delegateName} لنطاق فرع (${session.branchName}) أثناء انقطاع النت (وقت الخروج: $breachTimeStr).',
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

      // 1. إرسال للمشرفين المباشرين لشركة المندوب
      if (session.companyId.isNotEmpty) {
        final supervisorSnap = await _firestore
            .collection('users')
            .where('companyUID', isEqualTo: session.companyId)
            .get();

        for (final doc in supervisorSnap.docs) {
          final data = doc.data();
          final role = (data['role'] ?? '').toString().toLowerCase();
          final pos = (data['position'] ?? '').toString().toLowerCase();

          if (role.contains('admin') ||
              role.contains('supervisor') ||
              pos.contains('supervisor')) {
            await _notificationsCollection.add({
              'title': title,
              'body': body,
              'type': type,
              'delegateUid': doc.id,
              'companyId': session.companyId,
              'organizationId': session.organizationId,
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
          }
        }
      }

      // 2. إرسال لبث المشرفين العام للشركة
      await _notificationsCollection.add({
        'title': title,
        'body': body,
        'type': type,
        'delegateUid': 'supervisor_${session.companyId}',
        'companyId': session.companyId,
        'organizationId': session.organizationId,
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
      final now = DateTime.now();
      final startOfDay = DateTime(now.year, now.month, now.day);
      final endOfDay = startOfDay.add(const Duration(days: 1));

      // جلب الفروع للحصول على إحداثياتها ونصف قطر الزون
      final branchesSnap = await _firestore.collection('branches').get();
      final Map<String, Map<String, dynamic>> branchesByName = {};
      for (final doc in branchesSnap.docs) {
        final data = doc.data();
        final name = (data['branchName'] ?? data['name'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          branchesByName[name] = data;
        }
      }

      Query<Map<String, dynamic>> attendanceQuery =
          _firestore.collection('attendance');

      if (companyId != null && companyId.isNotEmpty) {
        attendanceQuery = attendanceQuery.where('companyId', isEqualTo: companyId);
      } else if (organizationId != null && organizationId.isNotEmpty) {
        attendanceQuery =
            attendanceQuery.where('organizationId', isEqualTo: organizationId);
      }

      final attendanceSnap = await attendanceQuery.get();

      for (final doc in attendanceSnap.docs) {
        final data = doc.data();
        final type = (data['type'] ?? '').toString();
        if (type != 'check_in') continue;

        final ts = data['timestamp'];
        if (ts is Timestamp) {
          final date = ts.toDate();
          if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) continue;
        }

        final delegateId = (data['delegateId'] ?? data['userId'] ?? '').toString();
        if (delegateId.isEmpty) continue;

        final branchName = (data['branchName'] ?? '').toString();
        final branchData = branchesByName[branchName] ?? {};

        final double branchLat = (branchData['latitude'] as num?)?.toDouble() ??
            (data['location']?['latitude'] as num?)?.toDouble() ??
            0.0;
        final double branchLng =
            (branchData['longitude'] as num?)?.toDouble() ??
                (data['location']?['longitude'] as num?)?.toDouble() ??
                0.0;
        final double geofenceRadius =
            (branchData['geofenceRadius'] as num?)?.toDouble() ?? 100.0;

        final trackingDoc = await _trackingCollection.doc(delegateId).get();
        if (!trackingDoc.exists) {
          // جلب بيانات المندوب للاسم ورقم الهاتف
          final userDoc = await _firestore.collection('users').doc(delegateId).get();
          final userData = userDoc.data() ?? {};
          final name = (userData['fullName'] ?? userData['name'] ?? 'مندوب').toString();
          final phone = (userData['phoneNumber'] ?? userData['phone'] ?? '').toString();

          await initializeTrackingSession(
            delegateId: delegateId,
            delegateName: name,
            delegatePhone: phone,
            companyId: companyId ?? (data['companyId'] ?? '').toString(),
            organizationId: organizationId ?? (data['organizationId'] ?? '').toString(),
            branchId: (branchData['id'] ?? '').toString(),
            branchName: branchName.isNotEmpty ? branchName : 'الفرع الميداني',
            branchLat: branchLat,
            branchLng: branchLng,
            geofenceRadius: geofenceRadius,
            currentLat: branchLat,
            currentLng: branchLng,
            checkInTime: ts is Timestamp ? ts.toDate() : now,
          );
        }
      }
    } catch (e) {
      debugPrint('Error populating today attendance to tracking: $e');
    }
  }
}
