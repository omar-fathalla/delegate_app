import 'package:equatable/equatable.dart';

class CapturedPhoto extends Equatable {
  final String uid;
  final String permissionId;
  final String organizationUID;
  final String companyUID;
  final String branchId;
  final String branchName;
  final String delegateUID;
  final String delegateName;
  final String photoUrl;
  final String comment;
  final double latitude;
  final double longitude;
  final DateTime capturedAt;

  const CapturedPhoto({
    required this.uid,
    required this.permissionId,
    required this.organizationUID,
    required this.companyUID,
    required this.branchId,
    required this.branchName,
    required this.delegateUID,
    required this.delegateName,
    required this.photoUrl,
    required this.comment,
    required this.latitude,
    required this.longitude,
    required this.capturedAt,
  });

  @override
  List<Object?> get props => [
        uid,
        permissionId,
        organizationUID,
        companyUID,
        branchId,
        branchName,
        delegateUID,
        delegateName,
        photoUrl,
        comment,
        latitude,
        longitude,
        capturedAt,
      ];
}
