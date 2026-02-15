import 'package:cloud_firestore/cloud_firestore.dart';
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
    required super.companyUID,
    required super.status,
    required super.documents,
  });

  factory DelegateModel.fromJson(Map<String, dynamic> json, String uid) {
    DateTime parseDate(dynamic date) {
      if (date is Timestamp) return date.toDate();
      if (date is String) return DateTime.parse(date);
      return DateTime.now();
    }

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
          return DelegateStatus.approved;
        case 'Suspended':
          return DelegateStatus.suspended;
        case 'Rejected':
          return DelegateStatus.rejected;
        default:
          return DelegateStatus.pending;
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
      birthDate: parseDate(json['birthDate']),
      organizationUID: json['organizationUID'] ?? '',
      companyUID: json['companyUID'] ?? '',
      status: parseStatus(json['status']),
      documents: (json['documents'] as List? ?? [])
          .map(
            (doc) =>
                DelegateDocumentModel.fromJson(doc as Map<String, dynamic>),
          )
          .toList(),
    );
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
          return 'Approved';
        case DelegateStatus.suspended:
          return 'Suspended';
        case DelegateStatus.rejected:
          return 'Rejected';
        case DelegateStatus.pending:
          return 'Pending';
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
      'companyUID': companyUID,
      'status': statusToString(status),
      'documents': documents
          .map((doc) => (doc as DelegateDocumentModel).toJson())
          .toList(),
    };
  }
}

class DelegateDocumentModel extends DelegateDocument {
  const DelegateDocumentModel({
    required super.documentKey,
    required super.documentStatus,
    required super.documentURL,
    super.rejectionReason,
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
        default:
          return DocumentKey.personalPhoto;
      }
    }

    DocumentStatus parseStatus(String? status) {
      switch (status) {
        case 'Approved':
          return DocumentStatus.approved;
        case 'Rejected':
          return DocumentStatus.rejected;
        default:
          return DocumentStatus.pending;
      }
    }

    return DelegateDocumentModel(
      documentKey: parseKey(json['documentKey']),
      documentStatus: parseStatus(json['documentStatus']),
      documentURL: json['documentURL'] ?? '',
      rejectionReason: json['rejectionReason'],
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
      }
    }

    String statusToString(DocumentStatus status) {
      switch (status) {
        case DocumentStatus.approved:
          return 'Approved';
        case DocumentStatus.rejected:
          return 'Rejected';
        case DocumentStatus.pending:
          return 'Pending';
      }
    }

    return {
      'documentKey': keyToString(documentKey),
      'documentStatus': statusToString(documentStatus),
      'documentURL': documentURL,
      'rejectionReason': rejectionReason,
    };
  }
}
