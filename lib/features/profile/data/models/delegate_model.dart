import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/utils/date_time_utils.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class DelegateModel extends Delegate {
  const DelegateModel({
    required super.uid,
    required super.firstName,
    required super.middleName,
    required super.lastName,
    required super.fullName,
    required super.nationalityID,
    required super.motherName,
    required super.city,
    required super.phoneNumber,
    required super.gender,
    required super.position,
    required super.birthDate,
    required super.organizationUID,
    required super.organizationName,
    required super.companyUID,
    required super.companyName,
    required super.status,
    super.statusReason,
    required super.delegatePublicId,
    required super.allReceiptCodes,
    required super.createdAt,
    required super.createdBy,
    required super.hasPendingUpdate,
    required super.isDeductedFromCompany,
    required super.isPrinted,
    required super.isProfileComplete,
    super.latestRequestId,
    required super.numberOfDocuments,
    required super.paymentAmount,
    super.receiptCode,
    super.updatedAt,
    super.updatedBy,
    required super.version,
    required super.documents,
    super.role,
    super.email,
  });

  factory DelegateModel.fromJson(Map<String, dynamic> json, String uid) {
    DelegateGender parseGender(String? gender) {
      return gender == 'Female' ? DelegateGender.female : DelegateGender.male;
    }

    DelegatePosition parsePosition(String? position) {
      return position == 'Supervisor'
          ? DelegatePosition.supervisor
          : DelegatePosition.promoter;
    }

    DelegateStatus parseStatus(String? status) {
      switch (status) {
        case 'Approved':
        case 'approved':
          return DelegateStatus.approved;
        case 'Suspended':
        case 'suspended':
          return DelegateStatus.suspended;
        case 'Rejected':
        case 'rejected':
          return DelegateStatus.rejected;
        case 'Active':
        case 'active':
          return DelegateStatus.active;
        default:
          return DelegateStatus.pending;
      }
    }

    UserRole parseRole(String? role) {
      switch (role) {
        case 'super_admin':
          return UserRole.superAdmin;
        case 'organization-admin':
          return UserRole.organizationAdmin;
        case 'admin':
        case 'company-admin':
          return UserRole.admin;
        case 'marketing':
          return UserRole.marketing;
        case 'marketing_promotion':
          return UserRole.marketingPromotion;
        case 'technical_support':
          return UserRole.technicalSupport;
        case 'branches_marketing':
        case 'branches-marketing':
        case 'branches_marketing_manager':
          return UserRole.branchesMarketingManager;
        default:
          return UserRole.delegate;
      }
    }

    return DelegateModel(
      uid: uid,
      firstName: json['firstName'] ?? '',
      middleName: json['middleName'] ?? '',
      lastName: json['lastName'] ?? '',
      fullName: json['fullName'] ?? '',
      nationalityID: json['nationalityID'] ?? '',
      motherName: json['motherName'] ?? '',
      city: json['city'] ?? '',
      phoneNumber: json['phoneNumber'] ?? '',
      gender: parseGender(json['gender']),
      position: parsePosition(json['position']),
      birthDate: DateTimeUtils.parseDate(json['birthDate']),
      organizationUID: json['organizationUID'] ?? '',
      organizationName: json['organizationName'] ?? '',
      companyUID: json['companyUID'] ?? '',
      companyName: json['companyName'] ?? '',
      status: parseStatus(json['status']),
      statusReason: json['statusReason'],
      delegatePublicId: json['delegatePublicId'] ?? '',
      allReceiptCodes: (json['allReceiptCodes'] as List? ?? [])
          .map((e) => e.toString())
          .toList(),
      createdAt: DateTimeUtils.parseDate(json['createdAt']),
      createdBy: json['createdBy'] ?? '',
      hasPendingUpdate: json['hasPendingUpdate'] ?? false,
      isDeductedFromCompany: json['isDeductedFromCompany'] ?? false,
      isPrinted: json['isPrinted'] ?? false,
      isProfileComplete: json['isProfileComplete'] ?? false,
      latestRequestId: json['latestRequestId'],
      numberOfDocuments: json['numberOfDocuments'] ?? 0,
      paymentAmount: json['paymentAmount'] ?? 0,
      receiptCode: json['receiptCode'],
      updatedAt: DateTimeUtils.parseNullableDate(json['updatedAt']),
      updatedBy: json['updatedBy'],
      version: json['version'] ?? 1,
      documents: (json['documents'] as List? ?? [])
          .map(
            (doc) =>
                DelegateDocumentModel.fromJson(doc as Map<String, dynamic>),
          )
          .toList(),
      role: parseRole(json['role']),
      email: json['email'],
    );
  }

  static String roleToString(UserRole role) {
    switch (role) {
      case UserRole.superAdmin:
        return 'super_admin';
      case UserRole.organizationAdmin:
        return 'organization-admin';
      case UserRole.admin:
        return 'admin';
      case UserRole.marketing:
        return 'marketing';
      case UserRole.marketingPromotion:
        return 'marketing_promotion';
      case UserRole.technicalSupport:
        return 'technical_support';
      case UserRole.branchesMarketingManager:
        return 'branches_marketing';
      case UserRole.delegate:
        return 'delegate';
    }
  }

  Map<String, dynamic> toJson() {
    String genderToString(DelegateGender gender) {
      return gender == DelegateGender.female ? 'Female' : 'Male';
    }

    String positionToString(DelegatePosition position) {
      return position == DelegatePosition.supervisor
          ? 'Supervisor'
          : 'Promoter';
    }

    String statusToString(DelegateStatus status) {
      switch (status) {
        case DelegateStatus.approved:
          return 'approved';
        case DelegateStatus.suspended:
          return 'suspended';
        case DelegateStatus.rejected:
          return 'rejected';
        case DelegateStatus.pending:
          return 'pending';
        case DelegateStatus.active:
          return 'active';
      }
    }

    return {
      'uid': uid,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName,
      'nationalityID': nationalityID,
      'motherName': motherName,
      'city': city,
      'phoneNumber': phoneNumber,
      'gender': genderToString(gender),
      'position': positionToString(position),
      'birthDate': Timestamp.fromDate(birthDate),
      'organizationUID': organizationUID,
      'organizationName': organizationName,
      'companyUID': companyUID,
      'companyName': companyName,
      'status': statusToString(status),
      'statusReason': statusReason,
      'delegatePublicId': delegatePublicId,
      'allReceiptCodes': allReceiptCodes,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
      'hasPendingUpdate': hasPendingUpdate,
      'isDeductedFromCompany': isDeductedFromCompany,
      'isPrinted': isPrinted,
      'isProfileComplete': isProfileComplete,
      'latestRequestId': latestRequestId,
      'numberOfDocuments': numberOfDocuments,
      'paymentAmount': paymentAmount,
      'receiptCode': receiptCode,
      'updatedAt': updatedAt != null ? Timestamp.fromDate(updatedAt!) : null,
      'updatedBy': updatedBy,
      'version': version,
      'documents': documents
          .map((doc) => (doc as DelegateDocumentModel).toJson())
          .toList(),
      'role': roleToString(role),
      'email': email,
    };
  }

  /// JSON for local caching (uses ISO strings instead of Firestore Timestamps)
  Map<String, dynamic> toLocalJson() {
    String genderToString(DelegateGender gender) {
      return gender == DelegateGender.female ? 'Female' : 'Male';
    }

    String positionToString(DelegatePosition position) {
      return position == DelegatePosition.supervisor
          ? 'Supervisor'
          : 'Promoter';
    }

    String statusToString(DelegateStatus status) {
      switch (status) {
        case DelegateStatus.approved:
          return 'approved';
        case DelegateStatus.suspended:
          return 'suspended';
        case DelegateStatus.rejected:
          return 'rejected';
        case DelegateStatus.pending:
          return 'pending';
        case DelegateStatus.active:
          return 'active';
      }
    }

    return {
      'uid': uid,
      'firstName': firstName,
      'middleName': middleName,
      'lastName': lastName,
      'fullName': fullName,
      'nationalityID': nationalityID,
      'motherName': motherName,
      'city': city,
      'phoneNumber': phoneNumber,
      'gender': genderToString(gender),
      'position': positionToString(position),
      'birthDate': birthDate.toIso8601String(),
      'organizationUID': organizationUID,
      'organizationName': organizationName,
      'companyUID': companyUID,
      'companyName': companyName,
      'status': statusToString(status),
      'statusReason': statusReason,
      'delegatePublicId': delegatePublicId,
      'allReceiptCodes': allReceiptCodes,
      'createdAt': createdAt.toIso8601String(),
      'createdBy': createdBy,
      'hasPendingUpdate': hasPendingUpdate,
      'isDeductedFromCompany': isDeductedFromCompany,
      'isPrinted': isPrinted,
      'isProfileComplete': isProfileComplete,
      'latestRequestId': latestRequestId,
      'numberOfDocuments': numberOfDocuments,
      'paymentAmount': paymentAmount,
      'receiptCode': receiptCode,
      'updatedAt': updatedAt?.toIso8601String(),
      'updatedBy': updatedBy,
      'version': version,
      'documents': documents
          .map((doc) => (doc as DelegateDocumentModel).toLocalJson())
          .toList(),
      'role': roleToString(role),
      'email': email,
    };
  }
}

