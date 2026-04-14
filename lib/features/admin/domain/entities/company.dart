import 'package:equatable/equatable.dart';

/// Company entity representing a company in the system
class Company extends Equatable {
  final String uid;
  final String name;
  final String companyCodeInOrg;
  final String organizationUID;
  final String type;
  final String status;
  final DateTime createdAt;
  final DateTime updatedAt;
  final int admins;
  final int delegates;
  final bool deferredPayment;
  final String? description;
  final String? address;
  final String? phone;
  final String? email;
  final int? code; // إضافة حقل الكود كرقم

  const Company({
    required this.uid,
    required this.name,
    required this.companyCodeInOrg,
    required this.organizationUID,
    required this.type,
    required this.status,
    required this.createdAt,
    required this.updatedAt,
    required this.admins,
    required this.delegates,
    required this.deferredPayment,
    this.description,
    this.address,
    this.phone,
    this.email,
    this.code, // إضافة حقل الكود
  });

  @override
  List<Object?> get props => [
    uid,
    name,
    companyCodeInOrg,
    organizationUID,
    type,
    status,
    createdAt,
    updatedAt,
    admins,
    delegates,
    deferredPayment,
    description,
    address,
    phone,
    email,
    code, // إضافة حقل الكود
  ];
}
