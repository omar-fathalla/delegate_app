import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/captured_photo.dart';
import '../repositories/photo_permission_repository.dart';

class GetCapturedPhotos implements UseCase<List<CapturedPhoto>, GetCapturedPhotosParams> {
  final PhotoPermissionRepository repository;

  GetCapturedPhotos(this.repository);

  @override
  Future<Either<Failure, List<CapturedPhoto>>> call(GetCapturedPhotosParams params) {
    return repository.getCapturedPhotos(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
    );
  }
}

class GetCapturedPhotosParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;

  const GetCapturedPhotosParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, permissionId];
}
