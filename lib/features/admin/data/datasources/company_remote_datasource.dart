import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';

import '../../../../core/models/pagination_response.dart';
import '../models/company_model.dart';

/// Remote data source for company operations
abstract class CompanyRemoteDataSource {
  /// Search companies by company code with pagination
  Future<PaginationResponse<CompanyModel>> searchCompaniesByCode({
    required String organizationUID,
    required String companyCode,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  });

  /// Get all companies with pagination
  Future<PaginationResponse<CompanyModel>> getCompanies({
    required String organizationUID,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  });

  /// Get company by ID
  Future<CompanyModel> getCompanyById({
    required String organizationUID,
    required String companyUID,
  });
}

class CompanyRemoteDataSourceImpl implements CompanyRemoteDataSource {
  final FirebaseFirestore firestore;

  CompanyRemoteDataSourceImpl({required this.firestore});

  @override
  Future<PaginationResponse<CompanyModel>> searchCompaniesByCode({
    required String organizationUID,
    required String companyCode,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  }) async {
    try {
      developer.log('═══════════════════════════════════════════════════');
      developer.log('🔍 بدء البحث في Firestore');
      developer.log('Organization UID: $organizationUID');
      developer.log('Search Query: "$companyCode"');
      developer.log('═══════════════════════════════════════════════════');

      if (companyCode.isEmpty) {
        developer.log('📋 عرض جميع الشركات (بحث فارغ)');
        return await getCompanies(
          organizationUID: organizationUID,
          lastDocument: lastDocument,
          limit: limit,
        );
      }

      // استراتيجية البحث المحسّنة:
      // 1. نحاول البحث بالكود كرقم (أسرع - server-side)
      // 2. إذا لم نجد، نبحث في companyCodeInOrg (server-side)
      // 3. إذا لم نجد، نجلب كل الشركات ونبحث client-side

      List<QueryDocumentSnapshot> allResults = [];
      int searchTier = 0;

      // محاولة 1: البحث بالكود كرقم
      try {
        final codeAsNumber = int.parse(companyCode);
        searchTier = 1;
        developer.log('');
        developer.log('🔢 [المحاولة 1] البحث بالكود كرقم: $codeAsNumber');
        developer.log('   المسار: organizations/$organizationUID/companies');
        developer.log('   الشرط: code == $codeAsNumber');

        final codeQuery = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .where('code', isEqualTo: codeAsNumber)
            .get();

        developer.log('   النتيجة: ${codeQuery.docs.length} شركة');

        if (codeQuery.docs.isNotEmpty) {
          developer.log('   ✅ نجح! وجدنا ${codeQuery.docs.length} شركة');
          allResults.addAll(codeQuery.docs);

          // طباعة تفاصيل النتائج
          for (var doc in codeQuery.docs) {
            final data = doc.data();
            developer.log('      📄 ${data['name']}');
            developer.log('         - code: ${data['code']}');
            developer.log(
              '         - companyCodeInOrg: ${data['companyCodeInOrg']}',
            );
          }
        } else {
          developer.log('   ⚠️ لم نجد نتائج');
        }
      } catch (e) {
        developer.log('');
        developer.log('⚠️ [المحاولة 1] الكود ليس رقماً: $e');
      }

      // محاولة 2: البحث في companyCodeInOrg
      if (allResults.isEmpty) {
        searchTier = 2;
        developer.log('');
        developer.log('🔍 [المحاولة 2] البحث في companyCodeInOrg');
        developer.log('   المسار: organizations/$organizationUID/companies');
        developer.log('   الشرط: companyCodeInOrg == "$companyCode"');

        final codeOrgQuery = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .where('companyCodeInOrg', isEqualTo: companyCode)
            .get();

        developer.log('   النتيجة: ${codeOrgQuery.docs.length} شركة');

        if (codeOrgQuery.docs.isNotEmpty) {
          developer.log('   ✅ نجح! وجدنا ${codeOrgQuery.docs.length} شركة');
          allResults.addAll(codeOrgQuery.docs);

          // طباعة تفاصيل النتائج
          for (var doc in codeOrgQuery.docs) {
            final data = doc.data();
            developer.log('      📄 ${data['name']}');
            developer.log('         - code: ${data['code']}');
            developer.log(
              '         - companyCodeInOrg: ${data['companyCodeInOrg']}',
            );
          }
        } else {
          developer.log('   ⚠️ لم نجد نتائج');
        }
      }

      // محاولة 3: البحث في كل الشركات (client-side)
      if (allResults.isEmpty) {
        searchTier = 3;
        developer.log('');
        developer.log('🔄 [المحاولة 3] البحث في كل الشركات (client-side)');
        developer.log('   جاري جلب جميع الشركات...');

        final allCompaniesSnapshot = await firestore
            .collection('organizations')
            .doc(organizationUID)
            .collection('companies')
            .get();

        developer.log(
          '   📊 إجمالي الشركات في المنظمة: ${allCompaniesSnapshot.docs.length}',
        );

        if (allCompaniesSnapshot.docs.isEmpty) {
          developer.log('   ⚠️ لا توجد شركات في هذه المنظمة!');
          developer.log('   تحقق من organizationUID: $organizationUID');
        } else {
          developer.log(
            '   جاري البحث في الحقول: name, code, companyCodeInOrg',
          );

          final searchQuery = companyCode.toLowerCase();
          int matchCount = 0;

          allResults = allCompaniesSnapshot.docs.where((doc) {
            final data = doc.data();
            final name = (data['name'] ?? '').toString().toLowerCase();
            final code = (data['code'] ?? '').toString();
            final companyCodeInOrg = (data['companyCodeInOrg'] ?? '')
                .toString();

            final nameMatch = name.contains(searchQuery);
            final codeMatch = code.contains(companyCode);
            final codeInOrgMatch = companyCodeInOrg.contains(companyCode);

            final isMatch = nameMatch || codeMatch || codeInOrgMatch;

            if (isMatch) {
              matchCount++;
              developer.log('      ✓ تطابق #$matchCount: ${data['name']}');
              developer.log(
                '        - name: ${data['name']} ${nameMatch ? "✓" : ""}',
              );
              developer.log(
                '        - code: ${data['code']} ${codeMatch ? "✓" : ""}',
              );
              developer.log(
                '        - companyCodeInOrg: ${data['companyCodeInOrg']} ${codeInOrgMatch ? "✓" : ""}',
              );
            }

            return isMatch;
          }).toList();

          developer.log('   📊 عدد النتائج المطابقة: ${allResults.length}');
        }
      }

      developer.log('');
      developer.log('═══════════════════════════════════════════════════');
      developer.log('📊 ملخص البحث:');
      developer.log('   - المحاولة المستخدمة: $searchTier');
      developer.log('   - إجمالي النتائج: ${allResults.length}');

      if (allResults.isEmpty) {
        developer.log('   ❌ لم نجد أي نتائج!');
        developer.log('');
        developer.log('💡 اقتراحات:');
        developer.log('   1. تحقق من organizationUID: $organizationUID');
        developer.log('   2. تحقق من وجود الشركة في Firestore Console');
        developer.log(
          '   3. تحقق من اسم الحقل (code vs companyCode vs companyCodeInOrg)',
        );
        developer.log('   4. تحقق من نوع البيانات (رقم vs نص)');
      } else {
        developer.log('   ✅ وجدنا ${allResults.length} شركة');
        developer.log('');
        developer.log('📄 أول 5 نتائج:');
        for (var i = 0; i < allResults.take(5).length; i++) {
          final doc = allResults[i];
          final data = doc.data() as Map<String, dynamic>;
          developer.log('   ${i + 1}. ${data['name']}');
          developer.log('      - code: ${data['code']}');
          developer.log(
            '      - companyCodeInOrg: ${data['companyCodeInOrg']}',
          );
        }
      }
      developer.log('═══════════════════════════════════════════════════');

      // تطبيق pagination
      int startIndex = 0;
      if (lastDocument != null) {
        startIndex =
            allResults.indexWhere((doc) => doc.id == lastDocument.id) + 1;
        if (startIndex == 0) startIndex = 0; // إذا لم نجد lastDocument
      }

      final paginatedDocs = allResults
          .skip(startIndex)
          .take(limit + 1)
          .toList();

      return _buildPaginationResponse(paginatedDocs, limit);
    } catch (e, stackTrace) {
      developer.log('═══════════════════════════════════════════════════');
      developer.log('❌ خطأ في البحث!');
      developer.log('الخطأ: $e');
      developer.log('Stack trace: $stackTrace');
      developer.log('═══════════════════════════════════════════════════');
      throw Exception('Failed to search companies: $e');
    }
  }

