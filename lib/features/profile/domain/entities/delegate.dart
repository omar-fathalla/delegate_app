import 'package:equatable/equatable.dart';

enum DelegateGender { male, female }

enum DelegatePosition { supervisor, promoter }

enum DelegateStatus { pending, approved, suspended, rejected, active }

enum DocumentKey {
  personalPhoto,
  nationalityId,
  authorizationLetter,
  insuranceLetter,
  healthCertificate,
  paymentReceipt,
  electronicPaymentReceipt,
}

enum DocumentStatus { pending, approved, rejected, notProvided }

enum UserRole {
  delegate,
  admin,
  superAdmin,
  marketing,
  marketingPromotion,
  organizationAdmin,
  technicalSupport,
}

class Delegate extends Equatable {
  final String uid;
  final String firstName;
  final String middleName;
  final String lastName;
  final String fullName;
  final String nationalityID;
  final String motherName;
  final String city;
  final String phoneNumber;
  final DelegateGender gender;
  final DelegatePosition position;
  final DateTime birthDate;
  final String organizationUID;
  final String organizationName;
  final String companyUID;
  final String companyName;
  final DelegateStatus status;
  final String? statusReason;
  final String delegatePublicId;
  final List<String> allReceiptCodes;
  final DateTime createdAt;
  final String createdBy;
  final bool hasPendingUpdate;
  final bool isDeductedFromCompany;
  final bool isPrinted;
  final bool isProfileComplete;
  final String? latestRequestId;
  final int numberOfDocuments;
  final num paymentAmount;
  final String? receiptCode;
  final DateTime? updatedAt;
  final String? updatedBy;
  final int version;
  final List<DelegateDocument> documents;
  final UserRole role;
  final String? email;

  const Delegate({
    required this.uid,
    required this.firstName,
    required this.middleName,
    required this.lastName,
    required this.fullName,
    required this.nationalityID,
    required this.motherName,
    required this.city,
    required this.phoneNumber,
    required this.gender,
    required this.position,
    required this.birthDate,
    required this.organizationUID,
    required this.organizationName,
    required this.companyUID,
    required this.companyName,
    required this.status,
    this.statusReason,
    required this.delegatePublicId,
    required this.allReceiptCodes,
    required this.createdAt,
    required this.createdBy,
    required this.hasPendingUpdate,
    required this.isDeductedFromCompany,
    required this.isPrinted,
    required this.isProfileComplete,
    this.latestRequestId,
    required this.numberOfDocuments,
    required this.paymentAmount,
    this.receiptCode,
    this.updatedAt,
    this.updatedBy,
    required this.version,
    required this.documents,
    this.role = UserRole.delegate,
    this.email,
  });

  @override
  List<Object?> get props => [
    uid,
    firstName,
    middleName,
    lastName,
    fullName,
    nationalityID,
    motherName,
    city,
    phoneNumber,
    gender,
    position,
    birthDate,
    organizationUID,
    organizationName,
    companyUID,
    companyName,
    status,
    statusReason,
    delegatePublicId,
    allReceiptCodes,
    createdAt,
    createdBy,
    hasPendingUpdate,
    isDeductedFromCompany,
    isPrinted,
    isProfileComplete,
    latestRequestId,
    numberOfDocuments,
    paymentAmount,
    receiptCode,
    updatedAt,
    updatedBy,
    version,
    documents,
    role,
    email,
  ];
}

class DelegateDocument extends Equatable {
  final DocumentKey documentKey;
  final DocumentStatus documentStatus;
  final String documentURL;
  final String? rejectionReason;
  final DateTime? reviewedAt;
  final String? reviewedBy;
  final DateTime? uploadedAt;
  final String? receiptCode;
  final String? secondaryURL;

  const DelegateDocument({
    required this.documentKey,
    required this.documentStatus,
    required this.documentURL,
    this.rejectionReason,
    this.reviewedAt,
    this.reviewedBy,
    this.uploadedAt,
    this.receiptCode,
    this.secondaryURL,
  });

  @override
  List<Object?> get props => [
    documentKey,
    documentStatus,
    documentURL,
    rejectionReason,
    reviewedAt,
    reviewedBy,
    uploadedAt,
    receiptCode,
    secondaryURL,
  ];
}
