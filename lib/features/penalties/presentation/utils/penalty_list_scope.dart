import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// TAS-73: the penalties list a staff user loads. The rules allow a
/// `penalties` list only when the query proves the tenant, so only global
/// staff (super admin, technical support) list everything. Company staff
/// list their company; org-scoped staff (no companyUID) list their
/// organization by `organizationId`.
PenaltyEvent penaltyListEventFor(
  Delegate user, {
  bool companyViewOnly = false,
}) {
  final company = user.companyUID.trim();
  final org = user.organizationUID.trim();
  final isGlobal =
      user.role == UserRole.superAdmin || user.role == UserRole.technicalSupport;
  if (isGlobal && !companyViewOnly) return const LoadAllPenaltiesEvent();
  if (company.isNotEmpty) return LoadCompanyPenaltiesEvent(company);
  if (org.isNotEmpty) return LoadCompanyPenaltiesEvent('', organizationId: org);
  return const LoadAllPenaltiesEvent();
}
