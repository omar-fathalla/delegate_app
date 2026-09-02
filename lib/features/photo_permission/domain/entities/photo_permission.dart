import 'package:equatable/equatable.dart';

class PhotoPermission extends Equatable {
  final String uid;
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final List<String> branchIds;
  final List<String> branchNames;
  final DateTime startDate;
  final DateTime endDate;
  final String status;
  final String requestedBy;
  final String? approvedBy;
  final DateTime createdAt;
  final DateTime updatedAt;
  final bool isSupervisorEnabled;
  final String? department;

  const PhotoPermission({
    required this.uid,
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.companyCode,
    required this.branchIds,
    required this.branchNames,
    required this.startDate,
    required this.endDate,
    required this.status,
    required this.requestedBy,
    this.approvedBy,
    required this.createdAt,
    required this.updatedAt,
    required this.isSupervisorEnabled,
    this.department,
  });

  @override
  List<Object?> get props => [
        uid,
        organizationUID,
        companyUID,
        companyName,
        companyCode,
        branchIds,
        branchNames,
        startDate,
        endDate,
        status,
        requestedBy,
        approvedBy,
        createdAt,
        updatedAt,
        isSupervisorEnabled,
        department,
      ];
}
