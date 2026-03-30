import 'package:equatable/equatable.dart';

class AdminUser extends Equatable {
  final String uid;
  final String phoneNumber;
  final String email;
  final String displayName;
  final String role;
  final String? organizationUID;
  final String? companyUID;
  final DateTime createdAt;
  final String createdBy;
  final String temporaryPassword;
  final bool isActive;

  const AdminUser({
    required this.uid,
    required this.phoneNumber,
    required this.email,
    required this.displayName,
    required this.role,
    this.organizationUID,
    this.companyUID,
    required this.createdAt,
    required this.createdBy,
    required this.temporaryPassword,
    this.isActive = true,
  });

  @override
  List<Object?> get props => [
    uid,
    phoneNumber,
    email,
    displayName,
    role,
    organizationUID,
    companyUID,
    createdAt,
    createdBy,
    temporaryPassword,
    isActive,
  ];
}
