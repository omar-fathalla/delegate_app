import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/photo_permission.dart';
import '../repositories/photo_permission_repository.dart';

class RequestPhotoPermission implements UseCase<PhotoPermission, RequestPhotoPermissionParams> {
  final PhotoPermissionRepository repository;

  RequestPhotoPermission(this.repository);

  @override
  Future<Either<Failure, PhotoPermission>> call(RequestPhotoPermissionParams params) {
    return repository.requestPermission(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      companyName: params.companyName,
      companyCode: params.companyCode,
      branchIds: params.branchIds,
      branchNames: params.branchNames,
      startDate: params.startDate,
      endDate: params.endDate,
      requestedBy: params.requestedBy,
      department: params.department,
    );
  }
}

class RequestPhotoPermissionParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final List<String> branchIds;
  final List<String> branchNames;
  final DateTime startDate;
  final DateTime endDate;
  final String requestedBy;
  final String? department;

  const RequestPhotoPermissionParams({
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.companyCode,
    required this.branchIds,
    required this.branchNames,
    required this.startDate,
    required this.endDate,
    required this.requestedBy,
    this.department,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        companyName,
        companyCode,
        branchIds,
        branchNames,
        startDate,
        endDate,
        requestedBy,
        department,
      ];
}
