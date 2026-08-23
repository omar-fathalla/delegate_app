import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../repositories/photo_permission_repository.dart';

class UpdatePhotoPermissionBranches implements UseCase<void, UpdatePhotoPermissionBranchesParams> {
  final PhotoPermissionRepository repository;

  UpdatePhotoPermissionBranches(this.repository);

  @override
  Future<Either<Failure, void>> call(UpdatePhotoPermissionBranchesParams params) async {
    return await repository.updatePermissionBranches(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
      branchIds: params.branchIds,
      branchNames: params.branchNames,
    );
  }
}

class UpdatePhotoPermissionBranchesParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final List<String> branchIds;
  final List<String> branchNames;

  const UpdatePhotoPermissionBranchesParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.branchIds,
    required this.branchNames,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, permissionId, branchIds, branchNames];
}
