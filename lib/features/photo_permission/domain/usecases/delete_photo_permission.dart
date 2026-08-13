import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../repositories/photo_permission_repository.dart';

class DeletePhotoPermission implements UseCase<void, DeletePhotoPermissionParams> {
  final PhotoPermissionRepository repository;

  DeletePhotoPermission(this.repository);

  @override
  Future<Either<Failure, void>> call(DeletePhotoPermissionParams params) async {
    return await repository.deletePermission(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
    );
  }
}

class DeletePhotoPermissionParams {
  final String organizationUID;
  final String companyUID;
  final String permissionId;

  DeletePhotoPermissionParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
  });
}
