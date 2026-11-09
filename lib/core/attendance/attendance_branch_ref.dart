import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:equatable/equatable.dart';

/// Stable branch identity for attendance check-in/out (id + org + display name).
class AttendanceBranchRef extends Equatable {
  final String? branchId;
  final String branchOrganizationUID;
  final String branchName;

  const AttendanceBranchRef({
    this.branchId,
    required this.branchOrganizationUID,
    required this.branchName,
  });

  factory AttendanceBranchRef.fromBranch(
    Branch branch, {
    required String fallbackOrganizationUID,
  }) {
    final org = (branch.organizationUID?.trim().isNotEmpty == true)
        ? branch.organizationUID!.trim()
        : fallbackOrganizationUID;
    return AttendanceBranchRef(
      branchId: branch.id.trim().isNotEmpty ? branch.id.trim() : null,
      branchOrganizationUID: org,
      branchName: branch.branchName.trim(),
    );
  }

  factory AttendanceBranchRef.legacyNameOnly({
    required String branchName,
    required String delegateOrganizationUID,
  }) {
    return AttendanceBranchRef(
      branchId: null,
      branchOrganizationUID: delegateOrganizationUID.trim(),
      branchName: branchName.trim(),
    );
  }

  factory AttendanceBranchRef.fromQrMap(
    Map<String, dynamic> map, {
    required String delegateOrganizationUID,
  }) {
    final name = (map['branch'] as String?)?.trim() ??
        (map['branchName'] as String?)?.trim() ??
        '';
    final id = (map['branchId'] as String?)?.trim();
    final org = (map['organizationUID'] as String?)?.trim() ??
        (map['organizationId'] as String?)?.trim() ??
        delegateOrganizationUID;
    return AttendanceBranchRef(
      branchId: (id != null && id.isNotEmpty) ? id : null,
      branchOrganizationUID: org,
      branchName: name,
    );
  }

  factory AttendanceBranchRef.fromAttendanceLog(Map<String, dynamic> data) {
    final id = (data['branchId'] as String?)?.trim();
    final org = (data['branchOrganizationUID'] as String?)?.trim() ??
        (data['organizationId'] as String?)?.trim() ??
        '';
    final name = (data['branchName'] as String?)?.trim() ?? '';
    return AttendanceBranchRef(
      branchId: (id != null && id.isNotEmpty) ? id : null,
      branchOrganizationUID: org,
      branchName: name,
    );
  }

  Map<String, dynamic> toCheckInFields() {
    return {
      'branchName': branchName,
      if (branchId != null && branchId!.isNotEmpty) 'branchId': branchId,
      if (branchOrganizationUID.isNotEmpty)
        'branchOrganizationUID': branchOrganizationUID,
    };
  }

  @override
  List<Object?> get props => [branchId, branchOrganizationUID, branchName];
}

bool attendanceSameBranch(
  AttendanceBranchRef? a,
  AttendanceBranchRef? b,
) {
  if (a == null || b == null) return false;
  final aId = a.branchId;
  final bId = b.branchId;
  if (aId != null &&
      aId.isNotEmpty &&
      bId != null &&
      bId.isNotEmpty &&
      aId == bId) {
    return a.branchOrganizationUID == b.branchOrganizationUID;
  }
  return a.branchName.trim() == b.branchName.trim() &&
      a.branchOrganizationUID == b.branchOrganizationUID;
}
