import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';

abstract class NotificationRemoteDataSource {
  Future<List<NotificationModel>> getNotifications(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
  });

  Stream<int> getUnreadCount(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
  });

  Future<void> markAsRead(String notificationId);

  Future<void> markAllAsRead(String delegateUid, String organizationId);

  Future<void> deleteNotificationForUser(String notificationId, String userUid);
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
  }) async {
    final Set<String> docIds = {};
    final List<QueryDocumentSnapshot> docs = [];

    void addDocs(List<QueryDocumentSnapshot> newDocs) {
      for (final doc in newDocs) {
        if (!docIds.contains(doc.id)) {
          docIds.add(doc.id);
          docs.add(doc);
        }
      }
    }

    // 1. Direct UID matching
    final userSnap = await _collection
        .where('delegateUid', isEqualTo: delegateUid)
        .limit(50)
        .get();
    addDocs(userSnap.docs);

    // 2. Broadcast matching
    final broadcastSnap = await _collection
        .where('delegateUid', isEqualTo: 'all')
        .limit(30)
        .get();
    addDocs(broadcastSnap.docs);

    // 3. Direct delegateUid as phone_...
    final phoneTagSnap = await _collection
        .where('delegateUid', isEqualTo: 'phone_$delegateUid')
        .limit(30)
        .get();
    addDocs(phoneTagSnap.docs);

    final phonesToCheck = <String>{
      if (phoneNumber != null && phoneNumber.isNotEmpty) phoneNumber,
      if (RegExp(r'^\+?[0-9]{8,15}$').hasMatch(delegateUid)) delegateUid,
    };

    // 4. If super-admin, also fetch notifications for all super-admin users
    if (delegateUid == 'super-admin-login' ||
        delegateUid.toLowerCase().contains('super')) {
      try {
        final adminDocs = await firestore
            .collection('users')
            .where('role', isEqualTo: 'super-admin')
            .get();
        for (final doc in adminDocs.docs) {
          final uSnap = await _collection
              .where('delegateUid', isEqualTo: doc.id)
              .limit(30)
              .get();
          addDocs(uSnap.docs);
          final data = doc.data();
          final p = (data['phoneNumber'] ??
                  data['phone'] ??
                  data['mobileNumber'] ??
                  data['mobile']) as String?;
          if (p != null && p.isNotEmpty) phonesToCheck.add(p);
        }
      } catch (_) {}
    }

    // 5. Try getting user phone number, companyId, and role from users/delegates
    try {
      String? phone;
      String? userCompanyId;
      String? userRole;

      final userDoc = await firestore.collection('users').doc(delegateUid).get();
      if (userDoc.exists) {
        final userData = userDoc.data();
        phone = (userData?['phoneNumber'] ??
                userData?['phone'] ??
                userData?['mobileNumber']) as String?;
        userCompanyId = (userData?['companyUID'] ?? userData?['companyId']) as String?;
        userRole = userData?['role']?.toString();
      }
      if (phone == null || phone.isEmpty) {
        final userQuery = await firestore
            .collection('users')
            .where('uid', isEqualTo: delegateUid)
            .limit(1)
            .get();
        if (userQuery.docs.isNotEmpty) {
          final userData = userQuery.docs.first.data();
          phone = (userData['phoneNumber'] ??
                  userData['phone'] ??
                  userData['mobileNumber']) as String?;
          userCompanyId ??= (userData['companyUID'] ?? userData['companyId']) as String?;
          userRole ??= userData['role']?.toString();
        }
      }
      if (phone == null || phone.isEmpty) {
        final delQuery = await firestore
            .collectionGroup('delegates')
            .where('uid', isEqualTo: delegateUid)
            .limit(1)
            .get();
        if (delQuery.docs.isNotEmpty) {
          final delData = delQuery.docs.first.data();
          phone = (delData['phoneNumber'] ??
                  delData['phone'] ??
                  delData['mobileNumber']) as String?;
          userCompanyId ??= (delData['companyUID'] ?? delData['companyId']) as String?;
          userRole ??= delData['role']?.toString();
        }
      }

      // Company-level & Supervisor notifications
      if (userCompanyId != null && userCompanyId.isNotEmpty) {
        final compSnap1 = await _collection
            .where('delegateUid', isEqualTo: 'company_$userCompanyId')
            .limit(30)
            .get();
        addDocs(compSnap1.docs);

        final compSnap2 = await _collection
            .where('delegateUid', isEqualTo: 'supervisor_$userCompanyId')
            .limit(30)
            .get();
        addDocs(compSnap2.docs);

        final compSnap3 = await _collection
            .where('companyId', isEqualTo: userCompanyId)
            .where('delegateUid', isEqualTo: 'all_company_supervisors')
            .limit(30)
            .get();
        addDocs(compSnap3.docs);
      }

      // Role-specific broadcasts
      final normalizedRole = userRole?.toLowerCase() ?? '';
      if (normalizedRole.contains('marketing') || normalizedRole.contains('branches')) {
        for (final r in ['branchesMarketingManager', 'branches_marketing', 'marketing']) {
          final rSnap = await _collection.where('delegateUid', isEqualTo: r).limit(30).get();
          addDocs(rSnap.docs);
        }
      }
      if (normalizedRole.contains('org') || normalizedRole.contains('organization')) {
        for (final r in ['organizationAdmin', 'organization_admin']) {
          final rSnap = await _collection.where('delegateUid', isEqualTo: r).limit(30).get();
          addDocs(rSnap.docs);
        }
      }

      if (phone != null && phone.isNotEmpty) {
        phonesToCheck.add(phone);
      }

      for (final rawP in phonesToCheck) {
        final cleanPhone = rawP.replaceAll(RegExp(r'\s+'), '').trim();
        final variations = <String>{
          cleanPhone,
          cleanPhone.startsWith('0') ? cleanPhone.substring(1) : '0$cleanPhone',
          if (!cleanPhone.startsWith('+')) '+20$cleanPhone',
          if (!cleanPhone.startsWith('+') && cleanPhone.startsWith('0'))
            '+20${cleanPhone.substring(1)}',
          if (!cleanPhone.startsWith('+')) '+971$cleanPhone',
        };

        for (final p in variations) {
          // Check users collection by phone to get their Firestore UIDs
          try {
            final uSnap = await firestore
                .collection('users')
                .where('phoneNumber', isEqualTo: p)
                .limit(5)
                .get();
            for (final uDoc in uSnap.docs) {
              final notifByUid = await _collection
                  .where('delegateUid', isEqualTo: uDoc.id)
                  .limit(30)
                  .get();
              addDocs(notifByUid.docs);
            }
          } catch (_) {}

          final pSnap1 = await _collection.where('phoneNumber', isEqualTo: p).limit(30).get();
          addDocs(pSnap1.docs);
          final pSnap2 = await _collection.where('delegateUid', isEqualTo: 'phone_$p').limit(30).get();
          addDocs(pSnap2.docs);
          final pSnap3 = await _collection.where('delegateUid', isEqualTo: p).limit(30).get();
          addDocs(pSnap3.docs);
        }
      }
    } catch (_) {}

    // Filter out notifications deleted by this user (Soft Delete)
    final filteredDocs = docs.where((doc) {
      final data = doc.data() as Map<String, dynamic>?;
      final deletedBy = data?['deletedBy'];
      if (deletedBy is List) {
        if (deletedBy.contains(delegateUid)) return false;
        if (phoneNumber != null && deletedBy.contains(phoneNumber)) return false;
      }
      return true;
    }).toList();

    // Sort in memory instead of in Firestore (Newest First)
    filteredDocs.sort((a, b) {
      final aData = a.data() as Map<String, dynamic>?;
      final bData = b.data() as Map<String, dynamic>?;
      final aTime =
          (aData?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      final bTime =
          (bData?['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now();
      return bTime.compareTo(aTime); // descending
    });

    return filteredDocs.map((doc) => NotificationModel.fromFirestore(doc)).toList();
  }

  @override
  Stream<int> getUnreadCount(
    String delegateUid,
    String organizationId, {
    String? phoneNumber,
  }) {
    return Stream.fromFuture(
      getNotifications(
        delegateUid,
        organizationId,
        phoneNumber: phoneNumber,
      ),
    ).map((list) => list.where((n) => !n.isRead).length);
  }

  @override
  Future<void> markAsRead(String notificationId) async {
    await _collection.doc(notificationId).update({
      'isRead': true,
      'readAt': FieldValue.serverTimestamp(),
    });
  }

  @override
  Future<void> markAllAsRead(String delegateUid, String organizationId) async {
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
  }

  @override
  Future<void> deleteNotificationForUser(
    String notificationId,
    String userUid,
  ) async {
    await _collection.doc(notificationId).update({
      'deletedBy': FieldValue.arrayUnion([userUid]),
    });
  }
}
