import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/photo_permission.dart';
import '../repositories/photo_permission_repository.dart';

class TogglePhotoPermission implements UseCase<PhotoPermission, TogglePhotoPermissionParams> {
  final PhotoPermissionRepository repository;

  TogglePhotoPermission(this.repository);

  @override
  Future<Either<Failure, PhotoPermission>> call(TogglePhotoPermissionParams params) {
    return repository.togglePermissionBySupervisor(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
      isEnabled: params.isEnabled,
    );
  }
}

class TogglePhotoPermissionParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final bool isEnabled;

  const TogglePhotoPermissionParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.isEnabled,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        isEnabled,
      ];
}
