import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import '../../domain/entities/photo_permission.dart';
import '../../domain/entities/captured_photo.dart';
import '../../domain/repositories/photo_permission_repository.dart';
import '../datasources/photo_permission_remote_datasource.dart';

class PhotoPermissionRepositoryImpl implements PhotoPermissionRepository {
  final PhotoPermissionRemoteDataSource remoteDataSource;

  PhotoPermissionRepositoryImpl({required this.remoteDataSource});

  @override
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
  }) async {
    try {
      final result = await remoteDataSource.requestPermission(
        organizationUID: organizationUID,
        companyUID: companyUID,
        companyName: companyName,
        companyCode: companyCode,
        branchIds: branchIds,
        branchNames: branchNames,
        startDate: startDate,
        endDate: endDate,
        requestedBy: requestedBy,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء إرسال طلب إذن التصوير.'));
    }
  }

  @override
  Future<Either<Failure, PhotoPermission>> approvePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String status,
    required String approvedBy,
  }) async {
    try {
      final result = await remoteDataSource.approvePermission(
        organizationUID: organizationUID,
        companyUID: companyUID,
        permissionId: permissionId,
        status: status,
        approvedBy: approvedBy,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء معالجة الطلب.'));
    }
  }

  @override
  Future<Either<Failure, PhotoPermission>> togglePermissionBySupervisor({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required bool isEnabled,
  }) async {
    try {
      final result = await remoteDataSource.togglePermissionBySupervisor(
        organizationUID: organizationUID,
        companyUID: companyUID,
        permissionId: permissionId,
        isEnabled: isEnabled,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء تعديل حالة الإذن.'));
    }
  }

  @override
  Future<Either<Failure, List<PhotoPermission>>> getPermissions({
    required String organizationUID,
    required String companyUID,
  }) async {
    try {
      final result = await remoteDataSource.getPermissions(
        organizationUID: organizationUID,
        companyUID: companyUID,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء جلب الأذونات.'));
    }
  }

  @override
  Future<Either<Failure, List<PhotoPermission>>> getOngoingPermissions({
    required String organizationUID,
  }) async {
    try {
      final result = await remoteDataSource.getOngoingPermissions(
        organizationUID: organizationUID,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء جلب الأذونات الجارية.'));
    }
  }

  @override
  Future<Either<Failure, CapturedPhoto>> uploadPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String branchId,
    required String branchName,
    required String delegateUID,
    required String delegateName,
    required File imageFile,
    required String comment,
    required double latitude,
    required double longitude,
  }) async {
    try {
      final result = await remoteDataSource.uploadPhoto(
        organizationUID: organizationUID,
        companyUID: companyUID,
        permissionId: permissionId,
        branchId: branchId,
        branchName: branchName,
        delegateUID: delegateUID,
        delegateName: delegateName,
        imageFile: imageFile,
        comment: comment,
        latitude: latitude,
        longitude: longitude,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء رفع التقرير الميداني وصورته.'));
    }
  }

  @override
  Future<Either<Failure, List<CapturedPhoto>>> getCapturedPhotos({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  }) async {
    try {
      final result = await remoteDataSource.getCapturedPhotos(
        organizationUID: organizationUID,
        companyUID: companyUID,
        permissionId: permissionId,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء جلب الصور المسجلة.'));
    }
  }

  @override
  Future<Either<Failure, List<CapturedPhoto>>> getDelegateCapturedPhotos({
    required String delegateUID,
  }) async {
    try {
      final result = await remoteDataSource.getDelegateCapturedPhotos(
        delegateUID: delegateUID,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء جلب تقرير صور المندوب.'));
    }
  }

  @override
  Future<Either<Failure, List<CapturedPhoto>>> getCompanyCapturedPhotos({
    required String companyUID,
    String? organizationUID,
  }) async {
    try {
      final result = await remoteDataSource.getCompanyCapturedPhotos(
        companyUID: companyUID,
        organizationUID: organizationUID,
      );
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء جلب صور الشركة.'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteCapturedPhoto({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
    required String photoId,
    required String photoUrl,
  }) async {
    try {
      await remoteDataSource.deleteCapturedPhoto(
        organizationUID: organizationUID,
        companyUID: companyUID,
        permissionId: permissionId,
        photoId: photoId,
        photoUrl: photoUrl,
      );
      return const Right(null);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ أثناء محاولة حذف الصورة.'));
    }
  }

  @override
  Future<Either<Failure, void>> deletePermission({
    required String organizationUID,
    required String companyUID,
    required String permissionId,
  }) async {
    try {
      await remoteDataSource.deletePermission(
        organizationUID: organizationUID,
        companyUID: companyUID,
        permissionId: permissionId,
      );
      return const Right(null);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع أثناء حذف إذن التصوير.'));
    }
  }
}
