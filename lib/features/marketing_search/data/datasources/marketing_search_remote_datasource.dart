import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/models/pagination_response.dart';
import '../../../../core/services/firestore_resilience_helper.dart';
import '../../../admin/data/models/company_model.dart';
import '../../../profile/data/models/delegate_model.dart';

/// Remote data source for marketing search operations
abstract class MarketingSearchRemoteDataSource {
  /// Search for companies by name in Firestore
  /// [startAfterDoc] is used for pagination - pass the last document from previous batch
  Future<PaginationResponse<CompanyModel>> searchCompanyByName({
    required String organizationUID,
    required String companyName,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  });

  /// Search for delegates by phone number in Firestore
  /// [startAfterDoc] is used for pagination - pass the last document from previous batch
  Future<PaginationResponse<DelegateModel>> searchDelegateByPhone({
    required String organizationUID,
    required String phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  });

  /// Search for delegates by name in Firestore
  /// [startAfterDoc] is used for pagination - pass the last document from previous batch
  Future<PaginationResponse<DelegateModel>> searchDelegateByName({
    required String organizationUID,
    required String name,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  });
}

class MarketingSearchRemoteDataSourceImpl
    implements MarketingSearchRemoteDataSource {
  final FirebaseFirestore firestore;

  static final Map<String, List<QueryDocumentSnapshot<Map<String, dynamic>>>>
      _orgDelegatesCache = {};
  static final Map<String, DateTime> _orgDelegatesCacheTime = {};
  static const Duration _cacheTtl = Duration(minutes: 2);

  MarketingSearchRemoteDataSourceImpl({required this.firestore});

  @override
  Future<PaginationResponse<CompanyModel>> searchCompanyByName({
    required String organizationUID,
    required String companyName,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    try {
      developer.log('═══════════════════════════════════════════════════');
      developer.log('🔍 [Marketing] البحث عن شركة');
      developer.log('Organization UID: $organizationUID');
      developer.log('Company Name: "$companyName"');
      developer.log('Limit: $limit');
      // تحويل الكود للمقارنة (بدون lowercase لأنه قد يكون case-sensitive)
      final searchCode = companyName.trim();

      // استخراج الكود كرقم لتسهيل البحث
      final numericCode = int.tryParse(searchCode);
      developer.log('🔍 البحث بكود: $searchCode (الرقم: $numericCode)');

      final companiesRef = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies');

      List<QueryDocumentSnapshot> allDocs = [];

      if (numericCode != null) {
        // إذا كان الإدخال رقماً، نقوم بتنفيذ 3 استعلامات مختلفة دمجاً لنتائجها
        // للبرهنة على عدم حاجتنا لإنشاء Index معقد في فايربيز
        final futures = await Future.wait([
          companiesRef.where('code', isEqualTo: numericCode).limit(limit + 1).getResilient(forceServer: true),
          companiesRef.where('companyCodeInOrg', isEqualTo: numericCode).limit(limit + 1).getResilient(forceServer: true),
          companiesRef.where('companyCodeInOrg', isGreaterThanOrEqualTo: searchCode)
              .where('companyCodeInOrg', isLessThanOrEqualTo: '$searchCode\uf8ff').limit(limit + 1).getResilient(forceServer: true),
        ]);

        for (var snapshot in futures) {
          allDocs.addAll(snapshot.docs);
        }
      } else {
        // بحث نصي فقط
        final snapshot = await companiesRef
            .where('companyCodeInOrg', isGreaterThanOrEqualTo: searchCode)
            .where('companyCodeInOrg', isLessThanOrEqualTo: '$searchCode\uf8ff')
            .limit(limit + 1)
            .getResilient(forceServer: true);
        allDocs.addAll(snapshot.docs);
      }

      // تصفية التكرارات باستخدام Set لمقارنة معرّفات الوثائق (IDs)
      final uniqueDocsMap = <String, QueryDocumentSnapshot>{};
      for (var doc in allDocs) {
        uniqueDocsMap[doc.id] = doc;
      }
      
      final uniqueDocs = uniqueDocsMap.values.toList();

      // Check if we have more items than the limit
      final hasMore = uniqueDocs.length > limit;
      final itemsToReturn = hasMore
          ? uniqueDocs.take(limit).toList()
          : uniqueDocs;

      developer.log('📊 إجمالي النتائج: ${itemsToReturn.length}');
      developer.log('📊 هل يوجد المزيد: $hasMore');

      if (itemsToReturn.isNotEmpty) {
        for (var doc in itemsToReturn) {
          final data = doc.data() as Map<String, dynamic>;
          developer.log('   ✓ ${data['name']}');
          developer.log(
            '     - Code: ${data['companyCodeInOrg'] ?? data['code']}',
          );
        }
      }

      developer.log('═══════════════════════════════════════════════════');

      // تحويل النتائج إلى Models
      final companies = itemsToReturn
          .map((doc) => CompanyModel.fromFirestore(doc))
          .toList();

      return PaginationResponse<CompanyModel>(
        items: companies,
        hasReachedMax: !hasMore,
        // Since we query manually, pagination using startAfterDoc is not fully reliable when merged, 
        // but we return the last doc of the merged set.
        lastDoc: itemsToReturn.isNotEmpty ? itemsToReturn.last : null,
      );
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في البحث عن الشركة: $e');
      developer.log('Stack trace: $stackTrace');
      rethrow;
    }
  }

  @override
  Future<PaginationResponse<DelegateModel>> searchDelegateByPhone({
    required String organizationUID,
    required String phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    try {
      developer.log('═══════════════════════════════════════════════════');
      developer.log('🔍 [Marketing] البحث عن مندوب');
      developer.log('Organization UID: $organizationUID');
      developer.log('Phone Number: "$phoneNumber"');
      developer.log('Limit: $limit');
      developer.log('Start After Doc: ${startAfterDoc?.id ?? "null"}');
      developer.log('═══════════════════════════════════════════════════');

      // تطبيع رقم الهاتف
      final normalizedPhone = _normalizePhoneNumber(phoneNumber);
      developer.log('📱 الرقم بعد التطبيع: $normalizedPhone');

      // البحث في كل المندوبين باستخدام collectionGroup
      developer.log('🔍 البحث في collectionGroup(delegates)...');

      Query query = firestore
          .collectionGroup('delegates')
          .where('organizationUID', isEqualTo: organizationUID)
          .where('phoneNumber', isEqualTo: normalizedPhone)
          .limit(limit + 1); // +1 to check if there are more items

      // Apply pagination if startAfterDoc is provided
      if (startAfterDoc != null) {
        query = query.startAfterDocument(startAfterDoc);
      }

      final snapshot = await query.getResilient(forceServer: true);

      // Deduplicate by companyUID + doc.id
      final seenKeys = <String>{};
      final uniqueDocs = <QueryDocumentSnapshot>[];
      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>;
        final key = '${data['companyUID'] ?? ''}_${doc.id}';
        if (seenKeys.add(key)) {
          uniqueDocs.add(doc);
        }
      }

      // Check if we have more items than the limit
      final hasMore = uniqueDocs.length > limit;
      final itemsToReturn = hasMore
          ? uniqueDocs.take(limit).toList()
          : uniqueDocs;

      developer.log('📊 إجمالي النتائج: ${itemsToReturn.length}');
      developer.log('📊 هل يوجد المزيد: $hasMore');

      if (itemsToReturn.isNotEmpty) {
        for (var doc in itemsToReturn) {
          final data = doc.data() as Map<String, dynamic>;
          developer.log('   ✓ ${data['firstName']} ${data['lastName']}');
          developer.log('     - Phone: ${data['phoneNumber']}');
          developer.log('     - Company: ${data['companyUID']}');
        }
      }

      developer.log('═══════════════════════════════════════════════════');

      // تحويل النتائج إلى Models
      final delegates = itemsToReturn
          .map(
            (doc) => DelegateModel.fromJson(
              doc.data() as Map<String, dynamic>,
              doc.id,
            ),
          )
          .toList();

      return PaginationResponse<DelegateModel>(
        items: delegates,
        hasReachedMax: !hasMore,
        lastDoc: itemsToReturn.isNotEmpty ? itemsToReturn.last : null,
      );
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في البحث عن المندوب: $e');
      developer.log('Stack trace: $stackTrace');
      throw Exception('Failed to search delegate: $e');
    }
  }

  /// تطبيع النصوص العربية لتسهيل وتوسيع دقة البحث
  String _normalizeArabic(String text) {
    return text
        .trim()
        .toLowerCase()
        .replaceAll(RegExp(r'[إأآا]'), 'ا')
        .replaceAll('ة', 'ه')
        .replaceAll('ى', 'ي')
        .replaceAll(RegExp(r'[\u064B-\u065F\u0640]'), '') // حذف التشكيل والتطويل
        .replaceAll(RegExp(r'\s+'), ' ');
  }

  @override
  Future<PaginationResponse<DelegateModel>> searchDelegateByName({
    required String organizationUID,
    required String name,
    String? phoneNumber,
    int limit = 20,
    DocumentSnapshot? startAfterDoc,
  }) async {
    try {
      final cleanName = name.trim();
      final normalizedQuery = _normalizeArabic(cleanName);
      final queryWords = normalizedQuery.split(' ').where((w) => w.isNotEmpty).toList();

      final normalizedPhone = phoneNumber != null && phoneNumber.trim().isNotEmpty
          ? _normalizePhoneNumber(phoneNumber)
          : null;

      developer.log('═══════════════════════════════════════════════════');
      developer.log('🔍 [Marketing] البحث عن مندوب بالاسم');
      developer.log('Organization UID: $organizationUID');
      developer.log('Name Query: "$cleanName" (Normalized: "$normalizedQuery")');
      if (normalizedPhone != null) {
        developer.log('Phone Filter: "$normalizedPhone"');
      }
      developer.log('Limit: $limit');
      developer.log('═══════════════════════════════════════════════════');

      // Use 2-minute in-memory cache per organizationUID so repeated searches / pagination don't re-download all delegates
      final now = DateTime.now();
      final cachedAt = _orgDelegatesCacheTime[organizationUID];
      List<QueryDocumentSnapshot<Map<String, dynamic>>> orgDocs;
      if (_orgDelegatesCache.containsKey(organizationUID) &&
          cachedAt != null &&
          now.difference(cachedAt) < _cacheTtl) {
        orgDocs = _orgDelegatesCache[organizationUID]!;
      } else {
        final snapshot = await firestore
            .collectionGroup('delegates')
            .where('organizationUID', isEqualTo: organizationUID)
            .getResilient(forceServer: true);
        final seenKeys = <String>{};
        orgDocs = [];
        for (final doc in snapshot.docs) {
          final data = doc.data();
          final key = '${data['companyUID'] ?? ''}_${doc.id}';
          if (seenKeys.add(key)) {
            orgDocs.add(doc);
          }
        }
        _orgDelegatesCache[organizationUID] = orgDocs;
        _orgDelegatesCacheTime[organizationUID] = now;
      }

      // مطابقة الأسماء ذكياً باللغة العربية مع دعم المقاطع المختلفة
      final matchedDocs = orgDocs.where((doc) {
        final data = doc.data();

        // تصفية الهاتف إن وجد
        if (normalizedPhone != null) {
          final docPhone = (data['phoneNumber'] as String?) ?? '';
          final normDocPhone = _normalizePhoneNumber(docPhone);
          if (!normDocPhone.contains(normalizedPhone)) {
            return false;
          }
        }

        final rawFullName = (data['fullName'] as String?)?.trim() ?? '';
        final first = (data['firstName'] as String?)?.trim() ?? '';
        final middle = (data['middleName'] as String?)?.trim() ?? '';
        final last = (data['lastName'] as String?)?.trim() ?? '';
        final altName = (data['name'] as String?)?.trim() ?? '';
        final combined = [first, middle, last].where((s) => s.isNotEmpty).join(' ');

        final target = _normalizeArabic('$rawFullName $combined $altName');

        // يجب أن يحتوي النص الهدف على جميع كلمات البحث المدخلة
        return queryWords.every((word) => target.contains(word));
      }).toList();

      developer.log('📊 إجمالي المناديب المطابقين للاسم: ${matchedDocs.length}');

      // تطبيق التصفح Pagination باستخدام startAfterDoc
      int startIndex = 0;
      if (startAfterDoc != null) {
        final lastIndex = matchedDocs.indexWhere((d) => d.id == startAfterDoc.id);
        if (lastIndex != -1) {
          startIndex = lastIndex + 1;
        }
      }

      final pageDocs = matchedDocs.skip(startIndex).take(limit).toList();
      final hasMore = (startIndex + pageDocs.length) < matchedDocs.length;

      final delegates = pageDocs
          .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
          .toList();

      return PaginationResponse<DelegateModel>(
        items: delegates,
        hasReachedMax: !hasMore,
        lastDoc: pageDocs.isNotEmpty ? pageDocs.last : null,
      );
    } catch (e, stackTrace) {
      developer.log('❌ خطأ في البحث عن المندوب بالاسم: $e');
      developer.log('Stack trace: $stackTrace');
      throw Exception('Failed to search delegate by name: $e');
    }
  }

  /// تطبيع رقم الهاتف المصري
  /// يزيل +20، 0020، 002 ويحتفظ بـ 01XXXXXXXXX
  String _normalizePhoneNumber(String phone) {
    String normalized = phone.trim();

    // إزالة المسافات والشرطات
    normalized = normalized.replaceAll(RegExp(r'[\s\-]'), '');

    // إزالة +20
    if (normalized.startsWith('+20')) {
      normalized = '0${normalized.substring(3)}';
    }
    // إزالة 0020
    else if (normalized.startsWith('0020')) {
      normalized = '0${normalized.substring(4)}';
    }
    // إزالة 002
    else if (normalized.startsWith('002')) {
      normalized = '0${normalized.substring(3)}';
    }
    // إزالة +2
    else if (normalized.startsWith('+2')) {
      normalized = '0${normalized.substring(2)}';
    }
    // إزالة 20 في البداية (بدون +)
    else if (normalized.startsWith('20') && normalized.length == 12) {
      normalized = '0${normalized.substring(2)}';
    }

    return normalized;
  }
}
