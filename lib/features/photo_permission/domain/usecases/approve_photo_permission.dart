import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/photo_permission.dart';
import '../repositories/photo_permission_repository.dart';

class ApprovePhotoPermission implements UseCase<PhotoPermission, ApprovePhotoPermissionParams> {
  final PhotoPermissionRepository repository;

  ApprovePhotoPermission(this.repository);

  @override
  Future<Either<Failure, PhotoPermission>> call(ApprovePhotoPermissionParams params) {
    return repository.approvePermission(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
      status: params.status,
      approvedBy: params.approvedBy,
    );
  }
}

class ApprovePhotoPermissionParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final String status;
  final String approvedBy;

  const ApprovePhotoPermissionParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.status,
    required this.approvedBy,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        status,
        approvedBy,
      ];
}
