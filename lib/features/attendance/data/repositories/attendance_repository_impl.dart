import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance_pagination_result.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:delegate_app/core/attendance/attendance_branch_resolve.dart';
import 'package:delegate_app/features/admin/data/models/branch_model.dart';
import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:delegate_app/core/services/trusted_time_anchor.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_server_api.dart';
import 'package:delegate_app/features/attendance/data/datasources/offline_branch_cache.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:geolocator/geolocator.dart';
import 'package:uuid/uuid.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  final AttendanceRemoteDataSource remoteDataSource;
  final AttendanceLocalDataSource localDataSource;
  final AttendanceOfflineQueue offlineQueue;

  /// TAS-363: branch coordinates for the geofence without network.
  final OfflineBranchCache? branchCache;

  final OfflineTimeCapture Function()? _captureTime;
  final Future<bool> Function()? _connectionCheck;
  final String Function() _newId;

  AttendanceRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.offlineQueue,
    this.branchCache,
    OfflineTimeCapture Function()? captureTime,
    Future<bool> Function()? hasConnection,
    String Function()? newId,
  }) : _captureTime = captureTime,
       _connectionCheck = hasConnection,
       _newId = newId ?? (() => const Uuid().v4());

  OfflineTimeCapture _offlineTime() {
    final capture = _captureTime;
    if (capture != null) return capture();
    try {
      if (sl.isRegistered<TrustedTimeService>()) {
        return sl<TrustedTimeService>().captureOfflineTime();
      }
    } catch (_) {}
    return OfflineTimeCapture(
      atMs: DateTime.now().millisecondsSinceEpoch,
      trusted: false,
      issue: OfflineTimeIssue.noSync,
    );
  }

  Future<bool> _hasConnection() async {
    final check = _connectionCheck;
    if (check != null) return check();
    try {
      final result = await Connectivity().checkConnectivity();
      return !result.contains(ConnectivityResult.none);
    } catch (_) {
      return true; // Default to true if check fails
    }
  }

  /// Validates that the user is within the geofence radius of the given branch.
  /// Uses [BranchModel.fromMap] for data parsing (Separation of Concerns).
  Future<void> _verifyGeofence({
    required double userLat,
    required double userLong,
    required AttendanceBranchRef branchRef,
    required bool isCheckIn,
  }) async {
    final resolved = await remoteDataSource.resolveBranch(
      branchId: branchRef.branchId,
      organizationUID: branchRef.branchOrganizationUID,
      branchName: branchRef.branchName,
    );
    if (resolved == null) {
      throw const ServerFailure(
        'لم يتم العثور على بيانات الفرع. يرجى التأكد من الرمز.',
      );
    }

    final branch = branchModelFromResolvedMap(
      resolved.data,
      documentId: resolved.documentId,
    );
    try {
      await branchCache?.save(
        branchRef.branchOrganizationUID,
        branch.id.trim().isNotEmpty ? branch.id : branchRef.branchId,
        CachedBranchLocation(
          branchName: branchRef.branchName,
          latitude: branch.latitude,
          longitude: branch.longitude,
          geofenceRadius: branch.geofenceRadius,
        ),
      );
    } catch (_) {}

    if (branch.latitude == 0.0 && branch.longitude == 0.0) {
      throw ServerFailure(
        'بيانات إحداثيات الفرع (${branchRef.branchName}) غير مكتملة في النظام. يرجى إبلاغ الإدارة.',
      );
    }

    final double distance = Geolocator.distanceBetween(
      userLat,
      userLong,
      branch.latitude,
      branch.longitude,
    );

    // تم إضافة 50 متر كمسافة احتياطية لمعالجة عدم دقة الـ GPS داخل المباني
    final double allowedRadius = branch.geofenceRadius + 50.0;

    if (distance > allowedRadius) {
      final action = isCheckIn ? 'تسجيل الحضور' : 'تسجيل الانصراف';
      throw ServerFailure(
        'أنت خارج نطاق الفرع (${distance.toInt()} متر). '
        'النطاق المسموح: ${allowedRadius.toInt()} متر لـ$action.',
      );
    }
  }

  @override
  Future<Either<Failure, Attendance>> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
    String? branchId,
    String? branchOrganizationUID,
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
  }) async {
    final offlineArgs = _OfflineCheckInArgs(
      userId: userId,
      lat: lat,
      long: long,
      companyId: companyId,
      organizationId: organizationId,
      deviceInfo: deviceInfo,
      branchName: branchName,
      branchId: branchId,
      branchOrganizationUID: branchOrganizationUID,
      delegateName: delegateName,
      phoneNumber: phoneNumber,
      companyName: companyName,
      personalPhotoURL: personalPhotoURL,
    );
    try {
      // TAS-363: without network the check-in is saved on the phone and
      // sent through delegateCheckIn when the network is back.
      if (!await _hasConnection()) {
        return Right(await _saveOfflineCheckIn(offlineArgs));
      }
      // A check-in saved offline and not sent yet must go first, or the
      // server would see no open session.
      if (offlineQueue.pendingCount(userId) > 0) {
        await syncPendingAttendance(userId: userId);
        if (offlineQueue.pending(userId).any((a) => a.isCheckIn)) {
          return Right(await _saveOfflineCheckIn(offlineArgs));
        }
      }

      // --- Anti-Fraud Geofencing ---
      if (branchName != null) {
        await _verifyGeofence(
          userLat: lat,
          userLong: long,
          branchRef: AttendanceBranchRef(
            branchId: branchId,
            branchOrganizationUID:
                (branchOrganizationUID ?? organizationId).trim(),
            branchName: branchName,
          ),
          isCheckIn: true,
        );
      }

      final result = await remoteDataSource.checkIn(
        userId,
        lat,
        long,
        companyId: companyId,
        organizationId: organizationId,
        deviceInfo: deviceInfo,
        branchName: branchName,
        branchId: branchId,
        branchOrganizationUID: branchOrganizationUID,
        delegateName: delegateName,
        phoneNumber: phoneNumber,
        companyName: companyName,
        personalPhotoURL: personalPhotoURL,
      );
      // Always cache attendance after successful remote write
      await localDataSource.cacheAttendance(result, organizationId, userId);
      return Right(result);
    } on Failure catch (e) {
      // The server could not be reached before anything was written: save
      // it on the phone instead (TAS-363).
      if (e.message == kCheckInOfflineMessage) {
        try {
          return Right(await _saveOfflineCheckIn(offlineArgs));
        } on Failure catch (offlineFailure) {
          return Left(offlineFailure);
        }
      }
      return Left(e);
    }
  }

  /// TAS-363: geofence on the saved branch coordinates, trusted time, then
  /// the queue. The server re-checks everything when it is sent.
  Future<AttendanceModel> _saveOfflineCheckIn(_OfflineCheckInArgs a) async {
    final name = a.branchName?.trim() ?? '';
    final ref = AttendanceBranchRef(
      branchId: a.branchId,
      branchOrganizationUID: (a.branchOrganizationUID ?? a.organizationId)
          .trim(),
      branchName: name,
    );
    final loc = name.isEmpty && (a.branchId ?? '').isEmpty
        ? null
        : branchCache?.find(ref);
    final branchId = (a.branchId?.trim().isNotEmpty == true)
        ? a.branchId!.trim()
        : loc?.branchId;
    if (loc == null ||
        !loc.hasCoordinates ||
        branchId == null ||
        branchId.isEmpty) {
      throw const ServerFailure(kOfflineBranchUnknownMessage);
    }
    final distance = Geolocator.distanceBetween(
      a.lat,
      a.long,
      loc.latitude,
      loc.longitude,
    );
    final allowed = loc.geofenceRadius + 50.0;
    if (distance > allowed) {
      throw ServerFailure(
        'أنت خارج نطاق الفرع (${distance.toInt()} متر). '
        'النطاق المسموح: ${allowed.toInt()} متر لـتسجيل الحضور.',
      );
    }
    final pending = offlineQueue.pending(a.userId);
    final closed = pending
        .where((p) => !p.isCheckIn)
        .map((p) => p.attendanceId)
        .toSet();
    if (pending.any((p) => p.isCheckIn && !closed.contains(p.id))) {
      throw const ServerFailure(kOfflineOpenSessionMessage);
    }

    final time = _offlineTime();
    final id = _newId();
    String? trimmed(String? v) =>
        (v == null || v.trim().isEmpty) ? null : v.trim();
    await offlineQueue.add(
      OfflineAttendanceAction(
        id: id,
        kind: OfflineAttendanceAction.checkInKind,
        delegateId: a.userId,
        attendanceId: id,
        lat: a.lat,
        lng: a.long,
        capturedAtMs: time.atMs,
        timeTrusted: time.trusted,
        syncedAtMs: time.syncedAtMs,
        checkIn: {
          'organizationId': a.organizationId,
          'companyId': a.companyId,
          'branchId': branchId,
          'branchOrganizationUID': ref.branchOrganizationUID,
          'branchName': name,
          'deviceInfo': a.deviceInfo,
          'delegateName': ?trimmed(a.delegateName),
          'phoneNumber': ?trimmed(a.phoneNumber),
          'companyName': ?trimmed(a.companyName),
          'personalPhotoURL': ?trimmed(a.personalPhotoURL),
        },
      ),
    );
    return AttendanceModel(
      id: id,
      userId: a.userId,
      organizationId: a.organizationId,
      checkInTime: time.at,
      latitude: a.lat,
      longitude: a.long,
      branchName: name,
      branchId: branchId,
      branchOrganizationUID: ref.branchOrganizationUID,
      isSynced: false,
    );
  }

  /// TAS-363: check-out saved on the phone, linked to its check-in id (an
  /// online one, or an offline one still queued). Never refused for the
  /// distance (same as the server).
  Future<AttendanceModel> _saveOfflineCheckOut({
    required String attendanceId,
    required String userId,
    required String organizationId,
    required double lat,
    required double long,
  }) async {
    if (userId.trim().isEmpty) {
      throw const ServerFailure(kCheckOutOfflineMessage);
    }
    final pending = offlineQueue.pending(userId);
    final outId = '${attendanceId}_out';
    final already = pending.where((p) => p.id == outId).firstOrNull;
    final time = already == null ? _offlineTime() : null;
    if (already == null) {
      await offlineQueue.add(
        OfflineAttendanceAction(
          id: outId,
          kind: OfflineAttendanceAction.checkOutKind,
          delegateId: userId,
          attendanceId: attendanceId,
          lat: lat,
          lng: long,
          capturedAtMs: time!.atMs,
          timeTrusted: time.trusted,
          syncedAtMs: time.syncedAtMs,
        ),
      );
    }
    final outAt = already?.capturedAt ?? time!.at;
    final queuedIn = pending
        .where((p) => p.isCheckIn && p.id == attendanceId)
        .firstOrNull;
    if (queuedIn != null) {
      return _queuedCheckInModel(queuedIn).copyWith(checkOutTime: outAt);
    }
    Attendance? known;
    try {
      final cached = await localDataSource.getLastAttendanceHistory(
        null,
        userId,
      );
      known = cached.where((c) => c.id == attendanceId).firstOrNull;
    } catch (_) {}
    return AttendanceModel(
      id: attendanceId,
      userId: userId,
      organizationId: organizationId,
      checkInTime: known?.checkInTime ?? outAt,
      checkOutTime: outAt,
      latitude: known?.latitude ?? lat,
      longitude: known?.longitude ?? long,
      branchName: known?.branchName,
      branchId: known?.branchId,
      branchOrganizationUID: known?.branchOrganizationUID,
      isSynced: false,
    );
  }

  AttendanceModel _queuedCheckInModel(OfflineAttendanceAction a) =>
      AttendanceModel(
        id: a.id,
        userId: a.delegateId,
        organizationId: (a.checkIn['organizationId'] as String?) ?? '',
        checkInTime: a.capturedAt,
        latitude: a.lat,
        longitude: a.lng,
        branchName: a.checkIn['branchName'] as String?,
        branchId: a.checkIn['branchId'] as String?,
        branchOrganizationUID: a.checkIn['branchOrganizationUID'] as String?,
        isSynced: false,
      );

  /// [items] with what is still queued on the phone for [userId]: offline
  /// check-ins not on the server yet, and offline check-outs (TAS-363).
  List<Attendance> _withPending(String userId, List<Attendance> items) {
    final pending = offlineQueue.pending(userId);
    if (pending.isEmpty) return items;
    final out = <Attendance>[...items];
    for (final a in pending.where((p) => p.isCheckIn)) {
      if (!out.any((i) => i.id == a.id)) out.add(_queuedCheckInModel(a));
    }
    for (final a in pending.where((p) => !p.isCheckIn)) {
      final i = out.indexWhere((x) => x.id == a.attendanceId);
      if (i == -1) continue;
      final x = out[i];
      out[i] = (x is AttendanceModel ? x : _toModel(x)).copyWith(
        checkOutTime: a.capturedAt,
        isSynced: false,
      );
    }
    out.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
    return out;
  }

  AttendanceModel _toModel(Attendance a) => AttendanceModel(
    id: a.id,
    userId: a.userId,
    organizationId: a.organizationId,
    checkInTime: a.checkInTime,
    checkOutTime: a.checkOutTime,
    latitude: a.latitude,
    longitude: a.longitude,
    imageUrl: a.imageUrl,
    branchName: a.branchName,
    branchId: a.branchId,
    branchOrganizationUID: a.branchOrganizationUID,
    isSynced: a.isSynced,
    isAutoCheckOut: a.isAutoCheckOut,
    autoCheckOutReason: a.autoCheckOutReason,
  );

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long, {
    required String userId,
    required String organizationId,
  }) async {
    try {
      // TAS-363: saved on the phone without network; a check-out of a
      // check-in that is itself still queued is queued after it.
      final queuedCheckIn = offlineQueue
          .pending(userId)
          .any((a) => a.isCheckIn && a.id == attendanceId);
      if (!await _hasConnection() || queuedCheckIn) {
        if (queuedCheckIn && await _hasConnection()) {
          await syncPendingAttendance(userId: userId);
        }
        final stillQueued = offlineQueue
            .pending(userId)
            .any((a) => a.isCheckIn && a.id == attendanceId);
        if (!await _hasConnection() || stillQueued) {
          return Right(
            await _saveOfflineCheckOut(
              attendanceId: attendanceId,
              userId: userId,
              organizationId: organizationId,
              lat: lat,
              long: long,
            ),
          );
        }
      }

      // --- Geofencing for Check-Out ---
      // Check-out records location and closes session without trapping employees if they forgot to check out on-site
      if (userId.isNotEmpty) {
        try {
          final activeAttendance = await remoteDataSource.findActiveAttendance(
            userId,
            organizationId,
          );
          if (activeAttendance != null &&
              activeAttendance.branchName != null &&
              activeAttendance.branchName!.trim().isNotEmpty) {
            await _verifyGeofence(
              userLat: lat,
              userLong: long,
              branchRef: AttendanceBranchRef.fromAttendanceLog({
                'branchId': activeAttendance.branchId,
                'branchOrganizationUID': activeAttendance.branchOrganizationUID,
                'organizationId': organizationId,
                'branchName': activeAttendance.branchName,
              }),
              isCheckIn: false,
            );
          }
        } catch (_) {
          // Allow check-out to proceed to avoid permanently locking active shifts
        }
      }

      final result = await remoteDataSource.checkOut(
        attendanceId,
        organizationId,
        lat,
        long,
      );
      await localDataSource.updateAttendance(result, organizationId, userId);
      return Right(result);
    } catch (e) {
      if (e is Failure && e.message == kCheckOutOfflineMessage) {
        try {
          return Right(
            await _saveOfflineCheckOut(
              attendanceId: attendanceId,
              userId: userId,
              organizationId: organizationId,
              lat: lat,
              long: long,
            ),
          );
        } on Failure catch (offlineFailure) {
          return Left(offlineFailure);
        }
      }
      if (e is Failure) return Left(e);
      return const Left(
        ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الانصراف.'),
      );
    }
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  }) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('لا يوجد اتصال بالإنترنت (وضع عدم الاتصال)');
      }
      final items = await remoteDataSource.getHistoryForMonth(
        userId,
        month: month,
        nationalityID: nationalityID,
        phoneNumber: phoneNumber,
      );
      return Right(items);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return Left(ServerFailure(e.toString()));
    }
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('لا يوجد اتصال بالإنترنت (وضع عدم الاتصال)');
      }

      final remoteHistory = await remoteDataSource.getHistory(
        userId,
        organizationId,
        nationalityID: nationalityID,
        phoneNumber: phoneNumber,
      );

      try {
        await localDataSource.overwriteHistory(remoteHistory, organizationId, userId);
      } catch (_) {}

      return Right(_withPending(userId, remoteHistory));
    } on Failure catch (e) {
      try {
        final localHistory = await localDataSource.getLastAttendanceHistory(
          organizationId,
          userId,
        );
        final filtered = _withPending(
          userId,
          localHistory.where((a) => a.userId == userId).toList(),
        );
        if (filtered.isNotEmpty) {
          return Right(filtered);
        }
      } catch (_) {}
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, AttendancePaginationResult>> getHistoryPaginated(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 20,
    dynamic lastDoc,
  }) async {
    try {
      if (!await _hasConnection()) {
        // Fallback to local history for the first page if offline
        if (lastDoc == null) {
          final localHistory = await localDataSource.getLastAttendanceHistory(
            organizationId,
            userId,
          );
          final filtered = _withPending(
            userId,
            localHistory.where((a) => a.userId == userId).toList(),
          );
          return Right(
            AttendancePaginationResult(
              items: filtered,
              hasReachedMax: true,
              lastDoc: null,
            ),
          );
        }
        return const Left(
          ServerFailure('لا يوجد اتصال بالإنترنت لتحميل المزيد.'),
        );
      }

      final response = await remoteDataSource.getHistoryPaginated(
        userId,
        organizationId,
        nationalityID: nationalityID,
        phoneNumber: phoneNumber,
        limit: limit,
        startAfter: lastDoc as DocumentSnapshot?,
      );

      // Cache the first page locally
      if (lastDoc == null && response.items.isNotEmpty) {
        try {
          await localDataSource.overwriteHistory(response.items, organizationId, userId);
        } catch (_) {}
      }

      return Right(
        AttendancePaginationResult(
          items: lastDoc == null
              ? _withPending(userId, response.items)
              : response.items,
          lastDoc: response.lastDoc,
          hasReachedMax: response.hasReachedMax,
        ),
      );
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return const Left(ServerFailure('فشل في تحميل سجل الحضور.'));
    }
  }

  @override
  Future<Either<Failure, Attendance?>> findActiveAttendance(
    String userId,
    String organizationId,
  ) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('No internet connection (offline mode)');
      }
      final result = await remoteDataSource.findActiveAttendance(
        userId,
        organizationId,
      );
      return Right(result);
    } on Failure catch (e) {
      return Left(e);
    }
  }

  /// TAS-363: sends what [userId] saved offline, oldest first, one by one
  /// through the attendance callables. An item leaves the queue only after
  /// the server answered for it: written / already written, or refused on
  /// purpose ([AttendanceServerRefused], then its check-out goes too and the
  /// delegate is told why). Anything else (no network, server busy, signed
  /// out) stops and keeps the rest for the next try. Same key twice gives one
  /// record, so a retry after a lost answer is safe.
  @override
  Future<Either<Failure, void>> syncPendingAttendance({String? userId}) async {
    final uid = userId?.trim() ?? '';
    if (uid.isEmpty) return const Right(null);
    final items = offlineQueue.pending(uid);
    if (items.isEmpty) return const Right(null);
    if (!await _hasConnection()) {
      return const Left(NetworkFailure(kOfflineSyncRetryMessage));
    }
    final rejected = <String>[];
    final droppedCheckIns = <String>{};
    for (final a in items) {
      if (!a.isCheckIn && droppedCheckIns.contains(a.attendanceId)) {
        await offlineQueue.remove(uid, a.id);
        continue;
      }
      try {
        await remoteDataSource.sendOfflineAction(a);
        await offlineQueue.remove(uid, a.id);
      } on AttendanceServerRefused catch (f) {
        await offlineQueue.remove(uid, a.id);
        if (a.isCheckIn) droppedCheckIns.add(a.id);
        rejected.add(f.message);
      } catch (_) {
        return const Left(NetworkFailure(kOfflineSyncRetryMessage));
      }
    }
    if (rejected.isNotEmpty) {
      return Left(
        OfflineAttendanceRejected(offlineRecordRejectedMessage(rejected.first)),
      );
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
    String? branchId,
    String? organizationUID,
  }) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('No internet connection');
      }
      await remoteDataSource.saveBranch(
        branchName: branchName,
        latitude: latitude,
        longitude: longitude,
        geofenceRadius: geofenceRadius,
        branchId: branchId,
        organizationUID: organizationUID,
      );
      return const Right(null);
    } on Failure catch (e) {
      return Left(e);
    } catch (_) {
      return const Left(
        ServerFailure('حدث خطأ غير متوقع أثناء حفظ بيانات الفرع.'),
      );
    }
  }
}

/// TAS-363: a record saved offline was refused by the server when sent.
class OfflineAttendanceRejected extends ServerFailure {
  const OfflineAttendanceRejected(super.message);
}

class _OfflineCheckInArgs {
  const _OfflineCheckInArgs({
    required this.userId,
    required this.lat,
    required this.long,
    required this.companyId,
    required this.organizationId,
    required this.deviceInfo,
    this.branchName,
    this.branchId,
    this.branchOrganizationUID,
    this.delegateName,
    this.phoneNumber,
    this.companyName,
    this.personalPhotoURL,
  });

  final String userId;
  final double lat;
  final double long;
  final String companyId;
  final String organizationId;
  final String deviceInfo;
  final String? branchName;
  final String? branchId;
  final String? branchOrganizationUID;
  final String? delegateName;
  final String? phoneNumber;
  final String? companyName;
  final String? personalPhotoURL;
}
