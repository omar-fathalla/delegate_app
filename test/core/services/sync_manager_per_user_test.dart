import 'dart:io';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/sync_manager.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/models/captured_photo_model.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockRemote extends Mock implements PhotoPermissionRemoteDataSource {}

/// In-memory queue with the same contract as the SQLite one.
class _FakeQueue extends PhotoOfflineDataSource {
  final rows = <Map<String, dynamic>>[];
  final failures = <int, int>{};

  @override
  Future<List<Map<String, dynamic>>> getPendingPhotos() async => rows;

  @override
  Future<List<Map<String, dynamic>>> getPendingPhotosForDelegates(Set<String> ids) async => rows
      .where((r) => ids.contains(r['delegateUID']))
      .map((r) => {...r, 'attempts': failures[r['id']] ?? 0})
      .toList();

  @override
  Future<void> recordFailure(int id, String error, {required bool countAttempt}) async {
    if (countAttempt) failures[id] = (failures[id] ?? 0) + 1;
  }

  @override
  Future<void> resetAttempts(Set<String> ids) async => failures.clear();

  @override
  Future<void> deletePendingPhoto(int id) async => rows.removeWhere((r) => r['id'] == id);
}

/// TAS-369: the photo queue belongs to the delegate who took the photos.
void main() {
  late Directory tmp;
  late _FakeQueue queue;
  late _MockRemote remote;

  Map<String, dynamic> row(int id, String owner) {
    final f = File('${tmp.path}/p$id.jpg')..writeAsBytesSync([1, 2, 3]);
    return {
      'id': id,
      'organizationUID': 'o1',
      'companyUID': 'c1',
      'permissionId': 'perm',
      'branchId': 'b1',
      'branchName': 'Fake Alpha',
      'delegateUID': owner,
      'delegateName': owner,
      'imagePath': f.path,
      'comment': '',
      'latitude': 0.0,
      'longitude': 0.0,
      'timestamp': id,
    };
  }

  setUpAll(() => registerFallbackValue(File('x')));

  setUp(() {
    tmp = Directory.systemTemp.createTempSync('tas369');
    queue = _FakeQueue();
    remote = _MockRemote();
  });

  tearDown(() => tmp.deleteSync(recursive: true));

  void uploadsOk() => when(() => remote.uploadPhoto(
        organizationUID: any(named: 'organizationUID'),
        companyUID: any(named: 'companyUID'),
        companyName: any(named: 'companyName'),
        companyCode: any(named: 'companyCode'),
        permissionId: any(named: 'permissionId'),
        branchId: any(named: 'branchId'),
        branchName: any(named: 'branchName'),
        delegateUID: any(named: 'delegateUID'),
        delegateName: any(named: 'delegateName'),
        imageFile: any(named: 'imageFile'),
        comment: any(named: 'comment'),
        latitude: any(named: 'latitude'),
        longitude: any(named: 'longitude'),
      )).thenAnswer((_) async => _FakePhoto());

  test('uploads only the signed-in delegate rows; a colleague rows stay', () async {
    queue.rows.addAll([row(1, 'del-1'), row(2, 'del-2')]);
    uploadsOk();
    final sync = SyncManager(offlineDataSource: queue, remoteDataSource: remote, isBackground: true,
        selfIds: () => {'del-1'});
    await sync.syncPendingPhotos();
    expect(queue.rows.map((r) => r['id']), [2], reason: 'del-2 photo waits for its owner');
    expect(sync.statusNotifier.value.pendingCount, 0, reason: 'the count is per user');
  });

  test('signed out: nothing uploads, nothing is deleted', () async {
    queue.rows.addAll([row(1, 'del-1')]);
    final sync = SyncManager(offlineDataSource: queue, remoteDataSource: remote, isBackground: true,
        selfIds: () => <String>{});
    await sync.syncPendingPhotos();
    expect(queue.rows, hasLength(1));
    verifyNever(() => remote.uploadPhoto(
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
          permissionId: any(named: 'permissionId'),
          branchId: any(named: 'branchId'),
          branchName: any(named: 'branchName'),
          delegateUID: any(named: 'delegateUID'),
          delegateName: any(named: 'delegateName'),
          imageFile: any(named: 'imageFile'),
          comment: any(named: 'comment'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        ));
  });

  test('permission-denied counts toward the limit; then the row waits for retry', () async {
    queue.rows.add(row(1, 'del-1'));
    when(() => remote.uploadPhoto(
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
          companyName: any(named: 'companyName'),
          companyCode: any(named: 'companyCode'),
          permissionId: any(named: 'permissionId'),
          branchId: any(named: 'branchId'),
          branchName: any(named: 'branchName'),
          delegateUID: any(named: 'delegateUID'),
          delegateName: any(named: 'delegateName'),
          imageFile: any(named: 'imageFile'),
          comment: any(named: 'comment'),
          latitude: any(named: 'latitude'),
          longitude: any(named: 'longitude'),
        )).thenThrow(FirebaseException(plugin: 'cloud_firestore', code: 'permission-denied'));
    final sync = SyncManager(offlineDataSource: queue, remoteDataSource: remote, isBackground: true,
        selfIds: () => {'del-1'});
    for (var i = 0; i < kPhotoSyncMaxAttempts + 2; i++) {
      await sync.syncPendingPhotos();
    }
    expect(queue.failures[1], kPhotoSyncMaxAttempts, reason: 'stops retrying at the limit');
    expect(sync.statusNotifier.value.failedCount, 1);
    expect(queue.rows, hasLength(1), reason: 'never deleted');

    uploadsOk();
    await sync.retryFailed();
    expect(queue.rows, isEmpty);
  });

  test('network errors do not count', () {
    expect(photoSyncErrorCounts(FirebaseException(plugin: 'x', code: 'unavailable')), isFalse);
    expect(photoSyncErrorCounts(const SocketException('offline')), isFalse);
    expect(photoSyncErrorCounts(FirebaseException(plugin: 'x', code: 'permission-denied')), isTrue);
  });

  test('queue migration v2 -> v3 adds the new columns and keeps the rows', () {
    final v2 = PhotoOfflineDataSource.upgradeStatements(2);
    expect(v2, hasLength(4));
    expect(v2.every((s) => s.startsWith('ALTER TABLE pending_photos ADD COLUMN')), isTrue);
    expect(v2.join(), allOf(contains('capturedAtMs'), contains('watermarkFailed'), contains('attempts'), contains('lastError')));
    expect(PhotoOfflineDataSource.upgradeStatements(1), hasLength(6));
    expect(PhotoOfflineDataSource.upgradeStatements(3), isEmpty);
    expect(PhotoOfflineDataSource.schemaVersion, 3);
  });
}

class _FakePhoto extends Fake implements CapturedPhotoModel {}
