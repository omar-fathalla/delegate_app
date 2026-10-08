import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/private_label/data/models/private_label_permissions_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';

abstract class PrivateLabelPermissionsRemoteDataSource {
  /// Stream real-time permissions for a specific user
  Stream<PrivateLabelPermissions?> streamUserPermissions(String userId);

  /// Fetch one-time permissions for a specific user
  Future<PrivateLabelPermissions?> getUserPermissions(String userId);

  /// Stream all configured permissions (for Super Admin dashboard)
  Stream<List<PrivateLabelPermissions>> streamAllPermissions();

  /// Update permissions and automatically dispatch a push/in-app notification to the user
  Future<void> updatePermissions({
    required PrivateLabelPermissions permissions,
    required String adminUid,
    required String adminName,
    String? adminRole,
  });

  /// Bulk update permissions for multiple users atomically via Firestore WriteBatch
  Future<void> bulkUpdatePermissions({
    required List<PrivateLabelPermissions> permissionsList,
    required String adminUid,
    required String adminName,
    String? adminRole,
    String? notificationActionLabel,
  });

  /// Search users across the organization/system to manage their Private Label permissions
  Future<List<Map<String, dynamic>>> searchUsers({
    String query = '',
    String roleFilter = 'marketing_promotion', // 'all', 'marketing_promotion', 'marketing', 'admin'
    String? organizationUID,
  });
}

