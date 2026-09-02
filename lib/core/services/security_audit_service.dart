import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:geolocator/geolocator.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// خدمة تدقيق الأمان ومكافحة التلاعب ورصد أجهزة الـ Fake Location
class SecurityAuditService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;

  /// تسجيل محاولة استخدام Fake GPS أو تزييف الموقع الجغرافي في سجل الأمان
  static Future<void> logMockLocationViolation({
    required Delegate delegate,
    required Position position,
    required String deviceModel,
    String? branchName,
    String? branchUID,
  }) async {
    try {
      final docRef = _firestore.collection('security_audit_logs').doc();

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
        'branchUID': branchUID ?? '',
        'branchName': branchName ?? '',
        'deviceModel': deviceModel.isNotEmpty ? deviceModel : 'Unknown Device',
        'violationType': 'fake_gps',
        'violationTitle': 'استخدام برنامج تزييف الموقع (Fake GPS)',
        'latitude': position.latitude,
        'longitude': position.longitude,
        'isMocked': true,
        'timestamp': FieldValue.serverTimestamp(),
        'createdAt': DateTime.now().toIso8601String(),
        'status': 'pending_review',
      });

      debugPrint('Security audit logged: Fake GPS attempt by ${delegate.fullName} on $deviceModel');
    } catch (e) {
      debugPrint('Error logging security audit: $e');
    }
  }
}
