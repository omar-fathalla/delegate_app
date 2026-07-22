import 'package:cloud_firestore/cloud_firestore.dart';
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
  /// enriched with delegate info (fullName, phoneNumber).
  Future<List<Map<String, dynamic>>> getTodayAttendanceByBranch({
    required String branchName,
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
          .orderBy('branchName')
          .get();
      return snapshot.docs
          .map((doc) => {'id': doc.id, ...doc.data()})
          .toList();
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
    try {
      final targetDate = date ?? DateTime.now();
      final todayStart = DateTime(targetDate.year, targetDate.month, targetDate.day);
      final todayEnd = todayStart.add(const Duration(days: 1));

      // ── Step 1: جلب سجلات اليوم بـ timestamp فقط (single-field index موجود افتراضياً) ──
      // نتجنّب استخدام multi-field composite index غير موجود.
      final logsSnapshot = await firestore
          .collection('attendance_logs')
          .where(
            'timestamp',
            isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart),
          )
          .where('timestamp', isLessThan: Timestamp.fromDate(todayEnd))
          .get();

      // ── Step 2: عزل الحضور الخاص بهذا الفرع فقط ──
      final checkInLogs = logsSnapshot.docs.where((doc) {
        final data = doc.data();
        return data['type'] == 'check_in' && data['branchName'] == branchName;
      }).toList();

      if (checkInLogs.isEmpty) return [];

      // ── Step 3: بناء Map لآخر check_in لكل مندوب ──
      final Map<String, Map<String, dynamic>> checkInByDelegate = {};
      for (final doc in checkInLogs) {
        final data = doc.data();
        final delegateId = data['delegateId'] as String? ??
            data['userId'] as String? ??
            '';
        if (delegateId.isEmpty) continue;

        final ts = data['timestamp'] as Timestamp?;
        // نحتفظ فقط بأحدث check_in لكل مندوب
        if (!checkInByDelegate.containsKey(delegateId)) {
          checkInByDelegate[delegateId] = {
            'checkInDocId': doc.id,
            'checkInTime': ts,
            'delegateId': delegateId,
            'branchName': data['branchName'],
            'checkOutTime': null,
          };
        } else {
          final existing =
              checkInByDelegate[delegateId]!['checkInTime'] as Timestamp?;
          if (ts != null && (existing == null || ts.compareTo(existing) > 0)) {
            checkInByDelegate[delegateId]!['checkInTime'] = ts;
            checkInByDelegate[delegateId]!['checkInDocId'] = doc.id;
          }
        }
      }

      if (checkInByDelegate.isEmpty) return [];

      final delegateIds = checkInByDelegate.keys.toSet();

      // ── Step 4: ربط check_out من نفس سجلات اليوم لكافة المندوبين بالفرع ──
      // حتى لو لم يكن يحتوي الانصراف على branchName
      final checkOutLogs = logsSnapshot.docs.where((doc) {
        final data = doc.data();
        final type = data['type'] as String? ?? '';
        final delegateId = data['delegateId'] as String? ??
            data['userId'] as String? ??
            '';
        return type == 'check_out' && delegateIds.contains(delegateId);
      }).toList();

      for (final doc in checkOutLogs) {
        final data = doc.data();
        final delegateId = data['delegateId'] as String? ??
            data['userId'] as String? ??
            '';
        
        final existingOut =
            checkInByDelegate[delegateId]!['checkOutTime'] as Timestamp?;
        final ts = data['timestamp'] as Timestamp?;
        
        // قد يكون هناك انصراف خاص بحضور آخر لنفس المندوب في نفس اليوم بفرع آخر
        // لزيادة الدقة يمكننا التأكد أن relatedCheckInId يطابق checkInDocId، إن وُجد.
        final relatedId = data['relatedCheckInId'] as String?;
        final currentCheckInDocId = checkInByDelegate[delegateId]!['checkInDocId'];
        
        if (relatedId != null && relatedId != currentCheckInDocId) {
          continue; // انصراف لا يخص هذا الحضور
        }

        // نحتفظ بأحدث check_out
        if (ts != null &&
            (existingOut == null || ts.compareTo(existingOut) > 0)) {
          checkInByDelegate[delegateId]!['checkOutTime'] = ts;
        }
      }

      // ── Step 5: جلب بيانات المناديب من collectionGroup بـ organizationUID ──
      // نجلب كل المناديب في المنظمة مرة واحدة ثم نصفّيهم في Dart
      // (يتجنّب استخدام FieldPath.documentId whereIn على collectionGroup)

      final delegatesSnapshot = await firestore
          .collectionGroup('delegates')
          .where('organizationUID', isEqualTo: organizationId)
          .get();

      final delegateLookup = <String, Map<String, dynamic>>{};
      for (final doc in delegatesSnapshot.docs) {
        if (delegateIds.contains(doc.id)) {
          delegateLookup[doc.id] = {'uid': doc.id, ...doc.data()};
        }
      }

      // ── Step 6: بناء القائمة النهائية ──
      final results = <Map<String, dynamic>>[];
      for (final delegateId in delegateIds) {
        final record = Map<String, dynamic>.from(checkInByDelegate[delegateId]!);
        final delegateData = delegateLookup[delegateId];
        record['fullName'] = delegateData?['fullName'] ?? 'مندوب';
        record['phoneNumber'] = delegateData?['phoneNumber'] ?? '';
        record['companyName'] = delegateData?['companyName'] ?? '';
        record['companyUID'] = delegateData?['companyUID'] ?? '';
        record['imageUrl'] = delegateData?['personalPhotoURL'];
        record['delegateData'] = delegateData;
        results.add(record);
      }

      // ترتيب: الأحدث check_in أولاً
      results.sort((a, b) {
        final at = a['checkInTime'] as Timestamp?;
        final bt = b['checkInTime'] as Timestamp?;
        if (at == null && bt == null) return 0;
        if (at == null) return 1;
        if (bt == null) return -1;
        return bt.compareTo(at);
      });

      return results;
    } on FirebaseException catch (e) {
      // نُظهر الخطأ الحقيقي من Firebase لتسهيل التشخيص
      throwFirestoreFailure(
        e,
        'فشل في جلب بيانات الحضور للفرع (${e.code}): ${e.message}',
      );
    } catch (e, st) {
      // نُظهر الخطأ الفعلي بدلاً من رسالة عامة
      throw ServerFailure('خطأ غير متوقع: $e\n$st');
    }
  }
}


