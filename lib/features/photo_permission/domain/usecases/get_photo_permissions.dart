import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/photo_permission.dart';
import '../repositories/photo_permission_repository.dart';

class GetPhotoPermissions implements UseCase<List<PhotoPermission>, GetPhotoPermissionsParams> {
  final PhotoPermissionRepository repository;

  GetPhotoPermissions(this.repository);

  @override
  Future<Either<Failure, List<PhotoPermission>>> call(GetPhotoPermissionsParams params) {
    return repository.getPermissions(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
    );
  }
}

class GetPhotoPermissionsParams extends Equatable {
  final String organizationUID;
  final String companyUID;

  const GetPhotoPermissionsParams({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID];
}
