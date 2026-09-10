import 'dart:io';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:device_info_plus/device_info_plus.dart';
import 'package:flutter/foundation.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:uuid/uuid.dart';
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
      if (Platform.isAndroid) {
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
        deviceId = 'web_or_desktop_${Platform.operatingSystem}';
        deviceModel = Platform.operatingSystem;
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
    final currentBrand = deviceDetails['brand'] ?? '';
    final currentOsVersion = deviceDetails['osVersion'] ?? '';

    final boundDeviceId = delegate.boundDeviceId?.trim() ?? '';
    final boundDeviceModel = delegate.boundDeviceModel?.trim() ?? '';

    // 3. الحالة الأولى: الحساب غير مقترن بأي جهاز حتى الآن (أول تسجيل دخول أو بعد Reset)
    if (boundDeviceId.isEmpty) {
      try {
        await _updateDelegateDeviceInFirestore(
          delegate: delegate,
          deviceId: currentDeviceId,
          deviceModel: currentDeviceModel,
          brand: currentBrand,
          osVersion: currentOsVersion,
        );

        debugPrint('Device successfully bound for delegate ${delegate.fullName}: $currentDeviceModel ($currentDeviceId)');

        return DeviceVerificationResult(
          status: DeviceVerificationStatus.boundNew,
          currentDeviceId: currentDeviceId,
          currentDeviceModel: currentDeviceModel,
          message: 'تم اعتماد وربط هذا الجهاز لحسابك بنجاح',
        );
      } catch (e) {
        debugPrint('Error binding device to Firestore: $e');
        // في حال حدوث خطأ في الشبكة، نسمح بالمرور
        return DeviceVerificationResult(
          status: DeviceVerificationStatus.boundNew,
          currentDeviceId: currentDeviceId,
          currentDeviceModel: currentDeviceModel,
        );
      }
    }

    // 4. الحالة الثانية: الجهاز الحالي مطابق للجهاز المعتمد
    if (boundDeviceId == currentDeviceId) {
      // تحديث وقت آخر ظهور للجهاز في الخلفية
      _touchDeviceLastSeen(delegate).ignore();

      return DeviceVerificationResult(
        status: DeviceVerificationStatus.allowed,
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

  /// تحديث بيانات الربط في مستند المندوب بـ Firestore
  static Future<void> _updateDelegateDeviceInFirestore({
    required Delegate delegate,
    required String deviceId,
    required String deviceModel,
    required String brand,
    required String osVersion,
  }) async {
    final updateData = {
      'boundDeviceId': deviceId,
      'boundDeviceModel': deviceModel,
      'boundDeviceBrand': brand,
      'boundDeviceOs': osVersion,
      'deviceBoundAt': FieldValue.serverTimestamp(),
      'deviceLastSeenAt': FieldValue.serverTimestamp(),
      'isDeviceLocked': true,
    };

    // المسار المباشر إن توفرت معرفات المنظمة والشركة
    if (delegate.organizationUID.isNotEmpty &&
        delegate.companyUID.isNotEmpty &&
        delegate.uid.isNotEmpty) {
      final docRef = _firestore
          .collection('organizations')
          .doc(delegate.organizationUID)
          .collection('companies')
          .doc(delegate.companyUID)
          .collection('delegates')
          .doc(delegate.uid);

      await docRef.set(updateData, SetOptions(merge: true));
      return;
    }

    // البحث عن المستند عبر collectionGroup
    final snap = await _firestore
        .collectionGroup('delegates')
        .where('phoneNumber', isEqualTo: delegate.phoneNumber)
        .get();

    for (final doc in snap.docs) {
      if (doc.id == delegate.uid || doc.data()['nationalityID'] == delegate.nationalityID) {
        await doc.reference.set(updateData, SetOptions(merge: true));
      }
    }
  }

  /// تحديث توقيت آخر نشاط للجهاز
  static Future<void> _touchDeviceLastSeen(Delegate delegate) async {
    try {
      if (delegate.organizationUID.isNotEmpty &&
          delegate.companyUID.isNotEmpty &&
          delegate.uid.isNotEmpty) {
        await _firestore
            .collection('organizations')
            .doc(delegate.organizationUID)
            .collection('companies')
            .doc(delegate.companyUID)
            .collection('delegates')
            .doc(delegate.uid)
            .update({'deviceLastSeenAt': FieldValue.serverTimestamp()});
      }
    } catch (_) {}
  }

  /// توثيق محاولة الدخول المخالفة في سجل الأمان
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

  /// فك ربط جهاز المندوب (إعادة تعيين الجهاز من قبل المدير أو الدعم الفني)
  static Future<void> resetDelegateDeviceBinding({
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

    // البحث عن المستند عبر collectionGroup
    final snap = await _firestore.collectionGroup('delegates').get();
    for (final doc in snap.docs) {
      if (doc.id == delegateUid) {
        await doc.reference.update(resetData);
        return;
      }
    }
  }
}
