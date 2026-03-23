import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
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
  Future<List<AttendanceModel>> getHistory(String userId, String organizationId);

  /// Finds the active attendance record (where checkOutTime is null)
  /// for the given [userId] in the specified [organizationId].
  /// Returns `null` if no active session exists.
  Future<AttendanceModel?> findActiveAttendance(String userId, String organizationId);

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

  /// Helper: Get the organization-scoped attendance_logs collection
  /// Path: /organizations/{organizationId}/attendance_logs
  CollectionReference<Map<String, dynamic>> _attendanceCollection(
      String organizationId) =>
      firestore
          .collection('organizations')
          .doc(organizationId)
          .collection(kAttendanceCollection);

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
          .timeout(const Duration(seconds: 5));

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
      final lastCheckInSnapshot = await _attendanceCollection(organizationId)
          .doc(attendanceId)
          .get()
          .timeout(const Duration(seconds: 5));

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
          })
          .timeout(const Duration(seconds: 5));

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
      String userId, String organizationId) async {
    try {
      // جرب orderBy أولاً
      QuerySnapshot<Map<String, dynamic>> querySnapshot;
      try {
        querySnapshot = await _attendanceCollection(organizationId)
            .where('delegateId', isEqualTo: userId)
            .orderBy('timestamp', descending: false)
            .get()
            .timeout(const Duration(seconds: 5));
      } catch (e) {
        // إذا فشل orderBy (مثل عدم وجود index)، جرب بدونه
        querySnapshot = await _attendanceCollection(organizationId)
            .where('delegateId', isEqualTo: userId)
            .get()
            .timeout(const Duration(seconds: 5));
      }

      // إذا لم توجد بيانات، أرجع قائمة فارغة (ليس خطأ)
      if (querySnapshot.docs.isEmpty) {
        return [];
      }

      final List<AttendanceModel> history = [];
      final Map<String, AttendanceModel> openSessions = {};

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String?;

        if (type == 'check_in') {
          final model = AttendanceModel(
            id: doc.id,
            userId: data['delegateId'] ?? data['userId'] ?? '',
            organizationId: organizationId,
            checkInTime: data['timestamp'] != null
                ? (data['timestamp'] as Timestamp).toDate()
                : DateTime.now(),
            latitude:
                (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude:
                (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
            branchName: data['branchName'],
          );
          openSessions[doc.id] = model;
        } else if (type == 'check_out') {
          final relatedId = data['relatedCheckInId'] as String?;
          if (relatedId != null && openSessions.containsKey(relatedId)) {
            final checkInModel = openSessions.remove(relatedId)!;
            final completedSession = checkInModel.copyWith(
              checkOutTime: data['timestamp'] != null
                  ? (data['timestamp'] as Timestamp).toDate()
                  : DateTime.now(),
            );
            history.add(completedSession);
          }
        }
      }

      history.addAll(openSessions.values);
      history.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      return history;
    } on FirebaseException catch (e) {
      // إذا كانت المشكلة أن المجموعة غير موجودة، أرجع قائمة فارغة
      if (e.code == 'failed-precondition') {
        return [];
      }
      throwFirestoreFailure(e, 'فشل في تحميل سجل الحضور.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم.');
    } catch (_) {
      // في حالة الأخطاء غير المتوقعة، أرجع قائمة فارغة بدل خطأ
      return [];
    }
  }

  @override
  Future<AttendanceModel?> findActiveAttendance(
      String userId, String organizationId) async {
    try {
      final querySnapshot = await _attendanceCollection(organizationId)
          .where('delegateId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

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

      await batch.commit().timeout(const Duration(seconds: 10));
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
          .where('branchName', isEqualTo: branchName)
          .limit(1)
          .get()
          .timeout(const Duration(seconds: 5));

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      return querySnapshot.docs.first.data();
    } catch (_) {
      return null;
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
          .timeout(const Duration(seconds: 5));

      final Map<String, dynamic> data = {
        'branchName': branchName,
        'location': {
          'latitude': latitude,
          'longitude': longitude,
        },
        'geofenceRadius': geofenceRadius,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (querySnapshot.docs.isEmpty) {
        await firestore
            .collection('branches')
            .add(data)
            .timeout(const Duration(seconds: 5));
      } else {
        await querySnapshot.docs.first.reference
            .update(data)
            .timeout(const Duration(seconds: 5));
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حفظ بيانات الفرع.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء حفظ بيانات الفرع.');
    }
  }
}