class DelegateDocumentModel extends DelegateDocument {
  const DelegateDocumentModel({
    required super.documentKey,
    required super.documentStatus,
    required super.documentURL,
    super.rejectionReason,
    super.reviewedAt,
    super.reviewedBy,
    super.uploadedAt,
    super.receiptCode,
    super.secondaryURL,
  });

  factory DelegateDocumentModel.fromJson(Map<String, dynamic> json) {
    DocumentKey parseKey(String? key) {
      switch (key) {
        case 'personalPhoto':
          return DocumentKey.personalPhoto;
        case 'nationalityId':
          return DocumentKey.nationalityId;
        case 'authorizationLetter':
          return DocumentKey.authorizationLetter;
        case 'insuranceLetter':
          return DocumentKey.insuranceLetter;
        case 'healthCertificate':
          return DocumentKey.healthCertificate;
        case 'paymentReceipt':
          return DocumentKey.paymentReceipt;
        case 'electronicPaymentReceipt':
        case 'electronic_payment_receipt':
          return DocumentKey.electronicPaymentReceipt;
        default:
          return DocumentKey.personalPhoto;
      }
    }

    DocumentStatus parseStatus(String? status) {
      switch (status) {
        case 'Approved':
        case 'approved':
          return DocumentStatus.approved;
        case 'Rejected':
        case 'rejected':
          return DocumentStatus.rejected;
        case 'not_provided':
          return DocumentStatus.notProvided;
        default:
          return DocumentStatus.pending;
      }
    }

    return DelegateDocumentModel(
      documentKey: parseKey(json['documentKey']),
      documentStatus: parseStatus(json['documentStatus']),
      documentURL: json['documentURL'] ?? '',
      rejectionReason: json['rejectionReason'],
      reviewedAt: DateTimeUtils.parseNullableDate(json['reviewedAt']),
      reviewedBy: json['reviewedBy'],
      uploadedAt: DateTimeUtils.parseNullableDate(json['uploadedAt']),
      receiptCode: json['receiptCode'],
      secondaryURL: json['secondaryURL'],
    );
  }

