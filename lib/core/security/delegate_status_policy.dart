/// Firestore-aligned guards for delegate status changes (Mohamed 2026-11-15).
library;

import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Company supervisor ([UserRole.admin] without company-admin approver path)
/// replaces an active delegate's document through the server callable
/// `supervisorReuploadDelegateDocument`. Since TAS-373 only an ID card sends
/// the delegate back to review ([supervisorReuploadSendsDelegateToReview]).
bool shouldSupervisorMarkDelegatePendingOnDocReplace({
  required Delegate target,
  required UserRole? viewerRole,
  required String viewerUid,
  required String? viewerCompanyUID,
  required bool viewerIsDocApprover,
}) {
  if (target.status != DelegateStatus.active) return false;
  if (viewerUid == target.uid) return false;
  if (viewerRole != UserRole.admin) return false;
  if (viewerIsDocApprover) return false;
  final company = (viewerCompanyUID ?? '').trim();
  return company.isNotEmpty && company == target.companyUID;
}

/// TAS-373 (user decision 2026-11-27): a new ID card (front or back) sends
/// the delegate back to `pending` until an admin approves it; a new personal
/// photo or payment receipt keeps the delegate `active`.
bool supervisorReuploadSendsDelegateToReview(String docType) =>
    docType == 'nationalIdFront' || docType == 'nationalIdBack';

/// Only global roles may change status away from suspended (rules mirror).
bool canClientLiftSuspendedDelegateStatus(UserRole? role) {
  return role == UserRole.superAdmin || role == UserRole.technicalSupport;
}

/// Mirrors delegate hold pill visibility in admin delegates list.
bool delegateHoldShowsReactivate({
  required bool canSetHold,
  required bool delegateSuspended,
  required UserRole? viewerRole,
}) {
  return canSetHold &&
      (!delegateSuspended || canClientLiftSuspendedDelegateStatus(viewerRole));
}

bool _isSupervisorFirestoreRole(String role) {
  final norm =
      role.trim().toLowerCase().replaceAll('-', '_').replaceAll(' ', '_');
  return norm == 'supervisor' || norm == 'company_supervisor';
}

/// Unpaid [new_delegate] cancel: createdBy, supervisor, or global staff.
bool canCancelUnpaidNewDelegateRequest({
  required String requestType,
  required String? paymentStatus,
  required String callerUid,
  required String? createdBy,
  required String? supervisorUid,
  required String? callerFirestoreRole,
  required String? callerCompanyUID,
  required String? requestCompanyUID,
  UserRole? callerMappedRole,
}) {
  if (requestType != 'new_delegate') return true;
  if ((paymentStatus ?? '').trim().toLowerCase() == 'paid') return false;
  if (callerMappedRole == UserRole.superAdmin ||
      callerMappedRole == UserRole.technicalSupport) {
    return true;
  }
  if (callerUid == (createdBy ?? '').trim()) return true;
  if (callerUid == (supervisorUid ?? '').trim()) return true;
  final role = callerFirestoreRole ?? '';
  if (!_isSupervisorFirestoreRole(role)) return false;
  final co = (callerCompanyUID ?? '').trim();
  final reqCo = (requestCompanyUID ?? '').trim();
  return co.isNotEmpty && co == reqCo;
}