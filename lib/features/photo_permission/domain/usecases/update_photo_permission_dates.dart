import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../repositories/photo_permission_repository.dart';

class UpdatePhotoPermissionDates implements UseCase<void, UpdatePhotoPermissionDatesParams> {
  final PhotoPermissionRepository repository;

  UpdatePhotoPermissionDates(this.repository);

  @override
  Future<Either<Failure, void>> call(UpdatePhotoPermissionDatesParams params) async {
    return await repository.updatePermissionDates(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
      startDate: params.startDate,
      endDate: params.endDate,
    );
  }
}

class UpdatePhotoPermissionDatesParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final DateTime startDate;
  final DateTime endDate;

  const UpdatePhotoPermissionDatesParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.startDate,
    required this.endDate,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        startDate,
        endDate,
      ];
}
