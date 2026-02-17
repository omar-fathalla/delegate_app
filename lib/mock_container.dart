import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'dart:io';

class MockAuthDataSource implements AuthRemoteDataSource {
  @override
  Future<DelegateModel?> getDelegateByPhone(String phoneNumber) async {
    await Future.delayed(const Duration(seconds: 1)); // Simulate network
    if (phoneNumber == '01000000000') {
      return DelegateModel(
        uid: '1',
        firstName: 'أحمد',
        middleName: 'محمد',
        lastName: 'علي',
        fullName: 'أحمد محمد علي',
        nationalityID: '12345678901234',
        motherName: 'منى',
        city: 'القاهرة',
        phoneNumber: '01000000000',
        gender: DelegateGender.male,
        position: DelegatePosition.promoter,
        birthDate: DateTime(1995, 1, 1),
        organizationUID: 'org1',
        organizationName: 'منظمة تسهيل',
        companyUID: 'comp1',
        companyName: 'شركة تسهيل',
        status: DelegateStatus.active,
        delegatePublicId: 'DEL-001',
        allReceiptCodes: const [],
        createdAt: DateTime(2024, 1, 1),
        createdBy: 'admin',
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        paymentAmount: 0,
        version: 1,
        documents: const [],
      );
    } else {
      return null;
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
