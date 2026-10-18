import 'dart:convert';
import 'dart:io';
import 'package:bloc/bloc.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:equatable/equatable.dart';
import 'package:get_it/get_it.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/services/sync_manager.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/models/captured_photo_model.dart';
import 'package:delegate_app/features/photo_permission/data/models/photo_permission_model.dart';
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
import 'package:delegate_app/features/photo_permission/domain/usecases/update_photo_permission_dates.dart';

part 'photo_permission_event.dart';
part 'photo_permission_state.dart';

class PhotoPermissionBloc extends Bloc<PhotoPermissionEvent, PhotoPermissionState> {
  static final Map<String, List<PhotoPermission>> _permissionsCache = {};
  static final Map<String, List<PhotoPermission>> _ongoingCache = {};

  /// Clears in-memory caches (useful for testing or session switches).
  static void clearMemoryCache() {
    _permissionsCache.clear();
    _ongoingCache.clear();
  }

  /// Synchronously returns cached permissions if available in memory.
  static List<PhotoPermission>? getCachedPermissionsSync({
    required String organizationUID,
    String? companyUID,
  }) {
    final key = '${organizationUID}_${companyUID ?? "all"}';
    return _permissionsCache[key];
  }

  /// Synchronously returns cached ongoing permissions if available in memory.
  static List<PhotoPermission>? getCachedOngoingPermissionsSync({
    required String organizationUID,
  }) {
    return _ongoingCache[organizationUID];
  }

  static List<PhotoPermission> _deduplicatePermissions(List<PhotoPermission> list) {
    final seen = <String>{};
    final result = <PhotoPermission>[];
    for (final p in list) {
      final key = p.uid.isNotEmpty
          ? '${p.companyUID}_${p.uid}'
          : '${p.companyUID}_${p.createdAt.millisecondsSinceEpoch}';
      if (seen.add(key)) {
        result.add(p);
      }
    }
    return result;
  }

