import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:equatable/equatable.dart';

/// Stable branch identity for attendance check-in/out (id + org + display name).
class AttendanceBranchRef extends Equatable {
  final String? branchId;
  final String branchOrganizationUID;
  final String branchName;

  /// TAS-372: what the scanned QR proves, sent to `delegateCheckIn` as `qr`:
  /// the signed fields of a new QR, or `{legacy: true}` for an old one.
  /// Null when the branch did not come from a QR (geofence mode). Not part of
  /// the branch identity (not in [props]).
  final Map<String, dynamic>? qrProof;

  const AttendanceBranchRef({
    this.branchId,
    required this.branchOrganizationUID,
    required this.branchName,
    this.qrProof,
  });

  /// The same branch with the scanned QR's proof attached.
  AttendanceBranchRef withQrProof(Map<String, dynamic>? proof) =>
      AttendanceBranchRef(
        branchId: branchId,
        branchOrganizationUID: branchOrganizationUID,
        branchName: branchName,
        qrProof: proof,
      );

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

/// TAS-372: the proof of a scanned attendance QR map. A server-signed QR
/// (`sig` + `qrVersion`) sends its signed fields; any other QR (old JSON or a
/// plain branch name, pass null) is `{legacy: true}`.
Map<String, dynamic> attendanceQrProof(Map<String, dynamic>? qr) {
  final sig = qr?['sig'];
  final version = qr?['qrVersion'];
  if (qr == null || sig is! String || sig.trim().isEmpty || version is! int) {
    return const {'legacy': true};
  }
  return {
    'v': qr['v'],
    'branchId': (qr['branchId'] as String?)?.trim() ?? '',
    'organizationUID': (qr['organizationUID'] as String?)?.trim() ?? '',
    'qrVersion': version,
    'sig': sig.trim(),
  };
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
