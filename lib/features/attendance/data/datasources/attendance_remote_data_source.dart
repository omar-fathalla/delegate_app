import 'package:delegate_app/core/attendance/attendance_branch_ref.dart';
import 'package:delegate_app/core/attendance/attendance_branch_resolve.dart';
import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'package:delegate_app/features/attendance/domain/attendance_auto_close.dart';
import 'package:delegate_app/features/attendance/domain/attendance_action_messages.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:battery_plus/battery_plus.dart';
import 'package:geolocator/geolocator.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/features/attendance/data/models/attendance_model.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_engine.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/core/security/delegate_identity.dart';

abstract class AttendanceRemoteDataSource {
  Future<AttendanceModel> checkIn(
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
  });
  Future<AttendanceModel> checkOut(
    String attendanceId,
    String organizationId,
    double lat,
    double long,
  );
  Future<List<AttendanceModel>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  });
  Future<PaginationResponse<AttendanceModel>> getHistoryPaginated(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfter,
  });

  /// Fetches ALL attendance sessions whose check-in falls in [month]
  /// (device-local calendar month) across all affiliated organizations.
  /// Used for the monthly summary so figures never depend on pagination.
  Future<List<AttendanceModel>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  });

  /// Fetches recent attendance sessions across all affiliated organizations (for the home brief).
  Future<List<AttendanceModel>> getRecentSessionsAcrossOrgs(
    String userId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 6,
  });

  /// Finds the active attendance record (where checkOutTime is null)
  /// for the given [userId] in the specified [organizationId].
  /// Returns `null` if no active session exists.
  Future<AttendanceModel?> findActiveAttendance(
    String userId,
    String organizationId,
  );

  /// Emits real-time updates for active attendance of the delegate.
  Stream<AttendanceModel?> streamActiveAttendance(
    String userId,
    String organizationId,
  );

  /// Syncs an offline queue of attendance actions to Firestore.
  Future<void> syncOfflineQueue(List<Map<String, dynamic>> queue);

  /// Fetches branch details by name (legacy; prefer [resolveBranch]).
  Future<Map<String, dynamic>?> getBranchByName(String branchName);

  /// Resolves a branch by id and/or name scoped to an organization.
  Future<ResolvedBranchDocument?> resolveBranch({
    String? branchId,
    String? organizationUID,
    String? branchName,
  });

  /// Saves or updates a branch with its geofence data.
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
    String? branchId,
    String? organizationUID,
  });
}

class AttendanceRemoteDataSourceImpl implements AttendanceRemoteDataSource {
  final FirebaseFirestore firestore;

  /// Signed-in user, for `createdBy` on supervisor alerts (TAS-71). Falls
  /// back to the delegate's user id when no auth is available (tests).
  final FirebaseAuth? auth;

  AttendanceRemoteDataSourceImpl({required this.firestore, this.auth});

  /// Helper: Get the attendance_logs collection
  /// Path: /attendance_logs
  CollectionReference<Map<String, dynamic>> _attendanceCollection(
    String organizationId,
  ) => firestore.collection(kAttendanceCollection);

  @override
  Future<AttendanceModel> checkIn(
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
      final trustedNow = _trustedNow();
      final pendingKey = _pendingCheckInKey(userId, trustedNow);
      final pendingId = _pendingCheckInIds[pendingKey];

      // Guard against duplicate active check-in, decided on the server only.
      // If the server can't be reached nothing is written.
      AttendanceModel? existingActive;
      try {
        existingActive = await findActiveAttendance(
          userId,
          organizationId,
        ).timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Active check-in verification failed: $e');
        throw const ServerFailure(kCheckInOfflineMessage);
      }

      if (existingActive != null) {
        // A previous attempt that timed out has landed: that IS this check-in.
        if (pendingId != null && existingActive.id == pendingId) {
          _pendingCheckInIds.remove(pendingKey);
          return existingActive;
        }

        final isSameDay = existingActive.checkInTime.year == trustedNow.year &&
            existingActive.checkInTime.month == trustedNow.month &&
            existingActive.checkInTime.day == trustedNow.day;

        if (isSameDay) {
          final activeRef = AttendanceBranchRef.fromAttendanceLog({
            'branchId': existingActive.branchId,
            'branchOrganizationUID': existingActive.branchOrganizationUID,
            'organizationId': existingActive.organizationId,
            'branchName': existingActive.branchName,
          });
          final incomingRef = AttendanceBranchRef(
            branchId: branchId,
            branchOrganizationUID:
                (branchOrganizationUID ?? organizationId).trim(),
            branchName: branchName ?? '',
          );
          if (attendanceSameBranch(activeRef, incomingRef)) {
            throw const ServerFailure(
              'أنت مسجل حضور بالفعل في هذا الفرع وما زالت الجلسة جارية.',
            );
          } else {
            throw ServerFailure(
              'لديك تسجيل حضور نشط في فرع ${existingActive.branchName == null ? "آخر" : BranchDisplayCache.instance.displayName(existingActive.branchName!)}. يرجى تسجيل الانصراف أولاً.',
            );
          }
        }
      }

      final Map<String, dynamic> checkInPayload = {
            'delegateId': userId,
            'userId': userId,
            'companyId': companyId,
            'organizationId': organizationId,
            'timestamp': FieldValue.serverTimestamp(),
            'type': 'check_in',
            'location': {'latitude': lat, 'longitude': long},
            'deviceInfo': deviceInfo,
            'branchName': branchName,
            if (branchId != null && branchId.trim().isNotEmpty)
              'branchId': branchId.trim(),
            if ((branchOrganizationUID ?? organizationId).trim().isNotEmpty)
              'branchOrganizationUID':
                  (branchOrganizationUID ?? organizationId).trim(),
          };
      // Fix3: denormalize display fields so marketing cards skip N+1 profile reads.
      final trimmedName = delegateName?.trim();
      if (trimmedName != null && trimmedName.isNotEmpty) {
        checkInPayload['delegateName'] = trimmedName;
      }
      final trimmedPhone = phoneNumber?.trim();
      if (trimmedPhone != null && trimmedPhone.isNotEmpty) {
        checkInPayload['phoneNumber'] = trimmedPhone;
      }
      final trimmedCompany = companyName?.trim();
      if (trimmedCompany != null && trimmedCompany.isNotEmpty) {
        checkInPayload['companyName'] = trimmedCompany;
      }
      final trimmedPhoto = personalPhotoURL?.trim();
      if (trimmedPhoto != null && trimmedPhoto.isNotEmpty) {
        checkInPayload['personalPhotoURL'] = trimmedPhoto;
      }

      // Idempotent write: a retry after an unconfirmed attempt reuses the same
      // document ID, so a queued (offline-persisted) write can never become a
      // second check-in.
      final docId =
          pendingId ?? _attendanceCollection(organizationId).doc().id;
      _pendingCheckInIds[pendingKey] = docId;
      final docRef = _attendanceCollection(organizationId).doc(docId);
      try {
        await docRef.set(checkInPayload).timeout(const Duration(seconds: 15));
      } on TimeoutException {
        if (!await _existsOnServer(docRef)) {
          throw const ServerFailure(kCheckInUnknownMessage);
        }
      }
      _pendingCheckInIds.remove(pendingKey);

      DateTime currentTime;
      try {
        currentTime = sl<TrustedTimeService>().now;
      } catch (_) {
        currentTime = DateTime.now();
      }

      unawaited(
        _notifySupervisorsOfAttendance(
          userId: userId,
          companyId: companyId,
          organizationId: organizationId,
          branchName: branchName,
          type: 'check_in',
          time: currentTime,
        ),
      );

      unawaited(
        _syncDelegateTrackingCheckIn(
          userId: userId,
          companyId: companyId,
          organizationId: organizationId,
          branchRef: AttendanceBranchRef(
            branchId: branchId,
            branchOrganizationUID:
                (branchOrganizationUID ?? organizationId).trim(),
            branchName: branchName ?? '',
          ),
          lat: lat,
          long: long,
          time: currentTime,
        ),
      );

      return AttendanceModel(
        id: docRef.id,
        userId: userId,
        organizationId: organizationId,
        checkInTime: currentTime,
        latitude: lat,
        longitude: long,
        branchName: branchName,
        branchId: branchId,
        branchOrganizationUID: branchOrganizationUID ?? organizationId,
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تسجيل الحضور. حاول مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure();
    } on Failure {
      rethrow;
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء تسجيل الحضور.');
    }
  }

