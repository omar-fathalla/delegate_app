import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/models/pagination_response.dart'; // Added this import
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';

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

      return AttendanceModel(
        id: docRef.id,
        userId: userId,
        organizationId: organizationId,
        checkInTime: DateTime.now(),
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

      return AttendanceModel(
        id: attendanceId,
        userId: userId,
        organizationId: organizationId,
        checkInTime: (lastData['timestamp'] as Timestamp).toDate(),
        checkOutTime: DateTime.now(),
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
      final List<String> identifiers = [userId];
      if (nationalityID != null && nationalityID.isNotEmpty) {
        identifiers.add(nationalityID);
      }
      if (phoneNumber != null && phoneNumber.isNotEmpty) {
        identifiers.add(phoneNumber);
      }

      Query<Map<String, dynamic>> query = _attendanceCollection(organizationId)
          .where('delegateId', whereIn: identifiers)
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
    } catch (_) {
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
    final Map<String, AttendanceModel> openSessions = {};

    // In DESC order: check_out (newer) comes before check_in (older)
    for (var doc in docs) {
      final data = doc.data();
      final type = data['type'] as String?;

      if (type == 'check_out') {
        final relatedId = data['relatedCheckInId'] as String?;
        if (relatedId != null) {
          openSessions[relatedId] = AttendanceModel(
            id: relatedId,
            userId: userId,
            organizationId: organizationId,
            checkInTime: DateTime.now(), // Placeholder
            checkOutTime: data['timestamp'] != null
                ? (data['timestamp'] as Timestamp).toDate()
                : DateTime.now(),
            latitude:
                (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude:
                (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
          );
        }
      } else if (type == 'check_in') {
        final checkInId = doc.id;
        final checkInTime = data['timestamp'] != null
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now();
        final lat = (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0;
        final lng = (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0;
        final branchName = data['branchName'];

        if (openSessions.containsKey(checkInId)) {
          final session = openSessions.remove(checkInId)!;
          history.add(
            session.copyWith(
              checkInTime: checkInTime,
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
}
