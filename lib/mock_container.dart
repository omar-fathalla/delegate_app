import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/models/user_model.dart';
import 'dart:io';

class MockAuthDataSource implements AuthRemoteDataSource {
  @override
  Future<UserModel> login(String mobile, String motherName) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network
    if (mobile == '01000000000' && motherName == 'Mona') {
      return const UserModel(
        id: '1',
        name: 'Ahmed Delegate',
        mobile: '01000000000',
        motherName: 'Mona',
        role: 'delegate',
      );
    } else {
      throw const AuthFailure('Invalid credentials (Try: 01000000000 / Mona)');
    }
  }
}

class MockAttendanceDataSource implements AttendanceRemoteDataSource {
  final List<AttendanceModel> _history = [];

  @override
  Future<AttendanceModel> checkIn(
    String userId,
    double lat,
    double long, {
    File? image,
    String? branchName,
  }) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network delay
    final attendance = AttendanceModel(
      id: DateTime.now().toIso8601String(),
      userId: userId,
      checkInTime: DateTime.now(),
      latitude: lat,
      longitude: long,
      branchName: branchName,
    );
    _history.add(attendance);
    return attendance;
  }

  @override
  Future<AttendanceModel> checkOut(
    String attendanceId,
    double lat,
    double long,
  ) async {
    await Future.delayed(const Duration(seconds: 1));
    final index = _history.indexWhere((element) => element.id == attendanceId);
    if (index != -1) {
      final updated = AttendanceModel(
        id: _history[index].id,
        userId: _history[index].userId,
        checkInTime: _history[index].checkInTime,
        checkOutTime: DateTime.now(),
        latitude: lat,
        longitude: long,
      );
      _history[index] = updated;
      return updated;
    }
    throw const ServerFailure('Attendance record not found');
  }

  @override
  Future<List<AttendanceModel>> getHistory(String userId) async {
    await Future.delayed(const Duration(seconds: 1));
    return _history.where((element) => element.userId == userId).toList();
  }
}
