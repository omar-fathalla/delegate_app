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
  final String? department;

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
    this.department,
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
        department,
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
  final String companyName;
  final int? companyCode;
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
    this.companyName = '',
    this.companyCode,
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
        companyName,
        companyCode,
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
  final String? branchName;
  final int? limit;

  const LoadCompanyCapturedPhotosRequested({
    required this.companyUID,
    this.branchName,
    this.limit,
  });

  @override
  List<Object?> get props => [companyUID, branchName, limit];
}

class DeleteCapturedPhotoRequested extends PhotoPermissionEvent {
  final String photoId;
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final String photoUrl;

  const DeleteCapturedPhotoRequested({
    required this.photoId,
    this.organizationUID = '',
    this.companyUID = '',
    this.permissionId = '',
    this.photoUrl = '',
  });

  @override
  List<Object?> get props => [photoId, organizationUID, companyUID, permissionId, photoUrl];
}

class DeletePhotoPermissionRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;

  const DeletePhotoPermissionRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
      ];
}

class UpdatePhotoPermissionBranchesRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final List<String> branchIds;
  final List<String> branchNames;

  const UpdatePhotoPermissionBranchesRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.branchIds,
    required this.branchNames,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, permissionId, branchIds, branchNames];
}

class UpdatePhotoPermissionDatesRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String permissionId;
  final DateTime startDate;
  final DateTime endDate;

  const UpdatePhotoPermissionDatesRequested({
    required this.organizationUID,
    required this.companyUID,
    required this.permissionId,
    required this.startDate,
    required this.endDate,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        permissionId,
        startDate,
        endDate,
      ];
}

class UploadBatchPhotosRequested extends PhotoPermissionEvent {
  final String organizationUID;
  final String companyUID;
  final String companyName;
  final int? companyCode;
  final String permissionId;
  final String branchId;
  final String branchName;
  final String delegateUID;
  final String delegateName;
  final List<File> imageFiles;
  final String comment;
  final double latitude;
  final double longitude;

  const UploadBatchPhotosRequested({
    required this.organizationUID,
    required this.companyUID,
    this.companyName = '',
    this.companyCode,
    required this.permissionId,
    required this.branchId,
    required this.branchName,
    required this.delegateUID,
    required this.delegateName,
    required this.imageFiles,
    required this.comment,
    required this.latitude,
    required this.longitude,
  });

  @override
  List<Object?> get props => [
        organizationUID,
        companyUID,
        companyName,
        companyCode,
        permissionId,
        branchId,
        branchName,
        delegateUID,
        delegateName,
        imageFiles,
        comment,
        latitude,
        longitude,
      ];
}

