import 'package:equatable/equatable.dart';

/// Firestore collection of «مكان الفرع غلط» reports (TAS-397).
const String kBranchLocationReportsCollection = 'branch_location_reports';

/// Where a report is in its life:
/// open → forwarded (company supervisor) → fixed (chain admin / global
/// staff, after editing the branch by hand), or rejected (with a reason)
/// from open or forwarded. A closed report (rejected / fixed) may be filed
/// again by the same delegate for the same branch.
enum BranchReportStatus {
  open,
  forwarded,
  rejected,
  fixed;

  static BranchReportStatus parse(Object? raw) {
    final s = raw is String ? raw.trim() : '';
    for (final v in values) {
      if (v.name == s) return v;
    }
    return BranchReportStatus.open;
  }

  bool get isClosed =>
      this == BranchReportStatus.rejected || this == BranchReportStatus.fixed;

  String get label => switch (this) {
    BranchReportStatus.open => 'مستني المشرف',
    BranchReportStatus.forwarded => 'اتحوّل للتصحيح',
    BranchReportStatus.rejected => 'اترفض',
    BranchReportStatus.fixed => 'اتصحح',
  };
}

/// One report per delegate and branch: the id is `{delegateId}_{branchId}`
/// (the rules check it), so a second report while one is open is refused.
String branchReportId(String delegateId, String branchId) =>
    '${delegateId}_$branchId';

class BranchLocationReport extends Equatable {
  final String id;
  final String delegateId;
  final String delegateName;
  final String companyUID;
  final String organizationUID;
  final String branchId;
  final String branchName;

  /// The branch's position and radius on the system when it was reported.
  final double? branchLat;
  final double? branchLng;
  final double? branchRadius;

  /// Where the delegate stood.
  final double lat;
  final double lng;
  final double? accuracy;
  final bool isMocked;
  final double? distanceMeters;
  final String note;
  final BranchReportStatus status;
  final String rejectReason;
  final String reviewedByName;
  final String fixedByName;
  final DateTime? createdAt;

  const BranchLocationReport({
    required this.id,
    required this.delegateId,
    required this.delegateName,
    required this.companyUID,
    required this.organizationUID,
    required this.branchId,
    required this.branchName,
    required this.lat,
    required this.lng,
    required this.status,
    this.branchLat,
    this.branchLng,
    this.branchRadius,
    this.accuracy,
    this.isMocked = false,
    this.distanceMeters,
    this.note = '',
    this.rejectReason = '',
    this.reviewedByName = '',
    this.fixedByName = '',
    this.createdAt,
  });

  static double? _num(Object? v) => v is num ? v.toDouble() : null;
  static String _str(Object? v) => v is String ? v.trim() : '';

  factory BranchLocationReport.fromMap(String id, Map<String, dynamic> m) {
    final created = m['createdAt'];
    DateTime? createdAt;
    if (created is DateTime) {
      createdAt = created;
    } else {
      try {
        createdAt = (created as dynamic)?.toDate() as DateTime?;
      } catch (_) {
        createdAt = null;
      }
    }
    return BranchLocationReport(
      id: id,
      delegateId: _str(m['delegateId']),
      delegateName: _str(m['delegateName']),
      companyUID: _str(m['companyUID']),
      organizationUID: _str(m['organizationUID']),
      branchId: _str(m['branchId']),
      branchName: _str(m['branchName']),
      branchLat: _num(m['branchLat']),
      branchLng: _num(m['branchLng']),
      branchRadius: _num(m['branchRadius']),
      lat: _num(m['lat']) ?? 0,
      lng: _num(m['lng']) ?? 0,
      accuracy: _num(m['accuracy']),
      isMocked: m['isMocked'] == true,
      distanceMeters: _num(m['distanceMeters']),
      note: _str(m['note']),
      status: BranchReportStatus.parse(m['status']),
      rejectReason: _str(m['rejectReason']),
      reviewedByName: _str(m['reviewedByName']),
      fixedByName: _str(m['fixedByName']),
      createdAt: createdAt,
    );
  }

  bool get hasBranchPosition =>
      branchLat != null &&
      branchLng != null &&
      !(branchLat == 0 && branchLng == 0);

  @override
  List<Object?> get props => [
    id,
    delegateId,
    companyUID,
    organizationUID,
    branchId,
    lat,
    lng,
    status,
    rejectReason,
  ];
}

/// What the delegate sends. Only the delegate's own fields (the rules
/// refuse anything else on create).
class NewBranchLocationReport {
  final String delegateId;
  final String delegateName;
  final String companyUID;
  final String organizationUID;
  final String branchId;
  final String branchName;
  final double? branchLat;
  final double? branchLng;
  final double? branchRadius;
  final double lat;
  final double lng;
  final double? accuracy;
  final bool isMocked;
  final double? distanceMeters;
  final String note;

  const NewBranchLocationReport({
    required this.delegateId,
    required this.delegateName,
    required this.companyUID,
    required this.organizationUID,
    required this.branchId,
    required this.branchName,
    required this.lat,
    required this.lng,
    this.branchLat,
    this.branchLng,
    this.branchRadius,
    this.accuracy,
    this.isMocked = false,
    this.distanceMeters,
    this.note = '',
  });

  String get id => branchReportId(delegateId, branchId);

  /// Fields written on create; `createdAt` is added by the repository.
  Map<String, dynamic> toFields() => {
    'delegateId': delegateId,
    'delegateName': delegateName,
    'companyUID': companyUID,
    'organizationUID': organizationUID,
    'branchId': branchId,
    'branchName': branchName,
    if (branchLat != null) 'branchLat': branchLat,
    if (branchLng != null) 'branchLng': branchLng,
    if (branchRadius != null) 'branchRadius': branchRadius,
    'lat': lat,
    'lng': lng,
    if (accuracy != null) 'accuracy': accuracy,
    'isMocked': isMocked,
    if (distanceMeters != null) 'distanceMeters': distanceMeters,
    if (note.trim().isNotEmpty) 'note': note.trim(),
    'status': BranchReportStatus.open.name,
  };
}
