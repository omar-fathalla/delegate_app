part of 'photo_permission_bloc.dart';

abstract class PhotoPermissionState extends Equatable {
  const PhotoPermissionState();

  @override
  List<Object?> get props => [];
}

class PhotoPermissionInitial extends PhotoPermissionState {}

class PhotoPermissionLoading extends PhotoPermissionState {}

class PhotoPermissionUploadInProgress extends PhotoPermissionState {}

class PhotoPermissionsLoaded extends PhotoPermissionState {
  final List<PhotoPermission> permissions;
  const PhotoPermissionsLoaded({required this.permissions});

  @override
  List<Object?> get props => [permissions];
}

class OngoingPermissionsLoaded extends PhotoPermissionState {
  final List<PhotoPermission> permissions;
  const OngoingPermissionsLoaded({required this.permissions});

  @override
  List<Object?> get props => [permissions];
}

class PermissionActionSuccess extends PhotoPermissionState {
  final PhotoPermission permission;
  final String message;

  const PermissionActionSuccess({
    required this.permission,
    required this.message,
  });

  @override
  List<Object?> get props => [permission, message];
}

class CapturedPhotosLoaded extends PhotoPermissionState {
  final List<CapturedPhoto> photos;
  const CapturedPhotosLoaded({required this.photos});

  @override
  List<Object?> get props => [photos];
}

class PhotoUploadSuccess extends PhotoPermissionState {
  final CapturedPhoto photo;
  final bool isOffline;

  const PhotoUploadSuccess({
    required this.photo,
    this.isOffline = false,
  });

  @override
  List<Object?> get props => [photo, isOffline];
}

class PhotoPermissionActionSuccess extends PhotoPermissionState {
  final String message;
  
  const PhotoPermissionActionSuccess({required this.message});

  @override
  List<Object?> get props => [message];
}

class PhotoPermissionError extends PhotoPermissionState {
  final String message;
  const PhotoPermissionError({required this.message});

  @override
  List<Object?> get props => [message];
}

class PhotoDeleteSuccess extends PhotoPermissionState {}

class PhotoBatchUploadInProgress extends PhotoPermissionState {
  final int current;
  final int total;

  const PhotoBatchUploadInProgress({
    required this.current,
    required this.total,
  });

  @override
  List<Object?> get props => [current, total];
}

class PhotoBatchUploadSuccess extends PhotoPermissionState {
  final int uploadedCount;
  final bool isOffline;

  const PhotoBatchUploadSuccess({
    required this.uploadedCount,
    this.isOffline = false,
  });

  @override
  List<Object?> get props => [uploadedCount, isOffline];
}
