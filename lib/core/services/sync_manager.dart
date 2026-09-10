import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:flutter/foundation.dart';
import 'photo_cache_manager.dart';

class SyncState {
  final int pendingCount;
  final bool isSyncing;
  final int syncedCount;
  final int totalToSync;

  const SyncState({
    this.pendingCount = 0,
    this.isSyncing = false,
    this.syncedCount = 0,
    this.totalToSync = 0,
  });

  SyncState copyWith({
    int? pendingCount,
    bool? isSyncing,
    int? syncedCount,
    int? totalToSync,
  }) {
    return SyncState(
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      syncedCount: syncedCount ?? this.syncedCount,
      totalToSync: totalToSync ?? this.totalToSync,
    );
  }
}

class SyncManager {
  final PhotoOfflineDataSource offlineDataSource;
  final PhotoPermissionRemoteDataSource remoteDataSource;
  StreamSubscription? _connectivitySubscription;
  final ValueNotifier<SyncState> statusNotifier = ValueNotifier(const SyncState());

  SyncManager({
    required this.offlineDataSource,
    required this.remoteDataSource,
  }) {
    refreshPendingCount();

    // Listen for internet connection restoration when the app is in foreground
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        syncPendingPhotos();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    statusNotifier.dispose();
  }

  Future<void> refreshPendingCount() async {
    try {
      final pending = await offlineDataSource.getPendingPhotos();
      statusNotifier.value = statusNotifier.value.copyWith(
        pendingCount: pending.length,
      );
    } catch (_) {}
  }

  Future<void> syncPendingPhotos() async {
    if (statusNotifier.value.isSyncing) return;

    try {
      final pendingPhotos = await offlineDataSource.getPendingPhotos();

      if (pendingPhotos.isEmpty) {
        statusNotifier.value = const SyncState(pendingCount: 0, isSyncing: false);
        return;
      }

      final total = pendingPhotos.length;
      statusNotifier.value = statusNotifier.value.copyWith(
        isSyncing: true,
        pendingCount: total,
        totalToSync: total,
        syncedCount: 0,
      );

      debugPrint('SyncManager: Found $total pending photos to sync.');

      int completed = 0;
      for (var photoData in pendingPhotos) {
        final id = photoData['id'] as int;
        try {
          File? file = await PhotoCacheManager.resolveLocalPhotoFile(photoData['imagePath']);
          file ??= File(photoData['imagePath']);
          if (!await file.exists()) {
            debugPrint('SyncManager: File not found for pending photo ID $id. Deleting record.');
            await offlineDataSource.deletePendingPhoto(id);
            completed++;
            statusNotifier.value = statusNotifier.value.copyWith(
              syncedCount: completed,
              pendingCount: total - completed,
            );
            continue;
          }

          // Attempt to upload
          await remoteDataSource.uploadPhoto(
            organizationUID: photoData['organizationUID'],
            companyUID: photoData['companyUID'],
            companyName: (photoData['companyName'] as String?) ?? '',
            companyCode: photoData['companyCode'] as int?,
            permissionId: photoData['permissionId'],
            branchId: photoData['branchId'],
            branchName: photoData['branchName'],
            delegateUID: photoData['delegateUID'],
            delegateName: photoData['delegateName'],
            imageFile: file,
            comment: photoData['comment'] ?? '',
            latitude: photoData['latitude'] ?? 0.0,
            longitude: photoData['longitude'] ?? 0.0,
          );

          // If upload succeeds, delete the local record and the local file
          await offlineDataSource.deletePendingPhoto(id);
          try {
            await file.delete();
          } catch (e) {
            debugPrint('SyncManager: Failed to delete local image file after sync: $e');
          }
          completed++;
          statusNotifier.value = statusNotifier.value.copyWith(
            syncedCount: completed,
            pendingCount: total - completed,
          );
          debugPrint('SyncManager: Successfully synced photo ID $id');
        } catch (e) {
          debugPrint('SyncManager: Failed to sync photo ID $id: $e');
          // Will try again next time since we don't delete from SQLite on upload failure
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Error in sync process: $e');
    } finally {
      final remaining = await offlineDataSource.getPendingPhotos();
      statusNotifier.value = SyncState(
        pendingCount: remaining.length,
        isSyncing: false,
        syncedCount: 0,
        totalToSync: 0,
      );
    }
  }
}
