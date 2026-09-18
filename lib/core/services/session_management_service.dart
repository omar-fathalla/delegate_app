import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// نتيجة فحص صلاحية جلسة المندوب
class SessionVerificationResult {
  final bool isValid;
  final String? reason;
  final bool companyChanged;
  final String? newCompanyUID;
  final String? newCompanyName;

  const SessionVerificationResult({
    required this.isValid,
    this.reason,
    this.companyChanged = false,
    this.newCompanyUID,
    this.newCompanyName,
  });

  const SessionVerificationResult.valid()
      : isValid = true,
        reason = null,
        companyChanged = false,
        newCompanyUID = null,
        newCompanyName = null;

  const SessionVerificationResult.invalid({
    required this.reason,
    this.companyChanged = false,
    this.newCompanyUID,
    this.newCompanyName,
  }) : isValid = false;
}

/// خدمة مركزية لإدارة جلسات المناديب والخروج الإجباري (فردي وجماعي)
class SessionManagementService {
  static final FirebaseFirestore _firestore = FirebaseFirestore.instance;
  static const String defaultOrgId = 'PiioBFgxaHAeuRdjlDgj';

  /// فحص صلاحية جلسة المندوب المسجل محلياً
  static Future<SessionVerificationResult> checkSessionStatus({
    required Delegate delegate,
  }) async {
    // الرتب الإدارية والمشرفون لا ينطبق عليهم خروج المناديب الإجباري
    if (delegate.role != UserRole.delegate) {
      return const SessionVerificationResult.valid();
    }

    try {
      final orgId = delegate.organizationUID.isNotEmpty
          ? delegate.organizationUID
          : defaultOrgId;
      final compId = delegate.companyUID;

      // 1. فحص إبطال الجلسة العام (Global Emergency Reset)
      try {
        final globalConfigDoc = await _firestore
            .collection('system_config')
            .doc('session_control')
            .get();

        if (globalConfigDoc.exists && globalConfigDoc.data() != null) {
          final gData = globalConfigDoc.data()!;
          final globalResetAt = gData['globalForceLogoutBefore'] as Timestamp?;
          if (globalResetAt != null) {
            // إذا تم تفعيل إعادة التعيين العام بعد وقت إنشاء الجلسة، الجلسة ملغاة
            final sessionCreatedAt = delegate.createdAt;
            if (globalResetAt.toDate().isAfter(sessionCreatedAt)) {
              return SessionVerificationResult.invalid(
                reason: gData['reason'] as String? ??
                    'تم إنهاء الجلسة بواسطة الإدارة لتحديث عام في النظام. يُرجى تسجيل الدخول مجدداً.',
              );
            }
          }
        }
      } catch (_) {}

      // 2. فحص مستند المندوب المباشر في شركته المسجلة
      if (compId.isNotEmpty) {
        final delegateDoc = await _firestore
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(compId)
            .collection('delegates')
            .doc(delegate.uid)
            .get();

        if (delegateDoc.exists && delegateDoc.data() != null) {
          final data = delegateDoc.data()!;
          final requireReLogin = data['requireReLogin'] == true;
          if (requireReLogin) {
            final reason = data['forceLogoutReason'] as String? ??
                'تم إنهاء جلستك من الإدارة لتحديث بيانات الشركة. يُرجى إعادة تسجيل الدخول برقم الهاتف والرقم القومي.';
            return SessionVerificationResult.invalid(reason: reason);
          }

          // تحقق إضافي: هل تم تفعيل خروج جماعي لشركته؟
          final companyDoc = await _firestore
              .collection('organizations')
              .doc(orgId)
              .collection('companies')
              .doc(compId)
              .get();
          if (companyDoc.exists && companyDoc.data() != null) {
            final compData = companyDoc.data()!;
            final compResetAt = compData['delegatesForceLogoutAt'] as Timestamp?;
            if (compResetAt != null) {
              final sessionCreatedAt = delegate.createdAt;
              if (compResetAt.toDate().isAfter(sessionCreatedAt)) {
                return SessionVerificationResult.invalid(
                  reason: compData['forceLogoutReason'] as String? ??
                      'تم إنهاء جلسات مناديب الشركة لتحديث البيانات. يُرجى تسجيل الدخول برقم الهاتف والرقم القومي.',
                );
              }
            }
          }

          return const SessionVerificationResult.valid();
        }
      }

      // 3. إذا لم يتم العثور على مستند المندوب في شركته القديمة، نبحث برقم الهاتف لمعرفة ما إذا تم نقله لشركة أخرى!
      if (delegate.phoneNumber.isNotEmpty) {
        final querySnap = await _firestore
            .collectionGroup('delegates')
            .where('phoneNumber', isEqualTo: delegate.phoneNumber)
            .limit(1)
            .get();

        if (querySnap.docs.isNotEmpty) {
          final newDoc = querySnap.docs.first;
          final newData = newDoc.data();
          final newCompId = newData['companyUID'] as String? ?? '';
          final newCompName = newData['companyName'] as String? ?? '';

          if (newCompId != compId && newCompId.isNotEmpty) {
            return SessionVerificationResult.invalid(
              reason: 'تم نقلك إلى شركة "$newCompName". يُرجى تسجيل الدخول برقم الهاتف والرقم القومي لاعتماد بياناتك الجديدة.',
              companyChanged: true,
              newCompanyUID: newCompId,
              newCompanyName: newCompName,
            );
          }
        }
      }

      return const SessionVerificationResult.valid();
    } catch (e) {
      debugPrint('Error in SessionManagementService.checkSessionStatus: $e');
      // في حال تعذر الاتصال بالشبكة تماماً، لا نمنع المندوب ونسمح بالمرور
      return const SessionVerificationResult.valid();
    }
  }

