import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';

abstract class NotificationRemoteDataSource {
  Future<List<NotificationModel>> getNotifications(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
    String? userRole,
    DateTime? accountCreatedAt,
  });

  Stream<int> getUnreadCount(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
    String? userRole,
    DateTime? accountCreatedAt,
  });

  Future<void> markAsRead(String notificationId);

  Future<void> markAllAsRead(String delegateUid, String organizationId);

  Future<void> deleteNotificationForUser(String notificationId, String userUid);

  Future<void> deleteAllNotificationsForUser(
    List<String> notificationIds,
    String userUid, {
    String? phoneNumber,
  });
}

class NotificationRemoteDataSourceImpl implements NotificationRemoteDataSource {
  final FirebaseFirestore firestore;

  NotificationRemoteDataSourceImpl({required this.firestore});

  CollectionReference get _collection => firestore.collection('notifications');

  @override
  Future<List<NotificationModel>> getNotifications(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
    String? userRole,
    DateTime? accountCreatedAt,
  }) async {
    final Set<String> docIds = {};
    final List<QueryDocumentSnapshot> docs = [];
    String normalizedRole = userRole?.toLowerCase() ?? '';
    DateTime? userCreatedAt = accountCreatedAt;

    void addDocs(List<QueryDocumentSnapshot> newDocs) {
      for (final doc in newDocs) {
        if (!docIds.contains(doc.id)) {
          docIds.add(doc.id);
          docs.add(doc);
        }
      }
    }

    try {
      // 1. Initial parallel queries (UID, broadcast 'all', phone tag)
      final initialQueries = await Future.wait([
        _collection.where('delegateUid', isEqualTo: delegateUid).limit(50).get(),
        _collection.where('delegateUid', isEqualTo: 'all').limit(30).get(),
        _collection.where('delegateUid', isEqualTo: 'phone_$delegateUid').limit(30).get(),
      ]);

      for (final snap in initialQueries) {
        addDocs(snap.docs);
      }

      final phonesToCheck = <String>{
        if (phoneNumber != null && phoneNumber.isNotEmpty) phoneNumber,
        if (RegExp(r'^\+?[0-9]{8,15}$').hasMatch(delegateUid)) delegateUid,
      };

      // 2. Super admin matching
      if (delegateUid == 'super-admin-login' ||
          delegateUid.toLowerCase().contains('super')) {
        try {
          final adminDocs = await firestore
              .collection('users')
              .where('role', whereIn: ['super-admin', 'super_admin'])
              .get();
          final adminQueries = <Future<QuerySnapshot>>[];
          for (final doc in adminDocs.docs) {
            adminQueries.add(
              _collection.where('delegateUid', isEqualTo: doc.id).limit(30).get(),
            );
            final data = doc.data();
            final p = (data['phoneNumber'] ??
                    data['phone'] ??
                    data['mobileNumber'] ??
                    data['mobile']) as String?;
            if (p != null && p.isNotEmpty) phonesToCheck.add(p);
          }
          final adminSnaps = await Future.wait(adminQueries);
          for (final snap in adminSnaps) {
            addDocs(snap.docs);
          }
        } catch (_) {}
      }

      // 3. User profile lookup for companyId & role
      String? userCompanyId;
      try {
        final userDoc = await firestore.collection('users').doc(delegateUid).get();
        if (userDoc.exists) {
          final userData = userDoc.data();
          final p = (userData?['phoneNumber'] ??
                  userData?['phone'] ??
                  userData?['mobileNumber']) as String?;
          userCompanyId = (userData?['companyUID'] ?? userData?['companyId']) as String?;
          final r = userData?['role']?.toString();
          if (normalizedRole.isEmpty && r != null && r.isNotEmpty) {
            normalizedRole = r.toLowerCase();
          }
          userCreatedAt ??= (userData?['createdAt'] as Timestamp?)?.toDate();
          if (p != null && p.isNotEmpty) phonesToCheck.add(p);
        }
      } catch (_) {}

      // Fallback lookup from delegates collection if companyId or createdAt is still missing
      if (userCompanyId == null || userCreatedAt == null) {
        try {
          final delSnap = await firestore
              .collectionGroup('delegates')
              .where('uid', isEqualTo: delegateUid)
              .limit(1)
              .get();
          if (delSnap.docs.isNotEmpty) {
            final delData = delSnap.docs.first.data();
            userCompanyId ??= (delData['companyUID'] ?? delData['companyId']) as String?;
            if (normalizedRole.isEmpty) {
              normalizedRole = (delData['role']?.toString() ?? 'delegate').toLowerCase();
            }
            userCreatedAt ??= (delData['createdAt'] as Timestamp?)?.toDate();
          }
        } catch (_) {}
      }

      final isSupervisorOrAdmin = normalizedRole.contains('supervisor') ||
          normalizedRole.contains('admin') ||
          normalizedRole.contains('company_admin') ||
          normalizedRole.contains('company-admin') ||
          normalizedRole.contains('super') ||
          normalizedRole.contains('support') ||
          delegateUid == 'super-admin-login';

      final isDelegate = normalizedRole.contains('delegate') ||
          (!isSupervisorOrAdmin && (userRole?.toLowerCase() == 'delegate'));

      // 4. Parallel Company and Role broadcast queries
      final roleQueries = <Future<QuerySnapshot>>[];
      if (userCompanyId != null && userCompanyId.isNotEmpty) {
        roleQueries.add(
          _collection.where('delegateUid', isEqualTo: 'company_$userCompanyId').limit(30).get(),
        );
        // Only supervisors and admins receive supervisor-specific and all_company_supervisors broadcasts
        if (isSupervisorOrAdmin) {
          roleQueries.add(
            _collection.where('delegateUid', isEqualTo: 'supervisor_$userCompanyId').limit(30).get(),
          );
          roleQueries.add(
            _collection.where('companyId', isEqualTo: userCompanyId).where('delegateUid', isEqualTo: 'all_company_supervisors').limit(30).get(),
          );
        }
        if (isDelegate) {
          roleQueries.add(
            _collection.where('delegateUid', isEqualTo: 'delegates_$userCompanyId').limit(30).get(),
          );
        }
      }

      if (isDelegate) {
        roleQueries.add(_collection.where('delegateUid', isEqualTo: 'delegates').limit(30).get());
      }

      if (normalizedRole.contains('marketing') || normalizedRole.contains('branches')) {
        for (final r in ['branchesMarketingManager', 'branches_marketing', 'marketing']) {
          roleQueries.add(_collection.where('delegateUid', isEqualTo: r).limit(30).get());
        }
      }
      if (normalizedRole.contains('org') || normalizedRole.contains('organization')) {
        for (final r in ['organizationAdmin', 'organization_admin']) {
          roleQueries.add(_collection.where('delegateUid', isEqualTo: r).limit(30).get());
        }
      }
      if (normalizedRole.contains('super') ||
          delegateUid == 'super-admin-login' ||
          delegateUid.toLowerCase().contains('super')) {
        for (final r in ['super-admin', 'super_admin', 'superAdmin', 'role_super_admin']) {
          roleQueries.add(_collection.where('delegateUid', isEqualTo: r).limit(30).get());
        }
      }
      if (normalizedRole.contains('technical') ||
          normalizedRole.contains('support') ||
          delegateUid.toLowerCase().contains('support')) {
        for (final r in ['technicalSupport', 'technical-support', 'role_technical_support']) {
          roleQueries.add(_collection.where('delegateUid', isEqualTo: r).limit(30).get());
        }
      }

      if (roleQueries.isNotEmpty) {
        final roleSnaps = await Future.wait(roleQueries);
        for (final snap in roleSnaps) {
          addDocs(snap.docs);
        }
      }

      // 5. Parallel phone variation queries
      final phoneQueries = <Future<QuerySnapshot>>[];
      for (final rawP in phonesToCheck) {
        final cleanPhone = rawP.replaceAll(RegExp(r'\s+'), '').trim();
        final variations = <String>{
          cleanPhone,
          cleanPhone.startsWith('0') ? cleanPhone.substring(1) : '0$cleanPhone',
          if (!cleanPhone.startsWith('+')) '+20$cleanPhone',
          if (!cleanPhone.startsWith('+') && cleanPhone.startsWith('0'))
            '+20${cleanPhone.substring(1)}',
        };

        for (final p in variations) {
          phoneQueries.add(_collection.where('phoneNumber', isEqualTo: p).limit(30).get());
          phoneQueries.add(_collection.where('delegateUid', isEqualTo: 'phone_$p').limit(30).get());
          phoneQueries.add(_collection.where('delegateUid', isEqualTo: p).limit(30).get());
        }
      }

      if (phoneQueries.isNotEmpty) {
        final phoneSnaps = await Future.wait(phoneQueries);
        for (final snap in phoneSnaps) {
          addDocs(snap.docs);
        }
      }
    } catch (_) {}

    // Filter out notifications deleted by this user (Soft Delete) and role-restricted notifications
    final filteredDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      if (data == null) return false;

      final deletedBy = data['deletedBy'];
      if (deletedBy is List) {
        if (deletedBy.contains(delegateUid)) return false;
        if (phoneNumber != null && deletedBy.contains(phoneNumber)) return false;
      }

      final type = data['type']?.toString();

      // Delegate subscription requests are strictly restricted ONLY to Super Admin and Technical Support
      if (type == 'delegate_subscription_request' ||
          type == 'delegate_profile_edit' ||
          type == 'delegate_national_id_request') {
        final isPrivileged = normalizedRole.contains('super') ||
            normalizedRole.contains('technical') ||
            normalizedRole.contains('support') ||
            delegateUid == 'super-admin-login' ||
            delegateUid.toLowerCase().contains('super') ||
            delegateUid.toLowerCase().contains('support');
        if (!isPrivileged) return false;
      }

      final isSupervisorOrAdmin = normalizedRole.contains('supervisor') ||
          normalizedRole.contains('admin') ||
          normalizedRole.contains('company_admin') ||
          normalizedRole.contains('company-admin') ||
          normalizedRole.contains('super') ||
          normalizedRole.contains('support') ||
          delegateUid == 'super-admin-login';

      // Attendance check-in / check-out alerts are strictly for supervisors & admins to monitor their delegates.
      // Delegates should NEVER receive attendance alerts of other delegates or administrative check-in broadcasts.
      final isAttendance = type == 'attendance_check_in' ||
          type == 'attendance_check_out' ||
          data['attendanceType'] != null;
      if (isAttendance && !isSupervisorOrAdmin) {
        return false;
      }

      // Exclude historical notifications created BEFORE the user/delegate account was created
      final effectiveCreatedAt = accountCreatedAt ?? userCreatedAt;
      if (effectiveCreatedAt != null) {
        final notifTime = (data['createdAt'] as Timestamp?)?.toDate();
        if (notifTime != null &&
            notifTime.isBefore(effectiveCreatedAt.subtract(const Duration(minutes: 5)))) {
          return false;
        }
      }

      return true;
    }).toList();

    // Sort in memory (Newest First)
    filteredDocs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>?;
      final bData = b.data() as Map<String, dynamic>?;
      final aTime =
          (aData?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final bTime =
          (bData?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      return bTime.compareTo(aTime);
    });

    // Auto-pruning: Keep latest 100 notifications, prune excess older ones in background
    List<QueryDocumentSnapshot> activeDocs = filteredDocs;
    if (filteredDocs.length > 100) {
      activeDocs = filteredDocs.take(100).toList();
      final excessDocs = filteredDocs.skip(100).toList();
      final excessIds = excessDocs.map((d) => d.id).toList();
      unawaited(
        _pruneOlderNotificationsInBackground(
          excessIds,
          delegateUid,
          phoneNumber: phoneNumber,
        ),
      );
    }

    return activeDocs.map((doc) => NotificationModel.fromFirestore(doc)).toList();
  }

  Future<void> _pruneOlderNotificationsInBackground(
    List<String> notificationIds,
    String userUid, {
    String? phoneNumber,
  }) async {
    try {
      await deleteAllNotificationsForUser(
        notificationIds,
        userUid,
        phoneNumber: phoneNumber,
      );
    } catch (_) {}
  }

  @override
  Stream<int> getUnreadCount(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
    String? userRole,
    DateTime? accountCreatedAt,
  }) {
    return Stream.fromFuture(
      getNotifications(
        delegateUid,
        organizationId,
        phoneNumber: phoneNumber,
        userRole: userRole,
        accountCreatedAt: accountCreatedAt,
      ),
    ).map((list) => list.where((n) => !n.isRead).length);
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    try {
      await _collection.doc(notificationId).update({
        'isRead': true,
        'readAt': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }

  @override
  Future<void> markAllAsRead(String delegateUid, String organizationId) async {
    try {
      final snapshot = await _collection
          .where('delegateUid', isEqualTo: delegateUid)
          .where('organizationId', isEqualTo: organizationId)
          .where('isRead', isEqualTo: false)
          .get();

      final batch = firestore.batch();
      for (final doc in snapshot.docs) {
        batch.update(doc.reference, {
          'isRead': true,
          'readAt': FieldValue.serverTimestamp(),
        });
      }
      await batch.commit();
    } catch (_) {}
  }

  @override
  Future<void> deleteNotificationForUser(
    String notificationId,
    String userUid,
  ) async {
    try {
      await _collection.doc(notificationId).set({
        'deletedBy': FieldValue.arrayUnion([userUid]),
      }, SetOptions(merge: true));
    } catch (_) {}
  }

  @override
  Future<void> deleteAllNotificationsForUser(
    List<String> notificationIds,
    String userUid, {
    String? phoneNumber,
  }) async {
    if (notificationIds.isEmpty) return;

    final identifiers = <String>{
      userUid,
      if (phoneNumber != null && phoneNumber.isNotEmpty) phoneNumber,
    }.toList();

    const int chunkSize = 100;
    for (var i = 0; i < notificationIds.length; i += chunkSize) {
      final end = (i + chunkSize < notificationIds.length)
          ? i + chunkSize
          : notificationIds.length;
      final chunk = notificationIds.sublist(i, end);

      try {
        final batch = firestore.batch();
        for (final id in chunk) {
          batch.set(
            _collection.doc(id),
            {'deletedBy': FieldValue.arrayUnion(identifiers)},
            SetOptions(merge: true),
          );
        }
        await batch.commit();
      } catch (_) {}
    }
  }
}
