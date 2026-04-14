import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';
import 'dart:developer' as developer;

/// سكريبت للتحقق من بيانات الشركات في Firestore
/// Debug script to check company data in Firestore
void main() async {
  // تهيئة Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;

  developer.log('🔍 جاري البحث عن الشركات في Firestore...');
  developer.log('🔍 Searching for companies in Firestore...');

  try {
    // جلب جميع المنظمات
    final orgsSnapshot = await firestore.collection('organizations').get();

    developer.log('📊 عدد المنظمات: ${orgsSnapshot.docs.length}');
    developer.log('📊 Number of organizations: ${orgsSnapshot.docs.length}');

    for (var orgDoc in orgsSnapshot.docs) {
      final orgId = orgDoc.id;
      developer.log('\n🏢 منظمة: $orgId');
      developer.log('🏢 Organization: $orgId');

      // جلب الشركات في هذه المنظمة
      final companiesSnapshot = await firestore
          .collection('organizations')
          .doc(orgId)
          .collection('companies')
          .get();

      developer.log('📊 عدد الشركات: ${companiesSnapshot.docs.length}');
      developer.log('📊 Number of companies: ${companiesSnapshot.docs.length}');

      // طباعة تفاصيل كل شركة
      for (var companyDoc in companiesSnapshot.docs) {
        final data = companyDoc.data();
        developer.log('\n📄 شركة:');
        developer.log('📄 Company:');
        developer.log('  - ID: ${companyDoc.id}');
        developer.log('  - الاسم / Name: ${data['name']}');
        developer.log('  - الكود / Code: ${data['code']}');
        developer.log('  - companyCodeInOrg: ${data['companyCodeInOrg']}');
        developer.log('  - companyCode: ${data['companyCode']}');
        developer.log('  - companyId: ${data['companyId']}');
        developer.log('  - id: ${data['id']}');
        developer.log('  - جميع الحقول / All fields: ${data.keys.toList()}');

        // التحقق من وجود الكود 1048
        if (data['code'] == 1048 ||
            data['companyCodeInOrg'] == '1048' ||
            data['companyCode'] == '1048' ||
            data['companyId'] == 1048 ||
            data['id'] == '1048') {
          developer.log('🎯 وُجدت الشركة بالكود 1048!');
          developer.log('🎯 Found company with code 1048!');
        }

        // التحقق من وجود الكود 6047
        if (data['code'] == 6047 ||
            data['companyCodeInOrg'] == '6047' ||
            data['companyCode'] == '6047' ||
            data['companyId'] == 6047 ||
            data['id'] == '6047') {
          developer.log('🎯 وُجدت الشركة بالكود 6047!');
          developer.log('🎯 Found company with code 6047!');
        }
      }
    }

    developer.log('\n✅ انتهى التحقق من البيانات');
    developer.log('✅ Data check completed');
  } catch (e) {
    developer.log('❌ خطأ في التحقق من البيانات: $e');
    developer.log('❌ Error checking data: $e');
  }
}
