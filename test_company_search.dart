import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';

/// سكريبت اختبار البحث عن الشركات
/// Test script for company search
void main() async {
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;

  developer.log('🔍 اختبار البحث عن الشركات...');
  developer.log('🔍 Testing company search...');

  final testOrganizations = [
    'practice-firebase-72df1',
    'default-org',
    'test-org',
  ];

  final testCodes = ['1048', '6047', 1048, 6047];

  for (final orgId in testOrganizations) {
    developer.log('\n🏢 اختبار المنظمة: $orgId');
    developer.log('🏢 Testing organization: $orgId');

    try {
      final allCompaniesSnapshot = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .limit(10)
          .get();

      developer.log(
        '📊 عدد الشركات الموجودة: ${allCompaniesSnapshot.docs.length}',
      );
      developer.log(
        '📊 Number of companies found: ${allCompaniesSnapshot.docs.length}',
      );

      if (allCompaniesSnapshot.docs.isNotEmpty) {
        developer.log('📄 أول 5 شركات:');
        developer.log('📄 First 5 companies:');

        for (int i = 0; i < allCompaniesSnapshot.docs.length && i < 5; i++) {
          final doc = allCompaniesSnapshot.docs[i];
          final data = doc.data();
          developer.log(
            '  ${i + 1}. ${data['name']} - Code: ${data['code']} - companyCodeInOrg: ${data['companyCodeInOrg']}',
          );
        }

        for (final code in testCodes) {
          developer.log('\n🔍 البحث عن الكود: $code');
          developer.log('🔍 Searching for code: $code');

          Query query;

          if (code is int) {
            query = firestore
                .collection('organizations')
                .doc(orgId)
                .collection('companies')
                .where('code', isEqualTo: code)
                .limit(5);
          } else {
            query = firestore
                .collection('organizations')
                .doc(orgId)
                .collection('companies')
                .where('companyCodeInOrg', isEqualTo: code.toString())
                .limit(5);
          }

          final searchSnapshot = await query.get();
          developer.log('📊 نتائج البحث: ${searchSnapshot.docs.length}');
          developer.log('📊 Search results: ${searchSnapshot.docs.length}');

          for (final doc in searchSnapshot.docs) {
            final data = doc.data() as Map<String, dynamic>;
            developer.log(
              '  ✅ وُجدت: ${data['name']} - Code: ${data['code']} - companyCodeInOrg: ${data['companyCodeInOrg']}',
            );
            developer.log(
              '  ✅ Found: ${data['name']} - Code: ${data['code']} - companyCodeInOrg: ${data['companyCodeInOrg']}',
            );
          }
        }
      }
    } catch (e) {
      developer.log('❌ خطأ في اختبار المنظمة $orgId: $e');
      developer.log('❌ Error testing organization $orgId: $e');
    }
  }

  developer.log('\n✅ انتهى الاختبار');
  developer.log('✅ Test completed');
}
