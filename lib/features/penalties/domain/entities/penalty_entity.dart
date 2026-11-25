import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:equatable/equatable.dart';

enum ViolationCategory {
  unauthorizedPhotography,
  dataMissing,
  theft,
  protocolBreach,
  other;

  String get displayName {
    switch (this) {
      case ViolationCategory.unauthorizedPhotography:
        return 'تصوير بدون إذن رسمي';
      case ViolationCategory.dataMissing:
        return 'عدم تفعيل خصائص / بيانات ناقصة';
      case ViolationCategory.theft:
        return 'سرقة / تلفيات';
      case ViolationCategory.protocolBreach:
        return 'مخالفة تعليمات الفرع';
      case ViolationCategory.other:
        return 'أخرى';
    }
  }

  static ViolationCategory fromString(String category) {
    switch (category.toUpperCase()) {
      case 'UNAUTHORIZED_PHOTOGRAPHY':
        return ViolationCategory.unauthorizedPhotography;
      case 'DATA_MISSING':
        return ViolationCategory.dataMissing;
      case 'THEFT':
        return ViolationCategory.theft;
      case 'PROTOCOL_BREACH':
        return ViolationCategory.protocolBreach;
      default:
        return ViolationCategory.other;
    }
  }

  String toFirestoreString() {
    switch (this) {
      case ViolationCategory.unauthorizedPhotography:
        return 'UNAUTHORIZED_PHOTOGRAPHY';
      case ViolationCategory.dataMissing:
        return 'DATA_MISSING';
      case ViolationCategory.theft:
        return 'THEFT';
      case ViolationCategory.protocolBreach:
        return 'PROTOCOL_BREACH';
      case ViolationCategory.other:
        return 'OTHER';
    }
  }
}

enum PenaltyStatus {
  pendingBranchesMarketing,
  rejectedByBranchesMarketing,
  pendingGeneralManager,
  rejectedByGeneralManager,
  issued,
  acknowledged,
  deducted,
  disputed,
  cancelled;

  String get displayName {
    switch (this) {
      case PenaltyStatus.pendingBranchesMarketing:
        return 'بانتظار موافقة مدير تسويق الفروع';
      case PenaltyStatus.rejectedByBranchesMarketing:
        return 'مرفوضة من مدير تسويق الفروع';
      case PenaltyStatus.pendingGeneralManager:
        return 'بانتظار موافقة المدير العام';
      case PenaltyStatus.rejectedByGeneralManager:
        return 'مرفوضة من المدير العام';
      case PenaltyStatus.issued:
        return 'محررة وموافق عليها';
      case PenaltyStatus.acknowledged:
        return 'تم الإشعار';
      case PenaltyStatus.deducted:
        return 'تم الخصم';
      case PenaltyStatus.disputed:
        return 'قيد الاعتراض';
      case PenaltyStatus.cancelled:
        return 'ملغاة';
    }
  }

  static PenaltyStatus fromString(String status) {
    switch (status.toUpperCase()) {
      case 'PENDING_BRANCHES_MARKETING':
        return PenaltyStatus.pendingBranchesMarketing;
      case 'REJECTED_BRANCHES_MARKETING':
        return PenaltyStatus.rejectedByBranchesMarketing;
      case 'PENDING_GENERAL_MANAGER':
        return PenaltyStatus.pendingGeneralManager;
      case 'REJECTED_GENERAL_MANAGER':
        return PenaltyStatus.rejectedByGeneralManager;
      case 'ISSUED':
        return PenaltyStatus.issued;
      case 'ACKNOWLEDGED':
        return PenaltyStatus.acknowledged;
      case 'DEDUCTED':
        return PenaltyStatus.deducted;
      case 'DISPUTED':
        return PenaltyStatus.disputed;
      case 'CANCELLED':
        return PenaltyStatus.cancelled;
      default:
        return PenaltyStatus.pendingBranchesMarketing;
    }
  }

  String toFirestoreString() {
    switch (this) {
      case PenaltyStatus.pendingBranchesMarketing:
        return 'PENDING_BRANCHES_MARKETING';
      case PenaltyStatus.rejectedByBranchesMarketing:
        return 'REJECTED_BRANCHES_MARKETING';
      case PenaltyStatus.pendingGeneralManager:
        return 'PENDING_GENERAL_MANAGER';
      case PenaltyStatus.rejectedByGeneralManager:
        return 'REJECTED_GENERAL_MANAGER';
      case PenaltyStatus.issued:
        return 'ISSUED';
      case PenaltyStatus.acknowledged:
        return 'ACKNOWLEDGED';
      case PenaltyStatus.deducted:
        return 'DEDUCTED';
      case PenaltyStatus.disputed:
        return 'DISPUTED';
      case PenaltyStatus.cancelled:
        return 'CANCELLED';
    }
  }
}

