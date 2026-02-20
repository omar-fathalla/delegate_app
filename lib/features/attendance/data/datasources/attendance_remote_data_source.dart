import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:flutter/foundation.dart';

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
    double lat,
    double long,
  );
  Future<List<AttendanceModel>> getHistory(String userId);

  /// Finds the active attendance record (where checkOutTime is null)
  /// for the given [userId]. Returns `null` if no active session exists.
  Future<AttendanceModel?> findActiveAttendance(String userId);
}

class AttendanceRemoteDataSourceImpl implements AttendanceRemoteDataSource {
  final FirebaseFirestore firestore;

  AttendanceRemoteDataSourceImpl({required this.firestore});

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
      final docRef = await firestore.collection(kAttendanceCollection).add({
        'delegateId': userId,
        'companyId': companyId,
        'organizationId': organizationId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'check_in',
        'location': {'latitude': lat, 'longitude': long},
        'deviceInfo': deviceInfo,
        'branchName': branchName,
      });

      return AttendanceModel(
        id: docRef.id,
        userId: userId,
        checkInTime: DateTime.now(),
        latitude: lat,
        longitude: long,
        branchName: branchName,
      );
    } on FirebaseException catch (e) {
      debugPrint(
        'AttendanceRemoteDataSource.checkIn FirebaseException: ${e.code}',
      );
      throw const ServerFailure('فشل في تسجيل الحضور. حاول مرة أخرى.');
    } catch (e) {
      debugPrint('AttendanceRemoteDataSource.checkIn error: $e');
      throw const ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الحضور.');
    }
  }

  @override
  Future<AttendanceModel> checkOut(
    String attendanceId,
    double lat,
    double long,
  ) async {
    try {
      // NOTE: We don't have easy access to company/org ID here without fetching user again.
      // However, for check-out we mostly need userId and timestamp.
      // For consistency, we might want to fetch the check-in doc, but that's in the log list now.
      // COMPROMISE: We will proceed with minimal check-out info.
      // Ideally, the Bloc should pass the full context.
      // But for now, let's look up the LAST check-in to get the Organization info if needed.
      // OR, since we are just logging, maybe we can skip orgId for check-out if the backend correlates them?
      // No, let's fetch the last check-in to copy the IDs.

      final lastCheckInSnapshot = await firestore
          .collection(kAttendanceCollection)
          //.where('userId', isEqualTo: ...) // userId is not passed cleanly here, assumes attendanceId is enough?
          // BUT attendanceId was the DOC ID in the old system.
          // In the new system, we actually need the USER ID to find the last log.
          // The current signature takes `attendanceId`.
          // Implementation Detail: In the new system, `attendanceId` returned by checkIn is the ID of the 'check_in' log doc.
          // So we CAN fetch that doc to get metadata.
          .doc(attendanceId)
          .get();

      if (!lastCheckInSnapshot.exists) {
        throw const ServerFailure('سجل الحضور غير موجود.');
      }
      final lastData = lastCheckInSnapshot.data()!;
      final userId = lastData['delegateId'];
      final companyId = lastData['companyId'];
      final organizationId = lastData['organizationId'];

      await firestore.collection(kAttendanceCollection).add({
        'delegateId': userId,
        'companyId': companyId,
        'organizationId': organizationId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'check_out',
        'location': {'latitude': lat, 'longitude': long},
        'relatedCheckInId': attendanceId, // Link to the check-in
      });

      // Return a model representing the closed session
      return AttendanceModel(
        id: attendanceId,
        userId: userId,
        checkInTime: (lastData['timestamp'] as Timestamp).toDate(),
        checkOutTime: DateTime.now(),
        latitude: (lastData['location']['latitude'] as num).toDouble(),
        longitude: (lastData['location']['longitude'] as num).toDouble(),
        branchName: lastData['branchName'],
      );
    } on FirebaseException catch (e) {
      debugPrint(
        'AttendanceRemoteDataSource.checkOut FirebaseException: ${e.code}',
      );
      throw const ServerFailure('فشل في تسجيل الانصراف. حاول مرة أخرى.');
    } catch (e) {
      debugPrint('AttendanceRemoteDataSource.checkOut error: $e');
      throw const ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الانصراف.');
    }
  }

  @override
  Future<List<AttendanceModel>> getHistory(String userId) async {
    try {
      final querySnapshot = await firestore
          .collection(kAttendanceCollection)
          .where('delegateId', isEqualTo: userId)
          .orderBy('timestamp', descending: false) // Process chronologically
          .get();

      final List<AttendanceModel> history = [];
      final Map<String, AttendanceModel> openSessions = {};

      for (var doc in querySnapshot.docs) {
        final data = doc.data();
        final type = data['type'] as String?;

        if (type == 'check_in') {
          final model = AttendanceModel(
            id: doc.id,
            userId: data['delegateId'] ?? '',
            checkInTime: data['timestamp'] != null
                ? (data['timestamp'] as Timestamp).toDate()
                : DateTime.now(),
            latitude: (data['location']['latitude'] as num?)?.toDouble() ?? 0.0,
            longitude:
                (data['location']['longitude'] as num?)?.toDouble() ?? 0.0,
            branchName: data['branchName'],
          );
          openSessions[doc.id] = model;
        } else if (type == 'check_out') {
          final relatedId = data['relatedCheckInId'] as String?;
          if (relatedId != null && openSessions.containsKey(relatedId)) {
            final checkInModel = openSessions.remove(relatedId)!;
            final completedSession = AttendanceModel(
              id: checkInModel.id,
              userId: checkInModel.userId,
              checkInTime: checkInModel.checkInTime,
              checkOutTime: data['timestamp'] != null
                  ? (data['timestamp'] as Timestamp).toDate()
                  : DateTime.now(),
              latitude: checkInModel.latitude,
              longitude: checkInModel.longitude,
              branchName: checkInModel.branchName,
              // We could store check-out location too if model supports it
            );
            history.add(completedSession);
          }
        }
      }

      // Add any remaining open sessions (active check-ins)
      history.addAll(openSessions.values);

      // Sort by check-in time descending for the UI
      history.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

      return history;
    } on FirebaseException catch (e) {
      debugPrint(
        'AttendanceRemoteDataSource.getHistory FirebaseException: Code: ${e.code}, Message: ${e.message}, Plugin: ${e.plugin}',
      );
      throw const ServerFailure('فشل في تحميل سجل الحضور.');
    } catch (e) {
      debugPrint('AttendanceRemoteDataSource.getHistory error: $e');
      throw const ServerFailure('حدث خطأ غير متوقع أثناء تحميل السجل.');
    }
  }

  @override
  Future<AttendanceModel?> findActiveAttendance(String userId) async {
    try {
      // Get the single most recent log for this user
      final querySnapshot = await firestore
          .collection(kAttendanceCollection)
          .where('delegateId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isEmpty) {
        return null;
      }

      final doc = querySnapshot.docs.first;
      final data = doc.data();

      // If the last log is 'check_in', then the user is currently checked in.
      if (data['type'] == 'check_in') {
        return AttendanceModel(
          id: doc.id,
          userId: data['delegateId'] ?? '',
          checkInTime: data['timestamp'] != null
              ? (data['timestamp'] as Timestamp).toDate()
              : DateTime.now(),
          latitude: (data['location']['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude: (data['location']['longitude'] as num?)?.toDouble() ?? 0.0,
          branchName: data['branchName'],
        );
      }

      // If the last log is 'check_out', then there is no active session.
      return null;
    } on FirebaseException catch (e) {
      debugPrint(
        'AttendanceRemoteDataSource.findActiveAttendance FirebaseException: ${e.code}',
      );
      throw const ServerFailure('فشل في البحث عن جلسة الحضور النشطة.');
    } catch (e) {
      debugPrint('AttendanceRemoteDataSource.findActiveAttendance error: $e');
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }
}
