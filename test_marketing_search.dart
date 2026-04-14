import 'dart:developer' as developer;

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_core/firebase_core.dart';

/// سكريبت اختبار للبحث عن الشركة بالكود 512
/// يمكن تشغيله من Flutter test أو كـ standalone script
void main() async {
  // تهيئة Firebase
  await Firebase.initializeApp();

  final firestore = FirebaseFirestore.instance;
  final auth = FirebaseAuth.instance;

  developer.log(
    '═══════════════════════════════════════════════════════════════',
  );
  developer.log('🔍 اختبار البحث عن الشركة - كود 512');
  developer.log(
    '═══════════════════════════════════════════════════════════════',
  );
  developer.log('');

  // 1. التحقق من المستخدم الحالي
  final currentUser = auth.currentUser;
  if (currentUser == null) {
    developer.log('❌ لا يوجد مستخدم مسجل دخول');
    developer.log('يرجى تسجيل الدخول أولاً');
    return;
  }

  developer.log('✅ المستخدم: ${currentUser.uid}');
  developer.log('   Email: ${currentUser.email ?? "N/A"}');
  developer.log('');

  // 2. الحصول على بيانات المستخدم من users collection
  try {
    final userDoc = await firestore
        .collection('users')
        .doc(currentUser.uid)
        .get();

    if (!userDoc.exists) {
      developer.log('❌ لا يوجد document للمستخدم في users collection');
      developer.log('يرجى إنشاء حساب للمستخدم أولاً');
      return;
    }

    final userData = userDoc.data()!;
    developer.log('✅ بيانات المستخدم:');
    developer.log('   Role: ${userData['role']}');
    developer.log('   Organization UID: ${userData['organizationUID']}');
    developer.log('   Company UID: ${userData['companyUID'] ?? "N/A"}');
    developer.log('');

    final organizationUID = userData['organizationUID'] as String?;
    if (organizationUID == null) {
      developer.log('❌ المستخدم ليس لديه organizationUID');
      return;
    }

    // 3. البحث عن الشركة بالكود 512
    developer.log('🔍 البحث عن الشركة بالكود 512...');
    developer.log('   Organization: $organizationUID');
    developer.log('');

    // محاولة 1: البحث بالكود كرقم
    developer.log('📊 محاولة 1: البحث بـ code = 512 (رقم)');
    try {
      final query1 = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .where('code', isEqualTo: 512)
          .limit(5)
          .get();

      developer.log('   النتائج: ${query1.docs.length} شركة');

      if (query1.docs.isNotEmpty) {
        for (var doc in query1.docs) {
          final data = doc.data();
          developer.log('   ✓ ${data['name']}');
          developer.log('     - Code: ${data['code']}');
          developer.log(
            '     - Company Code In Org: ${data['companyCodeInOrg']}',
          );
          developer.log('     - ID: ${doc.id}');
          developer.log('');
        }
      }
    } catch (e) {
      developer.log('   ❌ خطأ: $e');
    }

    developer.log('');

    // محاولة 2: البحث بـ companyCodeInOrg
    developer.log('📊 محاولة 2: البحث بـ companyCodeInOrg = "512"');
    try {
      final query2 = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .where('companyCodeInOrg', isEqualTo: '512')
          .limit(5)
          .get();

      developer.log('   النتائج: ${query2.docs.length} شركة');

      if (query2.docs.isNotEmpty) {
        for (var doc in query2.docs) {
          final data = doc.data();
          developer.log('   ✓ ${data['name']}');
          developer.log('     - Code: ${data['code']}');
          developer.log(
            '     - Company Code In Org: ${data['companyCodeInOrg']}',
          );
          developer.log('     - ID: ${doc.id}');
          developer.log('');
        }
      }
    } catch (e) {
      developer.log('   ❌ خطأ: $e');
    }

    developer.log('');

    // محاولة 3: عرض جميع الشركات (أول 10)
    developer.log('📊 محاولة 3: عرض أول 10 شركات في المنظمة');
    try {
      final query3 = await firestore
          .collection('organizations')
          .doc(organizationUID)
          .collection('companies')
          .limit(10)
          .get();

      developer.log('   إجمالي الشركات: ${query3.docs.length}');
      developer.log('');

      if (query3.docs.isNotEmpty) {
        for (var doc in query3.docs) {
          final data = doc.data();
          developer.log('   • ${data['name']}');
          developer.log('     - Code: ${data['code']}');
          developer.log(
            '     - Company Code In Org: ${data['companyCodeInOrg'] ?? "N/A"}',
          );
          developer.log('');
        }
      }
    } catch (e) {
      developer.log('   ❌ خطأ: $e');
    }

    developer.log('');
    developer.log(
      '═══════════════════════════════════════════════════════════════',
    );
    developer.log('✅ انتهى الاختبار');
    developer.log(
      '═══════════════════════════════════════════════════════════════',
    );
  } catch (e, stackTrace) {
    developer.log('❌ خطأ عام: $e');
    developer.log('Stack trace: $stackTrace');
  }
}
