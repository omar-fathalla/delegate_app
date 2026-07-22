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
  const PhotoUploadSuccess({required this.photo});

  @override
  List<Object?> get props => [photo];
}

class PhotoPermissionError extends PhotoPermissionState {
  final String message;
  const PhotoPermissionError({required this.message});

  @override
  List<Object?> get props => [message];
}