class EvidenceFile extends Equatable {
  /// TAS-42: the Storage object path for new uploads, or the download URL
  /// of older documents. Display it through [StorageMediaResolver].
  final String fileUrl;
  final String fileType; // IMAGE, PDF, DOC
  final String fileName;

  /// Download URL also written as `fileUrl` next to `filePath`, for app
  /// versions that only read the URL (see [LegacyStorageUrls]).
  final String? legacyUrl;

  const EvidenceFile({
    required this.fileUrl,
    required this.fileType,
    required this.fileName,
    this.legacyUrl,
  });

  @override
  List<Object?> get props => [fileUrl, fileType, fileName];

  Map<String, dynamic> toJson() {
    if (StorageMediaRef.isStoragePath(fileUrl)) {
      final legacy = legacyUrl?.trim() ?? '';
      return {
        'filePath': fileUrl,
        if (legacy.isNotEmpty) 'fileUrl': legacy,
        'fileType': fileType,
        'fileName': fileName,
      };
    }
    return {
      'fileUrl': fileUrl,
      'fileType': fileType,
      'fileName': fileName,
    };
  }

  factory EvidenceFile.fromJson(Map<String, dynamic> json) {
    final path = json['filePath'];
    final hasPath = path is String && path.trim().isNotEmpty;
    return EvidenceFile(
      fileUrl: StorageMediaRef.pick(path: path, url: json['fileUrl']),
      fileType: json['fileType'] ?? 'IMAGE',
      fileName: json['fileName'] ?? '',
      legacyUrl: hasPath ? json['fileUrl'] as String? : null,
    );
  }
}

class PenaltyEntity extends Equatable {
  final String penaltyId;
  final String companyId;
  final String companyName;

  /// TAS-73: the company's organization, so org-admin and org-level
  /// marketing can list penalties by `organizationId`. Null on old docs.
  final String? organizationId;
  final String? branchId;
  final String? branchName;
  final String createdById;
  final String createdByName;
  final String? createdByPhone;
  final String title;
  final ViolationCategory category;
  final String incidentDescription;
  final double fineAmount;
  final String currency;
  final PenaltyStatus status;
  final List<EvidenceFile> evidenceFiles;
  final String? branchesMarketingApprovedBy;
  final DateTime? branchesMarketingApprovedAt;
  final String? generalManagerApprovedBy;
  final DateTime? generalManagerApprovedAt;
  final String? rejectionReason;
  final String? targetDelegateId;
  final String? targetDelegateName;
  final bool isRepeated;
  final bool isConfidential;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PenaltyEntity({
    required this.penaltyId,
    required this.companyId,
    required this.companyName,
    this.organizationId,
    this.branchId,
    this.branchName,
    required this.createdById,
    required this.createdByName,
    this.createdByPhone,
    required this.title,
    required this.category,
    required this.incidentDescription,
    required this.fineAmount,
    this.currency = 'EGP',
    this.status = PenaltyStatus.pendingBranchesMarketing,
    this.evidenceFiles = const [],
    this.branchesMarketingApprovedBy,
    this.branchesMarketingApprovedAt,
    this.generalManagerApprovedBy,
    this.generalManagerApprovedAt,
    this.rejectionReason,
    this.targetDelegateId,
    this.targetDelegateName,
    this.isRepeated = false,
    this.isConfidential = false,
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        penaltyId,
        companyId,
        companyName,
        organizationId,
        branchId,
        branchName,
        createdById,
        createdByName,
        createdByPhone,
        title,
        category,
        incidentDescription,
        fineAmount,
        currency,
        status,
        evidenceFiles,
        branchesMarketingApprovedBy,
        branchesMarketingApprovedAt,
        generalManagerApprovedBy,
        generalManagerApprovedAt,
        rejectionReason,
        targetDelegateId,
        targetDelegateName,
        isRepeated,
        isConfidential,
        createdAt,
        updatedAt,
      ];
}

/// Localized label for UI. [ViolationCategory.displayName] stays Arabic
/// because it is also used for search matching.
extension ViolationCategoryL10n on ViolationCategory {
  String localizedName(AppLocalizations l10n) {
    switch (this) {
      case ViolationCategory.unauthorizedPhotography:
        return l10n.catUnauthorizedPhoto;
      case ViolationCategory.dataMissing:
        return l10n.catDataMissing;
      case ViolationCategory.theft:
        return l10n.catTheftDamage;
      case ViolationCategory.protocolBreach:
        return l10n.catBranchRules;
      case ViolationCategory.other:
        return l10n.catOther;
    }
  }
}
