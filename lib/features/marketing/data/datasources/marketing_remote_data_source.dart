import 'package:delegate_app/core/services/branches_session_cache.dart';
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/marketing/data/services/delegate_profile_cache.dart';
import 'package:delegate_app/features/marketing/data/services/real_test_metrics.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

abstract class MarketingRemoteDataSource {
  /// Emits once each time today's attendance for [branchNames] changes on the
  /// server (TAS-260). The first snapshot of each query is skipped: it is the
  /// data the screen already loaded. Replaces the 30-second polling timer.
  Stream<void> watchTodayAttendanceChanges({
    required List<String> branchNames,
    required String organizationId,
    DateTime? date,
  });

  Future<List<Map<String, dynamic>>> getCompanies(String organizationUID);

  /// Get companies with pagination
  /// [lastDocument] is the last document from previous page (for pagination)
  /// [limit] is the number of companies to fetch (default 20)
  Future<Map<String, dynamic>> getCompaniesPaginated(
    String organizationUID, {
    DocumentSnapshot? lastDocument,
    int limit = 20,
  });

  Future<List<DelegateModel>> getDelegates(
    String organizationUID,
    String? companyUID,
  );

  /// Emits real-time updates for delegates/promoters
  Stream<List<DelegateModel>> streamDelegates(
    String organizationUID,
    String? companyUID,
  );

  /// Fetch all branches from Firestore
  Future<List<Map<String, dynamic>>> getBranches();

  /// Fetch today's attendance records for a specific branch,
  /// enriched with delegate info (fullName, phoneNumber, personalPhotoURL).
  Future<List<Map<String, dynamic>>> getTodayAttendanceByBranch({
    required String branchName,
    required String organizationId,
    DateTime? date,
  });

  /// Fetch today's attendance records for multiple branches in a single optimized query,
  /// enriched with delegate info (fullName, phoneNumber, personalPhotoURL).
  ///
  /// [onFirstPaint] is invoked once attendance logs (+ local profile caches) are ready,
  /// before any network profile enrichment. The returned Future completes with the
  /// fully enriched map (or the first-paint map if nothing was missing).
  Future<Map<String, List<Map<String, dynamic>>>> getTodayAttendanceForBranches({
    required List<String> branchNames,
    required String organizationId,
    DateTime? date,
    void Function(Map<String, List<Map<String, dynamic>>> partial)? onFirstPaint,
  });
}


/// Whether a delegate still needs a network profile fetch after denorm/cache.
///
/// Name + phone from the attendance log (or local cache) are enough.
/// Missing photo is a **known empty** — most delegates have no personal photo
/// on the check-in doc; requiring a photo forced ~N profile reads every cold load.
bool marketingNeedsNetworkEnrichment({
  required bool hasName,
  required bool hasPhone,
}) =>
    !hasName || !hasPhone;


class MarketingRemoteDataSourceImpl implements MarketingRemoteDataSource {
  final FirebaseFirestore firestore;
  final DelegateProfileCache? profileCache;

  MarketingRemoteDataSourceImpl({
    required this.firestore,
    this.profileCache,
  });

