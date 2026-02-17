import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:flutter/foundation.dart';

abstract class AttendanceRemoteDataSource {
  Future<AttendanceModel> checkIn(
    String userId,
    double lat,
    double long, {
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
    String? branchName,
  }) async {
    try {
      final docRef = await firestore.collection('attendance').add({
        'userId': userId,
        'checkInTime': FieldValue.serverTimestamp(),
        'latitude': lat,
        'longitude': long,
        'location': {'lat': lat, 'long': long},
        'branchName': branchName,
      });

      // Return a local object with DateTime.now() for immediate UI feedback.
      // The server timestamp will be set asynchronously by Firestore.
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
      await firestore.collection('attendance').doc(attendanceId).update({
        'checkOutTime': FieldValue.serverTimestamp(),
        'checkOutLat': lat,
        'checkOutLong': long,
      });

      final doc = await firestore
          .collection('attendance')
          .doc(attendanceId)
          .get();

      final data = doc.data()!;
      return AttendanceModel(
        id: doc.id,
        userId: data['userId'] ?? '',
        checkInTime: data['checkInTime'] != null
            ? (data['checkInTime'] as Timestamp).toDate()
            : DateTime.now(),
        checkOutTime: data['checkOutTime'] != null
            ? (data['checkOutTime'] as Timestamp).toDate()
            : DateTime.now(),
        latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
        longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
        imageUrl: data['imageUrl'],
        branchName: data['branchName'],
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
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .orderBy('checkInTime', descending: true)
          .get();

      return querySnapshot.docs.map((doc) {
        final data = doc.data();
        return AttendanceModel(
          id: doc.id,
          userId: data['userId'] ?? '',
          checkInTime: data['checkInTime'] != null
              ? (data['checkInTime'] as Timestamp).toDate()
              : DateTime.now(),
          checkOutTime: data['checkOutTime'] != null
              ? (data['checkOutTime'] as Timestamp).toDate()
              : null,
          latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
          imageUrl: data['imageUrl'],
          branchName: data['branchName'],
        );
      }).toList();
    } on FirebaseException catch (e) {
      debugPrint(
        'AttendanceRemoteDataSource.getHistory FirebaseException: ${e.code}',
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
      final querySnapshot = await firestore
          .collection('attendance')
          .where('userId', isEqualTo: userId)
          .where('checkOutTime', isNull: true)
          .orderBy('checkInTime', descending: true)
          .limit(1)
          .get();

      if (querySnapshot.docs.isNotEmpty) {
        final doc = querySnapshot.docs.first;
        final data = doc.data();
        return AttendanceModel(
          id: doc.id,
          userId: data['userId'] ?? '',
          checkInTime: data['checkInTime'] != null
              ? (data['checkInTime'] as Timestamp).toDate()
              : DateTime.now(),
          latitude: (data['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude: (data['longitude'] as num?)?.toDouble() ?? 0.0,
          imageUrl: data['imageUrl'],
          branchName: data['branchName'],
        );
      }
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