  @override
  Future<AttendanceModel> checkOut(
    String attendanceId,
    String organizationId,
    double lat,
    double long,
  ) async {
    try {
      final checkInRef = _attendanceCollection(organizationId).doc(attendanceId);
      // Deterministic ID: repeating the same check-out can't add a 2nd record.
      final outRef = _attendanceCollection(organizationId)
          .doc('${attendanceId}_out');

      // Decide on the server only, never on the offline cache.
      final DocumentSnapshot<Map<String, dynamic>> lastCheckInSnapshot;
      try {
        lastCheckInSnapshot = await checkInRef
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 8));
      } catch (e) {
        debugPrint('Check-out server read failed: $e');
        throw const ServerFailure(kCheckOutOfflineMessage);
      }

      if (!lastCheckInSnapshot.exists) {
        throw const ServerFailure('سجل الحضور غير موجود.');
      }
      final lastData = lastCheckInSnapshot.data()!;
      if (lastData['checkOutTime'] != null) {
        if (lastData['checkOutDocId'] == outRef.id) {
          // An earlier attempt that timed out has landed.
          return _checkedOutModel(attendanceId, organizationId, lastData);
        }
        throw const ServerFailure(kAlreadyCheckedOutMessage);
      }
      final userId = lastData['delegateId'] ?? lastData['userId'];
      final companyId = lastData['companyId'];

      // Keep a separate check_out log for history/HR, and denormalize
      // checkOutTime onto the check-in doc so marketing today-views skip
      // the historical follow-up query.
      final batch = firestore.batch();
      batch.set(outRef, {
        'delegateId': userId,
        'userId': userId,
        'companyId': companyId,
        'organizationId': organizationId,
        'timestamp': FieldValue.serverTimestamp(),
        'type': 'check_out',
        'location': {'latitude': lat, 'longitude': long},
        'relatedCheckInId': attendanceId,
        if (lastData['branchName'] != null) 'branchName': lastData['branchName'],
        if (lastData['branchId'] != null) 'branchId': lastData['branchId'],
        if (lastData['branchOrganizationUID'] != null)
          'branchOrganizationUID': lastData['branchOrganizationUID'],
      });
      batch.update(checkInRef, {
        'checkOutTime': FieldValue.serverTimestamp(),
        'checkOutLocation': {'latitude': lat, 'longitude': long},
        'checkOutDocId': outRef.id,
      });
      try {
        await batch.commit().timeout(const Duration(seconds: 15));
      } on TimeoutException {
        final confirmed = await _serverDocData(checkInRef);
        if (confirmed?['checkOutDocId'] != outRef.id) {
          throw const ServerFailure(kCheckOutUnknownMessage);
        }
      }