class PrivateLabelPermissionsRemoteDataSourceImpl
    implements PrivateLabelPermissionsRemoteDataSource {
  final FirebaseFirestore firestore;

  PrivateLabelPermissionsRemoteDataSourceImpl({FirebaseFirestore? firestore})
      : firestore = firestore ?? FirebaseFirestore.instance;

  static const String _collection = 'private_label_permissions';

  @override
  Stream<PrivateLabelPermissions?> streamUserPermissions(String userId) {
    if (userId.trim().isEmpty) {
      return Stream.value(null);
    }
    return firestore
        .collection(_collection)
        .doc(userId.trim())
        .snapshots()
        .map((doc) {
      if (!doc.exists || doc.data() == null) {
        return PrivateLabelPermissions.empty(userId.trim());
      }
      return PrivateLabelPermissionsModel.fromFirestore(doc);
    }).handleError((_) => PrivateLabelPermissions.empty(userId.trim()));
  }

  @override
  Future<PrivateLabelPermissions?> getUserPermissions(String userId) async {
    if (userId.trim().isEmpty) return null;
    try {
      final doc = await firestore.collection(_collection).doc(userId.trim()).get();
      if (!doc.exists || doc.data() == null) {
        return PrivateLabelPermissions.empty(userId.trim());
      }
      return PrivateLabelPermissionsModel.fromFirestore(doc);
    } catch (_) {
      return PrivateLabelPermissions.empty(userId.trim());
    }
  }

  @override
  Stream<List<PrivateLabelPermissions>> streamAllPermissions() {
    return firestore.collection(_collection).snapshots().map((snapshot) {
      return snapshot.docs
          .map((doc) => PrivateLabelPermissionsModel.fromFirestore(doc))
          .toList();
    }).handleError((_) => <PrivateLabelPermissions>[]);
  }

  @override
  Future<void> updatePermissions({
    required PrivateLabelPermissions permissions,
    required String adminUid,
    required String adminName,
    String? adminRole,
  }) async {
    final model = PrivateLabelPermissionsModel.fromEntity(
      permissions.copyWith(
        updatedAt: DateTime.now(),
        updatedBy: adminUid,
        updatedByName: adminName,
      ),
    );

    // 1. Persist to Firestore private_label_permissions collection
    await firestore
        .collection(_collection)
        .doc(permissions.userId.trim())
        .set(model.toMap(), SetOptions(merge: true));

    // 2. Dispatch automated notification to the targeted user
    try {
      final buffer = StringBuffer();
      if (permissions.hasAnyPermission) {
        buffer.writeln('تم تحديث صلاحياتك في نظام Private Label:');
        buffer.writeln('• التوثيق الميداني: ${permissions.canCapture ? "مفعل" : "معطل"}');
        buffer.writeln('• شاشة التقارير: ${permissions.canViewReports ? "مفعل" : "معطل"}');
        buffer.write('• شاشة الاعتمادات: ${permissions.canReviewAudit ? "مفعل" : "معطل"}');
      } else {
        buffer.write('تم إيقاف صلاحيات الوصول لنظام Private Label لحسابك.');
      }

      await firestore.collection('notifications').add({
        'delegateUid': permissions.userId.trim(),
        'organizationId': permissions.organizationUID.trim(),
        'companyId': permissions.companyUID.trim(),
        'title': 'صلاحيات Private Label',
        'body': buffer.toString(),
        'type': 'private_label_permission',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'senderName': adminName,
        'senderRole': adminRole ?? 'superAdmin',
        'senderUid': adminUid,
      });
    } catch (_) {
      // Don't fail the permission save if sending the notification log encounters an issue
    }
  }

  @override
  Future<void> bulkUpdatePermissions({
    required List<PrivateLabelPermissions> permissionsList,
    required String adminUid,
    required String adminName,
    String? adminRole,
    String? notificationActionLabel,
  }) async {
    if (permissionsList.isEmpty) return;

    final now = DateTime.now();
    // Firestore WriteBatch has a 500 operations limit.
    // Each user involves 1 permission set + 1 notification add = 2 operations.
    // Chunk size of 200 users => 400 operations per batch, safely under 500 limit.
    const chunkSize = 200;

    for (var i = 0; i < permissionsList.length; i += chunkSize) {
      final end = (i + chunkSize < permissionsList.length)
          ? i + chunkSize
          : permissionsList.length;
      final chunk = permissionsList.sublist(i, end);

      final batch = firestore.batch();

      for (final p in chunk) {
        final updatedModel = PrivateLabelPermissionsModel.fromEntity(
          p.copyWith(
            updatedAt: now,
            updatedBy: adminUid,
            updatedByName: adminName,
          ),
        );

        final docRef = firestore.collection(_collection).doc(p.userId.trim());
        batch.set(docRef, updatedModel.toMap(), SetOptions(merge: true));

        // Queue automated notification log
        final notifRef = firestore.collection('notifications').doc();
        final buffer = StringBuffer();
        if (notificationActionLabel != null && notificationActionLabel.isNotEmpty) {
          buffer.writeln(notificationActionLabel);
        }
        if (p.hasAnyPermission) {
          buffer.writeln('حالة صلاحياتك في نظام Private Label:');
          buffer.writeln('• التوثيق الميداني: ${p.canCapture ? "مفعل" : "معطل"}');
          buffer.writeln('• شاشة التقارير: ${p.canViewReports ? "مفعل" : "معطل"}');
          buffer.write('• شاشة الاعتمادات: ${p.canReviewAudit ? "مفعل" : "معطل"}');
        } else {
          buffer.write('تم إيقاف صلاحيات الوصول لنظام Private Label لحسابك.');
        }

        batch.set(notifRef, {
          'delegateUid': p.userId.trim(),
          'organizationId': p.organizationUID.trim(),
          'companyId': p.companyUID.trim(),
          'title': 'صلاحيات Private Label',
          'body': buffer.toString(),
          'type': 'private_label_permission',
          'isRead': false,
          'createdAt': FieldValue.serverTimestamp(),
          'senderName': adminName,
          'senderRole': adminRole ?? 'superAdmin',
          'senderUid': adminUid,
        });
      }

      await batch.commit();
    }
  }

  @override
  Future<List<Map<String, dynamic>>> searchUsers({
    String query = '',
    String roleFilter = 'marketing_promotion',
    String? organizationUID,
  }) async {
    final cleanQuery = query.trim().toLowerCase();

    // 1. Fetch organization names mapping
    final orgMap = <String, String>{};
    try {
      final orgSnap = await firestore.collection('organizations').get();
      for (final doc in orgSnap.docs) {
        final d = doc.data();
        final name = (d['name'] ?? d['title'] ?? '').toString().trim();
        if (name.isNotEmpty) {
          orgMap[doc.id] = name;
          final u = d['organizationUID']?.toString().trim();
          if (u != null && u.isNotEmpty) orgMap[u] = name;
        }
      }
    } catch (_) {}

    // 2. Fetch all users from `users` collection
    final userSnap = await firestore.collection('users').get();
    final results = <Map<String, dynamic>>[];

    for (final doc in userSnap.docs) {
      final data = doc.data();
      final uid = doc.id;

      // Extract display name
      final displayName = (data['displayName'] ??
              data['fullName'] ??
              data['name'] ??
              '${data['firstName'] ?? ''} ${data['lastName'] ?? ''}')
          .toString()
          .trim();
      final phone = (data['phoneNumber'] ?? data['phone'] ?? '').toString().trim();
      final email = (data['email'] ?? '').toString().trim();
      final rawRole = (data['role'] ?? '').toString().trim();
      final normRole = rawRole.toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
      final orgUid = (data['organizationUID'] ?? data['organizationId'] ?? '').toString().trim();
      final orgName = (data['organizationName'] ?? orgMap[orgUid] ?? '').toString().trim();
      final compUid = (data['companyUID'] ?? data['companyId'] ?? '').toString().trim();
      final compName = (data['companyName'] ?? '').toString().trim();

      // Role filter check
      bool roleMatches = false;
      if (roleFilter == 'all') {
        roleMatches = true;
      } else if (roleFilter == 'marketing_promotion') {
        roleMatches = normRole.contains('promotion');
      } else if (roleFilter == 'marketing') {
        roleMatches = normRole.contains('marketing') && !normRole.contains('promotion');
      } else if (roleFilter == 'admin') {
        roleMatches = normRole.contains('admin') || normRole.contains('company');
      } else {
        roleMatches = normRole == roleFilter.toLowerCase();
      }

      if (!roleMatches) continue;

      // Organization filter check
      if (organizationUID != null && organizationUID.isNotEmpty && orgUid != organizationUID) {
        continue;
      }

      // Query filter check (name, phone, email, company)
      if (cleanQuery.isNotEmpty) {
        final matchesName = displayName.toLowerCase().contains(cleanQuery);
        final matchesPhone = phone.toLowerCase().contains(cleanQuery);
        final matchesEmail = email.toLowerCase().contains(cleanQuery);
        final matchesCompany = compName.toLowerCase().contains(cleanQuery);
        final matchesOrg = orgName.toLowerCase().contains(cleanQuery);
        if (!matchesName && !matchesPhone && !matchesEmail && !matchesCompany && !matchesOrg) {
          continue;
        }
      }

      results.add({
        'uid': uid,
        'displayName': displayName.isEmpty ? 'بدون اسم' : displayName,
        'phoneNumber': phone,
        'email': email,
        'role': rawRole.isEmpty ? 'marketingPromotion' : rawRole,
        'organizationUID': orgUid,
        'organizationName': orgName,
        'companyUID': compUid,
        'companyName': compName,
      });
    }

    // Sort by name
    results.sort((a, b) =>
        (a['displayName'] as String).compareTo(b['displayName'] as String));

    return results;
  }
}