  static Future<List<PhotoPermission>?> _loadDiskCache(String storageKey) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final raw = prefs.getString(storageKey);
      if (raw == null || raw.isEmpty) return null;
      final decoded = jsonDecode(raw) as List<dynamic>;
      return decoded
          .map((e) => PhotoPermissionModel.fromJson(Map<String, dynamic>.from(e as Map)))
          .toList();
    } catch (_) {
      return null;
    }
  }

  static Future<void> _saveDiskCache(
    String storageKey,
    List<PhotoPermission> permissions, {
    String? organizationUIDForMetrics,
  }) async {
    try {
      final prefs = await SharedPreferences.getInstance();
      final capped = permissions.take(100).map((p) => PhotoPermissionModel.fromEntity(p).toJson()).toList();
      await prefs.setString(storageKey, jsonEncode(capped));

      if (organizationUIDForMetrics != null && organizationUIDForMetrics.isNotEmpty) {
        final now = DateTime.now();
        int pending = 0;
        int active = 0;
        for (final p in permissions) {
          if (p.status == 'pending') {
            pending++;
          } else if (p.status == 'approved' && !now.isAfter(p.endDate)) {
            active++;
          }
        }
        await prefs.setInt('photo_permissions_pending_count_$organizationUIDForMetrics', pending);
        await prefs.setInt('photo_permissions_active_count_$organizationUIDForMetrics', active);
      }
    } catch (_) {}
  }

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
  final UpdatePhotoPermissionDates updatePhotoPermissionDates;

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
    required this.updatePhotoPermissionDates,
  }) : super(PhotoPermissionInitial()) {
    on<RequestPermissionRequested>(_onRequestPermission);
    on<LoadPermissionsRequested>(_onLoadPermissions);
    on<LoadOngoingPermissionsRequested>(_onLoadOngoingPermissions);
    on<ApprovePermissionRequested>(_onApprovePermission);
    on<TogglePermissionRequested>(_onTogglePermission);
    on<UploadPhotoRequested>(_onUploadPhoto);
    on<UploadBatchPhotosRequested>(_onUploadBatchPhotos);
    on<LoadCapturedPhotosRequested>(_onLoadCapturedPhotos);
    on<LoadDelegateCapturedPhotosRequested>(_onLoadDelegateCapturedPhotos);
    on<LoadCompanyCapturedPhotosRequested>(_onLoadCompanyCapturedPhotos);
    on<DeleteCapturedPhotoRequested>(_onDeleteCapturedPhoto);
    on<DeletePhotoPermissionRequested>(_onDeletePhotoPermission);
    on<UpdatePhotoPermissionBranchesRequested>(_onUpdatePhotoPermissionBranches);
    on<UpdatePhotoPermissionDatesRequested>(_onUpdatePhotoPermissionDates);
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
        department: event.department,
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
    final cacheKey =
        '${event.organizationUID}_${event.companyUID.isEmpty ? "all" : event.companyUID}';
    final storageKey = 'photo_permissions_cache_v1_$cacheKey';
    bool hasEmittedCache = false;

    // 1. Instant 0ms In-Memory Cache Emit
    final memCached = _permissionsCache[cacheKey];
    if (memCached != null && memCached.isNotEmpty) {
      emit(PhotoPermissionsLoaded(permissions: memCached));
      hasEmittedCache = true;
    } else {
      // 2. Persistent Disk Cache (SharedPreferences) Emit
      final diskCached = await _loadDiskCache(storageKey);
      if (diskCached != null && diskCached.isNotEmpty) {
        final deduped = _deduplicatePermissions(diskCached);
        _permissionsCache[cacheKey] = deduped;
        emit(PhotoPermissionsLoaded(permissions: deduped));
        hasEmittedCache = true;
      }
    }

    if (!hasEmittedCache) {
      emit(PhotoPermissionLoading());
    }

    // 3. Stale-While-Revalidate Background Network Fetch
    final result = await getPhotoPermissions(
      GetPhotoPermissionsParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
      ),
    );
    await result.fold(
      (failure) async {
        if (!hasEmittedCache) {
          emit(PhotoPermissionError(message: failure.message));
        }
      },
      (permissions) async {
        final deduped = _deduplicatePermissions(permissions);
        _permissionsCache[cacheKey] = deduped;
        await _saveDiskCache(
          storageKey,
          deduped,
          organizationUIDForMetrics:
              event.companyUID.isEmpty ? event.organizationUID : null,
        );
        emit(PhotoPermissionsLoaded(permissions: deduped));
      },
    );
  }

  Future<void> _onLoadOngoingPermissions(
    LoadOngoingPermissionsRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    final cacheKey = event.organizationUID;
    final storageKey = 'ongoing_photo_permissions_cache_v1_$cacheKey';
    bool hasEmittedCache = false;

    // 1. Instant 0ms In-Memory Cache Emit
    final memCached = _ongoingCache[cacheKey];
    if (memCached != null && memCached.isNotEmpty) {
      emit(OngoingPermissionsLoaded(permissions: memCached));
      hasEmittedCache = true;
    } else {
      // 2. Persistent Disk Cache (SharedPreferences) Emit
      final diskCached = await _loadDiskCache(storageKey);
      if (diskCached != null && diskCached.isNotEmpty) {
        final deduped = _deduplicatePermissions(diskCached);
        _ongoingCache[cacheKey] = deduped;
        emit(OngoingPermissionsLoaded(permissions: deduped));
        hasEmittedCache = true;
      }
    }

    if (!hasEmittedCache) {
      emit(PhotoPermissionLoading());
    }

    // 3. Stale-While-Revalidate Background Network Fetch
    final result = await getOngoingPhotoPermissions(
      GetOngoingPhotoPermissionsParams(
        organizationUID: event.organizationUID,
      ),
    );
    await result.fold(
      (failure) async {
        if (!hasEmittedCache) {
          emit(PhotoPermissionError(message: failure.message));
        }
      },
      (permissions) async {
        final deduped = _deduplicatePermissions(permissions);
        _ongoingCache[cacheKey] = deduped;
        await _saveDiskCache(storageKey, deduped);
        emit(OngoingPermissionsLoaded(permissions: deduped));
      },
    );
  }

  void _updateCachedPermission(PhotoPermission updated) {
    for (final key in _permissionsCache.keys.toList()) {
      final list = _permissionsCache[key];
      if (list != null) {
        final next = list
            .map((p) => (p.uid == updated.uid && p.companyUID == updated.companyUID) ? updated : p)
            .toList();
        _permissionsCache[key] = next;
        _saveDiskCache('photo_permissions_cache_v1_$key', next);
      }
    }
    for (final key in _ongoingCache.keys.toList()) {
      final list = _ongoingCache[key];
      if (list != null) {
        final next = list
            .map((p) => (p.uid == updated.uid && p.companyUID == updated.companyUID) ? updated : p)
            .toList();
        _ongoingCache[key] = next;
        _saveDiskCache('ongoing_photo_permissions_cache_v1_$key', next);
      }
    }
  }

  void _updateCachedPermissionBranches({
    required String companyUID,
    required String permissionId,
    required List<String> branchIds,
    required List<String> branchNames,
  }) {
    PhotoPermission mapItem(PhotoPermission p) {
      if (p.uid == permissionId && (companyUID.isEmpty || p.companyUID == companyUID)) {
        return PhotoPermissionModel(
          uid: p.uid,
          organizationUID: p.organizationUID,
          companyUID: p.companyUID,
          companyName: p.companyName,
          companyCode: p.companyCode,
          branchIds: branchIds,
          branchNames: branchNames,
          startDate: p.startDate,
          endDate: p.endDate,
          status: p.status,
          requestedBy: p.requestedBy,
          approvedBy: p.approvedBy,
          createdAt: p.createdAt,
          updatedAt: DateTime.now(),
          isSupervisorEnabled: p.isSupervisorEnabled,
          department: p.department,
        );
      }
      return p;
    }

    for (final key in _permissionsCache.keys.toList()) {
      final list = _permissionsCache[key];
      if (list != null) {
        final next = list.map(mapItem).toList();
        _permissionsCache[key] = next;
        _saveDiskCache('photo_permissions_cache_v1_$key', next);
      }
    }
    for (final key in _ongoingCache.keys.toList()) {
      final list = _ongoingCache[key];
      if (list != null) {
        final next = list.map(mapItem).toList();
        _ongoingCache[key] = next;
        _saveDiskCache('ongoing_photo_permissions_cache_v1_$key', next);
      }
    }
  }

  void _updateCachedPermissionDates({
    required String companyUID,
    required String permissionId,
    required DateTime startDate,
    required DateTime endDate,
  }) {
    PhotoPermission mapItem(PhotoPermission p) {
      if (p.uid == permissionId && (companyUID.isEmpty || p.companyUID == companyUID)) {
        return PhotoPermissionModel(
          uid: p.uid,
          organizationUID: p.organizationUID,
          companyUID: p.companyUID,
          companyName: p.companyName,
          companyCode: p.companyCode,
          branchIds: p.branchIds,
          branchNames: p.branchNames,
          startDate: startDate,
          endDate: endDate,
          status: p.status,
          requestedBy: p.requestedBy,
          approvedBy: p.approvedBy,
          createdAt: p.createdAt,
          updatedAt: DateTime.now(),
          isSupervisorEnabled: p.isSupervisorEnabled,
          department: p.department,
        );
      }
      return p;
    }

    for (final key in _permissionsCache.keys.toList()) {
      final list = _permissionsCache[key];
      if (list != null) {
        final next = list.map(mapItem).toList();
        _permissionsCache[key] = next;
        _saveDiskCache('photo_permissions_cache_v1_$key', next);
      }
    }
    for (final key in _ongoingCache.keys.toList()) {
      final list = _ongoingCache[key];
      if (list != null) {
        final next = list.map(mapItem).toList();
        _ongoingCache[key] = next;
        _saveDiskCache('ongoing_photo_permissions_cache_v1_$key', next);
      }
    }
  }

  void _removeCachedPermission(String companyUID, String permissionId) {
    for (final key in _permissionsCache.keys.toList()) {
      final list = _permissionsCache[key];
      if (list != null) {
        final next = list
            .where((p) => !(p.uid == permissionId && (companyUID.isEmpty || p.companyUID == companyUID)))
            .toList();
        _permissionsCache[key] = next;
        _saveDiskCache('photo_permissions_cache_v1_$key', next);
      }
    }
    for (final key in _ongoingCache.keys.toList()) {
      final list = _ongoingCache[key];
      if (list != null) {
        final next = list
            .where((p) => !(p.uid == permissionId && (companyUID.isEmpty || p.companyUID == companyUID)))
            .toList();
        _ongoingCache[key] = next;
        _saveDiskCache('ongoing_photo_permissions_cache_v1_$key', next);
      }
    }
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
      (permission) {
        _updateCachedPermission(permission);
        emit(
          PermissionActionSuccess(
            permission: permission,
            message: event.status == 'approved'
                ? 'تمت الموافقة على إذن التصوير وتفعيله بنجاح.'
                : 'تم رفض طلب إذن التصوير.',
          ),
        );
      },
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
      (permission) {
        _updateCachedPermission(permission);
        emit(
          PermissionActionSuccess(
            permission: permission,
            message: event.isEnabled
                ? 'تم تفعيل إذن التصوير بنجاح للمناديب.'
                : 'تم إيقاف/تجميد إذن التصوير مؤقتاً.',
          ),
        );
      },
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
            companyName: event.companyName,
            companyCode: event.companyCode,
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
        'companyName': event.companyName,
        'companyCode': event.companyCode,
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
        companyName: event.companyName,
        companyCode: event.companyCode,
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

  Future<void> _onUploadBatchPhotos(
    UploadBatchPhotosRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    if (event.imageFiles.isEmpty) {
      emit(const PhotoPermissionError(message: 'يرجى التقاط صورة واحدة على الأقل قبل الحفظ.'));
      return;
    }

    final total = event.imageFiles.length;
    emit(PhotoBatchUploadInProgress(current: 0, total: total));

    bool isConnected = false;
    try {
      final connectivityResults = await Connectivity().checkConnectivity();
      isConnected = connectivityResults.any((r) =>
          r == ConnectivityResult.mobile ||
          r == ConnectivityResult.wifi ||
          r == ConnectivityResult.ethernet);
    } catch (_) {
      isConnected = true;
    }

    int processedCount = 0;
    int offlineCount = 0;

    for (int i = 0; i < total; i++) {
      final file = event.imageFiles[i];
      emit(PhotoBatchUploadInProgress(current: i + 1, total: total));

      bool photoUploaded = false;

      if (isConnected) {
        try {
          final result = await uploadCapturedPhoto(
            UploadCapturedPhotoParams(
              organizationUID: event.organizationUID,
              companyUID: event.companyUID,
              companyName: event.companyName,
              companyCode: event.companyCode,
              permissionId: event.permissionId,
              branchId: event.branchId,
              branchName: event.branchName,
              delegateUID: event.delegateUID,
              delegateName: event.delegateName,
              imageFile: file,
              comment: event.comment,
              latitude: event.latitude,
              longitude: event.longitude,
            ),
          );

          if (result.isRight()) {
            photoUploaded = true;
            processedCount++;
          }
        } catch (_) {
          // If upload fails mid-batch, fallback to offline persistence for this photo
          photoUploaded = false;
        }
      }

      if (!photoUploaded) {
        try {
          final offlineDataSource = GetIt.I<PhotoOfflineDataSource>();
          final persistentImagePath =
              await offlineDataSource.saveImageToPersistentDirectory(file);

          await offlineDataSource.savePendingPhoto({
            'organizationUID': event.organizationUID,
            'companyUID': event.companyUID,
            'companyName': event.companyName,
            'companyCode': event.companyCode,
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

          offlineCount++;
          processedCount++;
        } catch (_) {
          // Continue to attempt saving remaining photos
        }
      }
    }

    if (offlineCount > 0) {
      try {
        GetIt.I<SyncManager>().syncPendingPhotos();
      } catch (_) {}
    }

    if (processedCount > 0) {
      emit(PhotoBatchUploadSuccess(
        uploadedCount: processedCount,
        isOffline: offlineCount > 0,
      ));
    } else {
      emit(const PhotoPermissionError(message: 'فشل في رفع وحفظ الصور، يرجى المحاولة مرة أخرى.'));
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
      GetCompanyCapturedPhotosParams(
        companyUID: event.companyUID,
        branchName: event.branchName,
        limit: event.limit,
      ),
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
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
        photoUrl: event.photoUrl,
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
      (_) {
        _removeCachedPermission(event.companyUID, event.permissionId);
        emit(const PhotoPermissionActionSuccess(message: 'تم حذف إذن التصوير بنجاح.'));
      },
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
      (_) {
        _updateCachedPermissionBranches(
          companyUID: event.companyUID,
          permissionId: event.permissionId,
          branchIds: event.branchIds,
          branchNames: event.branchNames,
        );
        emit(const PhotoPermissionActionSuccess(message: 'تم تعديل الفروع بنجاح'));
      },
    );
  }

  Future<void> _onUpdatePhotoPermissionDates(
    UpdatePhotoPermissionDatesRequested event,
    Emitter<PhotoPermissionState> emit,
  ) async {
    emit(PhotoPermissionLoading());
    final result = await updatePhotoPermissionDates(
      UpdatePhotoPermissionDatesParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        permissionId: event.permissionId,
        startDate: event.startDate,
        endDate: event.endDate,
      ),
    );
    result.fold(
      (failure) => emit(PhotoPermissionError(message: failure.message)),
      (_) {
        _updateCachedPermissionDates(
          companyUID: event.companyUID,
          permissionId: event.permissionId,
          startDate: event.startDate,
          endDate: event.endDate,
        );
        emit(const PhotoPermissionActionSuccess(message: 'تم تعديل تاريخ صلاحية إذن التصوير بنجاح'));
      },
    );
  }
}

