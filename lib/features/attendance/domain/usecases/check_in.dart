import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';

class CheckIn implements UseCase<Attendance, CheckInParams> {
  final AttendanceRepository repository;

  CheckIn(this.repository);

  @override
  Future<Either<Failure, Attendance>> call(CheckInParams params) async {
    if (params.currentHistory != null) {
      // 1. Guard against checking in while another session is still active (unclosed)
      final activeAttendance = params.currentHistory!.cast<Attendance?>().firstWhere(
        (attendance) => attendance?.checkOutTime == null,
        orElse: () => null,
      );

      if (activeAttendance != null) {
        final now = DateTime.now();
        final isToday = activeAttendance.checkInTime.year == now.year &&
            activeAttendance.checkInTime.month == now.month &&
            activeAttendance.checkInTime.day == now.day;

        if (isToday) {
          if (activeAttendance.branchName == params.branchName) {
            return const Left(
              ServerFailure('أنت مسجل حضور بالفعل في هذا الفرع وما زالت الجلسة جارية.'),
            );
          } else {
            return Left(
              ServerFailure(
                'لديك تسجيل حضور نشط في فرع ${activeAttendance.branchName ?? "آخر"}. يرجى تسجيل الانصراف أولاً.',
              ),
            );
          }
        }
      }

      // 2. Guard against duplicate visits to the same branch on the same day
      if (params.branchName != null) {
        final now = DateTime.now();
        final hasVisitedToday = params.currentHistory!.any((attendance) {
          final isSameDay = attendance.checkInTime.year == now.year &&
              attendance.checkInTime.month == now.month &&
              attendance.checkInTime.day == now.day;
          return isSameDay && attendance.branchName == params.branchName;
        });

        if (hasVisitedToday) {
          return const Left(
            ServerFailure('لا يمكن تكرار زيارة نفس الفرع في نفس اليوم'),
          );
        }
      }
    }

    return await repository.checkIn(
      params.userId,
      params.lat,
      params.long,
      companyId: params.companyId,
      organizationId: params.organizationId,
      deviceInfo: params.deviceInfo,
      branchName: params.branchName,
      delegateName: params.delegateName,
      phoneNumber: params.phoneNumber,
      companyName: params.companyName,
      personalPhotoURL: params.personalPhotoURL,
    );
  }
}

class CheckInParams extends Equatable {
  final String userId;
  final String companyId;
  final String organizationId;
  final String deviceInfo;
  final double lat;
  final double long;
  final String? branchName;
  final List<Attendance>? currentHistory;
  final String? delegateName;
  final String? phoneNumber;
  final String? companyName;
  final String? personalPhotoURL;

  const CheckInParams({
    required this.userId,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    required this.lat,
    required this.long,
    this.branchName,
    this.currentHistory,
    this.delegateName,
    this.phoneNumber,
    this.companyName,
    this.personalPhotoURL,
  });

  @override
  List<Object?> get props => [
    userId,
    companyId,
    organizationId,
    deviceInfo,
    lat,
    long,
    branchName,
    currentHistory,
    delegateName,
    phoneNumber,
    companyName,
    personalPhotoURL,
  ];
}
