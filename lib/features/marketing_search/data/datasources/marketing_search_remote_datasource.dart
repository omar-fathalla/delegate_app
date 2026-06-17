import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/models/pagination_response.dart';
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
}

class MarketingSearchRemoteDataSourceImpl
    implements MarketingSearchRemoteDataSource {
  final FirebaseFirestore firestore;

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
          companiesRef
              .where('code', isEqualTo: numericCode)
              .limit(limit + 1)
              .get(),
          companiesRef
              .where('companyCodeInOrg', isEqualTo: numericCode)
              .limit(limit + 1)
              .get(),
          companiesRef
              .where('companyCodeInOrg', isGreaterThanOrEqualTo: searchCode)
              .where(
                'companyCodeInOrg',
                isLessThanOrEqualTo: '$searchCode\uf8ff',
              )
              .limit(limit + 1)
              .get(),
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
            .get();
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

      final snapshot = await query.get();

      // Check if we have more items than the limit
      final hasMore = snapshot.docs.length > limit;
      final itemsToReturn = hasMore
          ? snapshot.docs.take(limit).toList()
          : snapshot.docs;

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
