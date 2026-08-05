import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:flutter/foundation.dart';

class SyncManager {
  final PhotoOfflineDataSource offlineDataSource;
  final PhotoPermissionRemoteDataSource remoteDataSource;
  StreamSubscription? _connectivitySubscription;
  bool _isSyncing = false;

  SyncManager({
    required this.offlineDataSource,
    required this.remoteDataSource,
  }) {
    // Listen for internet connection restoration when the app is in foreground
    _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
      if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
        syncPendingPhotos();
      }
    });
  }

  void dispose() {
    _connectivitySubscription?.cancel();
  }

  Future<void> syncPendingPhotos() async {
    if (_isSyncing) return;
    _isSyncing = true;

    try {
      final pendingPhotos = await offlineDataSource.getPendingPhotos();
      
      if (pendingPhotos.isEmpty) {
        _isSyncing = false;
        return;
      }

      debugPrint('SyncManager: Found ${pendingPhotos.length} pending photos to sync.');

      for (var photoData in pendingPhotos) {
        final id = photoData['id'] as int;
        
        try {
          final file = File(photoData['imagePath']);
          if (!await file.exists()) {
            debugPrint('SyncManager: File not found for pending photo ID $id. Deleting record.');
            await offlineDataSource.deletePendingPhoto(id);
            continue;
          }

          // Attempt to upload
          await remoteDataSource.uploadPhoto(
            organizationUID: photoData['organizationUID'],
            companyUID: photoData['companyUID'],
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
          debugPrint('SyncManager: Successfully synced photo ID $id');
        } catch (e) {
          debugPrint('SyncManager: Failed to sync photo ID $id: $e');
          // Will try again next time since we don't delete from SQLite on upload failure
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Error in sync process: $e');
    } finally {
      _isSyncing = false;
    }
  }
}
