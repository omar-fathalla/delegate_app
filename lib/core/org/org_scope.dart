import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// TAS-262: helpers that keep non-global staff (everyone except super admin
/// and technical support) inside their own organization's data.

/// Super admin and technical support see every organization.
bool isGlobalStaffRole(UserRole role) =>
    role == UserRole.superAdmin || role == UserRole.technicalSupport;

/// The organization a non-global user is limited to, or null when the user
/// is global staff (no limit).
///
/// A non-global user with no organization gets an empty string, which
/// matches nothing: better an empty list than another org's data.
String? orgScopeFor(Delegate user) {
  if (isGlobalStaffRole(user.role)) return null;
  final org = user.organizationUID.trim();
  if (org.isEmpty || org == 'all') return '';
  return org;
}

/// Whether a branch document belongs to [orgUid]. Branch docs carry
/// `organizationUID` and/or the older `organizationId`.
bool branchBelongsToOrg(Map<String, dynamic> data, String orgUid) {
  if (orgUid.isEmpty) return false;
  final a = (data['organizationUID'] as Object?)?.toString().trim() ?? '';
  final b = (data['organizationId'] as Object?)?.toString().trim() ?? '';
  return a == orgUid || b == orgUid;
}
