import 'package:cloud_firestore/cloud_firestore.dart';
import '../../domain/entities/photo_permission.dart';

class PhotoPermissionModel extends PhotoPermission {
  const PhotoPermissionModel({
    required super.uid,
    required super.organizationUID,
    required super.companyUID,
    required super.companyName,
    super.companyCode,
    required super.branchIds,
    required super.branchNames,
    required super.startDate,
    required super.endDate,
    required super.status,
    required super.requestedBy,
    super.approvedBy,
    required super.createdAt,
    required super.updatedAt,
    required super.isSupervisorEnabled,
    super.department,
  });

  factory PhotoPermissionModel.fromFirestore(DocumentSnapshot doc) {
    final data = doc.data() as Map<String, dynamic>? ?? {};

    DateTime parseDateTime(dynamic value) {
      if (value is Timestamp) {
        return value.toDate();
      } else if (value is String) {
        return DateTime.tryParse(value) ?? DateTime.now();
      }
      return DateTime.now();
    }

    return PhotoPermissionModel(
      uid: doc.id,
      organizationUID: data['organizationUID']?.toString() ?? '',
      companyUID: data['companyUID']?.toString() ?? '',
      companyName: data['companyName']?.toString() ?? '',
      companyCode: data['companyCode'] != null
          ? int.tryParse(data['companyCode'].toString())
          : (data['companyCodeInOrg'] != null
              ? int.tryParse(data['companyCodeInOrg'].toString())
              : (data['code'] != null ? int.tryParse(data['code'].toString()) : null)),
      branchIds: List<String>.from(data['branchIds'] as List? ?? []),
      branchNames: List<String>.from(data['branchNames'] as List? ?? []),
      startDate: parseDateTime(data['startDate']),
      endDate: parseDateTime(data['endDate']),
      status: data['status']?.toString() ?? 'pending',
      requestedBy: data['requestedBy']?.toString() ?? '',
      approvedBy: data['approvedBy']?.toString(),
      createdAt: parseDateTime(data['createdAt']),
      updatedAt: parseDateTime(data['updatedAt']),
      isSupervisorEnabled: data['isSupervisorEnabled'] != false,
      department: data['department']?.toString(),
    );
  }

  Map<String, dynamic> toFirestore() {
    return {
      'organizationUID': organizationUID,
      'companyUID': companyUID,
      'companyName': companyName,
      'companyCode': companyCode,
      'branchIds': branchIds,
      'branchNames': branchNames,
      'startDate': Timestamp.fromDate(startDate),
      'endDate': Timestamp.fromDate(endDate),
      'status': status,
      'requestedBy': requestedBy,
      'approvedBy': approvedBy,
      'createdAt': Timestamp.fromDate(createdAt),
      'updatedAt': Timestamp.fromDate(updatedAt),
      'isSupervisorEnabled': isSupervisorEnabled,
      if (department != null && department!.isNotEmpty) 'department': department,
    };
  }

  factory PhotoPermissionModel.fromEntity(PhotoPermission entity) {
    if (entity is PhotoPermissionModel) return entity;
    return PhotoPermissionModel(
      uid: entity.uid,
      organizationUID: entity.organizationUID,
      companyUID: entity.companyUID,
      companyName: entity.companyName,
      companyCode: entity.companyCode,
      branchIds: entity.branchIds,
      branchNames: entity.branchNames,
      startDate: entity.startDate,
      endDate: entity.endDate,
      status: entity.status,
      requestedBy: entity.requestedBy,
      approvedBy: entity.approvedBy,
      createdAt: entity.createdAt,
      updatedAt: entity.updatedAt,
      isSupervisorEnabled: entity.isSupervisorEnabled,
      department: entity.department,
    );
  }

  factory PhotoPermissionModel.fromJson(Map<String, dynamic> json) {
    DateTime parseDate(dynamic v) {
      if (v is int) return DateTime.fromMillisecondsSinceEpoch(v);
      if (v is String) return DateTime.tryParse(v) ?? DateTime.now();
      return DateTime.now();
    }

    return PhotoPermissionModel(
      uid: json['uid']?.toString() ?? '',
      organizationUID: json['organizationUID']?.toString() ?? '',
      companyUID: json['companyUID']?.toString() ?? '',
      companyName: json['companyName']?.toString() ?? '',
      companyCode: json['companyCode'] != null
          ? int.tryParse(json['companyCode'].toString())
          : null,
      branchIds: List<String>.from(json['branchIds'] as List? ?? const []),
      branchNames: List<String>.from(json['branchNames'] as List? ?? const []),
      startDate: parseDate(json['startDate']),
      endDate: parseDate(json['endDate']),
      status: json['status']?.toString() ?? 'pending',
      requestedBy: json['requestedBy']?.toString() ?? '',
      approvedBy: json['approvedBy']?.toString(),
      createdAt: parseDate(json['createdAt']),
      updatedAt: parseDate(json['updatedAt']),
      isSupervisorEnabled: json['isSupervisorEnabled'] != false,
      department: json['department']?.toString(),
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'organizationUID': organizationUID,
      'companyUID': companyUID,
      'companyName': companyName,
      'companyCode': companyCode,
      'branchIds': branchIds,
      'branchNames': branchNames,
      'startDate': startDate.millisecondsSinceEpoch,
      'endDate': endDate.millisecondsSinceEpoch,
      'status': status,
      'requestedBy': requestedBy,
      'approvedBy': approvedBy,
      'createdAt': createdAt.millisecondsSinceEpoch,
      'updatedAt': updatedAt.millisecondsSinceEpoch,
      'isSupervisorEnabled': isSupervisorEnabled,
      if (department != null && department!.isNotEmpty) 'department': department,
    };
  }
}

