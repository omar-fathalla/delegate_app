import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

abstract class AdminRepository {
  Future<Either<Failure, List<Map<String, dynamic>>>> getOrganizations();
  Future<Either<Failure, List<Branch>>> getBranches();
  Future<Either<Failure, Branch>> addBranch(Branch branch);
  Future<Either<Failure, Branch>> updateBranch(Branch branch);
  Future<Either<Failure, Unit>> deleteBranch(String branchId);
  Future<Either<Failure, AdminUser>> createAdmin({
    required String phoneNumber,
    required String email,
    required String displayName,
    String role = 'company-admin',
    String organizationUID = '',
  });
  Future<Either<Failure, List<AdminUser>>> getAdmins();
  Future<Either<Failure, Unit>> updateAdminUser(AdminUser admin);
  Future<Either<Failure, Unit>> deleteAdminUser(String adminId);
  Future<Either<Failure, Unit>> suspendAdminUser(String adminId, bool suspend);
  Future<Either<Failure, List<Delegate>>> getCompanyDelegates(
    String organizationUID,
    String companyUID,
  );
  Future<Either<Failure, DashboardSummary>> getDashboardSummary(
    String organizationUID,
    String companyUID,
  );
  Future<Either<Failure, List<AdminUser>>> getMarketingEmployees();
  Future<Either<Failure, Unit>> updateMarketingEmployee(AdminUser employee);
  Future<Either<Failure, Unit>> deleteMarketingEmployee(String employeeId);
  Future<Either<Failure, Unit>> suspendMarketingEmployee(
    String employeeId,
    bool suspend,
  );
}

