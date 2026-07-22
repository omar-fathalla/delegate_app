import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/photo_permission.dart';
import '../repositories/photo_permission_repository.dart';

class GetOngoingPhotoPermissions implements UseCase<List<PhotoPermission>, GetOngoingPhotoPermissionsParams> {
  final PhotoPermissionRepository repository;

  GetOngoingPhotoPermissions(this.repository);

  @override
  Future<Either<Failure, List<PhotoPermission>>> call(GetOngoingPhotoPermissionsParams params) {
    return repository.getOngoingPermissions(
      organizationUID: params.organizationUID,
    );
  }
}

class GetOngoingPhotoPermissionsParams extends Equatable {
  final String organizationUID;

  const GetOngoingPhotoPermissionsParams({
    required this.organizationUID,
  });

  @override
  List<Object?> get props => [organizationUID];
}
