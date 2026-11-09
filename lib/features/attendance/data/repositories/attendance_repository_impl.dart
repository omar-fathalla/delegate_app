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
import 'package:geolocator/geolocator.dart';

class AttendanceRepositoryImpl implements AttendanceRepository {
  final AttendanceRemoteDataSource remoteDataSource;
  final AttendanceLocalDataSource localDataSource;
  final AttendanceOfflineQueue offlineQueue;

  AttendanceRepositoryImpl({
    required this.remoteDataSource,
    required this.localDataSource,
    required this.offlineQueue,
  });

  Future<bool> _hasConnection() async {
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
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure(kCheckInOfflineMessage);
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
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long, {
    required String userId,
    required String organizationId,
  }) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure(kCheckOutOfflineMessage);
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

      return Right(remoteHistory);
    } on Failure catch (e) {
      try {
        final localHistory = await localDataSource.getLastAttendanceHistory(organizationId, userId);
        final filtered = localHistory.where((a) => a.userId == userId).toList();
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
          final localHistory = await localDataSource.getLastAttendanceHistory(organizationId, userId);
          final filtered = localHistory
              .where((a) => a.userId == userId)
              .toList();
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
          items: response.items,
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

  @override
  Future<Either<Failure, void>> syncPendingAttendance() async {
    try {
      final queue = await offlineQueue.getQueue();
      if (queue.isEmpty) {
        return const Right(null);
      }

      await remoteDataSource.syncOfflineQueue(queue);
      await offlineQueue.clearQueue();
      return const Right(null);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      return const Left(ServerFailure('خطأ غير متوقع أثناء المزامنة.'));
    }
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