  /// إزالة علامة طلب إعادة تسجيل الدخول فور تسجيل المندوب الدخول بنجاح
  static Future<void> clearReLoginFlag({
    required String delegateUid,
    required String organizationUID,
    required String companyUID,
  }) async {
    final orgId = organizationUID.isNotEmpty ? organizationUID : defaultOrgId;
    if (delegateUid.isEmpty) return;

    try {
      // 1. التحقق وتحديث مستند المندوب في شركته إذا كان موجوداً
      if (companyUID.isNotEmpty) {
        final delegateDocRef = _firestore
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .doc(delegateUid);

        final docSnap =
            await delegateDocRef.get().timeout(const Duration(seconds: 3));
        if (docSnap.exists) {
          await delegateDocRef.update({
            'requireReLogin': false,
            'reLoginCompletedAt': FieldValue.serverTimestamp(),
          }).timeout(const Duration(seconds: 3));
          return;
        }
      }

      // 2. التحقق وتحديث مستند المستخدم في users (للمديرين والمشرفين والدعم الفني)
      final userDocRef = _firestore.collection('users').doc(delegateUid);
      final userSnap =
          await userDocRef.get().timeout(const Duration(seconds: 3));
      if (userSnap.exists) {
        await userDocRef.update({
          'requireReLogin': false,
          'reLoginCompletedAt': FieldValue.serverTimestamp(),
        }).timeout(const Duration(seconds: 3));
      }
    } catch (e) {
      debugPrint('Error in clearReLoginFlag: $e');
    }
  }

  /// تسجيل خروج إجباري لمندوب فردي (Force Logout Delegate)
  static Future<bool> forceLogoutDelegate({
    required String delegateUid,
    required String organizationUID,
    required String companyUID,
    String? delegateName,
    String? delegatePhone,
    String? reason,
    String? adminUid,
  }) async {
    final orgId = organizationUID.isNotEmpty ? organizationUID : defaultOrgId;
    if (delegateUid.isEmpty) return false;

    final defaultReason = reason ??
        'تم إنهاء الجلسة من الإدارة لتحديث بيانات الشركة. يُرجى تسجيل الدخول برقم الهاتف والرقم القومي.';

    try {
      // إذا كان معرّف الشركة معروفاً
      if (companyUID.isNotEmpty) {
        await _firestore
            .collection('organizations')
            .doc(orgId)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .doc(delegateUid)
            .update({
          'requireReLogin': true,
          'forceLogoutAt': FieldValue.serverTimestamp(),
          'forceLogoutReason': defaultReason,
          'forceLogoutBy': adminUid ?? 'super-admin',
        });
      } else {
        // البحث عبر collectionGroup وتحديث كل مستندات المندوب بهذا المعرّف
        final docs = await _firestore
            .collectionGroup('delegates')
            .where('uid', isEqualTo: delegateUid)
            .get();

        final batch = _firestore.batch();
        for (final doc in docs.docs) {
          batch.update(doc.reference, {
            'requireReLogin': true,
            'forceLogoutAt': FieldValue.serverTimestamp(),
            'forceLogoutReason': defaultReason,
            'forceLogoutBy': adminUid ?? 'super-admin',
          });
        }
        await batch.commit();
      }

      // توثيق العملية في سجل الأمان
      _logSessionAction(
        actionType: 'إنهاء جلسة مندوب (فردي)',
        delegateUid: delegateUid,
        delegateName: delegateName,
        delegatePhone: delegatePhone,
        companyUID: companyUID,
        organizationUID: orgId,
        adminUid: adminUid,
        reason: defaultReason,
      ).ignore();

      return true;
    } catch (e) {
      debugPrint('Error in forceLogoutDelegate: $e');
      return false;
    }
  }

