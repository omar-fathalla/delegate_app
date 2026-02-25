import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';

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
    required String branchName,
    required bool isCheckIn,
  }) async {
    final branchData = await remoteDataSource.getBranchByName(branchName);
    if (branchData == null) {
      throw const ServerFailure(
        'لم يتم العثور على بيانات الفرع. يرجى التأكد من الرمز.',
      );
    }

    // Model handles data structure variations (nested vs top-level)
    final branch = BranchModel.fromMap(branchData);

    if (branch.latitude == 0.0 && branch.longitude == 0.0) {
      debugPrint(
        'DEBUG: Missing coordinates for $branchName — '
        'lat: ${branch.latitude}, long: ${branch.longitude}',
      );
      throw ServerFailure(
        'بيانات إحداثيات الفرع ($branchName) غير مكتملة في النظام. يرجى إبلاغ الإدارة.',
      );
    }

    final double distance = Geolocator.distanceBetween(
      userLat,
      userLong,
      branch.latitude,
      branch.longitude,
    );

    if (distance > branch.geofenceRadius) {
      final action = isCheckIn ? 'تسجيل الحضور' : 'تسجيل الانصراف';
      throw ServerFailure(
        'أنت خارج نطاق الفرع (${distance.toInt()} متر). '
        'النطاق المسموح: ${branch.geofenceRadius.toInt()} متر لـ$action.',
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
  }) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('No internet connection (offline mode)');
      }

      // --- Anti-Fraud Geofencing ---
      if (branchName != null) {
        await _verifyGeofence(
          userLat: lat,
          userLong: long,
          branchName: branchName,
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
      );
      // Always cache attendance after successful remote write
      await localDataSource.cacheAttendance(result);
      return Right(result);
    } on Failure catch (e) {
      // We removed the offline fallback here to satisfy the "internet required" for anti-fraud
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, Attendance>> checkOut(
    String attendanceId,
    double lat,
    double long, {
    required String userId,
  }) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('No internet connection (offline mode)');
      }

      // --- Anti-Fraud Geofencing for Check-Out (Non-Blocking) ---
      // Geofencing errors should NOT prevent check-out, only warn.
      // Only actual "out of range" violations should block.
      if (userId.isNotEmpty) {
        try {
          final activeAttendance = await remoteDataSource.findActiveAttendance(
            userId,
          );
          if (activeAttendance != null && activeAttendance.branchName != null) {
            await _verifyGeofence(
              userLat: lat,
              userLong: long,
              branchName: activeAttendance.branchName!,
              isCheckIn: false,
            );
          }
        } catch (e) {
          // Only rethrow actual geofencing violations (out of range)
          if (e is ServerFailure && e.message.contains('خارج نطاق')) {
            rethrow;
          }
          // All other errors (missing index, network, etc.) → log and continue
          debugPrint('Geofencing check-out skipped (non-blocking): $e');
        }
      }

      final result = await remoteDataSource.checkOut(attendanceId, lat, long);
      await localDataSource.updateAttendance(result);
      return Right(result);
    } catch (e) {
      if (e is Failure) return Left(e);
      debugPrint('Unexpected error in AttendanceRepository.checkOut: $e');
      return const Left(
        ServerFailure('حدث خطأ غير متوقع أثناء تسجيل الانصراف.'),
      );
    }
  }

  @override
  Future<Either<Failure, List<Attendance>>> getHistory(String userId) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('No internet connection (offline mode)');
      }

      // Firestore is the single source of truth (already filtered by delegateId)
      final remoteHistory = await remoteDataSource.getHistory(userId);

      // Cache this delegate's data for offline fallback
      try {
        await localDataSource.overwriteHistory(remoteHistory);
      } catch (_) {
        // Cache failure is non-critical
      }

      return Right(remoteHistory);
    } on Failure catch (e) {
      // Offline fallback: use local cache but filter by userId
      try {
        final localHistory = await localDataSource.getLastAttendanceHistory();
        final filtered = localHistory.where((a) => a.userId == userId).toList();
        if (filtered.isNotEmpty) {
          return Right(filtered);
        }
      } catch (_) {
        // If local also fails, return the original remote failure
      }
      return Left(e);
    }
  }

  @override
  Future<Either<Failure, Attendance?>> findActiveAttendance(
    String userId,
  ) async {
    try {
      if (!await _hasConnection()) {
        throw const ServerFailure('No internet connection (offline mode)');
      }
      final result = await remoteDataSource.findActiveAttendance(userId);
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
      );
      return const Right(null);
    } on Failure catch (e) {
      return Left(e);
    } catch (e) {
      debugPrint('AttendanceRepository.saveBranch error: $e');
      return const Left(
        ServerFailure('حدث خطأ غير متوقع أثناء حفظ بيانات الفرع.'),
      );
    }
  }
}
