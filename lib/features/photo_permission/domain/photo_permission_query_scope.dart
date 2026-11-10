
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// How the photo-permissions list should be constrained for the signed-in user.
/// Super-admin / technical support may list everything. Marketing and
/// org-admin are scoped to their organization (and company, when set).
class PhotoPermissionQueryScope {
  final String organizationUID;
  final String companyUID;
  final bool isGlobalStaff;

  const PhotoPermissionQueryScope({
    required this.organizationUID,
    required this.companyUID,
    required this.isGlobalStaff,
  });

  bool get hasFilter => organizationUID.isNotEmpty || companyUID.isNotEmpty;

  /// An unscoped, non-global user would hit a permission-denied
  /// collection-group list and spin forever. Do not query in that case.
  bool get shouldQuery => isGlobalStaff || hasFilter;

  factory PhotoPermissionQueryScope.forRole({
    required UserRole role,
    required String organizationUID,
    required String companyUID,
  }) {
    final isGlobal =
        role == UserRole.superAdmin || role == UserRole.technicalSupport;
    if (isGlobal) {
      return const PhotoPermissionQueryScope(
        organizationUID: '',
        companyUID: '',
        isGlobalStaff: true,
      );
    }
    return PhotoPermissionQueryScope(
      organizationUID: organizationUID,
      companyUID: companyUID,
      isGlobalStaff: false,
    );
  }
}
