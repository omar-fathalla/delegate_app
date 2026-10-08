import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';

class PrivateLabelPermissionsModel extends PrivateLabelPermissions {
  const PrivateLabelPermissionsModel({
    required super.userId,
    super.userName,
    super.phoneNumber,
    super.userRole,
    super.organizationUID,
    super.organizationName,
    super.companyUID,
    super.companyName,
    super.canCapture,
    super.canViewReports,
    super.canReviewAudit,
    super.updatedAt,
    super.updatedBy,
    super.updatedByName,
  });

  factory PrivateLabelPermissionsModel.fromFirestore(DocumentSnapshot doc) {
    final data = (doc.data() as Map<String, dynamic>?) ?? {};
    return PrivateLabelPermissionsModel.fromMap(doc.id, data);
  }

  factory PrivateLabelPermissionsModel.fromMap(String id, Map<String, dynamic> data) {
    DateTime? parseDate(dynamic val) {
      if (val == null) return null;
      if (val is Timestamp) return val.toDate();
      if (val is DateTime) return val;
      if (val is String) return DateTime.tryParse(val);
      return null;
    }

    return PrivateLabelPermissionsModel(
      userId: id,
      userName: (data['userName'] ?? data['name'] ?? data['displayName'] ?? '').toString(),
      phoneNumber: (data['phoneNumber'] ?? data['phone'] ?? '').toString(),
      userRole: (data['userRole'] ?? data['role'] ?? '').toString(),
      organizationUID: (data['organizationUID'] ?? data['organizationId'] ?? '').toString(),
      organizationName: (data['organizationName'] ?? '').toString(),
      companyUID: (data['companyUID'] ?? data['companyId'] ?? '').toString(),
      companyName: (data['companyName'] ?? '').toString(),
      canCapture: data['canCapture'] == true,
      canViewReports: data['canViewReports'] == true || data['canAccessReport'] == true,
      canReviewAudit: data['canReviewAudit'] == true || data['canAccessAudit'] == true,
      updatedAt: parseDate(data['updatedAt']),
      updatedBy: data['updatedBy']?.toString(),
      updatedByName: data['updatedByName']?.toString(),
    );
  }

  Map<String, dynamic> toMap() {
    return {
      'userId': userId,
      'userName': userName,
      'phoneNumber': phoneNumber,
      'userRole': userRole,
      'organizationUID': organizationUID,
      'organizationName': organizationName,
      'companyUID': companyUID,
      'companyName': companyName,
      'canCapture': canCapture,
      'canViewReports': canViewReports,
      'canReviewAudit': canReviewAudit,
      'updatedAt': FieldValue.serverTimestamp(),
      if (updatedBy != null && updatedBy!.isNotEmpty) 'updatedBy': updatedBy,
      if (updatedByName != null && updatedByName!.isNotEmpty) 'updatedByName': updatedByName,
    };
  }

  factory PrivateLabelPermissionsModel.fromEntity(PrivateLabelPermissions entity) {
    return PrivateLabelPermissionsModel(
      userId: entity.userId,
      userName: entity.userName,
      phoneNumber: entity.phoneNumber,
      userRole: entity.userRole,
      organizationUID: entity.organizationUID,
      organizationName: entity.organizationName,
      companyUID: entity.companyUID,
      companyName: entity.companyName,
      canCapture: entity.canCapture,
      canViewReports: entity.canViewReports,
      canReviewAudit: entity.canReviewAudit,
      updatedAt: entity.updatedAt,
      updatedBy: entity.updatedBy,
      updatedByName: entity.updatedByName,
    );
  }
}
