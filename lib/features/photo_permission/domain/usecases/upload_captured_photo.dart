import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import '../entities/captured_photo.dart';
import '../repositories/photo_permission_repository.dart';

class UploadCapturedPhoto implements UseCase<CapturedPhoto, UploadCapturedPhotoParams> {
  final PhotoPermissionRepository repository;

  UploadCapturedPhoto(this.repository);

  @override
  Future<Either<Failure, CapturedPhoto>> call(UploadCapturedPhotoParams params) {
    return repository.uploadPhoto(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      permissionId: params.permissionId,
      branchId: params.branchId,
      branchName: params.branchName,
      delegateUID: params.delegateUID,
      delegateName: params.delegateName,
      imageFile: params.imageFile,
      comment: params.comment,
      latitude: params.latitude,
      longitude: params.longitude,
    );
  }
}

class UploadCapturedPhotoParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final String branchId;
  final String branchName;
  final String delegateUID;
  final String delegateName;
  final File imageFile;
  final String comment;
  final double latitude;
  final double longitude;

  const UploadCapturedPhotoParams({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.branchId,
    required this.branchName,
    required this.delegateUID,
    required this.delegateName,
    required this.imageFile,
    required this.comment,
    required this.latitude,
    required this.longitude,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        branchId,
        branchName,
        delegateUID,
        delegateName,
        imageFile,
        comment,
        latitude,
        longitude,
      ];
}
