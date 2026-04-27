import 'dart:math';

import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/datasources/manage_marketing_remote_datasource.dart';
import 'package:delegate_app/features/admin/data/models/admin_user_model.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class AdminRepositoryImpl implements AdminRepository {
  final AdminRemoteDataSource remoteDataSource;
  final ManageMarketingRemoteDataSource marketingDataSource;

  AdminRepositoryImpl({
    required this.remoteDataSource,
    required this.marketingDataSource,
  });


  @override
  Future<Either<Failure, List<Map<String, dynamic>>>> getOrganizations() async {
    try {
      final orgs = await remoteDataSource.getOrganizations();
      return Right(orgs);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, List<Branch>>> getBranches() async {
    try {
      final branches = await remoteDataSource.getBranches();
      return Right(branches);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Branch>> addBranch(Branch branch) async {
    try {
      final model = BranchModel(
        id: branch.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
      );
      final result = await remoteDataSource.addBranch(model);
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Branch>> updateBranch(Branch branch) async {
    try {
      final model = BranchModel(
        id: branch.id,
        branchName: branch.branchName,
        latitude: branch.latitude,
        longitude: branch.longitude,
        geofenceRadius: branch.geofenceRadius,
      );
      final result = await remoteDataSource.updateBranch(model);
      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteBranch(String branchId) async {
    try {
      await remoteDataSource.deleteBranch(branchId);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  String _generateTemporaryPassword() {
    const chars = 'ABCDEFGHJKLMNPQRSTUVWXYZabcdefghjkmnpqrstuvwxyz23456789';
    final random = Random.secure();
    return List.generate(8, (_) => chars[random.nextInt(chars.length)]).join();
  }

  @override
  Future<Either<Failure, AdminUser>> createAdmin({
    required String phoneNumber,
    required String email,
    required String displayName,
    String role = 'company-admin',
    String organizationUID = '',
  }) async {
    try {
      final tempPassword = _generateTemporaryPassword();
      final adminModel = AdminUserModel(
        uid: '',
        phoneNumber: phoneNumber,
        email: email,
        displayName: displayName,
        role: role,
        organizationUID: organizationUID,
        createdAt: DateTime.now(),
        createdBy: 'super-admin',
        temporaryPassword: tempPassword,
      );

      final result = await remoteDataSource.createAdmin(adminModel);

      await remoteDataSource.sendActivationEmail(
        email: email,
        phoneNumber: phoneNumber,
        temporaryPassword: tempPassword,
        displayName: displayName,
      );

      return Right(result);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, List<AdminUser>>> getAdmins() async {
    try {
      final admins = await remoteDataSource.getAdmins();
      return Right(admins);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateAdminUser(AdminUser admin) async {
    try {
      final model = AdminUserModel(
        uid: admin.uid,
        phoneNumber: admin.phoneNumber,
        email: admin.email,
        displayName: admin.displayName,
        role: admin.role,
        createdAt: admin.createdAt,
        createdBy: admin.createdBy,
        temporaryPassword: admin.temporaryPassword,
        isActive: admin.isActive,
      );
      await remoteDataSource.updateAdminUser(model);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteAdminUser(String adminId) async {
    try {
      await remoteDataSource.deleteAdminUser(adminId);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> suspendAdminUser(
    String adminId,
    bool suspend,
  ) async {
    try {
      await remoteDataSource.suspendAdminUser(adminId, suspend);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, List<Delegate>>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  ) async {
    try {
      final delegates = await remoteDataSource.getCompanyDelegates(
        organizationUID,
        companyUID,
      );
      return Right(delegates);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, DashboardSummary>> getDashboardSummary(
    String organizationUID,
    String companyUID,
  ) async {
    try {
      final delegates = await remoteDataSource.getCompanyDelegates(
        organizationUID,
        companyUID,
      );
      final checkedInCount = await remoteDataSource.getTodayCheckedInCount(
        organizationUID,
        companyUID,
      );

      final totalDelegates = delegates.length;
      final absentToday = (totalDelegates - checkedInCount).clamp(
        0,
        totalDelegates,
      );

      return Right(
        DashboardSummary(
          totalDelegates: totalDelegates,
          checkedInToday: checkedInCount,
          absentToday: absentToday,
        ),
      );
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, List<AdminUser>>> getMarketingEmployees() async {
    try {
      final employees = await marketingDataSource.getMarketingEmployees();
      return Right(employees);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> updateMarketingEmployee(
    AdminUser employee,
  ) async {
    try {
      final model = AdminUserModel(
        uid: employee.uid,
        phoneNumber: employee.phoneNumber,
        email: employee.email,
        displayName: employee.displayName,
        role: employee.role,
        createdAt: employee.createdAt,
        createdBy: employee.createdBy,
        temporaryPassword: employee.temporaryPassword,
        isActive: employee.isActive,
      );
      await marketingDataSource.updateMarketingEmployee(model);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> deleteMarketingEmployee(
    String employeeId,
  ) async {
    try {
      await marketingDataSource.deleteMarketingEmployee(employeeId);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }

  @override
  Future<Either<Failure, Unit>> suspendMarketingEmployee(
    String employeeId,
    bool suspend,
  ) async {
    try {
      await marketingDataSource.suspendMarketingEmployee(employeeId, suspend);
      return const Right(unit);
    } on Failure catch (f) {
      return Left(f);
    } catch (_) {
      return const Left(ServerFailure('حدث خطأ غير متوقع.'));
    }
  }
}
