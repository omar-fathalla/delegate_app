import 'package:equatable/equatable.dart';

/// Entity representing granular user permissions for the Private Label system.
///
/// Contains permissions for:
/// - [canCapture]: Daily field documentation (photo capture of products & shelf price tags).
/// - [canViewReports]: Private Label performance reports & rankings.
/// - [canReviewAudit]: Audit review, verification, and price discrepancy triage.
class PrivateLabelPermissions extends Equatable {
  final String userId;
  final String userName;
  final String phoneNumber;
  final String userRole;
  final String organizationUID;
  final String organizationName;
  final String companyUID;
  final String companyName;

  /// 1. صلاحية التوثيق الميداني اليومي وتصوير المنتجات وبطاقات الأسعار
  final bool canCapture;

  /// 2. صلاحية شاشة تقارير البرايفت ليبل ومؤشرات الأداء الشهرية
  final bool canViewReports;

  /// 3. صلاحية شاشة تدقيق واعتماد توثيقات البرايفت ليبل
  final bool canReviewAudit;

  final DateTime? updatedAt;
  final String? updatedBy;
  final String? updatedByName;

  const PrivateLabelPermissions({
    required this.userId,
    this.userName = '',
    this.phoneNumber = '',
    this.userRole = '',
    this.organizationUID = '',
    this.organizationName = '',
    this.companyUID = '',
    this.companyName = '',
    this.canCapture = false,
    this.canViewReports = false,
    this.canReviewAudit = false,
    this.updatedAt,
    this.updatedBy,
    this.updatedByName,
  });

  /// Factory creating default revoked permissions for a user.
  factory PrivateLabelPermissions.empty(String userId) {
    return PrivateLabelPermissions(userId: userId);
  }

  /// Whether the user has any of the 3 Private Label permissions enabled.
  bool get hasAnyPermission => canCapture || canViewReports || canReviewAudit;

  PrivateLabelPermissions copyWith({
    String? userId,
    String? userName,
    String? phoneNumber,
    String? userRole,
    String? organizationUID,
    String? organizationName,
    String? companyUID,
    String? companyName,
    bool? canCapture,
    bool? canViewReports,
    bool? canReviewAudit,
    DateTime? updatedAt,
    String? updatedBy,
    String? updatedByName,
  }) {
    return PrivateLabelPermissions(
      userId: userId ?? this.userId,
      userName: userName ?? this.userName,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      userRole: userRole ?? this.userRole,
      organizationUID: organizationUID ?? this.organizationUID,
      organizationName: organizationName ?? this.organizationName,
      companyUID: companyUID ?? this.companyUID,
      companyName: companyName ?? this.companyName,
      canCapture: canCapture ?? this.canCapture,
      canViewReports: canViewReports ?? this.canViewReports,
      canReviewAudit: canReviewAudit ?? this.canReviewAudit,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      updatedByName: updatedByName ?? this.updatedByName,
    );
  }

  @override
  List<Object?> get props => [
    userId,
    userName,
    phoneNumber,
    userRole,
    organizationUID,
    organizationName,
    companyUID,
    companyName,
    canCapture,
    canViewReports,
    canReviewAudit,
    updatedAt,
    updatedBy,
    updatedByName,
  ];
}
