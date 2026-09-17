import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/error/firestore_error_handler.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';

abstract class MarketingRemoteDataSource {
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
  Future<Map<String, List<Map<String, dynamic>>>> getTodayAttendanceForBranches({
    required List<String> branchNames,
    required String organizationId,
    DateTime? date,
  });
}

class MarketingRemoteDataSourceImpl implements MarketingRemoteDataSource {
  final FirebaseFirestore firestore;

  MarketingRemoteDataSourceImpl({required this.firestore});

  @override
  Future<List<Map<String, dynamic>>> getCompanies(
    String organizationUID,
  ) async {
    try {
      final snapshot = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .get();

      // Get list of companies with their data
      final companies = snapshot.docs
          .map((doc) => {'uid': doc.id, ...doc.data()})
          .toList();

      // For each company, try to find the marketing user
      for (var company in companies) {
        try {
          // Query users collection for marketing user in this company
          final userQuery = await firestore
              .collection('users')
              .where('organizationUID', isEqualTo: organizationUID)
              .where('companyUID', isEqualTo: company['uid'])
              .where('role', isEqualTo: 'marketing')
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            final userData = userQuery.docs.first.data();
            company['marketingUserName'] =
                userData['displayName'] ?? 'موظف تسويق';
          } else {
            company['marketingUserName'] = null;
          }
        } catch (_) {
          // If query fails, continue without marketing user name
          company['marketingUserName'] = null;
        }
      }

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

      final snapshot = await query.get();

      // Check if there are more companies
      final hasMore = snapshot.docs.length > limit;
      final docs = hasMore ? snapshot.docs.take(limit).toList() : snapshot.docs;

      // Get list of companies with their data
      final companies = docs
          .map((doc) => {'uid': doc.id, ...doc.data() as Map<String, dynamic>})
          .toList();

      // For each company, try to find the marketing user
      for (var company in companies) {
        try {
          // Query users collection for marketing user in this company
          final userQuery = await firestore
              .collection('users')
              .where('organizationUID', isEqualTo: organizationUID)
              .where('companyUID', isEqualTo: company['uid'])
              .where('role', isEqualTo: 'marketing')
              .limit(1)
              .get();

          if (userQuery.docs.isNotEmpty) {
            final userData = userQuery.docs.first.data();
            company['marketingUserName'] =
                userData['displayName'] ?? 'موظف تسويق';
          } else {
            company['marketingUserName'] = null;
          }
        } catch (_) {
          // If query fails, continue without marketing user name
          company['marketingUserName'] = null;
        }
      }

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
            .get();
        return snapshot.docs
            .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
            .toList();
      } else {
        // If companyUID is null, fetch all delegates in the organization
        // We can do this via collectionGroup 'delegates' where organizationUID matches
        final snapshot = await firestore
            .collectionGroup('delegates')
            .where('organizationUID', isEqualTo: organizationUID)
            .get();
        return snapshot.docs
            .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
            .toList();
      }
    } on FirebaseException catch (e) {
      throwFirestoreFailure(e, 'فشل في جلب المندوبين.');
    } catch (_) {
      throw const ServerFailure('حدث خطأ غير متوقع.');
    }
  }

  // ─────────────────────────────────────────────
  // Branch Features
  // ─────────────────────────────────────────────

  @override
  Future<List<Map<String, dynamic>>> getBranches() async {
    try {
      final snapshot = await firestore
          .collection('branches')
          .get();
      final list = snapshot.docs
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
  Future<Map<String, List<Map<String, dynamic>>>> getTodayAttendanceForBranches({
    required List<String> branchNames,
    required String organizationId,
    DateTime? date,
  }) async {
    if (branchNames.isEmpty) return {};

    try {
      final targetDate = date ?? DateTime.now();
      final todayStart = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // ── Step 1: جلب سجلات الحضور الخاصة بالفروع المطلوبة فقط بـ whereIn ──
      // لتقسيم الفروع في مجموعات حتى 30 فرع لكل استعلام
      final branchChunks = <List<String>>[];
      for (var i = 0; i < branchNames.length; i += 30) {
        branchChunks.add(
          branchNames.sublist(
            i,
            (i + 30 > branchNames.length) ? branchNames.length : i + 30,
          ),
        );
      }

      final List<QueryDocumentSnapshot<Map<String, dynamic>>> branchLogsDocs = [];
      for (final chunk in branchChunks) {
        final snap = await firestore
            .collection(kAttendanceCollection)
            .where('branchName', whereIn: chunk)
            .get();
        branchLogsDocs.addAll(snap.docs);
      }

      // تصفية سجلات اليوم حسب النطاق الزمني
      final todayDocs = branchLogsDocs.where((doc) {
        final data = doc.data();
        final ts = data['timestamp'] as Timestamp?;
        if (ts == null) return false;
        final d = ts.toDate();
        return d.isAfter(todayStart.subtract(const Duration(seconds: 1))) &&
            d.isBefore(todayEnd);
      }).toList();

      // خريطة فرز الحضور حسب الفرع
      final Map<String, List<Map<String, dynamic>>> result = {
        for (final b in branchNames) b: [],
      };

      // Map: branchName -> Map<delegateId, record>
      final Map<String, Map<String, Map<String, dynamic>>> checkInsByBranch = {
        for (final b in branchNames) b: {},
      };

      final allDelegateIds = <String>{};

      for (final doc in todayDocs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        final branch = data['branchName'] as String? ?? '';
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
              'checkOutTime': null,
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
            }
          }
        }
      }

      // معالجة الانصراف check_out من السجلات المجلوبة
      for (final doc in todayDocs) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        if (type != 'check_out') continue;

        final branch = data['branchName'] as String? ?? '';
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

      if (missingCheckOutDelegateIds.isNotEmpty) {
        final uniqueMissing = missingCheckOutDelegateIds.toSet().toList();
        for (var i = 0; i < uniqueMissing.length; i += 30) {
          final chunk = uniqueMissing.sublist(
            i,
            (i + 30 > uniqueMissing.length) ? uniqueMissing.length : i + 30,
          );
          try {
            final outSnap = await firestore
                .collection(kAttendanceCollection)
                .where('delegateId', whereIn: chunk)
                .where('type', isEqualTo: 'check_out')
                .get();

            for (final doc in outSnap.docs) {
              final data = doc.data();
              final ts = data['timestamp'] as Timestamp?;
              if (ts == null) continue;
              final d = ts.toDate();
              if (d.isBefore(todayStart) || d.isAfter(todayEnd)) continue;

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
      }

      // ── Step 2: تحديد المنظمة وجلب بيانات وصور المناديب بالتوازي ──
      String defaultOrgId = organizationId.trim();
      if (defaultOrgId.isEmpty) {
        for (final doc in todayDocs) {
          final o = doc.data()['organizationId'] as String? ??
              doc.data()['organizationUID'] as String? ??
              doc.data()['orgId'] as String? ??
              doc.data()['orgUID'] as String?;
          if (o != null && o.trim().isNotEmpty) {
            defaultOrgId = o.trim();
            break;
          }
        }
      }
      if (defaultOrgId.isEmpty) {
        defaultOrgId = 'PiioBFgxaHAeuRdjlDgj'; // Fathalla Market default
      }

      final delegateLookup = <String, Map<String, dynamic>>{};
      final companyNameCache = <String, String>{};

      if (allDelegateIds.isNotEmpty) {
        final delegateIdsList = allDelegateIds.toList();
        const batchSize = 25;
        for (var i = 0; i < delegateIdsList.length; i += batchSize) {
          final end = (i + batchSize > delegateIdsList.length)
              ? delegateIdsList.length
              : i + batchSize;
          final batch = delegateIdsList.sublist(i, end);

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

              final effectiveOrgId = (orgId != null && orgId.isNotEmpty)
                  ? orgId
                  : defaultOrgId;

              // 1. المسار المباشر في الشركة
              if (companyId != null && companyId.isNotEmpty && effectiveOrgId.isNotEmpty) {
                final directDoc = await firestore
                    .collection('organizations')
                    .doc(effectiveOrgId)
                    .collection('companies')
                    .doc(companyId)
                    .collection('delegates')
                    .doc(delegateId)
                    .get();

                if (directDoc.exists && directDoc.data() != null) {
                  final dData = Map<String, dynamic>.from(directDoc.data()!);
                  dData['uid'] = directDoc.id;
                  dData['companyUID'] = companyId;
                  dData['organizationUID'] = effectiveOrgId;
                  delegateLookup[delegateId] = dData;
                  return;
                }
              }

              // 2. البحث في مجموعة users
              final userDoc = await firestore.collection('users').doc(delegateId).get();
              if (userDoc.exists && userDoc.data() != null) {
                final uData = userDoc.data()!;
                final userCompId = uData['companyUID'] as String? ?? uData['companyId'] as String?;
                final userOrgId = uData['organizationUID'] as String? ??
                    uData['orgUID'] as String? ??
                    effectiveOrgId;

                if (userCompId != null && userCompId.isNotEmpty && userOrgId.isNotEmpty) {
                  final directDoc = await firestore
                      .collection('organizations')
                      .doc(userOrgId)
                      .collection('companies')
                      .doc(userCompId)
                      .collection('delegates')
                      .doc(delegateId)
                      .get();

                  if (directDoc.exists && directDoc.data() != null) {
                    final dData = Map<String, dynamic>.from(directDoc.data()!);
                    dData['uid'] = directDoc.id;
                    dData['companyUID'] = userCompId;
                    dData['organizationUID'] = userOrgId;
                    delegateLookup[delegateId] = dData;
                    return;
                  }
                }
                delegateLookup[delegateId] = {'uid': userDoc.id, ...uData};
                return;
              }

              // 3. مجموعة delegates الجذرية
              final rootDoc = await firestore.collection('delegates').doc(delegateId).get();
              if (rootDoc.exists && rootDoc.data() != null) {
                delegateLookup[delegateId] = {'uid': rootDoc.id, ...rootDoc.data()!};
                return;
              }
            } catch (_) {}
          }));
        }

        // جلب أسماء الشركات لكافة سجلات الحضور والمناديب بالتوازي
        final allCompanyIdsToFetch = <String>{};
        for (final branch in branchNames) {
          for (final entry in checkInsByBranch[branch]!.values) {
            final cid = entry['companyIdInLog'] as String?;
            if (cid != null && cid.isNotEmpty) allCompanyIdsToFetch.add(cid);
          }
        }
        for (final dData in delegateLookup.values) {
          final cid = dData['companyUID'] as String?;
          if (cid != null && cid.isNotEmpty) allCompanyIdsToFetch.add(cid);
        }

        await Future.wait(allCompanyIdsToFetch.map((compId) async {
          if (companyNameCache.containsKey(compId)) return;
          try {
            final compDoc = await firestore
                .collection('organizations')
                .doc(defaultOrgId)
                .collection('companies')
                .doc(compId)
                .get();
            if (compDoc.exists && compDoc.data() != null) {
              companyNameCache[compId] =
                  compDoc.data()!['name'] as String? ?? '';
            } else {
              companyNameCache[compId] = '';
            }
          } catch (_) {
            companyNameCache[compId] = '';
          }
        }));
      }

      // ── Step 3: بناء القائمة النهائية لكل فرع ──
      for (final branch in branchNames) {
        final recordsMap = checkInsByBranch[branch] ?? {};
        final branchRecords = <Map<String, dynamic>>[];

        for (final entry in recordsMap.entries) {
          final delegateId = entry.key;
          final rawCheckIn = entry.value;
          final record = Map<String, dynamic>.from(rawCheckIn);
          var delegateData = delegateLookup[delegateId];

          final logName = rawCheckIn['delegateNameInLog'] as String?;
          final logCompany = rawCheckIn['companyNameInLog'] as String?;
          final logCompanyId = rawCheckIn['companyIdInLog'] as String?;
          final logPhone = rawCheckIn['phoneInLog'] as String?;

          String? resolvedFullName;
          if (delegateData != null) {
            final fn = delegateData['fullName'] as String?;
            final n = delegateData['name'] as String?;
            final first = delegateData['firstName'] as String? ?? '';
            final middle = delegateData['middleName'] as String? ?? '';
            final last = delegateData['lastName'] as String? ?? '';
            final combined = '$first $middle $last'.replaceAll(RegExp(r'\s+'), ' ').trim();

            if (fn != null && fn.trim().isNotEmpty) {
              resolvedFullName = fn.trim();
            } else if (combined.isNotEmpty) {
              resolvedFullName = combined;
            } else if (n != null && n.trim().isNotEmpty) {
              resolvedFullName = n.trim();
            }
          }

          final resolvedCompanyName = delegateData?['companyName'] as String? ??
              (logCompanyId != null ? companyNameCache[logCompanyId] : null) ??
              (delegateData?['companyUID'] != null ? companyNameCache[delegateData!['companyUID']] : null) ??
              logCompany ??
              '';

          // جلب الصورة الشخصية من كافة المسارات المحتملة بما فيها قائمة documents
          final photoUrl = _extractPersonalPhoto(delegateData) ??
              _extractPersonalPhoto(rawCheckIn);

          final effectiveRecordOrg = delegateData?['organizationUID'] ??
              rawCheckIn['organizationIdInLog'] ??
              defaultOrgId;

          delegateData ??= {
            'uid': delegateId,
            'fullName': (resolvedFullName != null && resolvedFullName.isNotEmpty)
                ? resolvedFullName
                : (logName != null && logName.isNotEmpty ? logName : 'مندوب'),
            'phoneNumber': logPhone ?? '',
            'companyName': resolvedCompanyName,
            'companyUID': logCompanyId ?? '',
            'organizationUID': effectiveRecordOrg,
            'personalPhotoURL': photoUrl,
            'status': 'Active',
            'role': 'delegate',
          };

          record['fullName'] = (resolvedFullName != null && resolvedFullName.isNotEmpty)
              ? resolvedFullName
              : (delegateData['fullName'] ?? (logName != null && logName.isNotEmpty ? logName : 'مندوب'));
          record['phoneNumber'] = delegateData['phoneNumber'] ?? logPhone ?? '';
          record['companyName'] = resolvedCompanyName;
          record['companyUID'] = delegateData['companyUID'] ?? logCompanyId ?? '';
          record['organizationId'] = effectiveRecordOrg;
          record['imageUrl'] = photoUrl;
          record['personalPhotoURL'] = photoUrl;
          record['supervisorPhone'] = delegateData['supervisorPhone'] ?? rawCheckIn['supervisorPhone'];
          record['supervisorName'] = delegateData['supervisorName'] ?? rawCheckIn['supervisorName'];
          record['createdBy'] = delegateData['createdBy'] ?? rawCheckIn['createdBy'];
          record['delegateData'] = delegateData;
          branchRecords.add(record);
        }

        // ترتيب: الأحدث check_in أولاً
        branchRecords.sort((a, b) {
          final at = a['checkInTime'] as Timestamp?;
          final bt = b['checkInTime'] as Timestamp?;
          if (at == null && bt == null) return 0;
          if (at == null) return 1;
          if (bt == null) return -1;
          return bt.compareTo(at);
        });

        result[branch] = branchRecords;
      }

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




