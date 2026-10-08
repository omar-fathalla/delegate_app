import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/captured_photo.dart';
import '../repositories/photo_permission_repository.dart';

class GetCompanyCapturedPhotos implements UseCase<List<CapturedPhoto>, GetCompanyCapturedPhotosParams> {
  final PhotoPermissionRepository repository;

  GetCompanyCapturedPhotos(this.repository);

  @override
  Future<Either<Failure, List<CapturedPhoto>>> call(GetCompanyCapturedPhotosParams params) {
    return repository.getCompanyCapturedPhotos(
      companyUID: params.companyUID,
      organizationUID: params.organizationUID,
      branchName: params.branchName,
      limit: params.limit,
    );
  }
}

class GetCompanyCapturedPhotosParams extends Equatable {
  final String companyUID;
  final String? organizationUID;
  final String? branchName;
  final int? limit;

  const GetCompanyCapturedPhotosParams({
    required this.companyUID,
    this.organizationUID,
    this.branchName,
    this.limit,
  });

  @override
  List<Object?> get props => [companyUID, organizationUID, branchName, limit];
}
