part of 'photo_permission_bloc.dart';

abstract class PhotoPermissionEvent extends Equatable {
  const PhotoPermissionEvent();

  @override
  List<Object?> get props => [];
}

class RequestPermissionRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final List<String> branchIds;
  final List<String> branchNames;
  final DateTime startDate;
  final DateTime endDate;
  final String requestedBy;

  const RequestPermissionRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.companyName,
    this.companyCode,
    required this.branchIds,
    required this.branchNames,
    required this.startDate,
    required this.endDate,
    required this.requestedBy,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        companyName,
        companyCode,
        branchIds,
        branchNames,
        startDate,
        endDate,
        requestedBy,
      ];
}

class LoadPermissionsRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;

  const LoadPermissionsRequested({
    required this.organizationUID,
    required this.companyUID,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID];
}

class LoadOngoingPermissionsRequested extends PhotoPermissionEvent {
  final String organizationUID;

  const LoadOngoingPermissionsRequested({required this.organizationUID});

  @override
  List<Object?> get props => [organizationUID];
}

class ApprovePermissionRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final String status;
  final String approvedBy;

  const ApprovePermissionRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.status,
    required this.approvedBy,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, permissionId, status, approvedBy];
}

class TogglePermissionRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final bool isEnabled;

  const TogglePermissionRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.isEnabled,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, permissionId, isEnabled];
}

class UploadPhotoRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final String branchId;
  final String branchName;
  final String delegateUID;
  final String delegateName;
  final File imageFile;
  final String comment;
  final double latitude;
  final double longitude;

  const UploadPhotoRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.branchId,
    required this.branchName,
    required this.delegateUID,
    required this.delegateName,
    required this.imageFile,
    required this.comment,
    required this.latitude,
    required this.longitude,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        branchId,
        branchName,
        delegateUID,
        delegateName,
        imageFile,
        comment,
        latitude,
        longitude,
      ];
}

class LoadCapturedPhotosRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;

  const LoadCapturedPhotosRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, permissionId];
}

class LoadDelegateCapturedPhotosRequested extends PhotoPermissionEvent {
  final String delegateUID;

  const LoadDelegateCapturedPhotosRequested({
    required this.delegateUID,
  });

  @override
  List<Object?> get props => [delegateUID];
}

class LoadCompanyCapturedPhotosRequested extends PhotoPermissionEvent {
  final String companyUID;

  const LoadCompanyCapturedPhotosRequested({
    required this.companyUID,
  });

  @override
  List<Object?> get props => [companyUID];
}

class DeleteCapturedPhotoRequested extends PhotoPermissionEvent {
  final String photoId;

  const DeleteCapturedPhotoRequested({
    required this.photoId,
  });

  @override
  List<Object?> get props => [photoId];
}
