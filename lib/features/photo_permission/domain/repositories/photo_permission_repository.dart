import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import '../entities/photo_permission.dart';
import '../entities/captured_photo.dart';

abstract class PhotoPermissionRepository {
  Future<Either<Failure, PhotoPermission>> requestPermission({
    required String organizationUID,
    required String companyUID,
    required String companyName,
    int? companyCode,
    required List<String> branchIds,
    required List<String> branchNames,
    required DateTime startDate,
    required DateTime endDate,
    required String requestedBy,
    String? department,
  });

  Future<Either<Failure, PhotoPermission>> approvePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String status,
    required String approvedBy,
  });

  Future<Either<Failure, PhotoPermission>> togglePermissionBySupervisor({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required bool isEnabled,
  });

  Future<Either<Failure, List<PhotoPermission>>> getPermissions({
    required String organizationUID,
    required String companyUID,
  });

  Future<Either<Failure, List<PhotoPermission>>> getOngoingPermissions({
    required String organizationUID,
  });

  Future<Either<Failure, void>> updatePermissionBranches({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required List<String> branchIds,
    required List<String> branchNames,
  });

  Future<Either<Failure, void>> updatePermissionDates({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required DateTime startDate,
    required DateTime endDate,
  });

  Future<Either<Failure, void>> deletePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  });

  Future<Either<Failure, CapturedPhoto>> uploadPhoto({
    required String organizationUID,
    required String companyUID,
    String companyName = '',
    int? companyCode,
    required String permissionId,
    required String branchId,
    required String branchName,
    required String delegateUID,
    required String delegateName,
    required File imageFile,
    required String comment,
    required double latitude,
    required double longitude,
  });

  Future<Either<Failure, List<CapturedPhoto>>> getCapturedPhotos({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  });

  Future<Either<Failure, List<CapturedPhoto>>> getDelegateCapturedPhotos({
    required String delegateUID,
  });

  Future<Either<Failure, List<CapturedPhoto>>> getCompanyCapturedPhotos({
    required String companyUID,
    String? organizationUID,
    String? branchName,
    int? limit,
  });

  Future<Either<Failure, void>> deleteCapturedPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String photoId,
    required String photoUrl,
  });
}
