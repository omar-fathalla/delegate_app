import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// نتيجة التحقق من بصمة الجهاز
enum DeviceVerificationStatus {
  allowed, // الجهاز مطابق ومصرح له
  boundNew, // تم ربط الجهاز الحالي كجهاز معتمد لأول مرة
  mismatched, // الجهاز غير مطابق لجهاز المندوب المعتمد
  bypassed, // تم التجاوز للرتب الإدارية والمشرفين
}

class DeviceVerificationResult {
  final DeviceVerificationStatus status;
  final String? boundDeviceModel;
  final String? currentDeviceModel;
  final String? currentDeviceId;
  final String? message;

  const DeviceVerificationResult({
    required this.status,
    this.boundDeviceModel,
    this.currentDeviceModel,
    this.currentDeviceId,
    this.message,
  });

  bool get isAllowed =>
      status == DeviceVerificationStatus.allowed ||
      status == DeviceVerificationStatus.boundNew ||
      status == DeviceVerificationStatus.bypassed;

  bool get isMismatched => status == DeviceVerificationStatus.mismatched;
}

/// خدمة ربط وقفل أجهزة المناديب بالعتاد ومنع فتح الحسابات من أجهزة أخرى
class DeviceBindingService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static final DeviceInfoPlugin _deviceInfoPlugin = DeviceInfoPlugin();

  /// رقم الدعم الفني المعتمد لفك ربط الأجهزة
  static const String technicalSupportPhone = '01211857725';

  /// استخراج بصمة ومعلومات العتاد للجهاز الحالي
  static Future<Map<String, String>> getCurrentDeviceDetails() async {
    String deviceId = '';
    String deviceModel = 'Unknown Device';
    String brand = '';
    String osVersion = '';

    try {
      if (kIsWeb) {
        deviceId = 'web_browser';
        deviceModel = 'Web Browser';
        brand = 'Browser';
        osVersion = 'Web';
      } else if (Platform.isAndroid) {
        final androidInfo = await _deviceInfoPlugin.androidInfo;
        deviceId = androidInfo.id;
        brand = androidInfo.brand;
        final model = androidInfo.model;
        deviceModel = brand.isNotEmpty ? '$brand $model'.trim() : model;
        osVersion = 'Android ${androidInfo.version.release} (SDK ${androidInfo.version.sdkInt})';
      } else if (Platform.isIOS) {
        final iosInfo = await _deviceInfoPlugin.iosInfo;
        deviceId = iosInfo.identifierForVendor ?? '';
        brand = 'Apple';
        final name = iosInfo.name;
        final model = iosInfo.model;
        deviceModel = name.isNotEmpty ? name : model;
        osVersion = 'iOS ${iosInfo.systemVersion}';
      } else {
        deviceId = 'desktop_platform';
        deviceModel = 'Desktop';
      }
    } catch (e) {
      debugPrint('Error reading device info: $e');
    }

    // Fallback if deviceId is somehow empty
    if (deviceId.isEmpty) {
      final prefs = await SharedPreferences.getInstance();
      var persistentId = prefs.getString('persistent_app_device_uuid');
      if (persistentId == null || persistentId.isEmpty) {
        persistentId = const Uuid().v4();
        await prefs.setString('persistent_app_device_uuid', persistentId);
      }
      deviceId = 'uuid_$persistentId';
    }

    return {
      'deviceId': deviceId.trim(),
      'deviceModel': deviceModel.trim(),
      'brand': brand.trim(),
      'osVersion': osVersion.trim(),
    };
  }

  /// التحقق من مطابقة الجهاز أو ربطه تلقائياً لأول مرة
  static Future<DeviceVerificationResult> verifyOrBindDevice({
    required Delegate delegate,
  }) async {
    // Web never reads a device id, compares a binding, or writes one.
    if (!WebRuntimePolicy.delegateDeviceBindingEnabled) {
      return const DeviceVerificationResult(
        status: DeviceVerificationStatus.bypassed,
        message: 'تم تجاوز فحص الجهاز على الويب',
      );
    }

    // 1. استثناء الرتب الإدارية والمشرفين (الحماية تطبق فقط على المندوب)
    if (delegate.role != UserRole.delegate) {
      return const DeviceVerificationResult(
        status: DeviceVerificationStatus.bypassed,
        message: 'تم تجاوز فحص الجهاز للرتب الإدارية',
      );
    }

    // 2. استخراج بيانات الجهاز الحالي
    final deviceDetails = await getCurrentDeviceDetails();
    final currentDeviceId = deviceDetails['deviceId'] ?? '';
    final currentDeviceModel = deviceDetails['deviceModel'] ?? 'جهاز غير معروف';

    final boundDeviceId = delegate.boundDeviceId?.trim() ?? '';
    final boundDeviceModel = delegate.boundDeviceModel?.trim() ?? '';

    // The server binds on delegateLoginV2. An empty field means there is no
    // legacy binding to compare (or the mirror has not arrived). Do not write
    // the binding from the client.
    if (boundDeviceId.isEmpty || boundDeviceId == currentDeviceId) {
      return DeviceVerificationResult(
        status: boundDeviceId.isEmpty
            ? DeviceVerificationStatus.boundNew
            : DeviceVerificationStatus.allowed,
        boundDeviceModel: boundDeviceModel,
        currentDeviceModel: currentDeviceModel,
        currentDeviceId: currentDeviceId,
      );
    }

    // 5. الحالة الثالثة: محاولة فتح من جهاز مختلف! (Device Mismatch / Unauthorized)
    debugPrint('UNAUTHORIZED DEVICE MISMATCH for delegate: ${delegate.fullName}. Bound: $boundDeviceModel ($boundDeviceId) vs Current: $currentDeviceModel ($currentDeviceId)');

    // توثيق المحاولة في سجل الأمان وكشف التزييف تلقائياً
    _logUnauthorizedDeviceAttempt(
      delegate: delegate,
      boundDeviceModel: boundDeviceModel,
      currentDeviceModel: currentDeviceModel,
      currentDeviceId: currentDeviceId,
    ).ignore();

    return DeviceVerificationResult(
      status: DeviceVerificationStatus.mismatched,
      boundDeviceModel: boundDeviceModel.isNotEmpty ? boundDeviceModel : 'جهاز معتمد سابق',
      currentDeviceModel: currentDeviceModel,
      currentDeviceId: currentDeviceId,
      message: 'هذا الحساب مقترن بجهاز آخر ($boundDeviceModel). يُرجى استخدام جهازك المعتمد أو التواصل مع الدعم الفني.',
    );
  }

  /// يسجّل موافقة فورية على فك الربط. تسجيل الدخول التالي يعيد الربط.
  static Future<void> resetDelegateDeviceBinding({
    required String delegateUid,
    String? organizationUID,
    String? companyUID,
    String? adminUid,
  }) async {
    final requestRef = _firestore.collection('device_unbind_requests').doc();
    await requestRef.set({
      'id': requestRef.id,
      'delegateUid': delegateUid,
      'organizationUID': organizationUID ?? '',
      'companyUID': companyUID ?? '',
      'status': 'approved',
      'reason': 'فك الربط من الإدارة',
      'createdAt': FieldValue.serverTimestamp(),
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': adminUid ?? 'admin',
      'requestedDeviceId': '',
    });
    try {
      await _clearMirroredBinding(
        delegateUid: delegateUid,
        organizationUID: organizationUID,
        companyUID: companyUID,
        adminUid: adminUid,
      );
    } catch (e) {
      debugPrint('Mirrored device fields were left for the server to replace: $e');
    }
  }

  static Future<void> _clearMirroredBinding({
    required String delegateUid,
    String? organizationUID,
    String? companyUID,
    String? adminUid,
  }) async {
    final resetData = {
      'boundDeviceId': FieldValue.delete(),
      'boundDeviceModel': FieldValue.delete(),
      'boundDeviceBrand': FieldValue.delete(),
      'boundDeviceOs': FieldValue.delete(),
      'deviceBoundAt': FieldValue.delete(),
      'isDeviceLocked': false,
      'deviceResetAt': FieldValue.serverTimestamp(),
      'deviceResetBy': adminUid ?? 'admin',
    };

    if (organizationUID != null &&
        organizationUID.isNotEmpty &&
        companyUID != null &&
        companyUID.isNotEmpty) {
      final docRef = _firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .collection('delegates')
          .doc(delegateUid);

      await docRef.update(resetData);
      return;
    }

    // TAS-75: no unscoped collection-group scan to find the doc. The rules
    // deny that list, and the approved device_unbind_requests doc already
    // tells the server to replace the binding.
    debugPrint('Device binding mirror skipped for $delegateUid: no org/company.');
  }
  static Future<void> _logUnauthorizedDeviceAttempt({
    required Delegate delegate,
    required String boundDeviceModel,
    required String currentDeviceModel,
    required String currentDeviceId,
  }) async {
    try {
      final docRef = _firestore.collection('security_audit_logs').doc();
      final now = DateTime.now();

      await docRef.set({
        'id': docRef.id,
        'delegateUid': delegate.uid,
        'delegateName': delegate.fullName.isNotEmpty
            ? delegate.fullName
            : '${delegate.firstName} ${delegate.lastName}'.trim(),
        'delegatePhone': delegate.phoneNumber,
        'organizationUID': delegate.organizationUID,
        'companyUID': delegate.companyUID,
        'companyName': delegate.companyName,
        'branchName': 'محاولة تبديل جهاز',
        'actionType': 'محاولة تسجيل دخول من جهاز غير مصرح به',
        'deviceModel': currentDeviceModel,
        'currentDeviceId': currentDeviceId,
        'boundDeviceModel': boundDeviceModel,
        'violationType': 'unauthorized_device_mismatch',
        'violationTitle': 'محاولة فتح الحساب من هاتف غير مقترن',
        'isMocked': false,
        'timestamp': FieldValue.serverTimestamp(),
        'realTimestamp': now.toIso8601String(),
        'createdAt': now.toIso8601String(),
        'status': 'blocked',
      });
    } catch (_) {}
  }

  /// التحقق مما إذا كان لدى المندوب طلب فك ارتباط معلق حالياً.
  /// `delegateLoginV2` auto-upserts a pending doc on a device mismatch.
  static Future<bool> hasPendingUnbindRequest(String delegateUid) async {
    try {
      return await _pendingUnbindExists(delegateUid);
    } catch (e) {
      debugPrint('Error checking pending unbind request: $e');
      return false;
    }
  }

  static Future<bool> _pendingUnbindExists(String delegateUid) async {
    final snap = await _firestore
        .collection('device_unbind_requests')
        .where('delegateUid', isEqualTo: delegateUid)
        .where('status', isEqualTo: 'pending')
        .limit(1)
        .get();
    return snap.docs.isNotEmpty;
  }

  /// إرسال طلب فك ارتباط الجهاز القديم من قبل المندوب.
  ///
  /// Idempotent with `delegateLoginV2`: if a pending request already
  /// exists (including one the server upserted on mismatch), this does
  /// not create a second document and returns false. If the pending
  /// lookup fails, it also skips create so a second request cannot be
  /// written by accident.
  static Future<bool> submitUnbindRequest({
    required Delegate delegate,
    String? currentDeviceModel,
    String? currentDeviceId,
    String? reason,
  }) async {
    try {
      try {
        if (await _pendingUnbindExists(delegate.uid)) return false;
      } catch (e) {
        debugPrint('Error checking pending unbind request before submit: $e');
        return false;
      }

      String devModel = currentDeviceModel ?? '';
      String devId = currentDeviceId ?? '';
      if (devModel.isEmpty || devId.isEmpty) {
        final details = await getCurrentDeviceDetails();
        if (devModel.isEmpty) devModel = details['deviceModel'] ?? 'Unknown Device';
        if (devId.isEmpty) devId = details['deviceId'] ?? '';
      }

      final docRef = _firestore.collection('device_unbind_requests').doc();
      await docRef.set({
        'id': docRef.id,
        'delegateUid': delegate.uid,
        'delegateName': delegate.fullName.isNotEmpty
            ? delegate.fullName
            : '${delegate.firstName} ${delegate.lastName}'.trim(),
        'delegatePhone': delegate.phoneNumber,
        'organizationUID': delegate.organizationUID,
        'companyUID': delegate.companyUID,
        'companyName': delegate.companyName,
        'boundDeviceId': delegate.boundDeviceId ?? '',
        'boundDeviceModel': delegate.boundDeviceModel ?? '',
        'requestedDeviceModel': devModel,
        'requestedDeviceId': devId,
        'status': 'pending',
        'reason': reason ?? 'طلب فك ارتباط الجهاز القديم لاستبدال الهاتف',
        'createdAt': FieldValue.serverTimestamp(),
      });
      return true;
    } catch (e) {
      debugPrint('Error submitting unbind request: $e');
      rethrow;
    }
  }

  /// TAS-51: a non-global staff notification must carry the sender's own
  /// organization or company (the rules no longer accept `createdBy` alone).
  /// Read from the admin's own users doc; empty values are left out.
  @visibleForTesting
  static Future<Map<String, String>> unbindNotificationTenant(String adminUid) async {
    try {
      final data = (await _firestore.collection('users').doc(adminUid).get()).data() ??
          const <String, dynamic>{};
      return callerTenantFields(data);
    } catch (e) {
      debugPrint('unbind notification: own tenant not read: $e');
      return const <String, String>{};
    }
  }

  /// The caller's own `organizationUID` / `companyUID` from a users doc.
  @visibleForTesting
  static Map<String, String> callerTenantFields(Map<String, dynamic> user) {
    String pick(String a, String b) {
      final v = (user[a] ?? user[b] ?? '').toString().trim();
      return v == 'all' ? '' : v;
    }
    final org = pick('organizationUID', 'organizationId');
    final co = pick('companyUID', 'companyId');
    return {
      if (org.isNotEmpty) 'organizationUID': org,
      if (co.isNotEmpty) 'companyUID': co,
    };
  }

  /// الموافقة على طلب فك الارتباط من قِبل الإدارة
  static Future<void> approveUnbindRequest({
    required String requestId,
    required String delegateUid,
    String? organizationUID,
    String? companyUID,
    required String adminUid,
    required String adminName,
  }) async {
    // 1. فك ربط جهاز المندوب
    try {
      await _clearMirroredBinding(
        delegateUid: delegateUid,
        organizationUID: organizationUID,
        companyUID: companyUID,
        adminUid: adminUid,
      );
    } catch (e) {
      debugPrint('Mirrored device fields were left for the server to replace: $e');
    }

    await _firestore.collection('device_unbind_requests').doc(requestId).update({
      'status': 'approved',
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': adminUid,
      'resolvedByName': adminName,
    });

    // 3. إرسال إشعار للمندوب
    try {
      await _firestore.collection('notifications').add({
        ...await unbindNotificationTenant(adminUid),
        'delegateUid': delegateUid,
        'title': 'تمت الموافقة على فك ربط جهازك',
        'body': 'تم فك ربط هاتفك القديم بنجاح. يمكنك الآن تسجيل الدخول من جهازك الجديد وسيتم اعتماده تلقائياً.',
        'type': 'device_unbound',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
        'senderName': adminName,
      });
    } catch (e) {
      debugPrint('Error sending unbind approval notification: $e');
    }
  }

  /// رفض طلب فك الارتباط من قِبل الإدارة
  static Future<void> rejectUnbindRequest({
    required String requestId,
    required String delegateUid,
    required String adminUid,
    required String adminName,
    String? reason,
  }) async {
    final rejectMsg = reason?.trim().isNotEmpty == true
        ? reason!.trim()
        : 'تم رفض طلب فك ارتباط الجهاز من قبل الإدارة';

    // 1. تحديث حالة الطلب إلى مرفوض
    await _firestore.collection('device_unbind_requests').doc(requestId).update({
      'status': 'rejected',
      'rejectReason': rejectMsg,
      'resolvedAt': FieldValue.serverTimestamp(),
      'resolvedBy': adminUid,
      'resolvedByName': adminName,
    });

    // 2. إرسال إشعار للمندوب
    try {
      await _firestore.collection('notifications').add({
        ...await unbindNotificationTenant(adminUid),
        'delegateUid': delegateUid,
        'title': 'تم رفض طلب فك ربط الجهاز',
        'body': rejectMsg,
        'type': 'device_unbind_rejected',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': adminUid,
        'senderName': adminName,
      });
    } catch (e) {
      debugPrint('Error sending unbind rejection notification: $e');
    }
  }
}