      // Auto-resolve any orphaned unclosed check-in for the same user and branch today
      try {
        final lastBranchId = lastData['branchId']?.toString().trim();
        Query<Map<String, dynamic>> orphanQuery = _attendanceCollection(
          organizationId,
        )
            .where('delegateId', isEqualTo: userId)
            .where('type', isEqualTo: 'check_in');
        if (lastBranchId != null && lastBranchId.isNotEmpty) {
          orphanQuery = orphanQuery.where('branchId', isEqualTo: lastBranchId);
        } else if (lastData['branchName'] != null) {
          orphanQuery = orphanQuery.where(
            'branchName',
            isEqualTo: lastData['branchName'],
          );
        }

        final orphanedSnaps = await orphanQuery
            .limit(5)
            .get()
            .timeout(const Duration(seconds: 4));

        for (final doc in orphanedSnaps.docs) {
          if (doc.id != attendanceId) {
            final outSnap = await _attendanceCollection(organizationId)
                .where('relatedCheckInId', isEqualTo: doc.id)
                .limit(1)
                .get()
                .timeout(const Duration(seconds: 3));

            if (outSnap.docs.isEmpty) {
              final orphanOutRef = _attendanceCollection(organizationId).doc();
              final orphanBatch = firestore.batch();
              orphanBatch.set(orphanOutRef, {
                'delegateId': userId,
                'userId': userId,
                'companyId': companyId,
                'organizationId': organizationId,
                'timestamp': FieldValue.serverTimestamp(),
                'type': 'check_out',
                'location': {'latitude': lat, 'longitude': long},
                'relatedCheckInId': doc.id,
                if (lastData['branchName'] != null) 'branchName': lastData['branchName'],
                if (lastData['branchId'] != null) 'branchId': lastData['branchId'],
                if (lastData['branchOrganizationUID'] != null)
                  'branchOrganizationUID': lastData['branchOrganizationUID'],
                'autoClosedDuplicate': true,
              });
              orphanBatch.update(doc.reference, {
                'checkOutTime': FieldValue.serverTimestamp(),
                'checkOutLocation': {'latitude': lat, 'longitude': long},
                'checkOutDocId': orphanOutRef.id,
                'autoClosedDuplicate': true,
              });
              await orphanBatch.commit();
            }
          }
        }
      } catch (e) {
        debugPrint('Auto-close orphaned check-in warning: $e');
      }

      DateTime currentOutTime;
      try {
        currentOutTime = sl<TrustedTimeService>().now;
      } catch (_) {
        currentOutTime = DateTime.now();
      }

      unawaited(
        _notifySupervisorsOfAttendance(
          userId: userId,
          companyId: companyId ?? '',
          organizationId: organizationId,
          branchName: lastData['branchName'] as String?,
          type: 'check_out',
          time: currentOutTime,
        ),
      );

      unawaited(
        _syncDelegateTrackingCheckOut(
          userId: userId,
        ),
      );