  Map<String, dynamic> toJson() {
    String keyToString(DocumentKey key) {
      switch (key) {
        case DocumentKey.personalPhoto:
          return 'personalPhoto';
        case DocumentKey.nationalityId:
          return 'nationalityId';
        case DocumentKey.authorizationLetter:
          return 'authorizationLetter';
        case DocumentKey.insuranceLetter:
          return 'insuranceLetter';
        case DocumentKey.healthCertificate:
          return 'healthCertificate';
        case DocumentKey.paymentReceipt:
          return 'paymentReceipt';
        case DocumentKey.electronicPaymentReceipt:
          return 'electronicPaymentReceipt';
      }
    }

    String statusToString(DocumentStatus status) {
      switch (status) {
        case DocumentStatus.approved:
          return 'approved';
        case DocumentStatus.rejected:
          return 'rejected';
        case DocumentStatus.pending:
          return 'pending';
        case DocumentStatus.notProvided:
          return 'not_provided';
      }
    }

    return {
      'documentKey': keyToString(documentKey),
      'documentStatus': statusToString(documentStatus),
      'documentURL': documentURL,
      'rejectionReason': rejectionReason,
      'reviewedAt': reviewedAt != null ? Timestamp.fromDate(reviewedAt!) : null,
      'reviewedBy': reviewedBy,
      'uploadedAt': uploadedAt != null ? Timestamp.fromDate(uploadedAt!) : null,
      'receiptCode': receiptCode,
      'secondaryURL': secondaryURL,
    };
  }

  /// JSON for local caching (uses ISO strings instead of Firestore Timestamps)
  Map<String, dynamic> toLocalJson() {
    String keyToString(DocumentKey key) {
      switch (key) {
        case DocumentKey.personalPhoto:
          return 'personalPhoto';
        case DocumentKey.nationalityId:
          return 'nationalityId';
        case DocumentKey.authorizationLetter:
          return 'authorizationLetter';
        case DocumentKey.insuranceLetter:
          return 'insuranceLetter';
        case DocumentKey.healthCertificate:
          return 'healthCertificate';
        case DocumentKey.paymentReceipt:
          return 'paymentReceipt';
        case DocumentKey.electronicPaymentReceipt:
          return 'electronicPaymentReceipt';
      }
    }

    String statusToString(DocumentStatus status) {
      switch (status) {
        case DocumentStatus.approved:
          return 'approved';
        case DocumentStatus.rejected:
          return 'rejected';
        case DocumentStatus.pending:
          return 'pending';
        case DocumentStatus.notProvided:
          return 'not_provided';
      }
    }

    return {
      'documentKey': keyToString(documentKey),
      'documentStatus': statusToString(documentStatus),
      'documentURL': documentURL,
      'rejectionReason': rejectionReason,
      'reviewedAt': reviewedAt?.toIso8601String(),
      'reviewedBy': reviewedBy,
      'uploadedAt': uploadedAt?.toIso8601String(),
      'receiptCode': receiptCode,
      'secondaryURL': secondaryURL,
    };
  }
}
