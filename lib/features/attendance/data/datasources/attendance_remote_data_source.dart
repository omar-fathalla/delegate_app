import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/injection_container.dart';

abstract class AttendanceRemoteDataSource {
  Future<AttendanceModel> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
  });
  Future<AttendanceModel> checkOut(
    String attendanceId,
    String organizationId,
    double lat,
    double long,
  );
  Future<List<AttendanceModel>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  });
  Future<PaginationResponse<AttendanceModel>> getHistoryPaginated(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfter,
  });

  /// Finds the active attendance record (where checkOutTime is null)
  /// for the given [userId] in the specified [organizationId].
  /// Returns `null` if no active session exists.
  Future<AttendanceModel?> findActiveAttendance(
    String userId,
    String organizationId,
  );

  /// Syncs an offline queue of attendance actions to Firestore.
  Future<void> syncOfflineQueue(List<Map<String, dynamic>> queue);

  /// Fetches branch details by name.
  Future<Map<String, dynamic>?> getBranchByName(String branchName);

  /// Saves or updates a branch with its geofence data.
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
  });
}

class AttendanceRemoteDataSourceImpl implements AttendanceRemoteDataSource {
  final FirebaseFirestore firestore;

  AttendanceRemoteDataSourceImpl({required this.firestore});

  /// Helper: Get the attendance_logs collection
  /// Path: /attendance_logs
  CollectionReference<Map<String, dynamic>> _attendanceCollection(
    String organizationId,
  ) => firestore.collection(kAttendanceCollection);

