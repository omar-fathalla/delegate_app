import 'dart:async';
import 'dart:io';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/security/delegate_identity.dart';
import 'package:flutter/foundation.dart';
import 'photo_cache_manager.dart';

class SyncState {
  final int pendingCount;
  final bool isSyncing;
  final int syncedCount;
  final int totalToSync;

  /// TAS-369: rows that hit the attempt limit; they wait for «إعادة المحاولة».
  final int failedCount;

  const SyncState({
    this.pendingCount = 0,
    this.isSyncing = false,
    this.syncedCount = 0,
    this.totalToSync = 0,
    this.failedCount = 0,
  });

  SyncState copyWith({
    int? pendingCount,
    bool? isSyncing,
    int? syncedCount,
    int? totalToSync,
    int? failedCount,
  }) {
    return SyncState(
      pendingCount: pendingCount ?? this.pendingCount,
      isSyncing: isSyncing ?? this.isSyncing,
      syncedCount: syncedCount ?? this.syncedCount,
      totalToSync: totalToSync ?? this.totalToSync,
      failedCount: failedCount ?? this.failedCount,
    );
  }
}

/// TAS-369: after this many counted failures a row stops retrying on its
/// own (network errors are not counted).
const int kPhotoSyncMaxAttempts = 5;

/// True when retrying will not help (rules refused, bad data), so the
/// attempt counts toward [kPhotoSyncMaxAttempts].
bool photoSyncErrorCounts(Object error) {
  if (error is FirebaseException) {
    return const {'permission-denied', 'invalid-argument', 'failed-precondition', 'not-found'}
        .contains(error.code);
  }
  return false;
}

class SyncManager {
  final PhotoOfflineDataSource offlineDataSource;
  final PhotoPermissionRemoteDataSource remoteDataSource;
  StreamSubscription? _connectivitySubscription;
  final ValueNotifier<SyncState> statusNotifier = ValueNotifier(const SyncState());

  /// Ids of the signed-in delegate (uid + delegateId claim). Empty = signed
  /// out: nothing is uploaded and the rows wait for their owner (TAS-369).
  final Set<String> Function() _selfIds;

  SyncManager({
    required this.offlineDataSource,
    required this.remoteDataSource,
    bool isBackground = false,
    Set<String> Function()? selfIds,
  }) : _selfIds = selfIds ?? DelegateIdentity.selfIds {
    refreshPendingCount();

    if (!isBackground) {
      // Listen for internet connection restoration when the app is in foreground
      _connectivitySubscription = Connectivity().onConnectivityChanged.listen((List<ConnectivityResult> results) {
        if (results.contains(ConnectivityResult.mobile) || results.contains(ConnectivityResult.wifi)) {
          syncPendingPhotos();
        }
      });
    }
  }

  void dispose() {
    _connectivitySubscription?.cancel();
    statusNotifier.dispose();
  }

  Future<List<Map<String, dynamic>>> _mine() =>
      offlineDataSource.getPendingPhotosForDelegates(_selfIds());

  static int _attempts(Map<String, dynamic> row) => (row['attempts'] as int?) ?? 0;

  Future<void> refreshPendingCount() async {
    try {
      final pending = await _mine();
      statusNotifier.value = statusNotifier.value.copyWith(
        pendingCount: pending.length,
        failedCount: pending.where((r) => _attempts(r) >= kPhotoSyncMaxAttempts).length,
      );
    } catch (_) {}
  }

  /// «فشلت، اضغط لإعادة المحاولة»: clears the attempt counter, then syncs.
  Future<void> retryFailed() async {
    await offlineDataSource.resetAttempts(_selfIds());
    await syncPendingPhotos();
  }

  Future<void> syncPendingPhotos() async {
    if (statusNotifier.value.isSyncing) return;

    try {
      // TAS-369: the signed-in delegate's rows only, and not the ones that
      // already failed too often (they wait for «إعادة المحاولة»).
      final pendingPhotos = (await _mine())
          .where((r) => _attempts(r) < kPhotoSyncMaxAttempts)
          .toList();

      if (pendingPhotos.isEmpty) {
        await refreshPendingCount();
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

          // Attempt to upload with strict timeout
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
          ).timeout(const Duration(seconds: 12));

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
          // Kept for the next try; a non-network error counts toward the limit.
          try {
            await offlineDataSource.recordFailure(id, '$e', countAttempt: photoSyncErrorCounts(e));
          } catch (_) {}
        }
      }
    } catch (e) {
      debugPrint('SyncManager: Error in sync process: $e');
    } finally {
      List<Map<String, dynamic>> remaining = const [];
      try {
        remaining = await _mine();
      } catch (_) {}
      statusNotifier.value = SyncState(
        pendingCount: remaining.length,
        isSyncing: false,
        syncedCount: 0,
        totalToSync: 0,
        failedCount: remaining.where((r) => _attempts(r) >= kPhotoSyncMaxAttempts).length,
      );
    }
  }
}