  /// Build pagination response from documents
  PaginationResponse<CompanyModel> _buildPaginationResponse(
    List<QueryDocumentSnapshot> docs,
    int limit,
  ) {
    final hasMore = docs.length > limit;
    final actualDocs = hasMore ? docs.take(limit).toList() : docs;

    final companies = actualDocs.map((doc) {
      return CompanyModel.fromFirestore(doc);
    }).toList();

    return PaginationResponse<CompanyModel>(
      items: companies,
      hasReachedMax: !hasMore,
      lastDoc: actualDocs.isNotEmpty ? actualDocs.last : null,
    );
  }

  @override
  Future<PaginationResponse<CompanyModel>> getCompanies({
    required String organizationUID,
    DocumentSnapshot? lastDocument,
    int limit = 20,
  }) async {
    try {
      Query query = firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .orderBy('createdAt', descending: true)
          .limit(limit + 1);

      if (lastDocument != null) {
        query = query.startAfterDocument(lastDocument);
      }

      final querySnapshot = await query.get();
      final docs = querySnapshot.docs;

      final hasMore = docs.length > limit;
      final actualDocs = hasMore ? docs.take(limit).toList() : docs;

      final companies = actualDocs
          .map((doc) => CompanyModel.fromFirestore(doc))
          .toList();

      return PaginationResponse<CompanyModel>(
        items: companies,
        hasReachedMax: !hasMore,
        lastDoc: actualDocs.isNotEmpty ? actualDocs.last : null,
      );
    } catch (e) {
      throw Exception('Failed to get companies: $e');
    }
  }

  @override
  Future<CompanyModel> getCompanyById({
    required String organizationUID,
    required String companyUID,
  }) async {
    try {
      final doc = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .doc(companyUID)
          .get();

      if (!doc.exists) {
        throw Exception('Company not found');
      }

      return CompanyModel.fromFirestore(doc);
    } catch (e) {
      throw Exception('Failed to get company: $e');
    }
  }
}
