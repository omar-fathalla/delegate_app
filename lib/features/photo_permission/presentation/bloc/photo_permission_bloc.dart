import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:get_it/get_it.dart';
import 'package:delegate_app/core/services/sync_manager.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/models/captured_photo_model.dart';
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
import 'package:delegate_app/features/photo_permission/domain/usecases/get_company_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/update_photo_permission_branches.dart';

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
  final GetCompanyCapturedPhotos getCompanyCapturedPhotos;
  final DeleteCapturedPhoto deleteCapturedPhoto;
  final DeletePhotoPermission deletePhotoPermission;
  final UpdatePhotoPermissionBranches updatePhotoPermissionBranches;

  PhotoPermissionBloc({
    required this.requestPhotoPermission,
    required this.approvePhotoPermission,
    required this.togglePhotoPermission,
    required this.getPhotoPermissions,
    required this.getOngoingPhotoPermissions,
    required this.uploadCapturedPhoto,
    required this.getCapturedPhotos,
    required this.getDelegateCapturedPhotos,
    required this.getCompanyCapturedPhotos,
    required this.deleteCapturedPhoto,
    required this.deletePhotoPermission,
    required this.updatePhotoPermissionBranches,
  }) : super(PhotoPermissionInitial()) {
    on<RequestPermissionRequested>(_onRequestPermission);
    on<LoadPermissionsRequested>(_onLoadPermissions);
    on<LoadOngoingPermissionsRequested>(_onLoadOngoingPermissions);
    on<ApprovePermissionRequested>(_onApprovePermission);
    on<TogglePermissionRequested>(_onTogglePermission);
    on<UploadPhotoRequested>(_onUploadPhoto);
    on<LoadCapturedPhotosRequested>(_onLoadCapturedPhotos);
    on<LoadDelegateCapturedPhotosRequested>(_onLoadDelegateCapturedPhotos);
    on<LoadCompanyCapturedPhotosRequested>(_onLoadCompanyCapturedPhotos);
    on<DeleteCapturedPhotoRequested>(_onDeleteCapturedPhoto);
    on<DeletePhotoPermissionRequested>(_onDeletePhotoPermission);
    on<UpdatePhotoPermissionBranchesRequested>(_onUpdatePhotoPermissionBranches);
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

    // 1. Check if device is connected to the internet -> Direct Upload to Cloud
    bool isConnected = false;
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      isConnected = connectivityResults.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
    } catch (_) {
      isConnected = true; // Attempt upload if check fails
    }

    if (isConnected) {
      try {
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

        if (result.isRight()) {
          final uploadedPhoto = result.getOrElse(() => throw Exception());
          emit(PhotoUploadSuccess(photo: uploadedPhoto, isOffline: false));
          return;
        }
      } catch (_) {
        // Fall through to offline persistent fallback if network upload fails
      }
    }

    // 2. Offline Fallback: Save image to persistent App Documents Directory and SQLite queue
    try {
      final offlineDataSource = GetIt.I<PhotoOfflineDataSource>();
      final persistentImagePath =
          await offlineDataSource.saveImageToPersistentDirectory(event.imageFile);

      await offlineDataSource.savePendingPhoto({
        'organizationUID': event.organizationUID,
        'companyUID': event.companyUID,
        'permissionId': event.permissionId,
        'branchId': event.branchId,
        'branchName': event.branchName,
        'delegateUID': event.delegateUID,
        'delegateName': event.delegateName,
        'imagePath': persistentImagePath,
        'comment': event.comment,
        'latitude': event.latitude,
        'longitude': event.longitude,
        'timestamp': DateTime.now().millisecondsSinceEpoch,
      });

      final offlinePhoto = CapturedPhotoModel(
        uid: 'pending_${DateTime.now().millisecondsSinceEpoch}',
        permissionId: event.permissionId,
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        branchId: event.branchId,
        branchName: event.branchName,
        delegateUID: event.delegateUID,
        delegateName: event.delegateName,
        photoUrl: persistentImagePath,
        comment: event.comment,
        latitude: event.latitude,
        longitude: event.longitude,
        capturedAt: DateTime.now(),
      );

      emit(PhotoUploadSuccess(photo: offlinePhoto, isOffline: true));

      // Trigger background sync service when connection is restored
      GetIt.I<SyncManager>().syncPendingPhotos();
    } catch (e) {
      emit(PhotoPermissionError(message: 'فشل في حفظ الصورة: $e'));
    }
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
    
    // 1. Fetch remote photos
    final result = await getDelegateCapturedPhotos(
      GetDelegateCapturedPhotosParams(
        delegateUID: event.delegateUID,
      ),
    );
    
    // 2. Fetch local pending photos
    final offlineDataSource = GetIt.I<PhotoOfflineDataSource>();
    final pendingMaps = await offlineDataSource.getPendingPhotos();
    
    final List<CapturedPhoto> pendingPhotos = pendingMaps
        .where((map) => map['delegateUID'] == event.delegateUID)
        .map((map) => CapturedPhotoModel(
              uid: 'pending_${map['id']}',
              permissionId: map['permissionId'],
              organizationUID: map['organizationUID'],
              companyUID: map['companyUID'],
              branchId: map['branchId'],
              branchName: map['branchName'],
              delegateUID: map['delegateUID'],
              delegateName: map['delegateName'],
              photoUrl: map['imagePath'],
              comment: map['comment'] ?? '',
              latitude: map['latitude'] ?? 0.0,
              longitude: map['longitude'] ?? 0.0,
              capturedAt: DateTime.fromMillisecondsSinceEpoch(map['timestamp']),
            ))
        .toList();

    result.fold(
      (failure) {
        if (pendingPhotos.isNotEmpty) {
          emit(CapturedPhotosLoaded(photos: pendingPhotos));
        } else {
          emit(PhotoPermissionError(message: failure.message));
        }
      },
      (photos) {
        final allPhotos = [...pendingPhotos, ...photos];
        // Sort newest first
        allPhotos.sort((a, b) => b.capturedAt.compareTo(a.capturedAt));
        emit(CapturedPhotosLoaded(photos: allPhotos));
      },
    );
  }

  Future<void> _onLoadCompanyCapturedPhotos(
    LoadCompanyCapturedPhotosRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await getCompanyCapturedPhotos(
      GetCompanyCapturedPhotosParams(companyUID: event.companyUID),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (photos) => emit(CapturedPhotosLoaded(photos: photos)),
    );
  }

  Future<void> _onDeleteCapturedPhoto(
    DeleteCapturedPhotoRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await deleteCapturedPhoto(
      DeleteCapturedPhotoParams(
        photoId: event.photoId,
        organizationUID: '',
        companyUID: '',
        permissionId: '',
        photoUrl: '',
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (_) => emit(const PhotoPermissionActionSuccess(message: 'تم حذف الصورة بنجاح')),
    );
  }

  Future<void> _onDeletePhotoPermission(
    DeletePhotoPermissionRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await deletePhotoPermission(
      DeletePhotoPermissionParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (_) => emit(const PhotoPermissionActionSuccess(message: 'تم حذف إذن التصوير بنجاح.')),
    );
  }

  Future<void> _onUpdatePhotoPermissionBranches(
    UpdatePhotoPermissionBranchesRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await updatePhotoPermissionBranches(
      UpdatePhotoPermissionBranchesParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
        branchIds: event.branchIds,
        branchNames: event.branchNames,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (_) => emit(PhotoPermissionActionSuccess(message: 'تم تعديل الفروع بنجاح')),
    );
  }
}
