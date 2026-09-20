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
    super.organizationName,
    super.companyUID,
    super.companyName,
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
      'isActive': isActive,
      'createdAt': Timestamp.fromDate(createdAt),
      'createdBy': createdBy,
    };
  }

  factory AdminUserModel.fromFirestore(
    DocumentSnapshot doc, [
    Map<String, String>? orgNamesMap,
  ]) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};

    String str(dynamic val) => val == null ? '' : val.toString().trim();

    // 1. Resolve Display Name
    final rawDisplayName = str(data['displayName']);
    final rawFullName = str(data['fullName']);
    final first = str(data['firstName']);
    final middle = str(data['middleName']);
    final last = str(data['lastName']);
    final combined = [first, middle, last].where((s) => s.isNotEmpty).join(' ');
    final altName = str(data['name']);

    String displayName = '';
    if (rawDisplayName.isNotEmpty) {
      displayName = rawDisplayName;
    } else if (rawFullName.isNotEmpty) {
      displayName = rawFullName;
    } else if (combined.isNotEmpty) {
      displayName = combined;
    } else if (altName.isNotEmpty) {
      displayName = altName;
    }

    // 2. Resolve Phone Number
    final phone = str(data['phoneNumber']).isNotEmpty
        ? str(data['phoneNumber'])
        : str(data['phone']);

    // 3. Resolve Email
    final email = str(data['email']);

    // 4. Resolve Role & Position
    final rawRole = str(data['role']);
    final rawPosition = str(data['position']).toLowerCase();
    String effectiveRole = rawRole;
    if (effectiveRole.isEmpty) {
      if (rawPosition == 'supervisor' || rawPosition == 'مشرف') {
        effectiveRole = 'supervisor';
      } else {
        effectiveRole = 'delegate';
      }
    } else if (rawPosition == 'supervisor' || rawPosition == 'مشرف') {
      if (effectiveRole == 'delegate' || effectiveRole == 'promoter') {
        effectiveRole = 'supervisor';
      }
    }

    // 5. Resolve Organization & Company
    String? orgUID = str(data['organizationUID']).isNotEmpty
        ? str(data['organizationUID'])
        : (str(data['organizationId']).isNotEmpty
            ? str(data['organizationId'])
            : (str(data['orgId']).isNotEmpty ? str(data['orgId']) : null));

    String? orgName = str(data['organizationName']).isNotEmpty
        ? str(data['organizationName'])
        : (str(data['organization_name']).isNotEmpty
            ? str(data['organization_name'])
            : null);

    if ((orgName == null || orgName.isEmpty) &&
        orgUID != null &&
        orgNamesMap != null &&
        orgNamesMap.containsKey(orgUID)) {
      orgName = orgNamesMap[orgUID];
    }

    String? compUID = str(data['companyUID']).isNotEmpty
        ? str(data['companyUID'])
        : (str(data['companyId']).isNotEmpty
            ? str(data['companyId'])
            : null);

    String? compName = str(data['companyName']).isNotEmpty
        ? str(data['companyName'])
        : (str(data['company_name']).isNotEmpty
            ? str(data['company_name'])
            : null);

    // 6. Resolve Active / Suspended State
    bool isActive = true;
    if (data['isActive'] is bool) {
      isActive = data['isActive'] as bool;
    } else if (data['status'] != null) {
      final s = str(data['status']).toLowerCase();
      isActive = (s != 'suspended' && s != 'rejected');
    }

    // 7. Resolve CreatedAt
    DateTime createdAt = DateTime.now();
    final rawCreatedAt = data['createdAt'];
    if (rawCreatedAt is Timestamp) {
      createdAt = rawCreatedAt.toDate();
    } else if (rawCreatedAt is String) {
      createdAt = DateTime.tryParse(rawCreatedAt) ?? DateTime.now();
    } else if (rawCreatedAt is int) {
      createdAt = DateTime.fromMillisecondsSinceEpoch(rawCreatedAt);
    }

    return AdminUserModel(
      uid: doc.id,
      phoneNumber: phone,
      email: email,
      displayName: displayName,
      role: effectiveRole,
      organizationUID: orgUID,
      organizationName: orgName,
      companyUID: compUID,
      companyName: compName,
      createdAt: createdAt,
      createdBy: str(data['createdBy']),
      temporaryPassword: str(data['password']),
      isActive: isActive,
    );
  }
}
