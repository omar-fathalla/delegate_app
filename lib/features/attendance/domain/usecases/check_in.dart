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
    if (params.currentHistory != null && params.branchName != null) {
      final now = DateTime.now();
      final hasVisitedToday = params.currentHistory!.any((attendance) {
        final isSameDay =
            attendance.checkInTime.year == now.year &&
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

    return await repository.checkIn(
      params.userId,
      params.lat,
      params.long,
      companyId: params.companyId,
      organizationId: params.organizationId,
      deviceInfo: params.deviceInfo,
      branchName: params.branchName,
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

  const CheckInParams({
    required this.userId,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    required this.lat,
    required this.long,
    this.branchName,
    this.currentHistory,
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
  ];
}
