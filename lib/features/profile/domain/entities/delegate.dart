import 'package:equatable/equatable.dart';

enum DelegateGender { male, female }

enum DelegatePosition { supervisor, promoter }

enum DelegateStatus { pending, approved, suspended, rejected }

enum DocumentKey {
  personalPhoto,
  nationalityId,
  authorizationLetter,
  insuranceLetter,
  healthCertificate,
  paymentReceipt,
}

enum DocumentStatus { pending, approved, rejected }

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
  final String companyUID;
  final DelegateStatus status;
  final List<DelegateDocument> documents;

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
    required this.companyUID,
    required this.status,
    required this.documents,
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
    companyUID,
    status,
    documents,
  ];
}

class DelegateDocument extends Equatable {
  final DocumentKey documentKey;
  final DocumentStatus documentStatus;
  final String documentURL;
  final String? rejectionReason;

  const DelegateDocument({
    required this.documentKey,
    required this.documentStatus,
    required this.documentURL,
    this.rejectionReason,
  });

  @override
  List<Object?> get props => [
    documentKey,
    documentStatus,
    documentURL,
    rejectionReason,
  ];
}
