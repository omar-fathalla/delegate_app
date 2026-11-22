import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class GetMarketingEmployees
    implements UseCase<List<AdminUser>, MarketingEmployeesScope> {
  final AdminRepository repository;

  GetMarketingEmployees(this.repository);

  @override
  Future<Either<Failure, List<AdminUser>>> call(MarketingEmployeesScope params) {
    return repository.getMarketingEmployees(
      companyUID: params.companyUID,
      organizationUID: params.organizationUID,
    );
  }
}

/// TAS-73: whose users the marketing-management screen lists. Empty for
/// global staff; otherwise the caller's company, or its organization.
class MarketingEmployeesScope extends Equatable {
  final String companyUID;
  final String organizationUID;

  const MarketingEmployeesScope({
    this.companyUID = '',
    this.organizationUID = '',
  });

  /// Global staff (super admin, technical support) list everyone.
  factory MarketingEmployeesScope.forUser({
    required bool isGlobalStaff,
    required String companyUID,
    required String organizationUID,
  }) {
    if (isGlobalStaff) return const MarketingEmployeesScope();
    return MarketingEmployeesScope(
      companyUID: companyUID.trim(),
      organizationUID: organizationUID.trim(),
    );
  }

  @override
  List<Object?> get props => [companyUID, organizationUID];
}