  @override
  Future<AttendanceModel> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
  }) async {
    try {
      final docRef = await _attendanceCollection(organizationId)
          .add({
            'delegateId': userId,
            'userId': userId,
            'companyId': companyId,
            'organizationId': organizationId,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'check_in',
            'location': {'latitude': lat, 'longitude': long},
            'deviceInfo': deviceInfo,
            'branchName': branchName,
          })
          .timeout(const Duration(seconds: 15));

      DateTime currentTime;
      try {
        currentTime = sl<TrustedTimeService>().now;
      } catch (_) {
        currentTime = DateTime.now();
      }

      unawaited(
        _notifySupervisorsOfAttendance(
          userId: userId,
          companyId: companyId,
          organizationId: organizationId,
          branchName: branchName,
          type: 'check_in',
          time: currentTime,
        ),
      );

      unawaited(
        _syncDelegateTrackingCheckIn(
          userId: userId,
          companyId: companyId,
          organizationId: organizationId,
          branchName: branchName,
          lat: lat,
          long: long,
          time: currentTime,
        ),
      );

      return AttendanceModel(
        id: docRef.id,
        userId: userId,
        organizationId: organizationId,
        checkInTime: currentTime,
        latitude: lat,
        longitude: long,
        branchName: branchName,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تسجيل الحضور. حاول مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure();
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء تسجيل الحضور.');
    }
  }

  @override
  Future<AttendanceModel> checkOut(
    String attendanceId,
    String organizationId,
    double lat,
    double long,
  ) async {
    try {
      final lastCheckInSnapshot = await _attendanceCollection(
        organizationId,
      ).doc(attendanceId).get().timeout(const Duration(seconds: 15));

      if (!lastCheckInSnapshot.exists) {
        throw const ServerFailure('سجل الحضور غير موجود.');
      }
      final lastData = lastCheckInSnapshot.data()!;
      final userId = lastData['delegateId'] ?? lastData['userId'];
      final companyId = lastData['companyId'];

      await _attendanceCollection(organizationId)
          .add({
            'delegateId': userId,
            'userId': userId,
            'companyId': companyId,
            'organizationId': organizationId,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'check_out',
            'location': {'latitude': lat, 'longitude': long},
            'relatedCheckInId': attendanceId,
            if (lastData['branchName'] != null) 'branchName': lastData['branchName'],
          })
          .timeout(const Duration(seconds: 15));

      DateTime currentOutTime;
      try {
        currentOutTime = sl<TrustedTimeService>().now;
      } catch (_) {
        currentOutTime = DateTime.now();
      }

      unawaited(
        _notifySupervisorsOfAttendance(
          userId: userId,
          companyId: companyId ?? '',
          organizationId: organizationId,
          branchName: lastData['branchName'] as String?,
          type: 'check_out',
          time: currentOutTime,
        ),
      );

      unawaited(
        _syncDelegateTrackingCheckOut(
          userId: userId,
        ),
      );

      return AttendanceModel(
        id: attendanceId,
        userId: userId,
        organizationId: organizationId,
        checkInTime: (lastData['timestamp'] as Timestamp).toDate(),
        checkOutTime: currentOutTime,
        latitude: (lastData['location']['latitude'] as num).toDouble(),
        longitude: (lastData['location']['longitude'] as num).toDouble(),
        branchName: lastData['branchName'],
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تسجيل الانصراف. حاول مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure();
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء تسجيل الانصراف.');
    }
  }

  @override
  Future<List<AttendanceModel>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) async {
    final response = await getHistoryPaginated(
      userId,
      organizationId,
      nationalityID: nationalityID,
      phoneNumber: phoneNumber,
      limit: 100,
    );
    return response.items;
  }

  String _normalizePhone(String phone) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    String normalized = phone.trim();
    normalized = normalized.replaceAll(RegExp(r'[^\d+٠-٩]'), '');

    for (int i = 0; i < arabic.length; i++) {
      normalized = normalized.replaceAll(arabic[i], english[i]);
    }

    if (normalized.startsWith('+20')) {
      normalized = '0${normalized.substring(3)}';
    } else if (normalized.startsWith('+2')) {
      normalized = normalized.substring(2);
    } else if (normalized.startsWith('0020')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('002')) {
      normalized = normalized.substring(3);
    }

    return normalized;
  }

  @override
  Future<PaginationResponse<AttendanceModel>> getHistoryPaginated(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final Set<String> identifiers = {userId};

      if (nationalityID != null && nationalityID.trim().isNotEmpty) {
        final cleanNat = nationalityID.trim();
        identifiers.add(cleanNat);

        // Resolve any other delegate UIDs registered under this National ID
        try {
          final natSnap = await firestore
              .collectionGroup('delegates')
              .where('nationalityID', isEqualTo: cleanNat)
              .limit(10)
              .get()
              .timeout(const Duration(seconds: 4));
          for (final doc in natSnap.docs) {
            identifiers.add(doc.id);
          }
        } catch (_) {}
      }

      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        final cleanPhone = phoneNumber.trim();
        final normalizedPhone = _normalizePhone(cleanPhone);
        identifiers.add(cleanPhone);
        if (normalizedPhone.isNotEmpty) {
          identifiers.add(normalizedPhone);
        }

        // Resolve any other delegate UIDs registered under this phone number
        try {
          final phoneSnap = await firestore
              .collectionGroup('delegates')
              .where('phoneNumber', isEqualTo: normalizedPhone)
              .limit(10)
              .get()
              .timeout(const Duration(seconds: 4));
          for (final doc in phoneSnap.docs) {
            identifiers.add(doc.id);
          }
        } catch (_) {}
      }

      final queryList = identifiers.where((id) => id.isNotEmpty).take(30).toList();

      Query<Map<String, dynamic>> query = _attendanceCollection(organizationId)
          .where('delegateId', whereIn: queryList)
          .orderBy('timestamp', descending: true)
          .limit(limit * 2);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      final querySnapshot = await query.get().timeout(
        const Duration(seconds: 10),
      );

      if (querySnapshot.docs.isEmpty) {
        return PaginationResponse(
          items: [],
          lastDoc: null,
          hasReachedMax: true,
        );
      }

      final history = _pairAttendanceDocs(
        querySnapshot.docs,
        userId,
        organizationId,
      );

      return PaginationResponse(
        items: history,
        lastDoc: querySnapshot.docs.last,
        hasReachedMax: querySnapshot.docs.length < (limit * 2),
      );
    } catch (e, stack) {
      debugPrint('Error in getHistoryPaginated: $e\n$stack');
      return PaginationResponse(items: [], lastDoc: null, hasReachedMax: true);
    }
  }

  /// Pairs check-in and check-out documents into [AttendanceModel] sessions.
  List<AttendanceModel> _pairAttendanceDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String userId,
    String organizationId,
  ) {
    final List<AttendanceModel> history = [];
    final Map<String, Map<String, dynamic>> checkOuts = {};
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> checkIns = [];

    // Separate check-ins and check-outs
    for (var doc in docs) {
      final data = doc.data();
      final type = data['type'] as String?;
      if (type == 'check_out') {
        final relatedId = data['relatedCheckInId'] as String?;
        if (relatedId != null) {
          checkOuts[relatedId] = data;
        }
      } else if (type == 'check_in') {
        checkIns.add(doc);
      }
    }

    // Process check-ins and match with corresponding check-outs if available
    for (var doc in checkIns) {
      final checkInId = doc.id;
      final data = doc.data();
      final checkInTime = data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now();
      final lat = (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0;
      final branchName = data['branchName'];

      if (checkOuts.containsKey(checkInId)) {
        final outData = checkOuts[checkInId]!;
        history.add(
          AttendanceModel(
            id: checkInId,
            userId: userId,
            organizationId: organizationId,
            checkInTime: checkInTime,
            checkOutTime: outData['timestamp'] != null
                ? (outData['timestamp'] as Timestamp).toDate()
                : DateTime.now(),
            latitude: lat,
            longitude: lng,
            branchName: branchName,
          ),
        );
      } else {
        history.add(
          AttendanceModel(
            id: checkInId,
            userId: userId,
            organizationId: organizationId,
            checkInTime: checkInTime,
            latitude: lat,
            longitude: lng,
            branchName: branchName,
          ),
        );
      }
    }

    history.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
    return history;
  }

  @override
  Future<AttendanceModel?> findActiveAttendance(
    String userId,
    String organizationId,
  ) async {
    try {
      final querySnapshot = await _attendanceCollection(organizationId)
          .where('delegateId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 15));

      if (querySnapshot.docs.isEmpty) return null;

      final doc = querySnapshot.docs.first;
      final data = doc.data();

      if (data['type'] == 'check_in') {
        return AttendanceModel(
          id: doc.id,
          userId: data['delegateId'] ?? data['userId'] ?? '',
          organizationId: organizationId,
          checkInTime: data['timestamp'] != null
              ? (data['timestamp'] as Timestamp).toDate()
              : DateTime.now(),
          latitude: (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude:
              (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
          branchName: data['branchName'],
        );
      }

      return null;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في البحث عن جلسة الحضور النشطة.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم.');
    } catch (_) {
      throwUnexpectedFailure();
    }
  }

  @override
  Future<void> syncOfflineQueue(List<Map<String, dynamic>> queue) async {
    try {
      final batch = firestore.batch();
      for (var action in queue) {
        final organizationId = action['organizationId'] as String? ?? '';
        final newDocRef = _attendanceCollection(organizationId).doc();
        final Map<String, dynamic> data = {
          'delegateId': action['delegateId'],
          'userId': action['delegateId'],
          'companyId': action['companyId'],
          'organizationId': organizationId,
          'timestamp': FieldValue.serverTimestamp(),
          'type': action['type'],
          'location': action['location'],
        };

        if (action['deviceInfo'] != null) {
          data['deviceInfo'] = action['deviceInfo'];
        }
        if (action['branchName'] != null) {
          data['branchName'] = action['branchName'];
        }
        if (action['relatedCheckInId'] != null) {
          data['relatedCheckInId'] = action['relatedCheckInId'];
        }

        batch.set(newDocRef, data);
      }

      await batch.commit().timeout(const Duration(seconds: 20));
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في مزامنة البيانات المؤجلة.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم أثناء المزامنة.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء المزامنة.');
    }
  }

  @override
  Future<Map<String, dynamic>?> getBranchByName(String branchName) async {
    try {
      final querySnapshot = await firestore
          .collection('branches')
          .where('branchName', isEqualTo: branchName.trim())
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 15));

      if (querySnapshot.docs.isEmpty) {
        final groupSnap = await firestore
            .collectionGroup('branches')
            .where('branchName', isEqualTo: branchName.trim())
            .limit(1)
            .get()
            .timeout(const Duration(seconds: 15));
        if (groupSnap.docs.isNotEmpty) {
          return groupSnap.docs.first.data();
        }
        return null;
      }

      return querySnapshot.docs.first.data();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الفرع. يرجى المحاولة مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم أثناء جلب بيانات الفرع.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء البحث عن الفرع.');
    }
  }

  @override
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
  }) async {
    try {
      final querySnapshot = await firestore
          .collection('branches')
          .where('branchName', isEqualTo: branchName)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 15));

      final Map<String, dynamic> data = {
        'branchName': branchName,
        'location': {'latitude': latitude, 'longitude': longitude},
        'geofenceRadius': geofenceRadius,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (querySnapshot.docs.isEmpty) {
        await firestore
            .collection('branches')
            .add(data)
            .timeout(const Duration(seconds: 15));
      } else {
        await querySnapshot.docs.first.reference
            .update(data)
            .timeout(const Duration(seconds: 15));
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حفظ بيانات الفرع.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء حفظ بيانات الفرع.');
    }
  }

  Future<void> _notifySupervisorsOfAttendance({
    required String userId,
    required String companyId,
    required String organizationId,
    required String? branchName,
    required String type,
    required DateTime time,
  }) async {
    try {
      if (companyId.isEmpty) return;

      // 1. Resolve delegate name
      String delegateName = 'المندوب';
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          final name = data?['fullName'] ??
              data?['name'] ??
              '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
          if (name is String && name.trim().isNotEmpty) {
            delegateName = name.trim();
          }
        }
      } catch (_) {}

      // Format time in Arabic: e.g. 02:00 م
      final isAm = time.hour < 12;
      final hour12 = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
      final hourStr = hour12.toString().padLeft(2, '0');
      final minStr = time.minute.toString().padLeft(2, '0');
      final periodStr = isAm ? 'ص' : 'م';
      final formattedTime = '$hourStr:$minStr $periodStr';
      final safeBranchName =
          (branchName != null && branchName.trim().isNotEmpty) ? branchName.trim() : 'الفرع';

      final bool isCheckIn = type == 'check_in';
      final title = isCheckIn
          ? 'تسجيل حضور مندوب: $delegateName'
          : 'تسجيل انصراف مندوب: $delegateName';
      final body = isCheckIn
          ? 'قام المندوب $delegateName بتسجيل الحضور بنجاح في فرع ($safeBranchName) الساعة $formattedTime.'
          : 'قام المندوب $delegateName بتسجيل الانصراف بنجاح من فرع ($safeBranchName) الساعة $formattedTime.';
      final notifType = isCheckIn ? 'attendance_check_in' : 'attendance_check_out';

      final notifiedSupervisorUids = <String>{};

      // 2. Direct Supervisor Notifications from users collection
      final supervisorQueries = [
        firestore.collection('users').where('companyUID', isEqualTo: companyId),
        firestore.collection('users').where('companyId', isEqualTo: companyId),
      ];

      for (final q in supervisorQueries) {
        try {
          final snap = await q.get();
          for (final doc in snap.docs) {
            if (notifiedSupervisorUids.contains(doc.id)) continue;
            final uData = doc.data();
            final role = uData['role']?.toString().toLowerCase() ?? '';
            final pos = uData['position']?.toString().toLowerCase() ?? '';
            if (role.contains('supervisor') ||
                role.contains('admin') ||
                role.contains('company') ||
                pos.contains('supervisor') ||
                role == 'admin') {
              notifiedSupervisorUids.add(doc.id);
              final phone =
                  (uData['phoneNumber'] ?? uData['phone'] ?? uData['mobileNumber']) as String?;
              await firestore.collection('notifications').add({
                'title': title,
                'body': body,
                'type': notifType,
                'attendanceType': type,
                'companyId': companyId,
                'organizationId': organizationId,
                'branchName': safeBranchName,
                'targetDelegateId': userId,
                'targetDelegateName': delegateName,
                'senderName': delegateName,
                'senderRole': 'delegate',
                'delegateUid': doc.id,
                if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
                'isRead': false,
                'read': false,
                'createdAt': Timestamp.fromDate(time),
                'deletedBy': <String>[],
              });
            }
          }
        } catch (_) {}
      }

      // 3. Broadcast channels for company & supervisors
      for (final targetKey in [
        'supervisor_$companyId',
        'company_$companyId',
        'all_company_supervisors',
      ]) {
        await firestore.collection('notifications').add({
          'title': title,
          'body': body,
          'type': notifType,
          'attendanceType': type,
          'companyId': companyId,
          'organizationId': organizationId,
          'branchName': safeBranchName,
          'targetDelegateId': userId,
          'targetDelegateName': delegateName,
          'senderName': delegateName,
          'senderRole': 'delegate',
          'delegateUid': targetKey,
          'isRead': false,
          'read': false,
          'createdAt': Timestamp.fromDate(time),
          'deletedBy': <String>[],
        });
      }
    } catch (_) {}
  }

  Future<void> _syncDelegateTrackingCheckIn({
    required String userId,
    required String companyId,
    required String organizationId,
    required String? branchName,
    required double lat,
    required double long,
    required DateTime time,
  }) async {
    try {
      String delegateName = 'مندوب';
      String delegatePhone = '';
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          delegateName = (data?['fullName'] ??
                  data?['name'] ??
                  '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim())
              .toString();
          delegatePhone = (data?['phoneNumber'] ??
                  data?['phone'] ??
                  data?['mobileNumber'] ??
                  '')
              .toString();
        }
      } catch (_) {}

      double branchLat = lat;
      double branchLng = long;
      double geofenceRadius = 100.0;
      String branchId = '';

      if (branchName != null && branchName.trim().isNotEmpty) {
        try {
          final branchQuery = await firestore
              .collection('branches')
              .where('branchName', isEqualTo: branchName.trim())
              .limit(1)
              .get();
          if (branchQuery.docs.isNotEmpty) {
            final bDoc = branchQuery.docs.first;
            final bData = bDoc.data();
            branchId = bDoc.id;
            branchLat = (bData['latitude'] as num?)?.toDouble() ?? lat;
            branchLng = (bData['longitude'] as num?)?.toDouble() ?? long;
            geofenceRadius =
                (bData['geofenceRadius'] as num?)?.toDouble() ?? 100.0;
          }
        } catch (_) {}
      }

      await firestore.collection('delegate_tracking').doc(userId).set({
        'delegateId': userId,
        'delegateName': delegateName,
        'delegatePhone': delegatePhone,
        'companyId': companyId,
        'organizationId': organizationId,
        'branchId': branchId,
        'branchName': branchName ?? 'الفرع الميداني',
        'branchLat': branchLat,
        'branchLng': branchLng,
        'geofenceRadius': geofenceRadius,
        'currentStatus': 'inside',
        'currentDistanceMeters': 0.0,
        'lastLatitude': lat,
        'lastLongitude': long,
        'lastUpdated': FieldValue.serverTimestamp(),
        'checkInTime': Timestamp.fromDate(time),
        'isOnline': true,
      }, SetOptions(merge: true));
    } catch (e) {
      debugPrint('Error syncing delegate tracking on checkIn: $e');
    }
  }

  Future<void> _syncDelegateTrackingCheckOut({
    required String userId,
  }) async {
    try {
      await firestore.collection('delegate_tracking').doc(userId).update({
        'currentStatus': 'checked_out',
        'isTrackingEnabled': false,
        'checkOutTime': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