  /// تسجيل خروج إجباري لجميع مناديب شركة محددة (Bulk Force Logout by Company)
  static Future<int> forceLogoutCompany({
    required String organizationUID,
    required String companyUID,
    String? companyName,
    String? reason,
    String? adminUid,
  }) async {
    final orgId = organizationUID.isNotEmpty ? organizationUID : defaultOrgId;
    if (companyUID.isEmpty) return 0;

    final defaultReason = reason ??
        'تم إنهاء جلسات مناديب الشركة من الإدارة لتحديث البيانات. يُرجى إعادة تسجيل الدخول.';

    try {
      // 1. تحديث مستند الشركة نفسه بختم زمني للخروج الجماعي
      await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyUID)
          .update({
        'delegatesForceLogoutAt': FieldValue.serverTimestamp(),
        'forceLogoutReason': defaultReason,
        'forceLogoutBy': adminUid ?? 'super-admin',
      });

      // 2. جلب جميع مناديب الشركة وتحديثهم
      final delegatesSnap = await _firestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .doc(companyUID)
          .collection('delegates')
          .get();

      if (delegatesSnap.docs.isEmpty) return 0;

      // تطبيق التحديثات على دفعات (حتى 400 وثيقة لكل batch)
      const batchLimit = 400;
      for (var i = 0; i < delegatesSnap.docs.length; i += batchLimit) {
        final chunk = delegatesSnap.docs.sublist(
          i,
          (i + batchLimit > delegatesSnap.docs.length)
              ? delegatesSnap.docs.length
              : i + batchLimit,
        );

        final batch = _firestore.batch();
        for (final doc in chunk) {
          batch.update(doc.reference, {
            'requireReLogin': true,
            'forceLogoutAt': FieldValue.serverTimestamp(),
            'forceLogoutReason': defaultReason,
            'forceLogoutBy': adminUid ?? 'super-admin',
          });
        }
        await batch.commit();
      }

      // توثيق في سجل الأمان
      _logSessionAction(
        actionType: 'إنهاء جلسات شركة كاملة (جماعي)',
        companyUID: companyUID,
        companyName: companyName,
        organizationUID: orgId,
        adminUid: adminUid,
        affectedCount: delegatesSnap.docs.length,
        reason: defaultReason,
      ).ignore();

      return delegatesSnap.docs.length;
    } catch (e) {
      debugPrint('Error in forceLogoutCompany: $e');
      return 0;
    }
  }

  /// تسجيل خروج إجباري طارئ لجميع المناديب في النظام بالكامل (Global Emergency Reset)
  static Future<bool> forceLogoutAllDelegates({
    String? adminUid,
    String? reason,
  }) async {
    final defaultReason = reason ??
        'تم تسجيل خروج شامل لجميع المناديب من قِبل السوبر أدمن لتحديث النظام. يُرجى إعادة تسجيل الدخول.';

    try {
      await _firestore.collection('system_config').doc('session_control').set({
        'globalForceLogoutBefore': FieldValue.serverTimestamp(),
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': adminUid ?? 'super-admin',
        'reason': defaultReason,
      }, SetOptions(merge: true));

      _logSessionAction(
        actionType: 'خروج طارئ عام لجميع المناديب (Global Reset)',
        adminUid: adminUid,
        reason: defaultReason,
      ).ignore();

      return true;
    } catch (e) {
      debugPrint('Error in forceLogoutAllDelegates: $e');
      return false;
    }
  }

  /// توثيق إجراءات الجلسات في سجل الأمان
  static Future<void> _logSessionAction({
    required String actionType,
    String? delegateUid,
    String? delegateName,
    String? delegatePhone,
    String? companyUID,
    String? companyName,
    String? organizationUID,
    String? adminUid,
    int? affectedCount,
    String? reason,
  }) async {
    try {
      await _firestore.collection('security_audit_logs').add({
        'actionType': actionType,
        'delegateUid': delegateUid,
        'delegateName': delegateName,
        'delegatePhone': delegatePhone,
        'companyUID': companyUID,
        'companyName': companyName,
        'organizationUID': organizationUID,
        'performedBy': adminUid ?? 'super-admin',
        'affectedCount': affectedCount ?? 1,
        'reason': reason,
        'timestamp': FieldValue.serverTimestamp(),
        'status': 'executed',
      });
    } catch (_) {}
  }
}
