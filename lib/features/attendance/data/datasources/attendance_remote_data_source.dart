import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';

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
        'branchName': branchName,
      });

      final doc = await docRef.get();
      // We need to construct the model manually here because serverTimestamp
      // might be null immediately after write in some offline scenarios,
      // but for now we trust the read.
      // A safer approach for UI is to return a local object with DateTime.now()
      return AttendanceModel(
        id: doc.id,
        userId: userId,
        checkInTime: DateTime.now(), // Use local time for immediate UI feedback
        latitude: lat,
        longitude: long,
        branchName: branchName,
      );
    } catch (e) {
      // ignore: avoid_print
      print('Check-in failed: $e');
      throw ServerFailure('Check-in failed: $e');
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
        userId: data['userId'],
        checkInTime: (data['checkInTime'] as Timestamp).toDate(),
        checkOutTime: DateTime.now(), // Local time for immediate UI
        latitude: (data['latitude'] as num).toDouble(),
        longitude: (data['longitude'] as num).toDouble(),
        imageUrl: data['imageUrl'],
        branchName: data['branchName'],
      );
    } catch (e) {
      throw const ServerFailure('Check-out failed');
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
          userId: data['userId'],
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
    } catch (e) {
      // ignore: avoid_print
      print('Failed to fetch history: $e');
      throw ServerFailure('Failed to fetch history: $e');
    }
  }
}
