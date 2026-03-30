import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';

class AdminUserModel extends AdminUser {
  const AdminUserModel({
    required super.uid,
    required super.phoneNumber,
    required super.email,
    required super.displayName,
    required super.role,
    super.organizationUID,
    super.companyUID,
    required super.createdAt,
    required super.createdBy,
    required super.temporaryPassword,
    super.isActive,
  });

  Map<String, dynamic> toMap() {
    return {
      'phoneNumber': phoneNumber,
      'email': email,
      'displayName': displayName,
      'role': role,
      'organizationUID': organizationUID ?? '',
      'companyUID': companyUID ?? '',
      'password': temporaryPassword,
      'isActive': true,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }

  factory AdminUserModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;
    return AdminUserModel(
      uid: doc.id,
      phoneNumber: data['phoneNumber'] ?? '',
      email: data['email'] ?? '',
      displayName: data['displayName'] ?? '',
      role: data['role'] ?? 'company-admin',
      organizationUID: data['organizationUID'],
      companyUID: data['companyUID'],
      createdAt: (data['createdAt'] as Timestamp?)?.toDate() ?? DateTime.now(),
      createdBy: data['createdBy'] ?? '',
      temporaryPassword: data['password'] ?? '',
      isActive: data['isActive'] ?? true,
    );
  }
}
