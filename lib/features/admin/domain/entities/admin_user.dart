import 'package:equatable/equatable.dart';

class AdminUser extends Equatable {
  final String uid;
  final String phoneNumber;
  final String email;
  final String displayName;
  final String role;
  final String? organizationUID;
  final String? organizationName;
  final String? companyUID;
  final String? companyName;
  final String? jobTitle;
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
    this.organizationName,
    this.companyUID,
    this.companyName,
    this.jobTitle,
    required this.createdAt,
    required this.createdBy,
    required this.temporaryPassword,
    this.isActive = true,
  });

  AdminUser copyWith({
    String? uid,
    String? phoneNumber,
    String? email,
    String? displayName,
    String? role,
    String? organizationUID,
    String? organizationName,
    String? companyUID,
    String? companyName,
    String? jobTitle,
    DateTime? createdAt,
    String? createdBy,
    String? temporaryPassword,
    bool? isActive,
  }) {
    return AdminUser(
      uid: uid ?? this.uid,
      phoneNumber: phoneNumber ?? this.phoneNumber,
      email: email ?? this.email,
      displayName: displayName ?? this.displayName,
      role: role ?? this.role,
      organizationUID: organizationUID ?? this.organizationUID,
      organizationName: organizationName ?? this.organizationName,
      companyUID: companyUID ?? this.companyUID,
      companyName: companyName ?? this.companyName,
      jobTitle: jobTitle ?? this.jobTitle,
      createdAt: createdAt ?? this.createdAt,
      createdBy: createdBy ?? this.createdBy,
      temporaryPassword: temporaryPassword ?? this.temporaryPassword,
      isActive: isActive ?? this.isActive,
    );
  }

  @override
  List<Object?> get props => [
    uid,
    phoneNumber,
    email,
    displayName,
    role,
    organizationUID,
    organizationName,
    companyUID,
    companyName,
    jobTitle,
    createdAt,
    createdBy,
    temporaryPassword,
    isActive,
  ];
}


