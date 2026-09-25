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
    super.boundDeviceId,
    super.boundDeviceModel,
    super.deviceBoundAt,
    super.isDeviceLocked = false,
    super.supervisorName,
    super.supervisorPhone,
    super.supervisorUid,
    super.allOrganizationNames = const [],
  });

  DelegateModel copyWith({
    String? uid,
    String? firstName,
    String? middleName,
    String? lastName,
    String? fullName,
    String? nationalityID,
    String? motherName,
    String? city,
    String? phoneNumber,
    DelegateGender? gender,
    DelegatePosition? position,
    DateTime? birthDate,
    String? organizationUID,
    String? organizationName,
    String? companyUID,
    String? companyName,
    DelegateStatus? status,
    String? statusReason,
    String? delegatePublicId,
    List<String>? allReceiptCodes,
    DateTime? createdAt,
    String? createdBy,
    bool? hasPendingUpdate,
    bool? isDeductedFromCompany,
    bool? isPrinted,
    bool? isProfileComplete,
    String? latestRequestId,
    int? numberOfDocuments,
    double? paymentAmount,
    String? receiptCode,
    DateTime? updatedAt,
    String? updatedBy,
    int? version,
    List<DelegateDocument>? documents,
    UserRole? role,
    String? email,
    String? boundDeviceId,
    String? boundDeviceModel,
    DateTime? deviceBoundAt,
    bool? isDeviceLocked,
    String? supervisorName,
    String? supervisorPhone,
    String? supervisorUid,
    List<String>? allOrganizationNames,
  }) {
    return DelegateModel(
      uid: uid ?? this.uid,
      firstName: firstName ?? this.firstName,
      middleName: middleName ?? this.middleName,
      lastName: lastName ?? this.lastName,
      fullName: fullName ?? this.fullName,
      nationalityID: nationalityID ?? this.nationalityID,
      motherName: motherName ?? this.motherName,
      city: city ?? this.city,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      gender: gender ?? this.gender,
      position: position ?? this.position,
      birthDate: birthDate ?? this.birthDate,
      organizationUID: organizationUID ?? this.organizationUID,
      organizationName: organizationName ?? this.organizationName,
      companyUID: companyUID ?? this.companyUID,
      companyName: companyName ?? this.companyName,
      status: status ?? this.status,
      statusReason: statusReason ?? this.statusReason,
      delegatePublicId: delegatePublicId ?? this.delegatePublicId,
      allReceiptCodes: allReceiptCodes ?? this.allReceiptCodes,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      hasPendingUpdate: hasPendingUpdate ?? this.hasPendingUpdate,
      isDeductedFromCompany: isDeductedFromCompany ?? this.isDeductedFromCompany,
      isPrinted: isPrinted ?? this.isPrinted,
      isProfileComplete: isProfileComplete ?? this.isProfileComplete,
      latestRequestId: latestRequestId ?? this.latestRequestId,
      numberOfDocuments: numberOfDocuments ?? this.numberOfDocuments,
      paymentAmount: paymentAmount ?? this.paymentAmount,
      receiptCode: receiptCode ?? this.receiptCode,
      updatedAt: updatedAt ?? this.updatedAt,
      updatedBy: updatedBy ?? this.updatedBy,
      version: version ?? this.version,
      documents: documents ?? this.documents,
      role: role ?? this.role,
      email: email ?? this.email,
      boundDeviceId: boundDeviceId ?? this.boundDeviceId,
      boundDeviceModel: boundDeviceModel ?? this.boundDeviceModel,
      deviceBoundAt: deviceBoundAt ?? this.deviceBoundAt,
      isDeviceLocked: isDeviceLocked ?? this.isDeviceLocked,
      supervisorName: supervisorName ?? this.supervisorName,
      supervisorPhone: supervisorPhone ?? this.supervisorPhone,
      supervisorUid: supervisorUid ?? this.supervisorUid,
      allOrganizationNames: allOrganizationNames ?? this.allOrganizationNames,
    );
  }

  factory DelegateModel.fromJson(Map<String, dynamic> json, String uid) {
    DelegateGender parseGender(String? gender) {
      return gender == 'Female' ? DelegateGender.female : DelegateGender.male;
    }

    DelegatePosition parsePosition(String? position) {
      final p = position?.trim().toLowerCase();
      return (p == 'supervisor' || p == 'مشرف')
          ? DelegatePosition.supervisor
          : DelegatePosition.promoter;
    }

    DelegateStatus parseStatus(String? status) {
      switch (status?.trim().toLowerCase()) {
        case 'approved':
          return DelegateStatus.approved;
        case 'suspended':
          return DelegateStatus.suspended;
        case 'rejected':
          return DelegateStatus.rejected;
        case 'active':
          return DelegateStatus.active;
        default:
          return DelegateStatus.pending;
      }
    }

    UserRole parseRole(String? role) {
      switch (role?.trim().toLowerCase()) {
        case 'super_admin':
        case 'superadmin':
          return UserRole.superAdmin;
        case 'organization-admin':
        case 'organization_admin':
        case 'organizationadmin':
          return UserRole.organizationAdmin;
        case 'admin':
        case 'company-admin':
        case 'company_admin':
        case 'companyadmin':
        case 'supervisor':
        case 'company_supervisor':
          return UserRole.admin;
        case 'marketing':
          return UserRole.marketing;
        case 'marketing_promotion':
        case 'marketingpromotion':
          return UserRole.marketingPromotion;
        case 'technical_support':
        case 'technical-support':
        case 'tech_support':
        case 'techsupport':
        case 'technicalsupport':
          return UserRole.technicalSupport;
        case 'branches_marketing':
        case 'branches-marketing':
        case 'branches_marketing_manager':
        case 'branchesmarketingmanager':
          return UserRole.branchesMarketingManager;
        case 'accountant':
        case 'accounting':
        case 'account_admin':
          return UserRole.accountant;
        default:
          return UserRole.delegate;
      }
    }

    final rawFullName = (json['fullName'] as String?)?.trim();
    final first = (json['firstName'] as String?)?.trim() ?? '';
    final middle = (json['middleName'] as String?)?.trim() ?? '';
    final last = (json['lastName'] as String?)?.trim() ?? '';
    final combined = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
    final altName = (json['name'] as String?)?.trim();
    final effectiveFullName = (rawFullName != null && rawFullName.isNotEmpty)
        ? rawFullName
        : (combined.isNotEmpty
            ? combined
            : (altName != null && altName.isNotEmpty ? altName : ''));

    final rawCompanyName = (json['companyName'] as String?)?.trim();
    final altCompanyName = (json['company_name'] as String?)?.trim();
    final effectiveCompanyName = (rawCompanyName != null && rawCompanyName.isNotEmpty)
        ? rawCompanyName
        : (altCompanyName ?? '');

    return DelegateModel(
      uid: uid,
      firstName: first,
      middleName: middle,
      lastName: last,
      fullName: effectiveFullName,
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
      companyName: effectiveCompanyName,
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
      documents: () {
        final List<DelegateDocumentModel> parsedDocs =
            (json['documents'] as List? ?? [])
                .map(
                  (doc) => DelegateDocumentModel.fromJson(
                    doc as Map<String, dynamic>,
                  ),
                )
                .toList();

        final bool hasPersonalPhoto = parsedDocs.any(
          (d) =>
              d.documentKey == DocumentKey.personalPhoto &&
              d.documentURL.isNotEmpty,
        );
        if (!hasPersonalPhoto) {
          final photoUrl = json['profileImageUrl'] ??
              json['profileImage'] ??
              json['personalPhotoURL'] ??
              json['personalPhotoUrl'] ??
              json['photoURL'] ??
              json['photoUrl'] ??
              json['avatarUrl'];
          if (photoUrl is String && photoUrl.trim().isNotEmpty) {
            parsedDocs.add(
              DelegateDocumentModel(
                documentKey: DocumentKey.personalPhoto,
                documentStatus: DocumentStatus.approved,
                documentURL: photoUrl.trim(),
                uploadedAt:
                    DateTimeUtils.parseNullableDate(json['createdAt']) ??
                        DateTime.now(),
              ),
            );
          }
        }

        final bool hasNationalId = parsedDocs.any(
          (d) =>
              d.documentKey == DocumentKey.nationalityId &&
              d.documentURL.isNotEmpty,
        );
        if (!hasNationalId) {
          final frontUrl = json['nationalIdFrontUrl'] ??
              json['nationalIdFrontURL'] ??
              json['nationalIdUrl'];
          final backUrl =
              json['nationalIdBackUrl'] ?? json['nationalIdBackURL'];
          if (frontUrl is String && frontUrl.trim().isNotEmpty) {
            parsedDocs.add(
              DelegateDocumentModel(
                documentKey: DocumentKey.nationalityId,
                documentStatus: DocumentStatus.approved,
                documentURL: frontUrl.trim(),
                secondaryURL: backUrl is String && backUrl.trim().isNotEmpty
                    ? backUrl.trim()
                    : null,
                uploadedAt:
                    DateTimeUtils.parseNullableDate(json['createdAt']) ??
                        DateTime.now(),
              ),
            );
          }
        }

        final bool hasReceipt = parsedDocs.any(
          (d) =>
              d.documentKey == DocumentKey.paymentReceipt &&
              d.documentURL.isNotEmpty,
        );
        if (!hasReceipt) {
          final receiptUrl = json['receiptImageUrl'] ?? json['receiptUrl'];
          if (receiptUrl is String && receiptUrl.trim().isNotEmpty) {
            parsedDocs.add(
              DelegateDocumentModel(
                documentKey: DocumentKey.paymentReceipt,
                documentStatus: DocumentStatus.approved,
                documentURL: receiptUrl.trim(),
                receiptCode: json['receiptCode']?.toString(),
                uploadedAt:
                    DateTimeUtils.parseNullableDate(json['createdAt']) ??
                        DateTime.now(),
              ),
            );
          }
        }

        return parsedDocs;
      }(),
      role: parseRole(json['role']),
      email: json['email'],
      boundDeviceId: json['boundDeviceId'],
      boundDeviceModel: json['boundDeviceModel'],
      deviceBoundAt: DateTimeUtils.parseNullableDate(json['deviceBoundAt']),
      isDeviceLocked: json['isDeviceLocked'] ?? false,
      supervisorName: (json['supervisorName'] as String?)?.trim() ?? (json['supervisor_name'] as String?)?.trim(),
      supervisorPhone: (json['supervisorPhone'] as String?)?.trim() ?? (json['supervisor_phone'] as String?)?.trim(),
      supervisorUid: (json['supervisorUid'] as String?)?.trim() ?? (json['supervisor_uid'] as String?)?.trim(),
      allOrganizationNames: (json['allOrganizationNames'] is List)
          ? (json['allOrganizationNames'] as List)
              .map((e) => e.toString())
              .toList()
          : const <String>[],
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
      case UserRole.accountant:
        return 'accountant';
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
      'boundDeviceId': boundDeviceId,
      'boundDeviceModel': boundDeviceModel,
      'deviceBoundAt': deviceBoundAt != null ? Timestamp.fromDate(deviceBoundAt!) : null,
      'isDeviceLocked': isDeviceLocked,
      if (supervisorName != null) 'supervisorName': supervisorName,
      if (supervisorPhone != null) 'supervisorPhone': supervisorPhone,
      if (supervisorUid != null) 'supervisorUid': supervisorUid,
      if (allOrganizationNames.isNotEmpty)
        'allOrganizationNames': allOrganizationNames,
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
      'boundDeviceId': boundDeviceId,
      'boundDeviceModel': boundDeviceModel,
      'deviceBoundAt': deviceBoundAt?.toIso8601String(),
      'isDeviceLocked': isDeviceLocked,
      if (supervisorName != null) 'supervisorName': supervisorName,
      if (supervisorPhone != null) 'supervisorPhone': supervisorPhone,
      if (supervisorUid != null) 'supervisorUid': supervisorUid,
      if (allOrganizationNames.isNotEmpty)
        'allOrganizationNames': allOrganizationNames,
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
