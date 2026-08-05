import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../repositories/photo_permission_repository.dart';

class DeleteCapturedPhoto implements UseCase<void, DeleteCapturedPhotoParams> {
  final PhotoPermissionRepository repository;

  DeleteCapturedPhoto(this.repository);

  @override
  Future<Either<Failure, void>> call(DeleteCapturedPhotoParams params) async {
    return await repository.deleteCapturedPhoto(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
      photoId: params.photoId,
      photoUrl: params.photoUrl,
    );
  }
}

class DeleteCapturedPhotoParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final String photoId;
  final String photoUrl;

  const DeleteCapturedPhotoParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.photoId,
    required this.photoUrl,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        photoId,
        photoUrl,
      ];
}