      return AttendanceModel(
        id: attendanceId,
        userId: userId,
        organizationId: organizationId,
        checkInTime: (lastData['timestamp'] as Timestamp).toDate(),
        checkOutTime: currentOutTime,
        latitude: (lastData['location']['latitude'] as num).toDouble(),
        longitude: (lastData['location']['longitude'] as num).toDouble(),
        branchName: lastData['branchName'],
      );
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في تسجيل الانصراف. حاول مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure();
    } on Failure {
      rethrow;
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء تسجيل الانصراف.');
    }
  }

  @override
  Future<List<AttendanceModel>> getHistory(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
  }) async {
    final response = await getHistoryPaginated(
      userId,
      organizationId,
      nationalityID: nationalityID,
      phoneNumber: phoneNumber,
      limit: 100,
    );
    return response.items;
  }

  String _normalizePhone(String phone) {
    const english = ['0', '1', '2', '3', '4', '5', '6', '7', '8', '9'];
    const arabic = ['٠', '١', '٢', '٣', '٤', '٥', '٦', '٧', '٨', '٩'];

    String normalized = phone.trim();
    normalized = normalized.replaceAll(RegExp(r'[^\d+٠-٩]'), '');

    for (int i = 0; i < arabic.length; i++) {
      normalized = normalized.replaceAll(arabic[i], english[i]);
    }

    if (normalized.startsWith('+20')) {
      normalized = '0${normalized.substring(3)}';
    } else if (normalized.startsWith('+2')) {
      normalized = normalized.substring(2);
    } else if (normalized.startsWith('0020')) {
      normalized = '0${normalized.substring(4)}';
    } else if (normalized.startsWith('002')) {
      normalized = normalized.substring(3);
    }

    return normalized;
  }

  @override
  Future<PaginationResponse<AttendanceModel>> getHistoryPaginated(
    String userId,
    String organizationId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfter,
  }) async {
    try {
      final queryList = await _resolveHistoryIdentifiers(
        userId,
        nationalityID: nationalityID,
        phoneNumber: phoneNumber,
      );
      final cleanOrgId = organizationId.trim();

      Query<Map<String, dynamic>> query = _attendanceCollection(organizationId);

      if (cleanOrgId.isNotEmpty) {
        query = query.where('organizationId', isEqualTo: cleanOrgId);
      }

      query = query
          .where('delegateId', whereIn: queryList)
          .orderBy('timestamp', descending: true)
          .limit(limit * 2);

      if (startAfter != null) {
        query = query.startAfterDocument(startAfter);
      }

      QuerySnapshot<Map<String, dynamic>> querySnapshot;
      try {
        querySnapshot = await query.getResilient(
          timeout: const Duration(seconds: 8),
          forceServer: true,
        );
      } catch (err) {
        debugPrint('Query with organizationId fallback to in-memory filter: $err');
        Query<Map<String, dynamic>> fallbackQuery = _attendanceCollection(organizationId)
            .where('delegateId', whereIn: queryList)
            .orderBy('timestamp', descending: true)
            .limit(limit * 2);
        if (startAfter != null) {
          fallbackQuery = fallbackQuery.startAfterDocument(startAfter);
        }
        querySnapshot = await fallbackQuery.getResilient(
          timeout: const Duration(seconds: 8),
          forceServer: true,
        );
      }

      if (querySnapshot.docs.isEmpty) {
        return PaginationResponse(
          items: [],
          lastDoc: null,
          hasReachedMax: true,
        );
      }

      final history = _pairAttendanceDocs(
        querySnapshot.docs,
        userId,
        cleanOrgId,
      );

      return PaginationResponse(
        items: history,
        lastDoc: querySnapshot.docs.last,
        hasReachedMax: querySnapshot.docs.length < (limit * 2),
      );
    } catch (e, stack) {
      debugPrint('Error in getHistoryPaginated: $e\n$stack');
      return PaginationResponse(items: [], lastDoc: null, hasReachedMax: true);
    }
  }

  /// Attendance `whereIn` may only contain owned UIDs. National ID and
  /// phone are not valid `delegateId` values for the security rules, and
  /// a collection-group scan by those fields is not query-provable
  /// without a matching claim (M31 3ff8e5d).
  Future<List<String>> _resolveHistoryIdentifiers(
    String userId, {
    String? nationalityID,
    String? phoneNumber,
  }) async {
    return {userId}.where((id) => id.isNotEmpty).take(30).toList();
  }

  @override
  Future<List<AttendanceModel>> getHistoryForMonth(
    String userId, {
    required DateTime month,
    String? nationalityID,
    String? phoneNumber,
  }) async {
    final queryList = await _resolveHistoryIdentifiers(
      userId,
      nationalityID: nationalityID,
      phoneNumber: phoneNumber,
    );
    final monthStart = DateTime(month.year, month.month);
    final monthEnd = DateTime(month.year, month.month + 1);
    // Check-outs of the month's last overnight session land after monthEnd,
    // so widen the upper bound by one day; sessions are filtered by check-in.
    final upper = monthEnd.add(const Duration(days: 1));

    final docs = <QueryDocumentSnapshot<Map<String, dynamic>>>[];
    DocumentSnapshot? cursor;
    const pageSize = 300;
    while (true) {
      Query<Map<String, dynamic>> query = _attendanceCollection('')
          .where('delegateId', whereIn: queryList)
          .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(monthStart))
          .where('timestamp', isLessThan: Timestamp.fromDate(upper))
          .orderBy('timestamp', descending: true)
          .limit(pageSize);
      if (cursor != null) query = query.startAfterDocument(cursor);
      final snap = await query.getResilient(
        timeout: const Duration(seconds: 10),
        forceServer: true,
      );
      docs.addAll(snap.docs);
      if (snap.docs.length < pageSize) break;
      cursor = snap.docs.last;
    }

    return _pairAttendanceDocs(docs, userId, '')
        .where((a) =>
            !a.checkInTime.isBefore(monthStart) &&
            a.checkInTime.isBefore(monthEnd))
        .toList();
  }

  @override
  Future<List<AttendanceModel>> getRecentSessionsAcrossOrgs(
    String userId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 6,
  }) async {
    try {
      // Only owned UIDs. NID/phone in the same whereIn is rejected by rules.
      final queryList = await _resolveHistoryIdentifiers(userId);

      final querySnapshot = await firestore
          .collection(kAttendanceCollection)
          .where('delegateId', whereIn: queryList)
          .orderBy('timestamp', descending: true)
          .limit(limit * 3)
          .getResilient(
            timeout: const Duration(seconds: 6),
            forceServer: false,
          );

      if (querySnapshot.docs.isEmpty) return [];

      final allSessions = _pairAttendanceDocs(querySnapshot.docs, userId, '');
      return allSessions.take(limit).toList();
    } catch (e) {
      debugPrint('Error in getRecentSessionsAcrossOrgs: $e');
      return [];
    }
  }

  /// Pairs check-in and check-out documents into [AttendanceModel] sessions.
  List<AttendanceModel> _pairAttendanceDocs(
    List<QueryDocumentSnapshot<Map<String, dynamic>>> docs,
    String userId,
    String organizationId,
  ) {
    final List<AttendanceModel> history = [];
    final Map<String, Map<String, dynamic>> checkOuts = {};
    final List<QueryDocumentSnapshot<Map<String, dynamic>>> checkIns = [];

    // Separate check-ins and check-outs
    for (var doc in docs) {
      final data = doc.data();
      final type = data['type'] as String?;
      if (type == 'check_out') {
        final relatedId = data['relatedCheckInId'] as String?;
        if (relatedId != null) {
          checkOuts[relatedId] = data;
        }
      } else if (type == 'check_in') {
        checkIns.add(doc);
      }
    }

    // Process check-ins and match with corresponding check-outs if available
    for (var doc in checkIns) {
      final checkInId = doc.id;
      final data = doc.data();
      final docOrg = (data['organizationId'] as String?)?.trim() ??
          (data['organizationUID'] as String?)?.trim() ??
          '';

      // Dual-layer strict multi-tenant isolation:
      if (organizationId.trim().isNotEmpty &&
          docOrg.isNotEmpty &&
          docOrg != organizationId.trim()) {
        continue;
      }

      final checkInTime = data['timestamp'] != null
          ? (data['timestamp'] as Timestamp).toDate()
          : DateTime.now();
      final lat = (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0;
      final branchName = data['branchName'];
      final targetOrgId = docOrg.isNotEmpty ? docOrg : organizationId;
      // Keep the branch reference: the attendance tab loads history for
      // all chains (organizationId ''), and check-out compares the open
      // session's branch with the current one (TAS-248).
      final branchId = data['branchId'] as String?;
      final branchOrganizationUID =
          (data['branchOrganizationUID'] as String?) ?? targetOrgId;

      // Prefer denormalized checkOutTime on the check-in doc (fix2),
      // fall back to paired check_out log for older records.
      DateTime? resolvedOut;
      var isAuto = data['isAutoCheckOut'] == true;
      String? autoReason = data['autoCheckOutReason'] as String?;
      if (data['checkOutTime'] is Timestamp) {
        resolvedOut = (data['checkOutTime'] as Timestamp).toDate();
      } else if (checkOuts.containsKey(checkInId)) {
        final outData = checkOuts[checkInId]!;
        isAuto = outData['isAutoCheckOut'] == true || isAuto;
        autoReason = (outData['autoCheckOutReason'] as String?) ?? autoReason;
        resolvedOut = outData['timestamp'] != null
            ? (outData['timestamp'] as Timestamp).toDate()
            : DateTime.now();
      }

      if (resolvedOut != null) {
        history.add(
          AttendanceModel(
            id: checkInId,
            userId: userId,
            organizationId: targetOrgId,
            checkInTime: checkInTime,
            checkOutTime: resolvedOut,
            latitude: lat,
            longitude: lng,
            branchName: branchName,
            branchId: branchId,
            branchOrganizationUID: branchOrganizationUID,
            isAutoCheckOut: isAuto,
            autoCheckOutReason: autoReason,
          ),
        );
      } else {
        // إذا مر أكثر من 11.5 ساعة على وقت تسجيل الحضور ولم يسجل انصراف، يتم إغلاقه ديناميكياً
        final isExpired = DateTime.now().difference(checkInTime) >= kAttendanceAutoCloseAfter;
        if (isExpired) {
          history.add(
            AttendanceModel(
              id: checkInId,
              userId: userId,
              organizationId: targetOrgId,
              checkInTime: checkInTime,
              checkOutTime: checkInTime.add(kAttendanceAutoCloseAfter),
              latitude: lat,
              longitude: lng,
              branchName: branchName,
              branchId: branchId,
              branchOrganizationUID: branchOrganizationUID,
              isAutoCheckOut: true,
              autoCheckOutReason: kAttendanceAutoCloseReasonAr,
            ),
          );
        } else {
          history.add(
            AttendanceModel(
              id: checkInId,
              userId: userId,
              organizationId: targetOrgId,
              checkInTime: checkInTime,
              latitude: lat,
              longitude: lng,
              branchName: branchName,
              branchId: branchId,
              branchOrganizationUID: branchOrganizationUID,
            ),
          );
        }
      }
    }

    history.sort((a, b) => b.checkInTime.compareTo(a.checkInTime));
    return history;
  }

  @override
  Future<AttendanceModel?> findActiveAttendance(
    String userId,
    String organizationId,
  ) async {
    try {
      final querySnapshot = await _attendanceCollection(organizationId)
          .where('delegateId', isEqualTo: userId)
          .orderBy('timestamp', descending: true)
          .limit(1)
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));

      if (querySnapshot.docs.isEmpty) return null;

      final doc = querySnapshot.docs.first;
      final data = doc.data();

      if (data['type'] == 'check_in') {
        // Denormalized checkout on the check-in doc (fix2) means session is closed.
        if (data['checkOutTime'] != null) {
          return null;
        }

        final checkInTime = data['timestamp'] != null
            ? (data['timestamp'] as Timestamp).toDate()
            : DateTime.now();

        DateTime nowTime;
        try {
          nowTime = sl<TrustedTimeService>().now;
        } catch (_) {
          nowTime = DateTime.now();
        }

        if (nowTime.difference(checkInTime) >= kAttendanceAutoCloseAfter) {
          // انتهت مدة الشفت (11.5 ساعة) - إغلاق الجلسة تلقائياً في الخلفية وتحرير المندوب
          unawaited(
            _autoCheckOutExpiredSession(
              checkInDoc: doc,
              organizationId: organizationId,
              autoCheckOutTime: checkInTime.add(kAttendanceAutoCloseAfter),
            ),
          );
          return null;
        }

        return AttendanceModel(
          id: doc.id,
          userId: data['delegateId'] ?? data['userId'] ?? '',
          organizationId: organizationId,
          checkInTime: checkInTime,
          latitude: (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
          longitude:
              (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
          branchName: data['branchName'],
          branchId: data['branchId'] as String?,
          branchOrganizationUID: (data['branchOrganizationUID'] as String?) ??
              data['organizationId'] as String?,
        );
      }

      return null;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في البحث عن جلسة الحضور النشطة.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم.');
    } catch (_) {
      throwUnexpectedFailure();
    }
  }

  /// In-flight check-in attempts whose result is unknown (timed out), keyed
  /// by delegate + day, so a retry reuses the same document ID.
  static final Map<String, String> _pendingCheckInIds = {};

  @visibleForTesting
  static void resetPendingAttempts() => _pendingCheckInIds.clear();

  static String _pendingCheckInKey(String userId, DateTime now) =>
      '$userId|${now.year}-${now.month}-${now.day}';

  DateTime _trustedNow() {
    try {
      return sl<TrustedTimeService>().now;
    } catch (_) {
      return DateTime.now();
    }
  }

  Future<Map<String, dynamic>?> _serverDocData(
    DocumentReference<Map<String, dynamic>> ref,
  ) async {
    try {
      final snap = await ref
          .get(const GetOptions(source: Source.server))
          .timeout(const Duration(seconds: 6));
      return snap.exists ? snap.data() : null;
    } catch (_) {
      return null;
    }
  }

  Future<bool> _existsOnServer(
    DocumentReference<Map<String, dynamic>> ref,
  ) async =>
      await _serverDocData(ref) != null;

  AttendanceModel _checkedOutModel(
    String attendanceId,
    String organizationId,
    Map<String, dynamic> data,
  ) {
    final out = data['checkOutTime'];
    return AttendanceModel(
      id: attendanceId,
      userId: (data['delegateId'] ?? data['userId'] ?? '').toString(),
      organizationId: organizationId,
      checkInTime: (data['timestamp'] as Timestamp).toDate(),
      checkOutTime: out is Timestamp ? out.toDate() : _trustedNow(),
      latitude: (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
      longitude: (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
      branchName: data['branchName'],
      branchId: data['branchId'] as String?,
      branchOrganizationUID: (data['branchOrganizationUID'] as String?) ??
          data['organizationId'] as String?,
    );
  }

  Future<void> _autoCheckOutExpiredSession({
    required DocumentSnapshot<Map<String, dynamic>> checkInDoc,
    required String organizationId,
    required DateTime autoCheckOutTime,
  }) async {
    try {
      final data = checkInDoc.data()!;
      final userId = (data['delegateId'] ?? data['userId'] ?? '').toString();
      final companyId = data['companyId'];
      final branchName = data['branchName'];
      final lat = (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0;
      final lng = (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0;

      final autoOutRef = _attendanceCollection(organizationId).doc();
      final autoBatch = firestore.batch();
      autoBatch.set(autoOutRef, {
        'delegateId': userId,
        'userId': userId,
        'companyId': companyId,
        'organizationId': organizationId,
        'timestamp': Timestamp.fromDate(autoCheckOutTime),
        'type': 'check_out',
        'location': {'latitude': lat, 'longitude': lng},
        'relatedCheckInId': checkInDoc.id,
        'isAutoCheckOut': true,
        'autoCheckOutReason': kAttendanceAutoCloseReasonAr,
        'branchName': ?branchName,
      });
      autoBatch.update(checkInDoc.reference, {
        'checkOutTime': Timestamp.fromDate(autoCheckOutTime),
        'checkOutLocation': {'latitude': lat, 'longitude': lng},
        'checkOutDocId': autoOutRef.id,
        'isAutoCheckOut': true,
        'autoCheckOutReason': kAttendanceAutoCloseReasonAr,
      });
      await autoBatch.commit();

      unawaited(
        _syncDelegateTrackingCheckOut(userId: userId),
      );
    } catch (e) {
      debugPrint('Error auto checking out expired session: $e');
    }
  }

  @override
  Stream<AttendanceModel?> streamActiveAttendance(
    String userId,
    String organizationId,
  ) {
    return _attendanceCollection(organizationId)
        .where('delegateId', isEqualTo: userId)
        .orderBy('timestamp', descending: true)
        .limit(1)
        .streamResilient(includeMetadataChanges: true)
        .map((snapshot) {
          if (snapshot.docs.isEmpty) return null;
          final doc = snapshot.docs.first;
          final data = doc.data();
          if (data['type'] == 'check_in') {
            if (data['checkOutTime'] != null) {
              return null;
            }
            return AttendanceModel(
              id: doc.id,
              userId: data['delegateId'] ?? data['userId'] ?? '',
              organizationId: organizationId,
              checkInTime: data['timestamp'] != null
                  ? (data['timestamp'] as Timestamp).toDate()
                  : DateTime.now(),
              latitude: (data['location']?['latitude'] as num?)?.toDouble() ?? 0.0,
              longitude:
                  (data['location']?['longitude'] as num?)?.toDouble() ?? 0.0,
              branchName: data['branchName'],
              branchId: data['branchId'] as String?,
              branchOrganizationUID:
                  (data['branchOrganizationUID'] as String?) ??
                  data['organizationId'] as String?,
            );
          }
          return null;
        });
  }

  @override
  Future<void> syncOfflineQueue(List<Map<String, dynamic>> queue) async {
    try {
      final batch = firestore.batch();
      for (var action in queue) {
        final organizationId = action['organizationId'] as String? ?? '';
        final newDocRef = _attendanceCollection(organizationId).doc();
        final Map<String, dynamic> data = {
          'delegateId': action['delegateId'],
          'userId': action['delegateId'],
          'companyId': action['companyId'],
          'organizationId': organizationId,
          'timestamp': FieldValue.serverTimestamp(),
          'type': action['type'],
          'location': action['location'],
        };

        if (action['deviceInfo'] != null) {
          data['deviceInfo'] = action['deviceInfo'];
        }
        if (action['branchName'] != null) {
          data['branchName'] = action['branchName'];
        }
        if (action['branchId'] != null) {
          data['branchId'] = action['branchId'];
        }
        if (action['branchOrganizationUID'] != null) {
          data['branchOrganizationUID'] = action['branchOrganizationUID'];
        }
        if (action['relatedCheckInId'] != null) {
          data['relatedCheckInId'] = action['relatedCheckInId'];
        }
        // Fix3: pass through denormalized display fields when queued offline.
        for (final key in [
          'delegateName',
          'phoneNumber',
          'companyName',
          'personalPhotoURL',
        ]) {
          final v = action[key];
          if (v is String && v.trim().isNotEmpty) {
            data[key] = v.trim();
          }
        }

        batch.set(newDocRef, data);

        // Denormalize checkout onto the related check-in (fix2).
        if (action['type'] == 'check_out' &&
            action['relatedCheckInId'] is String &&
            (action['relatedCheckInId'] as String).isNotEmpty) {
          final relatedId = action['relatedCheckInId'] as String;
          batch.update(
            _attendanceCollection(organizationId).doc(relatedId),
            {
              'checkOutTime': FieldValue.serverTimestamp(),
              'checkOutDocId': newDocRef.id,
              if (action['location'] != null) 'checkOutLocation': action['location'],
            },
          );
        }
      }

      await batch.commit().timeout(const Duration(seconds: 20));
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في مزامنة البيانات المؤجلة.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم أثناء المزامنة.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء المزامنة.');
    }
  }

  @override
  Future<ResolvedBranchDocument?> resolveBranch({
    String? branchId,
    String? organizationUID,
    String? branchName,
  }) async {
    try {
      final trimmedId = branchId?.trim() ?? '';
      final trimmedOrg = organizationUID?.trim() ?? '';
      final trimmedName = branchName?.trim() ?? '';

      if (trimmedId.isNotEmpty) {
        if (trimmedOrg.isNotEmpty) {
          final nestedRef = firestore
              .collection('organizations')
              .doc(trimmedOrg)
              .collection('branches')
              .doc(trimmedId);
          final nestedSnap = await nestedRef
              .get(const GetOptions(source: Source.server))
              .timeout(const Duration(seconds: 5));
          if (nestedSnap.exists && nestedSnap.data() != null) {
            return ResolvedBranchDocument(
              documentId: nestedSnap.id,
              data: {
                ...nestedSnap.data()!,
                'organizationUID': trimmedOrg,
              },
            );
          }
        }

        final rootDoc = await firestore
            .collection('branches')
            .doc(trimmedId)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
        if (rootDoc.exists && rootDoc.data() != null) {
          final data = rootDoc.data()!;
          if (trimmedOrg.isNotEmpty) {
            final docOrg = (data['organizationUID'] ?? data['organizationId'])
                ?.toString()
                .trim();
            if (docOrg != null && docOrg.isNotEmpty && docOrg != trimmedOrg) {
              return null;
            }
          }
          return ResolvedBranchDocument(documentId: rootDoc.id, data: data);
        }
      }

      if (trimmedName.isNotEmpty && trimmedOrg.isNotEmpty) {
        final scopedSnap = await firestore
            .collection('branches')
            .where('branchName', isEqualTo: trimmedName)
            .where('organizationUID', isEqualTo: trimmedOrg)
            .limit(1)
            .getResilient(
              timeout: const Duration(seconds: 5),
              forceServer: true,
            );
        if (scopedSnap.docs.isNotEmpty) {
          final doc = scopedSnap.docs.first;
          return ResolvedBranchDocument(documentId: doc.id, data: doc.data());
        }

        final nestedSnap = await firestore
            .collection('organizations')
            .doc(trimmedOrg)
            .collection('branches')
            .where('branchName', isEqualTo: trimmedName)
            .limit(1)
            .get(const GetOptions(source: Source.server))
            .timeout(const Duration(seconds: 5));
        if (nestedSnap.docs.isNotEmpty) {
          final doc = nestedSnap.docs.first;
          return ResolvedBranchDocument(
            documentId: doc.id,
            data: {
              ...doc.data(),
              'organizationUID': trimmedOrg,
            },
          );
        }
      }

      return null;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الفرع. يرجى المحاولة مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم أثناء جلب بيانات الفرع.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء البحث عن الفرع.');
    }
  }

  @override
  Future<Map<String, dynamic>?> getBranchByName(String branchName) async {
    final resolved = await resolveBranch(branchName: branchName);
    return resolved?.data;
  }

  @override
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
    String? branchId,
    String? organizationUID,
  }) async {
    try {
      final trimmedId = branchId?.trim() ?? '';
      final trimmedOrg = organizationUID?.trim() ?? '';
      final Map<String, dynamic> data = {
        'branchName': branchName,
        'location': {'latitude': latitude, 'longitude': longitude},
        'geofenceRadius': geofenceRadius,
        'updatedAt': FieldValue.serverTimestamp(),
        if (trimmedOrg.isNotEmpty) 'organizationUID': trimmedOrg,
      };

      if (trimmedId.isNotEmpty) {
        await firestore
            .collection('branches')
            .doc(trimmedId)
            .set(data, SetOptions(merge: true))
            .timeout(const Duration(seconds: 15));
        BranchesSessionCache.invalidate();
        return;
      }

      if (trimmedOrg.isNotEmpty) {
        final querySnapshot = await firestore
            .collection('branches')
            .where('branchName', isEqualTo: branchName)
            .where('organizationUID', isEqualTo: trimmedOrg)
            .limit(1)
            .getResilient(
              timeout: const Duration(seconds: 5),
              forceServer: true,
            );
        if (querySnapshot.docs.isNotEmpty) {
          await querySnapshot.docs.first.reference
              .update(data)
              .timeout(const Duration(seconds: 15));
          BranchesSessionCache.invalidate();
          return;
        }
      }

      await firestore
          .collection('branches')
          .add(data)
          .timeout(const Duration(seconds: 15));
      BranchesSessionCache.invalidate();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في حفظ بيانات الفرع.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء حفظ بيانات الفرع.');
    }
  }

  Future<void> _notifySupervisorsOfAttendance({
    required String userId,
    required String companyId,
    required String organizationId,
    required String? branchName,
    required String type,
    required DateTime time,
  }) async {
    try {
      if (companyId.isEmpty) return;

      // 1. Resolve delegate name
      String delegateName = 'المندوب';
      try {
        final userDoc = await firestore.collection('users').doc(userId).get();
        if (userDoc.exists) {
          final data = userDoc.data();
          final name = data?['fullName'] ??
              data?['name'] ??
              '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
          if (name is String && name.trim().isNotEmpty) {
            delegateName = name.trim();
          }
        }
      } catch (_) {}

      // Format time in Arabic: e.g. 02:00 م
      final isAm = time.hour < 12;
      final hour12 = time.hour == 0 ? 12 : (time.hour > 12 ? time.hour - 12 : time.hour);
      final hourStr = hour12.toString().padLeft(2, '0');
      final minStr = time.minute.toString().padLeft(2, '0');
      final periodStr = isAm ? 'ص' : 'م';
      final formattedTime = '$hourStr:$minStr $periodStr';
      final safeBranchName =
          (branchName != null && branchName.trim().isNotEmpty) ? branchName.trim() : 'الفرع';

      final bool isCheckIn = type == 'check_in';
      final title = isCheckIn
          ? 'تسجيل حضور مندوب: $delegateName'
          : 'تسجيل انصراف مندوب: $delegateName';
      final body = isCheckIn
          ? 'قام المندوب $delegateName بتسجيل الحضور بنجاح في فرع ($safeBranchName) الساعة $formattedTime.'
          : 'قام المندوب $delegateName بتسجيل الانصراف بنجاح من فرع ($safeBranchName) الساعة $formattedTime.';
      final notifType = isCheckIn ? 'attendance_check_in' : 'attendance_check_out';

      // TAS-71: one broadcast to the company's supervisors. A delegate cannot
      // list `users` under the rules, and the per-supervisor fan-out needed
      // that list. `supervisor_<companyUID>` is what the supervisor inbox
      // already reads, and the create rule needs `createdBy` == auth uid plus
      // the delegate's own company. The old `company_<id>` copy was readable
      // by every delegate in the company and the `all_company_supervisors`
      // copy was a duplicate, so neither is written any more.
      await firestore.collection('notifications').add({
        'title': title,
        'body': body,
        'type': notifType,
        'attendanceType': type,
        'companyId': companyId,
        'companyUID': companyId,
        'organizationId': organizationId,
        'organizationUID': organizationId,
        'branchName': safeBranchName,
        'targetDelegateId': userId,
        'targetDelegateName': delegateName,
        'senderName': delegateName,
        'senderRole': 'delegate',
        'delegateUid': 'supervisor_$companyId',
        // TAS-28: own delegate id (delegateId claim), not the Auth uid.
        'createdBy': (auth != null ? DelegateIdentity.current(auth) : null) ?? userId,
        'isRead': false,
        'read': false,
        'createdAt': FieldValue.serverTimestamp(),
        'deletedBy': <String>[],
      });
    } catch (e) {
      // Not fatal for the check-in itself, but it must not vanish silently.
      debugPrint('attendance supervisor alert failed ($type): $e');
    }
  }

  Future<void> _syncDelegateTrackingCheckIn({
    required String userId,
    required String companyId,
    required String organizationId,
    required AttendanceBranchRef branchRef,
    required double lat,
    required double long,
    required DateTime time,
  }) async {
    try {
      String delegateName = 'مندوب';
      String delegatePhone = '';
      try {
        if (organizationId.isNotEmpty && companyId.isNotEmpty) {
          final nestedDoc = await firestore
              .collection('organizations')
              .doc(organizationId)
              .collection('companies')
              .doc(companyId)
              .collection('delegates')
              .doc(userId)
              .get();
          if (nestedDoc.exists) {
            final data = nestedDoc.data();
            final rawFull = (data?['fullName'] ?? data?['name'])?.toString().trim();
            final combined = '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
            delegateName = (rawFull != null && rawFull.isNotEmpty) ? rawFull : (combined.isNotEmpty ? combined : 'مندوب');
            delegatePhone = (data?['phoneNumber'] ?? data?['phone'] ?? data?['mobileNumber'] ?? '').toString();
          }
        }

        if (delegateName == 'مندوب') {
          final delDoc = await firestore.collection('delegates').doc(userId).get();
          if (delDoc.exists) {
            final data = delDoc.data();
            final rawFull = (data?['fullName'] ?? data?['name'])?.toString().trim();
            final combined = '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim();
            delegateName = (rawFull != null && rawFull.isNotEmpty) ? rawFull : (combined.isNotEmpty ? combined : 'مندوب');
            delegatePhone = (data?['phoneNumber'] ?? data?['phone'] ?? data?['mobileNumber'] ?? '').toString();
          } else {
            final userDoc = await firestore.collection('users').doc(userId).get();
            if (userDoc.exists) {
              final data = userDoc.data();
              delegateName = (data?['fullName'] ??
                      data?['name'] ??
                      '${data?['firstName'] ?? ''} ${data?['lastName'] ?? ''}'.trim())
                  .toString();
              delegatePhone = (data?['phoneNumber'] ??
                      data?['phone'] ??
                      data?['mobileNumber'] ??
                      '')
                  .toString();
            }
          }
        }
      } catch (e, st) {
        debugPrint(
          'AttendanceTrackingSync: failed loading delegate profile on check-in: $e\n$st',
        );
      }

      double branchLat = 0.0;
      double branchLng = 0.0;
      double geofenceRadius = 100.0;
      String resolvedBranchId = branchRef.branchId ?? '';

      try {
        final resolved = await resolveBranch(
          branchId: branchRef.branchId,
          organizationUID: branchRef.branchOrganizationUID,
          branchName: branchRef.branchName,
        );
        if (resolved != null) {
          resolvedBranchId = resolved.documentId;
          final bData = resolved.data;
          final loc = bData['location'];
          if (loc is Map) {
            branchLat = (loc['latitude'] as num?)?.toDouble() ??
                (loc['lat'] as num?)?.toDouble() ??
                0.0;
            branchLng = (loc['longitude'] as num?)?.toDouble() ??
                (loc['lng'] as num?)?.toDouble() ??
                0.0;
          }
          branchLat = branchLat != 0.0
              ? branchLat
              : (bData['latitude'] as num?)?.toDouble() ?? 0.0;
          branchLng = branchLng != 0.0
              ? branchLng
              : (bData['longitude'] as num?)?.toDouble() ?? 0.0;
          geofenceRadius =
              (bData['geofenceRadius'] as num?)?.toDouble() ?? 100.0;
        }
      } catch (e, st) {
        debugPrint(
          'AttendanceTrackingSync: failed loading branch on check-in: $e\n$st',
        );
      }

      final branchName = branchRef.branchName;

      // احتساب المسافة الدقيقة عن الفرع ونسبة البطارية الحقيقية
      final exactDist =
          Geolocator.distanceBetween(lat, long, branchLat, branchLng);
      final isInside = exactDist <= (geofenceRadius + 50.0);

      int? batteryLevel;
      try {
        batteryLevel = await Battery().batteryLevel;
      } catch (e, st) {
        debugPrint(
          'AttendanceTrackingSync: failed reading battery on check-in: $e\n$st',
        );
      }

      await firestore.collection('delegate_tracking').doc(userId).set({
        'delegateId': userId,
        'delegateName': delegateName,
        'delegatePhone': delegatePhone,
        'companyId': companyId,
        'companyUID': companyId,
        'organizationId': organizationId,
        'organizationUID': organizationId,
        'branchId': resolvedBranchId,
        'branchName': branchName.isNotEmpty ? branchName : 'الفرع الميداني',
        'branchLat': branchLat,
        'branchLng': branchLng,
        'geofenceRadius': geofenceRadius,
        'currentStatus': isInside ? 'inside' : 'outside',
        'currentDistanceMeters': exactDist,
        'lastLatitude': lat,
        'lastLongitude': long,
        'speed': 0.0,
        'batteryLevel': ?batteryLevel,
        'isMoving': false,
        'lastUpdated': FieldValue.serverTimestamp(),
        'checkInTime': Timestamp.fromDate(time),
        'checkOutTime': FieldValue.delete(),
        'isOnline': true,
      }, SetOptions(merge: true));

      // تسجيل أول نقطة مسار (First Breadcrumb)
      try {
        await firestore
            .collection('delegate_tracking')
            .doc(userId)
            .collection('breadcrumbs')
            .add({
          'latitude': lat,
          'longitude': long,
          'timestamp': FieldValue.serverTimestamp(),
          'speed': 0.0,
          'batteryLevel': ?batteryLevel,
          'distanceMeters': exactDist,
          'isInside': isInside,
        });
      } catch (e, st) {
        debugPrint(
          'AttendanceTrackingSync: failed writing check-in breadcrumb: $e\n$st',
        );
      }

      // بدء محرك التتبع الدوري في جهاز المندوب
      try {
        unawaited(
          DelegateTrackingEngine().startTrackingSession(delegateId: userId),
        );
      } catch (e, st) {
        debugPrint(
          'AttendanceTrackingSync: failed starting tracking engine: $e\n$st',
        );
      }
    } catch (e, st) {
      // Never fail the attendance write because of tracking sync.
      debugPrint(
        'AttendanceTrackingSync: error syncing delegate tracking on check-in: $e\n$st',
      );
    }
  }

  Future<void> _syncDelegateTrackingCheckOut({
    required String userId,
  }) async {
    try {
      DelegateTrackingEngine().stopTrackingSession();
      await firestore.collection('delegate_tracking').doc(userId).update({
        'currentStatus': 'checked_out',
        // TAS-364: the session ends by status; isTrackingEnabled is the
        // supervisor's switch and a check-out no longer touches it.
        'isOnline': false,
        'checkOutTime': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (e, st) {
      // Never fail the attendance write because of tracking sync.
      debugPrint(
        'AttendanceTrackingSync: error syncing delegate tracking on check-out: $e\n$st',
      );
    }
  }
}
