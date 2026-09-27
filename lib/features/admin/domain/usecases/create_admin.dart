import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class CreateAdminParams {
  final String phoneNumber;
  final String email;
  final String displayName;
  final String role;
  final String organizationUID;
  final String? companyUID;
  final String? companyName;
  final String? jobTitle;

  const CreateAdminParams({
    required this.phoneNumber,
    required this.email,
    required this.displayName,
    this.role = 'company-admin',
    this.organizationUID = '',
    this.companyUID,
    this.companyName,
    this.jobTitle,
  });
}

class CreateAdmin implements UseCase<AdminUser, CreateAdminParams> {
  final AdminRepository repository;

  CreateAdmin(this.repository);

  @override
  Future<Either<Failure, AdminUser>> call(CreateAdminParams params) {
    return repository.createAdmin(
      phoneNumber: params.phoneNumber,
      email: params.email,
      displayName: params.displayName,
      role: params.role,
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      companyName: params.companyName,
      jobTitle: params.jobTitle,
    );
  }
}
