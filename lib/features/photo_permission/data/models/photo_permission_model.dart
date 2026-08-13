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
    };
  }
}
