import 'package:cloud_firestore/cloud_firestore.dart';

import '../../domain/entities/company.dart';

/// Company model for Firestore operations
class CompanyModel extends Company {
  const CompanyModel({
    required super.uid,
    required super.name,
    required super.companyCodeInOrg,
    required super.organizationUID,
    required super.type,
    required super.status,
    required super.createdAt,
    required super.updatedAt,
    required super.admins,
    required super.delegates,
    required super.deferredPayment,
    super.description,
    super.address,
    super.phone,
    super.email,
    super.code,
  });

  /// Create CompanyModel from Firestore document
  factory CompanyModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>;

    return CompanyModel(
      uid: doc.id,
      name: data['name']?.toString() ?? '',
      companyCodeInOrg: data['companyCodeInOrg']?.toString() ?? '',
      organizationUID: data['organizationUID']?.toString() ?? '',
      type: data['type']?.toString() ?? '',
      status: data['status']?.toString() ?? 'active',
      createdAt: data['createdAt'] is Timestamp
          ? (data['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(data['createdAt']?.toString() ?? '') ??
                DateTime.now(),
      updatedAt: data['updatedAt'] is Timestamp
          ? (data['updatedAt'] as Timestamp).toDate()
          : DateTime.tryParse(data['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
      admins: int.tryParse(data['admins']?.toString() ?? '0') ?? 0,
      delegates: int.tryParse(data['delegates']?.toString() ?? '0') ?? 0,
      deferredPayment:
          data['deferredPayment'] == true ||
          data['deferredPayment']?.toString() == 'true',
      description: data['description']?.toString(),
      address: data['address']?.toString(),
      phone: data['phone']?.toString(),
      email: data['email']?.toString(),
      code: data['code'] != null
          ? int.tryParse(data['code'].toString())
          : null, // إضافة حقل الكود
    );
  }

  /// Create CompanyModel from JSON
  factory CompanyModel.fromJson(Map<String, dynamic> json) {
    return CompanyModel(
      uid: json['uid'] ?? '',
      name: json['name']?.toString() ?? '',
      companyCodeInOrg: json['companyCodeInOrg']?.toString() ?? '',
      organizationUID: json['organizationUID']?.toString() ?? '',
      type: json['type']?.toString() ?? '',
      status: json['status']?.toString() ?? 'active',
      createdAt: json['createdAt'] is Timestamp
          ? (json['createdAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['createdAt']?.toString() ?? '') ??
                DateTime.now(),
      updatedAt: json['updatedAt'] is Timestamp
          ? (json['updatedAt'] as Timestamp).toDate()
          : DateTime.tryParse(json['updatedAt']?.toString() ?? '') ??
                DateTime.now(),
      admins: int.tryParse(json['admins']?.toString() ?? '0') ?? 0,
      delegates: int.tryParse(json['delegates']?.toString() ?? '0') ?? 0,
      deferredPayment:
          json['deferredPayment'] == true ||
          json['deferredPayment']?.toString() == 'true',
      description: json['description']?.toString(),
      address: json['address']?.toString(),
      phone: json['phone']?.toString(),
      email: json['email']?.toString(),
      code: json['code'] != null
          ? int.tryParse(json['code'].toString())
          : null, // إضافة حقل الكود
    );
  }

  /// Convert to JSON
  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'name': name,
      'companyCodeInOrg': companyCodeInOrg,
      'organizationUID': organizationUID,
      'type': type,
      'status': status,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'admins': admins,
      'delegates': delegates,
      'deferredPayment': deferredPayment,
      'description': description,
      'address': address,
      'phone': phone,
      'email': email,
      'code': code, // إضافة حقل الكود
    };
  }
}