  /// التطبيع الموحد لأسماء الفروع لمنع أي فقدان في السجلات بسبب الهمزات والمسافات
  static String normalizeBranchName(String name) {
    return name
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[أإآ]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  List<DelegateModel> _deduplicateDelegates(Iterable<DelegateModel> list) {
    final seen = <String>{};
    final result = <DelegateModel>[];
    for (final d in list) {
      final key = d.uid.isNotEmpty ? '${d.companyUID}_${d.uid}' : '${d.companyUID}_${d.phoneNumber}';
      if (seen.add(key)) {
        result.add(d);
      }
    }
    return result;
  }

  @override
  Future<List<Map<String, dynamic>>> getCompanies(
    String organizationUID,
  ) async {
    try {
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .getResilient(forceServer: true);

      // Get list of companies with their data, deduplicated by uid
      final seenIds = <String>{};
      final companies = <Map<String, dynamic>>[];
      for (final doc in snapshot.docs) {
        if (seenIds.add(doc.id)) {
          companies.add({'uid': doc.id, ...doc.data()});
        }
      }

      // Parallelize marketing user lookups across all companies instead of sequential N+1 loop
      await Future.wait(
        companies.map((company) async {
          try {
            final userQuery = await firestore
                .collection('users')
                .where('organizationUID', isEqualTo: organizationUID)
                .where('companyUID', isEqualTo: company['uid'])
                .where('role', isEqualTo: 'marketing')
                .limit(1)
                .getResilient(forceServer: true);

            if (userQuery.docs.isNotEmpty) {
              final userData = userQuery.docs.first.data();
              company['marketingUserName'] =
                  userData['displayName'] ?? 'موظف تسويق';
            } else {
              company['marketingUserName'] = null;
            }
          } catch (_) {
            company['marketingUserName'] = null;
          }
        }),
      );

      return companies;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب قائمة الشركات.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }

  @override
  Future<Map<String, dynamic>> getCompaniesPaginated(
    String organizationUID, {
    DocumentSnapshot? lastDocument,
    int limit = 20,
  }) async {
    try {
      // Build query with pagination
      Query query = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .orderBy('name') // Order by name for consistent pagination
          .limit(limit + 1); // Fetch one extra to check if there are more

      // If we have a last document, start after it
      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final snapshot = await query.getResilient(forceServer: true);

      // Check if there are more companies
      final hasMore = snapshot.docs.length > limit;
      final docs = hasMore ? snapshot.docs.take(limit).toList() : snapshot.docs;

      // Get list of companies with their data, deduplicated by uid
      final seenIds = <String>{};
      final companies = <Map<String, dynamic>>[];
      for (final doc in docs) {
        if (seenIds.add(doc.id)) {
          companies.add({'uid': doc.id, ...doc.data() as Map<String, dynamic>});
        }
      }

      // Parallelize marketing user lookups across the page instead of sequential N+1 loop
      await Future.wait(
        companies.map((company) async {
          try {
            final userQuery = await firestore
                .collection('users')
                .where('organizationUID', isEqualTo: organizationUID)
                .where('companyUID', isEqualTo: company['uid'])
                .where('role', isEqualTo: 'marketing')
                .limit(1)
                .getResilient(forceServer: true);

            if (userQuery.docs.isNotEmpty) {
              final userData = userQuery.docs.first.data();
              company['marketingUserName'] =
                  userData['displayName'] ?? 'موظف تسويق';
            } else {
              company['marketingUserName'] = null;
            }
          } catch (_) {
            company['marketingUserName'] = null;
          }
        }),
      );

      return {
        'companies': companies,
        'hasMore': hasMore,
        'lastDocument': docs.isNotEmpty ? docs.last : null,
      };
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب قائمة الشركات.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }

  @override
  Future<List<DelegateModel>> getDelegates(
    String organizationUID,
    String? companyUID,
  ) async {
    try {
      if (companyUID != null) {
        final snapshot = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
            .getResilient(forceServer: true);
        return _deduplicateDelegates(
          snapshot.docs.map((doc) => DelegateModel.fromJson(doc.data(), doc.id)),
        );
      } else {
        // If companyUID is null, fetch all delegates in the organization
        // We can do this via collectionGroup 'delegates' where organizationUID matches
        final snapshot = await firestore
            .collectionGroup('delegates')
            .where('organizationUID', isEqualTo: organizationUID)
            .getResilient(forceServer: true);
        return _deduplicateDelegates(
          snapshot.docs.map((doc) => DelegateModel.fromJson(doc.data(), doc.id)),
        );
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب المندوبين.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }

  @override
  Stream<List<DelegateModel>> streamDelegates(
    String organizationUID,
    String? companyUID,
  ) {
    final Query<Map<String, dynamic>> query = companyUID != null
        ? firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .doc(companyUID)
            .collection('delegates')
        : firestore
            .collectionGroup('delegates')
            .where('organizationUID', isEqualTo: organizationUID);

    return query.streamResilient(includeMetadataChanges: true).map((snapshot) {
      return _deduplicateDelegates(
        snapshot.docs.map((doc) => DelegateModel.fromJson(doc.data(), doc.id)),
      );
    });
  }

  // ─────────────────────────────────────────────
  // Branch Features
  // ─────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getBranches() async {
    try {
      final docs = await BranchesSessionCache.load(firestore);
      final list = docs
          .map((doc) {
            final data = doc.data();
            final name = (data['branchName'] as String?) ??
                (data['name'] as String?) ??
                (data['title'] as String?) ??
                '';
            return {
              'id': doc.id,
              'branchName': name,
              'name': name,
              if (data['organizationUID'] != null) 'organizationUID': data['organizationUID'],
              if (data['latitude'] != null) 'latitude': data['latitude'],
              if (data['longitude'] != null) 'longitude': data['longitude'],
            };
          })
          .where((b) => (b['branchName'] as String).isNotEmpty)
          .toList();
      list.sort((a, b) =>
          (a['branchName'] as String? ?? '').compareTo(b['branchName'] as String? ?? ''));
      return list;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب الفروع.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع عند جلب الفروع.');
    }
  }

  @override
  Future<List<Map<String, dynamic>>> getTodayAttendanceByBranch({
    required String branchName,
    required String organizationId,
    DateTime? date,
  }) async {
    final res = await getTodayAttendanceForBranches(
      branchNames: [branchName],
      organizationId: organizationId,
      date: date,
    );
    return res[branchName] ?? [];
  }

  @override
  Stream<void> watchTodayAttendanceChanges({
    required List<String> branchNames,
    required String organizationId,
    DateTime? date,
  }) {
    if (branchNames.isEmpty) return const Stream<void>.empty();
    final target = date ?? DateTime.now();
    final start = DateTime(target.year, target.month, target.day);
    final end = start.add(const Duration(days: 1));
    final orgId = attendanceQueryOrgId(organizationId);
    final chunks = branchQueryChunks(branchQueryTerms(branchNames).toList());
    final controller = StreamController<void>();
    final subs = <StreamSubscription<QuerySnapshot<Map<String, dynamic>>>>[];
    controller.onListen = () {
      for (final chunk in chunks) {
        var first = true;
        subs.add(firestore
            .collection(kAttendanceCollection)
            .where('organizationId', isEqualTo: orgId)
            .where('branchName', whereIn: chunk)
            .where('timestamp', isGreaterThanOrEqualTo: Timestamp.fromDate(start))
            .where('timestamp', isLessThan: Timestamp.fromDate(end))
            .limit(2000)
            .snapshots()
            .listen((snap) {
          if (first) {
            first = false;
            return;
          }
          if (snap.metadata.hasPendingWrites) return;
          if (snap.docChanges.isEmpty) return;
          if (!controller.isClosed) controller.add(null);
        }, onError: (Object e) {
          debugPrint('watchTodayAttendanceChanges: $e');
        }));
      }
    };
    controller.onCancel = () async {
      for (final s in subs) {
        await s.cancel();
      }
      subs.clear();
    };
    return controller.stream;
  }

  @override
  Future<Map<String, List<Map<String, dynamic>>>> getTodayAttendanceForBranches({
    required List<String> branchNames,
    required String organizationId,
    DateTime? date,
    void Function(Map<String, List<Map<String, dynamic>>> partial)? onFirstPaint,
  }) async {
    if (branchNames.isEmpty) return {};

    try {
      final targetDate = date ?? DateTime.now();
      final todayStart = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // ── Step 1: جلب سجلات الحضور مع تطبيع أسماء الفروع والاستعلام الموثوق ──
      final Map<String, String> normalizedToBranch = {
        for (final b in branchNames)
          if (b.trim().isNotEmpty) normalizeBranchName(b.trim()): b,
      };
      final queryBranchTerms = branchQueryTerms(branchNames);
      final queryBranchList = queryBranchTerms.toList();
      final branchChunks = branchQueryChunks(queryBranchList);

      // attendance_logs writes use `organizationId` (see AttendanceRemoteDataSource).
      // Bound the query by org + branchName variants + today's local calendar day
      // (device TZ; production users are Africa/Cairo) + a hard limit so we never
      // download the full historical collection.
      final queryOrgId = attendanceQueryOrgId(organizationId);
      final todayStartTs = Timestamp.fromDate(todayStart);
      final todayEndTs = Timestamp.fromDate(todayEnd);
      // Favorites UIs are typically << this; guards runaway orgs / bad data.
      const todayAttendanceQueryLimit = 2000;

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> todayDocs = [];
      final attSw = Stopwatch()..start();
      for (final chunk in branchChunks) {
        final snap = await firestore
            .collection(kAttendanceCollection)
            .where('organizationId', isEqualTo: queryOrgId)
            .where('branchName', whereIn: chunk)
            .where('timestamp', isGreaterThanOrEqualTo: todayStartTs)
            .where('timestamp', isLessThan: todayEndTs)
            .limit(todayAttendanceQueryLimit)
            .getResilient(forceServer: true);
        todayDocs.addAll(snap.docs);
      }
      attSw.stop();
      if (RealTestMetrics.enabled) {
        RealTestMetrics.attendanceQueryMs = attSw.elapsedMilliseconds;
        RealTestMetrics.attendanceDocs = todayDocs.length;
        RealTestMetrics.attendanceChunks = branchChunks.length;
      }

      // Map: branchName -> Map<delegateId, record>
      final Map<String, Map<String, Map<String, dynamic>>> checkInsByBranch = {
        for (final b in branchNames) b: {},
      };

      final allDelegateIds = <String>{};

      for (final doc in todayDocs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        final rawBranch = data['branchName'] as String? ?? '';
        final branch = normalizedToBranch[normalizeBranchName(rawBranch)] ?? rawBranch;
        if (!checkInsByBranch.containsKey(branch)) continue;

        if (type == 'check_in') {
          final delegateId = data['delegateId'] as String? ??
              data['userId'] as String? ??
              '';
          if (delegateId.isEmpty) continue;

          allDelegateIds.add(delegateId);

          final ts = data['timestamp'] as Timestamp?;
          final delegateNameInLog =
              data['delegateName'] ?? data['fullName'] ?? data['userName'];
          final orgIdInLog = data['organizationId'] as String? ??
              data['organizationUID'] as String? ??
              data['orgId'] as String? ??
              data['orgUID'] as String?;
          final companyNameInLog = data['companyName'];
          final companyIdInLog = data['companyId'] ?? data['companyUID'];
          final phoneInLog = data['phoneNumber'] ?? data['phone'];
          final photoInLog = data['personalPhotoURL'] ??
              data['personalPhotoUrl'] ??
              data['photoURL'] ??
              data['imageUrl'];

          // Prefer denormalized checkout on the check-in doc (fix2).
          final stampedOut = data['checkOutTime'] is Timestamp
              ? data['checkOutTime'] as Timestamp
              : null;

          final existing = checkInsByBranch[branch]![delegateId];
          if (existing == null) {
            checkInsByBranch[branch]![delegateId] = {
              'checkInDocId': doc.id,
              'checkInTime': ts,
              'delegateId': delegateId,
              'branchName': branch,
              'delegateNameInLog': delegateNameInLog,
              'companyNameInLog': companyNameInLog,
              'companyIdInLog': companyIdInLog,
              'organizationIdInLog': orgIdInLog,
              'phoneInLog': phoneInLog,
              'photoInLog': photoInLog,
              'checkOutTime': stampedOut,
            };
          } else {
            final existingTs = existing['checkInTime'] as Timestamp?;
            if (ts != null && (existingTs == null || ts.compareTo(existingTs) > 0)) {
              existing['checkInTime'] = ts;
              existing['checkInDocId'] = doc.id;
              if (delegateNameInLog != null) existing['delegateNameInLog'] = delegateNameInLog;
              if (companyNameInLog != null) existing['companyNameInLog'] = companyNameInLog;
              if (companyIdInLog != null) existing['companyIdInLog'] = companyIdInLog;
              if (orgIdInLog != null) existing['organizationIdInLog'] = orgIdInLog;
              if (phoneInLog != null) existing['phoneInLog'] = phoneInLog;
              if (photoInLog != null) existing['photoInLog'] = photoInLog;
              if (stampedOut != null) existing['checkOutTime'] = stampedOut;
            } else if (stampedOut != null && existing['checkOutTime'] == null) {
              existing['checkOutTime'] = stampedOut;
            }
          }
        }
      }

      // معالجة الانصراف check_out من السجلات المجلوبة مع التطبيع
      for (final doc in todayDocs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (type != 'check_out') continue;

        final rawBranch = data['branchName'] as String? ?? '';
        final branch = normalizedToBranch[normalizeBranchName(rawBranch)] ?? rawBranch;
        final delegateId = data['delegateId'] as String? ??
            data['userId'] as String? ??
            '';
        final ts = data['timestamp'] as Timestamp?;
        final relatedId = data['relatedCheckInId'] as String?;

        if (branch.isNotEmpty && checkInsByBranch.containsKey(branch)) {
          final record = checkInsByBranch[branch]![delegateId];
          if (record != null) {
            if (relatedId == null || relatedId == record['checkInDocId']) {
              final existingOut = record['checkOutTime'] as Timestamp?;
              if (ts != null && (existingOut == null || ts.compareTo(existingOut) > 0)) {
                record['checkOutTime'] = ts;
              }
            }
          }
        }
      }

      // في حال كان الانصراف لم يسجل فيه اسم الفرع، نبحث عن انصراف هؤلاء المناديب فقط
      final missingCheckOutDelegateIds = <String>[];
      for (final branch in branchNames) {
        for (final entry in checkInsByBranch[branch]!.entries) {
          if (entry.value['checkOutTime'] == null) {
            missingCheckOutDelegateIds.add(entry.key);
          }
        }
      }

      final coSw = Stopwatch()..start();
      var coChunks = 0;
      if (missingCheckOutDelegateIds.isNotEmpty) {
        final uniqueMissing = missingCheckOutDelegateIds.toSet().toList();
        // org + type + delegateId + ts>= + ts< (=5) → whereIn chunk <= 20.
        const checkoutWhereInChunkSize = 15;
        const checkoutConcurrency = 4;
        final checkoutChunks = <List<String>>[];
        for (var i = 0; i < uniqueMissing.length; i += checkoutWhereInChunkSize) {
          checkoutChunks.add(
            uniqueMissing.sublist(
              i,
              (i + checkoutWhereInChunkSize > uniqueMissing.length)
                  ? uniqueMissing.length
                  : i + checkoutWhereInChunkSize,
            ),
          );
        }
        coChunks = checkoutChunks.length;

        Future<void> fetchCheckoutChunk(List<String> chunk) async {
          try {
            final outSnap = await firestore
                .collection(kAttendanceCollection)
                .where('organizationId', isEqualTo: queryOrgId)
                .where('type', isEqualTo: 'check_out')
                .where('delegateId', whereIn: chunk)
                .where('timestamp', isGreaterThanOrEqualTo: todayStartTs)
                .where('timestamp', isLessThan: todayEndTs)
                .limit(todayAttendanceQueryLimit)
                .getResilient(forceServer: true);

            for (final doc in outSnap.docs) {
              final data = doc.data();
              final ts = data['timestamp'] as Timestamp?;
              if (ts == null) continue;
              final d = ts.toDate();
              if (d.isBefore(todayStart) || !d.isBefore(todayEnd)) continue;

              final delegateId = data['delegateId'] as String? ?? '';
              final relatedId = data['relatedCheckInId'] as String?;

              for (final branch in branchNames) {
                final record = checkInsByBranch[branch]?[delegateId];
                if (record != null) {
                  if (relatedId == null || relatedId == record['checkInDocId']) {
                    final existingOut = record['checkOutTime'] as Timestamp?;
                    if (existingOut == null || ts.compareTo(existingOut) > 0) {
                      record['checkOutTime'] = ts;
                    }
                  }
                }
              }
            }
          } catch (_) {}
        }

        for (var i = 0; i < checkoutChunks.length; i += checkoutConcurrency) {
          final end = (i + checkoutConcurrency > checkoutChunks.length)
              ? checkoutChunks.length
              : i + checkoutConcurrency;
          await Future.wait(
            checkoutChunks.sublist(i, end).map(fetchCheckoutChunk),
          );
        }
      }

      coSw.stop();
      if (RealTestMetrics.enabled) {
        RealTestMetrics.checkoutFallbackMs = coSw.elapsedMilliseconds;
        RealTestMetrics.checkoutMissingDelegates =
            missingCheckOutDelegateIds.toSet().length;
        RealTestMetrics.checkoutChunks = coChunks;
        RealTestMetrics.uniqueDelegates = allDelegateIds.length;
        RealTestMetrics.markT1();
      }

      // ── Step 2: first paint from log fields + local caches (session + persistent) ──
      final String defaultOrgId = queryOrgId;
      final companyNameCache = <String, String>{};

      // Warm company name cache for ids present on logs (kept from fix2/3).
      final allCompanyIdsToFetch = <String>{};
      for (final branch in branchNames) {
        for (final entry in checkInsByBranch[branch]!.values) {
          final cid = entry['companyIdInLog'] as String?;
          if (cid != null && cid.isNotEmpty) allCompanyIdsToFetch.add(cid);
        }
      }

      Map<String, List<Map<String, dynamic>>> buildBranchRecords({
        required Map<String, Map<String, dynamic>> delegateLookup,
        required bool enrichmentPending,
      }) {
        final out = <String, List<Map<String, dynamic>>>{
          for (final b in branchNames) b: <Map<String, dynamic>>[],
        };
        for (final branch in branchNames) {
          final recordsMap = checkInsByBranch[branch] ?? {};
          final branchRecords = <Map<String, dynamic>>[];
          for (final entry in recordsMap.entries) {
            final delegateId = entry.key;
            final rawCheckIn = entry.value;
            final record = Map<String, dynamic>.from(rawCheckIn);
            var delegateData = delegateLookup[delegateId];

            final logName = (rawCheckIn['delegateNameInLog'] as String?)?.trim();
            final logCompany = (rawCheckIn['companyNameInLog'] as String?)?.trim();
            final logCompanyId = rawCheckIn['companyIdInLog'] as String?;
            final logPhone = (rawCheckIn['phoneInLog'] as String?)?.trim();
            final logPhoto = rawCheckIn['photoInLog'];

            String? resolvedFullName;
            if (delegateData != null) {
              final fn = delegateData['fullName'] as String?;
              final n = delegateData['name'] as String?;
              final first = delegateData['firstName'] as String? ?? '';
              final middle = delegateData['middleName'] as String? ?? '';
              final last = delegateData['lastName'] as String? ?? '';
              final combined =
                  '$first $middle $last'.replaceAll(RegExp(r'\s+'), ' ').trim();
              if (fn != null && fn.trim().isNotEmpty) {
                resolvedFullName = fn.trim();
              } else if (combined.isNotEmpty) {
                resolvedFullName = combined;
              } else if (n != null && n.trim().isNotEmpty) {
                resolvedFullName = n.trim();
              }
            }
            if ((resolvedFullName == null || resolvedFullName.isEmpty) &&
                logName != null &&
                logName.isNotEmpty) {
              resolvedFullName = logName;
            }

            String resolvedCompanyName = '';
            final profileCompany = (delegateData?['companyName'] as String?)?.trim();
            if (profileCompany != null && profileCompany.isNotEmpty) {
              resolvedCompanyName = profileCompany;
            } else if (logCompanyId != null &&
                (companyNameCache[logCompanyId]?.isNotEmpty ?? false)) {
              resolvedCompanyName = companyNameCache[logCompanyId]!;
            } else {
              final profileCompanyUid = delegateData?['companyUID'] as String?;
              if (profileCompanyUid != null &&
                  (companyNameCache[profileCompanyUid]?.isNotEmpty ?? false)) {
                resolvedCompanyName = companyNameCache[profileCompanyUid]!;
              } else if (logCompany != null && logCompany.isNotEmpty) {
                resolvedCompanyName = logCompany;
              }
            }

            final photoUrl = _extractPersonalPhoto(delegateData) ??
                (logPhoto is String && logPhoto.trim().isNotEmpty
                    ? logPhoto.trim()
                    : null) ??
                _extractPersonalPhoto({
                  'personalPhotoURL': logPhoto,
                });

            final effectiveRecordOrg = delegateData?['organizationUID'] ??
                rawCheckIn['organizationIdInLog'] ??
                defaultOrgId;

            final profilePhone = (delegateData?['phoneNumber'] as String?)?.trim();
            final phone = (profilePhone != null && profilePhone.isNotEmpty)
                ? profilePhone
                : (logPhone ?? '');

            final hasName =
                resolvedFullName != null && resolvedFullName.isNotEmpty;
            // HARD: never show generic «مندوب» while enrichment may still fill a real name.
            final displayName = hasName
                ? resolvedFullName
                : (enrichmentPending ? '' : 'مندوب');

            delegateData ??= {
              'uid': delegateId,
              'fullName': displayName.isNotEmpty ? displayName : (logName ?? ''),
              'phoneNumber': phone,
              'companyName': resolvedCompanyName,
              'companyUID': logCompanyId ?? '',
              'organizationUID': effectiveRecordOrg,
              'personalPhotoURL': photoUrl,
              'status': 'Active',
              'role': 'delegate',
            };

            record['fullName'] = displayName;
            record['phoneNumber'] = phone;
            record['companyName'] = resolvedCompanyName;
            record['companyUID'] =
                delegateData['companyUID'] ?? logCompanyId ?? '';
            record['organizationId'] = effectiveRecordOrg;
            record['imageUrl'] = photoUrl;
            record['personalPhotoURL'] = photoUrl;
            record['supervisorPhone'] =
                delegateData['supervisorPhone'] ?? rawCheckIn['supervisorPhone'];
            record['supervisorName'] =
                delegateData['supervisorName'] ?? rawCheckIn['supervisorName'];
            record['createdBy'] =
                delegateData['createdBy'] ?? rawCheckIn['createdBy'];
            record['delegateData'] = delegateData;
            // Photo optional — incomplete only when name/phone/company missing.
            record['profileIncomplete'] = !hasName ||
                phone.isEmpty ||
                resolvedCompanyName.isEmpty;
            branchRecords.add(record);
          }

          branchRecords.sort((a, b) {
            final at = a['checkInTime'] as Timestamp?;
            final bt = b['checkInTime'] as Timestamp?;
            if (at == null && bt == null) return 0;
            if (at == null) return 1;
            if (bt == null) return -1;
            return bt.compareTo(at);
          });
          out[branch] = branchRecords;
        }
        return out;
      }

      // Apply session + persistent profile cache before first paint.
      final delegateLookup = <String, Map<String, dynamic>>{};
      final localProfileCache = profileCache;
      if (allDelegateIds.isNotEmpty && localProfileCache != null) {
        final cached = localProfileCache.getMany(allDelegateIds);
        for (final e in cached.entries) {
          final p = e.value;
          delegateLookup[e.key] = {
            'uid': e.key,
            'fullName': p.fullName,
            'phoneNumber': p.phoneNumber,
            'personalPhotoURL': p.personalPhotoURL,
            'companyName': p.effectiveCompanyName,
            'companyUID': p.companyUID ?? '',
            'organizationUID': p.organizationUID ?? defaultOrgId,
            'status': 'Active',
            'role': 'delegate',
            '_fromLocalCache': true,
          };
          if (p.companyUID != null &&
              p.companyUID!.isNotEmpty &&
              p.effectiveCompanyName.isNotEmpty) {
            companyNameCache[p.companyUID!] = p.effectiveCompanyName;
          }
        }
      }

      // Fetch company names for ids not yet cached (parallel, cheap).
      final companyIdsStillNeeded = allCompanyIdsToFetch
          .where((id) => !companyNameCache.containsKey(id) || companyNameCache[id]!.isEmpty)
          .toList();
      final compSw = Stopwatch()..start();
      await _fillCompanyNameCache(
        organizationId: defaultOrgId,
        companyIds: companyIdsStillNeeded,
        companyNameCache: companyNameCache,
      );
      compSw.stop();
      if (RealTestMetrics.enabled) {
        RealTestMetrics.companyPrePaintMs = compSw.elapsedMilliseconds;
        RealTestMetrics.companyPrePaintIds = companyIdsStillNeeded.length;
        RealTestMetrics.localCacheHits = delegateLookup.length;
      }

      // Determine which delegates still need network profile enrichment.
      bool needsNetwork(String delegateId, Map<String, dynamic> raw) {
        final cached = delegateLookup[delegateId];
        final logName = (raw['delegateNameInLog'] as String?)?.trim() ?? '';
        final logPhone = (raw['phoneInLog'] as String?)?.trim() ?? '';
        final hasName = (cached?['fullName'] as String?)?.trim().isNotEmpty == true ||
            logName.isNotEmpty;
        final hasPhone = (cached?['phoneNumber'] as String?)?.trim().isNotEmpty == true ||
            logPhone.isNotEmpty;
        // Photo is optional: absence is known-empty, not a reason to hit the network.
        return marketingNeedsNetworkEnrichment(
          hasName: hasName,
          hasPhone: hasPhone,
        );
      }

      final missingIds = <String>[];
      for (final branch in branchNames) {
        for (final e in checkInsByBranch[branch]!.entries) {
          if (needsNetwork(e.key, e.value) && !missingIds.contains(e.key)) {
            missingIds.add(e.key);
          }
        }
      }
      if (RealTestMetrics.enabled) {
        RealTestMetrics.enrichMissingCount = missingIds.length;
      }

      final firstPaint = buildBranchRecords(
        delegateLookup: delegateLookup,
        enrichmentPending: missingIds.isNotEmpty,
      );
      // Deep-ish copy for callback so later mutations don't race the UI.
      Map<String, List<Map<String, dynamic>>> copyResult(
        Map<String, List<Map<String, dynamic>>> src,
      ) {
        return {
          for (final e in src.entries)
            e.key: e.value.map((r) => Map<String, dynamic>.from(r)).toList(),
        };
      }

      onFirstPaint?.call(copyResult(firstPaint));

      // ── Step 3: network enrich ONLY missing ids (parallel paths, no 3-serial) ──
      final enSw = Stopwatch()..start();
      var enBatches = 0;
      if (missingIds.isNotEmpty) {
        const batchSize = 25;
        for (var i = 0; i < missingIds.length; i += batchSize) {
          enBatches++;
          final end = (i + batchSize > missingIds.length)
              ? missingIds.length
              : i + batchSize;
          final batch = missingIds.sublist(i, end);

          await Future.wait(batch.map((delegateId) async {
            try {
              String? companyId;
              String? orgId;
              for (final branch in branchNames) {
                final rec = checkInsByBranch[branch]?[delegateId];
                if (rec != null) {
                  final c = rec['companyIdInLog'] as String?;
                  if (c != null && c.isNotEmpty) companyId = c;
                  final o = rec['organizationIdInLog'] as String?;
                  if (o != null && o.isNotEmpty) orgId = o;
                  if (companyId != null && orgId != null) break;
                }
              }
              final effectiveOrgId =
                  (orgId != null && orgId.isNotEmpty) ? orgId : defaultOrgId;

              Map<String, dynamic>? resolved;

              // Fire candidate paths in PARALLEL (not serial 1→2→3).
              final futures = <Future<DocumentSnapshot<Map<String, dynamic>>>>[];
              DocumentReference<Map<String, dynamic>>? companyRef;
              if (companyId != null &&
                  companyId.isNotEmpty &&
                  effectiveOrgId.isNotEmpty) {
                companyRef = firestore
                    .collection('organizations')
                    .doc(effectiveOrgId)
                    .collection('companies')
                    .doc(companyId)
                    .collection('delegates')
                    .doc(delegateId);
                futures.add(companyRef.get());
              }
              futures.add(firestore.collection('users').doc(delegateId).get());
              futures.add(
                firestore.collection('delegates').doc(delegateId).get(),
              );

              final snaps = await Future.wait(futures);
              DocumentSnapshot<Map<String, dynamic>>? companySnap;
              DocumentSnapshot<Map<String, dynamic>>? userSnap;
              DocumentSnapshot<Map<String, dynamic>>? rootSnap;
              var idx = 0;
              if (companyRef != null) {
                companySnap = snaps[idx++];
              }
              userSnap = snaps[idx++];
              rootSnap = snaps[idx++];

              if (companySnap != null &&
                  companySnap.exists &&
                  companySnap.data() != null) {
                final dData = Map<String, dynamic>.from(companySnap.data()!);
                dData['uid'] = companySnap.id;
                dData['companyUID'] = companyId;
                dData['organizationUID'] = effectiveOrgId;
                resolved = dData;
              } else if (userSnap.exists && userSnap.data() != null) {
                final uData = Map<String, dynamic>.from(userSnap.data()!);
                final userCompId = uData['companyUID'] as String? ??
                    uData['companyId'] as String?;
                final userOrgId = uData['organizationUID'] as String? ??
                    uData['orgUID'] as String? ??
                    effectiveOrgId;
                // If users doc points at a company path we have not tried, fetch once.
                if (userCompId != null &&
                    userCompId.isNotEmpty &&
                    userOrgId.isNotEmpty &&
                    userCompId != companyId) {
                  try {
                    final nested = await firestore
                        .collection('organizations')
                        .doc(userOrgId)
                        .collection('companies')
                        .doc(userCompId)
                        .collection('delegates')
                        .doc(delegateId)
                        .get();
                    if (nested.exists && nested.data() != null) {
                      final dData = Map<String, dynamic>.from(nested.data()!);
                      dData['uid'] = nested.id;
                      dData['companyUID'] = userCompId;
                      dData['organizationUID'] = userOrgId;
                      resolved = dData;
                    }
                  } catch (_) {}
                }
                resolved ??= {'uid': userSnap.id, ...uData};
              } else if (rootSnap.exists && rootSnap.data() != null) {
                resolved = {'uid': rootSnap.id, ...rootSnap.data()!};
              }

              if (resolved != null) {
                delegateLookup[delegateId] = resolved;
                // Persist immutable display fields (+ company with TTL).
                final fn = resolved['fullName'] as String? ??
                    resolved['name'] as String?;
                final first = resolved['firstName'] as String? ?? '';
                final middle = resolved['middleName'] as String? ?? '';
                final last = resolved['lastName'] as String? ?? '';
                final combined =
                    '$first $middle $last'.replaceAll(RegExp(r'\s+'), ' ').trim();
                final name = (fn != null && fn.trim().isNotEmpty)
                    ? fn.trim()
                    : combined;
                final phone = (resolved['phoneNumber'] as String?) ??
                    (resolved['phone'] as String?) ??
                    '';
                final photo = _extractPersonalPhoto(resolved);
                final cName = (resolved['companyName'] as String?) ??
                    companyNameCache[resolved['companyUID']] ??
                    '';
                profileCache?.putFromMaps(
                  delegateId: delegateId,
                  fullName: name,
                  phoneNumber: phone,
                  personalPhotoURL: photo,
                  companyName: cName,
                  companyUID: resolved['companyUID'] as String? ?? companyId,
                  organizationUID:
                      resolved['organizationUID'] as String? ?? effectiveOrgId,
                );
              }
            } catch (_) {}
          }));
        }

        // Refresh company names for any newly discovered company UIDs.
        final extraCompanyIds = <String>{};
        for (final dData in delegateLookup.values) {
          final cid = dData['companyUID'] as String?;
          if (cid != null &&
              cid.isNotEmpty &&
              (companyNameCache[cid] == null || companyNameCache[cid]!.isEmpty)) {
            extraCompanyIds.add(cid);
          }
        }
        final comp2Sw = Stopwatch()..start();
        await _fillCompanyNameCache(
          organizationId: defaultOrgId,
          companyIds: extraCompanyIds,
          companyNameCache: companyNameCache,
        );
        comp2Sw.stop();
        if (RealTestMetrics.enabled) {
          RealTestMetrics.companyPostEnrichMs = comp2Sw.elapsedMilliseconds;
          RealTestMetrics.companyPostEnrichIds = extraCompanyIds.length;
        }

        unawaited(profileCache?.persist() ?? Future.value());
      }
      enSw.stop();
      if (RealTestMetrics.enabled) {
        RealTestMetrics.enrichMs = enSw.elapsedMilliseconds;
        RealTestMetrics.enrichBatches = enBatches;
      }

      final result = buildBranchRecords(
        delegateLookup: delegateLookup,
        enrichmentPending: false,
      );

      return result;
    } on FirebaseException catch (e) {
      throwFirestoreFailure(
        e,
        'فشل في جلب بيانات الحضور للفروع (${e.code}): ${e.message}',
      );
    } catch (e, st) {
      throw ServerFailure('خطأ غير متوقع: $e\n$st');
    }
  }


  /// Batch-fetch company display names with whereIn(documentId) chunks + in-memory cache.
  Future<void> _fillCompanyNameCache({
    required String organizationId,
    required Iterable<String> companyIds,
    required Map<String, String> companyNameCache,
  }) async {
    final needed = companyIds
        .where((id) =>
            id.isNotEmpty &&
            (!companyNameCache.containsKey(id) || companyNameCache[id]!.isEmpty))
        .toSet()
        .toList();
    if (needed.isEmpty) return;

    const whereInSize = 10; // keep well under Firestore whereIn cap
    const concurrency = 4;
    final chunks = <List<String>>[];
    for (var i = 0; i < needed.length; i += whereInSize) {
      chunks.add(
        needed.sublist(
          i,
          (i + whereInSize > needed.length) ? needed.length : i + whereInSize,
        ),
      );
    }

    Future<void> fetchChunk(List<String> chunk) async {
      try {
        final snap = await firestore
            .collection('organizations')
            .doc(organizationId)
            .collection('companies')
            .where(FieldPath.documentId, whereIn: chunk)
            .get();
        final found = <String>{};
        for (final doc in snap.docs) {
          found.add(doc.id);
          companyNameCache[doc.id] = doc.data()['name'] as String? ?? '';
        }
        for (final id in chunk) {
          if (!found.contains(id)) {
            companyNameCache[id] = '';
          }
        }
      } catch (_) {
        // Fallback: individual gets if whereIn unsupported/fails.
        await Future.wait(chunk.map((compId) async {
          try {
            final compDoc = await firestore
                .collection('organizations')
                .doc(organizationId)
                .collection('companies')
                .doc(compId)
                .get();
            companyNameCache[compId] = (compDoc.data()?['name'] as String?) ?? '';
          } catch (_) {
            companyNameCache[compId] = '';
          }
        }));
      }
    }

    for (var i = 0; i < chunks.length; i += concurrency) {
      final end =
          (i + concurrency > chunks.length) ? chunks.length : i + concurrency;
      await Future.wait(chunks.sublist(i, end).map(fetchChunk));
    }
  }

  /// استخراج رابط الصورة الشخصية للمندوب من كافة الحقول المحتملة بما فيها قائمة documents
  String? _extractPersonalPhoto(Map<String, dynamic>? data) {
    if (data == null) return null;

    // 1. الحقول المباشرة
    const directKeys = [
      'personalPhotoURL',
      'personalPhotoUrl',
      'personal_photo_url',
      'profileImageUrl',
      'profile_image_url',
      'photoURL',
      'photoUrl',
      'imageUrl',
      'image',
      'photo',
      'avatarUrl',
      'avatar',
    ];
    for (final k in directKeys) {
      final v = data[k];
      if (v is String && v.trim().isNotEmpty) {
        return v.trim();
      }
    }

    // 2. من قائمة documents
    final docs = data['documents'];
    if (docs is List) {
      for (final doc in docs) {
        if (doc is Map) {
          final key = doc['documentKey']?.toString().toLowerCase().replaceAll('_', '');
          final url = doc['documentURL']?.toString() ??
              doc['documentUrl']?.toString() ??
              doc['url']?.toString() ??
              doc['photoURL']?.toString() ??
              doc['photoUrl']?.toString();
          if ((key == 'personalphoto' || key == 'photo' || key == 'profilephoto') &&
              url != null &&
              url.trim().isNotEmpty) {
            return url.trim();
          }
        }
      }
    }

    // 3. من كائن personalPhoto
    final photoObj = data['personalPhoto'];
    if (photoObj is Map) {
      final url = photoObj['documentURL']?.toString() ??
          photoObj['documentUrl']?.toString() ??
          photoObj['url']?.toString();
      if (url != null && url.trim().isNotEmpty) {
        return url.trim();
      }
    }

    return null;
  }
}






/// Fathalla Market default when the marketing user has no organization.
String attendanceQueryOrgId(String organizationId) {
  final id = organizationId.trim();
  return id.isEmpty ? 'PiioBFgxaHAeuRdjlDgj' : id;
}

/// Branch name spellings sent to `whereIn` (hamza, taa marbuta, alef maqsura
/// variants), so no attendance record is missed.
Set<String> branchQueryTerms(List<String> branchNames) {
  final terms = <String>{};
  for (final b in branchNames) {
    final trimmed = b.trim();
    if (trimmed.isEmpty) continue;
    terms
      ..add(trimmed)
      ..add(trimmed.replaceAll(RegExp(r'[أإآ]'), 'ا'))
      ..add(trimmed.replaceAll('ا', 'أ'))
      ..add(trimmed.replaceAll('ه', 'ة'))
      ..add(trimmed.replaceAll('ة', 'ه'))
      ..add(trimmed.replaceAll('ى', 'ي'));
  }
  return terms;
}

/// Firestore caps (filter clauses * whereIn size) at 100. With
/// organizationId + branchName + timestamp>= + timestamp< (=4), max whereIn
/// is 25; chunks of 20 keep a margin.
List<List<String>> branchQueryChunks(List<String> terms, {int size = 20}) {
  return [
    for (var i = 0; i < terms.length; i += size)
      terms.sublist(i, i + size > terms.length ? terms.length : i + size),
  ];
}
