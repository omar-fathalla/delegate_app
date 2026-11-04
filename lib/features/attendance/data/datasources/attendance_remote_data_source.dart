import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'dart:async';
import 'package:flutter/foundation.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
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

abstract class AttendanceRemoteDataSource {
  Future<AttendanceModel> checkIn(
    String userId,
    double lat,
    double long, {
    required String companyId,
    required String organizationId,
    required String deviceInfo,
    String? branchName,
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

  /// Fetches branch details by name.
  Future<Map<String, dynamic>?> getBranchByName(String branchName);

  /// Saves or updates a branch with its geofence data.
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
  });
}

class AttendanceRemoteDataSourceImpl implements AttendanceRemoteDataSource {
  final FirebaseFirestore firestore;

  AttendanceRemoteDataSourceImpl({required this.firestore});

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
    String? delegateName,
    String? phoneNumber,
    String? companyName,
    String? personalPhotoURL,
  }) async {
    try {
      // Guard against duplicate active check-in in Firestore
      try {
        final existingActive = await findActiveAttendance(
          userId,
          organizationId,
        ).timeout(const Duration(seconds: 4));

        if (existingActive != null) {
          DateTime now;
          try {
            now = sl<TrustedTimeService>().now;
          } catch (_) {
            now = DateTime.now();
          }

          final isSameDay = existingActive.checkInTime.year == now.year &&
              existingActive.checkInTime.month == now.month &&
              existingActive.checkInTime.day == now.day;

          if (isSameDay) {
            if (existingActive.branchName == branchName) {
              throw const ServerFailure(
                'أنت مسجل حضور بالفعل في هذا الفرع وما زالت الجلسة جارية.',
              );
            } else {
              throw ServerFailure(
                'لديك تسجيل حضور نشط في فرع ${existingActive.branchName ?? "آخر"}. يرجى تسجيل الانصراف أولاً.',
              );
            }
          }
        }
      } on Failure {
        rethrow;
      } catch (e) {
        debugPrint('Active check-in verification warning: $e');
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

      final docRef = await _attendanceCollection(organizationId)
          .add(checkInPayload)
          .timeout(const Duration(seconds: 15));

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
          branchName: branchName,
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
      final lastCheckInSnapshot = await _attendanceCollection(
        organizationId,
      ).doc(attendanceId).get().timeout(const Duration(seconds: 15));

      if (!lastCheckInSnapshot.exists) {
        throw const ServerFailure('سجل الحضور غير موجود.');
      }
      final lastData = lastCheckInSnapshot.data()!;
      final userId = lastData['delegateId'] ?? lastData['userId'];
      final companyId = lastData['companyId'];

      // Keep a separate check_out log for history/HR, and denormalize
      // checkOutTime onto the check-in doc so marketing today-views skip
      // the historical follow-up query.
      final outRef = _attendanceCollection(organizationId).doc();
      final checkInRef = _attendanceCollection(organizationId).doc(attendanceId);
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
      });
      batch.update(checkInRef, {
        'checkOutTime': FieldValue.serverTimestamp(),
        'checkOutLocation': {'latitude': lat, 'longitude': long},
        'checkOutDocId': outRef.id,
      });
      await batch.commit().timeout(const Duration(seconds: 15));

      // Auto-resolve any orphaned unclosed check-in for the same user and branch today
      try {
        final orphanedSnaps = await _attendanceCollection(organizationId)
            .where('delegateId', isEqualTo: userId)
            .where('type', isEqualTo: 'check_in')
            .where('branchName', isEqualTo: lastData['branchName'])
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
      final Set<String> identifiers = {userId};

      if (nationalityID != null && nationalityID.trim().isNotEmpty) {
        final cleanNat = nationalityID.trim();
        identifiers.add(cleanNat);

        // Resolve any other delegate UIDs registered under this National ID
        try {
          final natSnap = await firestore
              .collectionGroup('delegates')
              .where('nationalityID', isEqualTo: cleanNat)
              .limit(10)
              .getResilient(
                timeout: const Duration(seconds: 4),
                forceServer: true,
              );
          for (final doc in natSnap.docs) {
            identifiers.add(doc.id);
          }
        } catch (_) {}
      }

      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        final cleanPhone = phoneNumber.trim();
        final normalizedPhone = _normalizePhone(cleanPhone);
        identifiers.add(cleanPhone);
        if (normalizedPhone.isNotEmpty) {
          identifiers.add(normalizedPhone);
        }

        // Resolve any other delegate UIDs registered under this phone number
        try {
          final phoneSnap = await firestore
              .collectionGroup('delegates')
              .where('phoneNumber', isEqualTo: normalizedPhone)
              .limit(10)
              .getResilient(
                timeout: const Duration(seconds: 4),
                forceServer: true,
              );
          for (final doc in phoneSnap.docs) {
            identifiers.add(doc.id);
          }
        } catch (_) {}
      }

      final queryList = identifiers.where((id) => id.isNotEmpty).take(30).toList();
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

  @override
  Future<List<AttendanceModel>> getRecentSessionsAcrossOrgs(
    String userId, {
    String? nationalityID,
    String? phoneNumber,
    int limit = 6,
  }) async {
    try {
      final Set<String> identifiers = {userId};
      if (nationalityID != null && nationalityID.trim().isNotEmpty) {
        identifiers.add(nationalityID.trim());
      }
      if (phoneNumber != null && phoneNumber.trim().isNotEmpty) {
        final cleanPhone = phoneNumber.trim();
        identifiers.add(cleanPhone);
        final normalized = _normalizePhone(cleanPhone);
        if (normalized.isNotEmpty) identifiers.add(normalized);
      }
      final queryList = identifiers.where((id) => id.isNotEmpty).take(30).toList();

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
            isAutoCheckOut: isAuto,
            autoCheckOutReason: autoReason,
          ),
        );
      } else {
        // إذا مر أكثر من 9 ساعات على وقت تسجيل الحضور ولم يسجل انصراف، يتم إغلاقه ديناميكياً
        final isExpired = DateTime.now().difference(checkInTime) >= const Duration(hours: 9);
        if (isExpired) {
          history.add(
            AttendanceModel(
              id: checkInId,
              userId: userId,
              organizationId: targetOrgId,
              checkInTime: checkInTime,
              checkOutTime: checkInTime.add(const Duration(hours: 9)),
              latitude: lat,
              longitude: lng,
              branchName: branchName,
              isAutoCheckOut: true,
              autoCheckOutReason: 'نهاية شيفت العمل (9 ساعات) - إغلاق تلقائي',
            ),
          );
        } else {
          history.add(
            AttendanceModel(
              id: checkInId,
              userId: userId,
              organizationId: organizationId,
              checkInTime: checkInTime,
              latitude: lat,
              longitude: lng,
              branchName: branchName,
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
          .getResilient(
            timeout: const Duration(seconds: 5),
            forceServer: true,
          );

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

        if (nowTime.difference(checkInTime) >= const Duration(hours: 9)) {
          // انتهت مدة الشفت (9 ساعات) - إغلاق الجلسة تلقائياً في الخلفية وتحرير المندوب
          unawaited(
            _autoCheckOutExpiredSession(
              checkInDoc: doc,
              organizationId: organizationId,
              autoCheckOutTime: checkInTime.add(const Duration(hours: 9)),
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
        'autoCheckOutReason': 'نهاية شيفت العمل (9 ساعات) - إغلاق تلقائي',
        'branchName': ?branchName,
      });
      autoBatch.update(checkInDoc.reference, {
        'checkOutTime': Timestamp.fromDate(autoCheckOutTime),
        'checkOutLocation': {'latitude': lat, 'longitude': lng},
        'checkOutDocId': autoOutRef.id,
        'isAutoCheckOut': true,
        'autoCheckOutReason': 'نهاية شيفت العمل (9 ساعات) - إغلاق تلقائي',
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
  Future<Map<String, dynamic>?> getBranchByName(String branchName) async {
    try {
      final querySnapshot = await firestore
          .collection('branches')
          .where('branchName', isEqualTo: branchName.trim())
          .limit(1)
          .getResilient(
            timeout: const Duration(seconds: 5),
            forceServer: true,
          );

      if (querySnapshot.docs.isEmpty) {
        final groupSnap = await firestore
            .collectionGroup('branches')
            .where('branchName', isEqualTo: branchName.trim())
            .limit(1)
            .getResilient(
              timeout: const Duration(seconds: 5),
              forceServer: true,
            );
        if (groupSnap.docs.isNotEmpty) {
          return groupSnap.docs.first.data();
        }
        return null;
      }

      return querySnapshot.docs.first.data();
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب بيانات الفرع. يرجى المحاولة مرة أخرى.');
    } on TimeoutException {
      throwTimeoutFailure('انتهت مهلة الاتصال بالخادم أثناء جلب بيانات الفرع.');
    } catch (_) {
      throwUnexpectedFailure('حدث خطأ غير متوقع أثناء البحث عن الفرع.');
    }
  }

  @override
  Future<void> saveBranch({
    required String branchName,
    required double latitude,
    required double longitude,
    required double geofenceRadius,
  }) async {
    try {
      final querySnapshot = await firestore
          .collection('branches')
          .where('branchName', isEqualTo: branchName)
          .limit(1)
          .getResilient(
            timeout: const Duration(seconds: 5),
            forceServer: true,
          );

      final Map<String, dynamic> data = {
        'branchName': branchName,
        'location': {'latitude': latitude, 'longitude': longitude},
        'geofenceRadius': geofenceRadius,
        'updatedAt': FieldValue.serverTimestamp(),
      };

      if (querySnapshot.docs.isEmpty) {
        await firestore
            .collection('branches')
            .add(data)
            .timeout(const Duration(seconds: 15));
      } else {
        await querySnapshot.docs.first.reference
            .update(data)
            .timeout(const Duration(seconds: 15));
      }
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

      final notifiedSupervisorUids = <String>{};

      // 2. Direct Supervisor Notifications from users collection
      final supervisorQueries = [
        firestore.collection('users').where('companyUID', isEqualTo: companyId),
        firestore.collection('users').where('companyId', isEqualTo: companyId),
      ];

      for (final q in supervisorQueries) {
        try {
          final snap = await q.get();
          for (final doc in snap.docs) {
            if (notifiedSupervisorUids.contains(doc.id)) continue;
            final uData = doc.data();
            final role = uData['role']?.toString().toLowerCase() ?? '';
            final pos = uData['position']?.toString().toLowerCase() ?? '';
            if (role.contains('supervisor') ||
                role.contains('admin') ||
                role.contains('company') ||
                pos.contains('supervisor') ||
                role == 'admin') {
              notifiedSupervisorUids.add(doc.id);
              final phone =
                  (uData['phoneNumber'] ?? uData['phone'] ?? uData['mobileNumber']) as String?;
              await firestore.collection('notifications').add({
                'title': title,
                'body': body,
                'type': notifType,
                'attendanceType': type,
                'companyId': companyId,
                'organizationId': organizationId,
                'branchName': safeBranchName,
                'targetDelegateId': userId,
                'targetDelegateName': delegateName,
                'senderName': delegateName,
                'senderRole': 'delegate',
                'delegateUid': doc.id,
                if (phone != null && phone.isNotEmpty) 'phoneNumber': phone,
                'isRead': false,
                'read': false,
                'createdAt': Timestamp.fromDate(time),
                'deletedBy': <String>[],
              });
            }
          }
        } catch (_) {}
      }

      // 3. Broadcast channels for company & supervisors
      for (final targetKey in [
        'supervisor_$companyId',
        'company_$companyId',
        'all_company_supervisors',
      ]) {
        await firestore.collection('notifications').add({
          'title': title,
          'body': body,
          'type': notifType,
          'attendanceType': type,
          'companyId': companyId,
          'organizationId': organizationId,
          'branchName': safeBranchName,
          'targetDelegateId': userId,
          'targetDelegateName': delegateName,
          'senderName': delegateName,
          'senderRole': 'delegate',
          'delegateUid': targetKey,
          'isRead': false,
          'read': false,
          'createdAt': Timestamp.fromDate(time),
          'deletedBy': <String>[],
        });
      }
    } catch (_) {}
  }

  Future<void> _syncDelegateTrackingCheckIn({
    required String userId,
    required String companyId,
    required String organizationId,
    required String? branchName,
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
      } catch (_) {}

      double branchLat = lat;
      double branchLng = long;
      double geofenceRadius = 100.0;
      String branchId = '';

      if (branchName != null && branchName.trim().isNotEmpty) {
        try {
          final branchQuery = await firestore
              .collection('branches')
              .where('branchName', isEqualTo: branchName.trim())
              .limit(1)
              .get();
          if (branchQuery.docs.isNotEmpty) {
            final bDoc = branchQuery.docs.first;
            final bData = bDoc.data();
            branchId = bDoc.id;
            branchLat = (bData['latitude'] as num?)?.toDouble() ?? lat;
            branchLng = (bData['longitude'] as num?)?.toDouble() ?? long;
            geofenceRadius =
                (bData['geofenceRadius'] as num?)?.toDouble() ?? 100.0;
          }
        } catch (_) {}
      }

      // احتساب المسافة الدقيقة عن الفرع ونسبة البطارية الحقيقية
      final exactDist =
          Geolocator.distanceBetween(lat, long, branchLat, branchLng);
      final isInside = exactDist <= (geofenceRadius + 50.0);

      int? batteryLevel;
      try {
        batteryLevel = await Battery().batteryLevel;
      } catch (_) {}

      await firestore.collection('delegate_tracking').doc(userId).set({
        'delegateId': userId,
        'delegateName': delegateName,
        'delegatePhone': delegatePhone,
        'companyId': companyId,
        'organizationId': organizationId,
        'branchId': branchId,
        'branchName': branchName ?? 'الفرع الميداني',
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
      } catch (_) {}

      // بدء محرك التتبع الدوري في جهاز المندوب
      try {
        unawaited(
          DelegateTrackingEngine().startTrackingSession(delegateId: userId),
        );
      } catch (_) {}
    } catch (e) {
      debugPrint('Error syncing delegate tracking on checkIn: $e');
    }
  }

  Future<void> _syncDelegateTrackingCheckOut({
    required String userId,
  }) async {
    try {
      DelegateTrackingEngine().stopTrackingSession();
      await firestore.collection('delegate_tracking').doc(userId).update({
        'currentStatus': 'checked_out',
        'isTrackingEnabled': false,
        'checkOutTime': FieldValue.serverTimestamp(),
        'lastUpdated': FieldValue.serverTimestamp(),
      });
    } catch (_) {}
  }
}
