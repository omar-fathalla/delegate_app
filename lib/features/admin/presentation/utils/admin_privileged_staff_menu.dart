import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// «المناديب — تعديل وإيقاف» — super-admin and technical support (Mohamed 2026-11-15).
const manageDelegatesMenuValue = 'manage_delegates';
const manageDelegatesMenuTitleAr = 'المناديب — تعديل وإيقاف';

bool privilegedStaffMenuIncludesManageDelegates(UserRole role) {
  return role == UserRole.superAdmin || role == UserRole.technicalSupport;
}