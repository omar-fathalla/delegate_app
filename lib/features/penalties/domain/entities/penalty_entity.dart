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
  issued,
  acknowledged,
  deducted,
  disputed,
  cancelled;

  String get displayName {
    switch (this) {
      case PenaltyStatus.issued:
        return 'محررة';
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
        return PenaltyStatus.issued;
    }
  }

  String toFirestoreString() {
    switch (this) {
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
  final String fileUrl;
  final String fileType; // IMAGE, PDF, DOC
  final String fileName;

  const EvidenceFile({
    required this.fileUrl,
    required this.fileType,
    required this.fileName,
  });

  @override
  List<Object?> get props => [fileUrl, fileType, fileName];

  Map<String, dynamic> toJson() => {
        'fileUrl': fileUrl,
        'fileType': fileType,
        'fileName': fileName,
      };

  factory EvidenceFile.fromJson(Map<String, dynamic> json) {
    return EvidenceFile(
      fileUrl: json['fileUrl'] ?? '',
      fileType: json['fileType'] ?? 'IMAGE',
      fileName: json['fileName'] ?? '',
    );
  }
}

class PenaltyEntity extends Equatable {
  final String penaltyId;
  final String companyId;
  final String companyName;
  final String createdById;
  final String createdByName;
  final String title;
  final ViolationCategory category;
  final String incidentDescription;
  final double fineAmount;
  final String currency;
  final PenaltyStatus status;
  final List<EvidenceFile> evidenceFiles;
  final DateTime createdAt;
  final DateTime updatedAt;

  const PenaltyEntity({
    required this.penaltyId,
    required this.companyId,
    required this.companyName,
    required this.createdById,
    required this.createdByName,
    required this.title,
    required this.category,
    required this.incidentDescription,
    required this.fineAmount,
    this.currency = 'EGP',
    this.status = PenaltyStatus.issued,
    this.evidenceFiles = const [],
    required this.createdAt,
    required this.updatedAt,
  });

  @override
  List<Object?> get props => [
        penaltyId,
        companyId,
        companyName,
        createdById,
        createdByName,
        title,
        category,
        incidentDescription,
        fineAmount,
        currency,
        status,
        evidenceFiles,
        createdAt,
        updatedAt,
      ];
}
