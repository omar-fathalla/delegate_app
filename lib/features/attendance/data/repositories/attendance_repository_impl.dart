import 'package:flutter/foundation.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/attendance/domain/entities/attendance.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
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
        final branchData = await remoteDataSource.getBranchByName(branchName);
        if (branchData == null) {
          throw const ServerFailure(
            'لم يتم العثور على بيانات الفرع الممسوح. يرجى التأكد من الرمز.',
          );
        }

        final latVal = branchData['latitude'];
        final longVal = branchData['longitude'];
        final radiusVal = branchData['geofenceRadius'];

        if (latVal != null && longVal != null && radiusVal != null) {
          final double branchLat = (latVal as num).toDouble();
          final double branchLong = (longVal as num).toDouble();
          final double radius = (radiusVal as num).toDouble();

          final double distance = Geolocator.distanceBetween(
            lat,
            long,
            branchLat,
            branchLong,
          );

          if (distance > radius) {
            throw ServerFailure(
              'أنت خارج نطاق الفرع (${distance.toInt()} متر). يرجى التواجد داخل نطاق $radius متر.',
            );
          }
        } else {
          // Log coordinates to help admin set up the branch
          debugPrint(
            'DEBUG: Current Location for $branchName: Lat $lat, Long $long',
          );
          throw ServerFailure(
            'بيانات إحداثيات الفرع ($branchName) غير مكتملة في النظام. يرجى إبلاغ الإدارة.',
          );
        }
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

      // --- Anti-Fraud Geofencing for Check-Out ---
      if (userId.isNotEmpty) {
        try {
          final activeAttendance = await remoteDataSource.findActiveAttendance(
            userId,
          );
          if (activeAttendance != null && activeAttendance.branchName != null) {
            final branchData = await remoteDataSource.getBranchByName(
              activeAttendance.branchName!,
            );
            if (branchData != null) {
              final latVal = branchData['latitude'];
              final longVal = branchData['longitude'];
              final radiusVal = branchData['geofenceRadius'];

              if (latVal != null && longVal != null && radiusVal != null) {
                final double branchLat = (latVal as num).toDouble();
                final double branchLong = (longVal as num).toDouble();
                final double radius = (radiusVal as num).toDouble();

                final double distance = Geolocator.distanceBetween(
                  lat,
                  long,
                  branchLat,
                  branchLong,
                );

                if (distance > radius) {
                  throw ServerFailure(
                    'أنت خارج نطاق الفرع (${distance.toInt()} متر). يرجى التواجد داخل نطاق $radius متر لتسجيل الانصراف.',
                  );
                }
              }
            }
          }
        } catch (e) {
          if (e is Failure) rethrow;
          debugPrint(
            'Geofencing check-out error ignored to prevent freeze: $e',
          );
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
      final remoteHistory = await remoteDataSource.getHistory(userId);

      // Combine with local unsynced items
      try {
        final localHistory = await localDataSource.getLastAttendanceHistory();
        final Map<String, AttendanceModel> mergedMap = {};

        // 1. Start with remote results
        for (var remote in remoteHistory) {
          mergedMap[remote.id] = remote;
        }

        // 2. Merge with local (prefer local if it has check-out and remote doesn't)
        for (var local in localHistory) {
          if (mergedMap.containsKey(local.id)) {
            final remote = mergedMap[local.id]!;
            if (local.checkOutTime != null && remote.checkOutTime == null) {
              // Local is fresher (just checked out locally, remote still stale)
              mergedMap[local.id] = local.copyWith(isSynced: false);
            }
          } else {
            // Local item not in remote yet (recently opened or offline)
            mergedMap[local.id] = local;
          }
        }

        final List<AttendanceModel> combined = mergedMap.values.toList();

        // Sort combined descending by checkInTime
        combined.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));

        // Update local cache so next time we have the freshest list
        await localDataSource.overwriteHistory(combined);

        return Right(combined);
      } catch (_) {
        // If combining fails, just return remote history
        return Right(remoteHistory);
      }
    } on Failure catch (e) {
      // On network error, fallback to local cache
      try {
        final localHistory = await localDataSource.getLastAttendanceHistory();
        if (localHistory.isNotEmpty) {
          return Right(localHistory);
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
