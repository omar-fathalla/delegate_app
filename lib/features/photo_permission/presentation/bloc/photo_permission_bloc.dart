import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/request_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/approve_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/toggle_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_photo_permissions.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_ongoing_photo_permissions.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/upload_captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_delegate_captured_photos.dart';

part 'photo_permission_event.dart';
part 'photo_permission_state.dart';

class PhotoPermissionBloc extends Bloc<PhotoPermissionEvent, PhotoPermissionState> {
  final RequestPhotoPermission requestPhotoPermission;
  final ApprovePhotoPermission approvePhotoPermission;
  final TogglePhotoPermission togglePhotoPermission;
  final GetPhotoPermissions getPhotoPermissions;
  final GetOngoingPhotoPermissions getOngoingPhotoPermissions;
  final UploadCapturedPhoto uploadCapturedPhoto;
  final GetCapturedPhotos getCapturedPhotos;
  final GetDelegateCapturedPhotos getDelegateCapturedPhotos;

  PhotoPermissionBloc({
    required this.requestPhotoPermission,
    required this.approvePhotoPermission,
    required this.togglePhotoPermission,
    required this.getPhotoPermissions,
    required this.getOngoingPhotoPermissions,
    required this.uploadCapturedPhoto,
    required this.getCapturedPhotos,
    required this.getDelegateCapturedPhotos,
  }) : super(PhotoPermissionInitial()) {
    on<RequestPermissionRequested>(_onRequestPermission);
    on<LoadPermissionsRequested>(_onLoadPermissions);
    on<LoadOngoingPermissionsRequested>(_onLoadOngoingPermissions);
    on<ApprovePermissionRequested>(_onApprovePermission);
    on<TogglePermissionRequested>(_onTogglePermission);
    on<UploadPhotoRequested>(_onUploadPhoto);
    on<LoadCapturedPhotosRequested>(_onLoadCapturedPhotos);
    on<LoadDelegateCapturedPhotosRequested>(_onLoadDelegateCapturedPhotos);
  }

  Future<void> _onRequestPermission(
    RequestPermissionRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await requestPhotoPermission(
      RequestPhotoPermissionParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        companyName: event.companyName,
        companyCode: event.companyCode,
        branchIds: event.branchIds,
        branchNames: event.branchNames,
        startDate: event.startDate,
        endDate: event.endDate,
        requestedBy: event.requestedBy,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (permission) => emit(
        PermissionActionSuccess(
          permission: permission,
          message: 'تم إرسال طلب إذن التصوير بنجاح إلى إدارة التسويق.',
        ),
      ),
    );
  }

  Future<void> _onLoadPermissions(
    LoadPermissionsRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await getPhotoPermissions(
      GetPhotoPermissionsParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (permissions) => emit(PhotoPermissionsLoaded(permissions: permissions)),
    );
  }

  Future<void> _onLoadOngoingPermissions(
    LoadOngoingPermissionsRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await getOngoingPhotoPermissions(
      GetOngoingPhotoPermissionsParams(
        organizationUID: event.organizationUID,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (permissions) => emit(OngoingPermissionsLoaded(permissions: permissions)),
    );
  }

  Future<void> _onApprovePermission(
    ApprovePermissionRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await approvePhotoPermission(
      ApprovePhotoPermissionParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
        status: event.status,
        approvedBy: event.approvedBy,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (permission) => emit(
        PermissionActionSuccess(
          permission: permission,
          message: event.status == 'approved'
              ? 'تمت الموافقة على إذن التصوير وتفعيله بنجاح.'
              : 'تم رفض طلب إذن التصوير.',
        ),
      ),
    );
  }

  Future<void> _onTogglePermission(
    TogglePermissionRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await togglePhotoPermission(
      TogglePhotoPermissionParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
        isEnabled: event.isEnabled,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (permission) => emit(
        PermissionActionSuccess(
          permission: permission,
          message: event.isEnabled
              ? 'تم تفعيل إذن التصوير بنجاح للمناديب.'
              : 'تم إيقاف/تجميد إذن التصوير مؤقتاً.',
        ),
      ),
    );
  }

  Future<void> _onUploadPhoto(
    UploadPhotoRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionUploadInProgress());
    final result = await uploadCapturedPhoto(
      UploadCapturedPhotoParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
        branchId: event.branchId,
        branchName: event.branchName,
        delegateUID: event.delegateUID,
        delegateName: event.delegateName,
        imageFile: event.imageFile,
        comment: event.comment,
        latitude: event.latitude,
        longitude: event.longitude,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (photo) => emit(PhotoUploadSuccess(photo: photo)),
    );
  }

  Future<void> _onLoadCapturedPhotos(
    LoadCapturedPhotosRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await getCapturedPhotos(
      GetCapturedPhotosParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (photos) => emit(CapturedPhotosLoaded(photos: photos)),
    );
  }

  Future<void> _onLoadDelegateCapturedPhotos(
    LoadDelegateCapturedPhotosRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await getDelegateCapturedPhotos(
      GetDelegateCapturedPhotosParams(
        delegateUID: event.delegateUID,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (photos) => emit(CapturedPhotosLoaded(photos: photos)),
    );
  }
}
