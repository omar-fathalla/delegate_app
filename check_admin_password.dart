// ignore_for_file: avoid_print

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_core/firebase_core.dart';
import 'lib/firebase_options.dart';

/// سكريبت للتحقق من بيانات المشرف في Firestore
/// هذا سكريبت تطوير (development script) وليس جزءاً من كود الإنتاج
void main() async {
  // تهيئة Firebase
  await Firebase.initializeApp(options: DefaultFirebaseOptions.currentPlatform);

  final firestore = FirebaseFirestore.instance;

  print('🔍 البحث عن المشرف برقم: 01101787850\n');

  try {
    // البحث في collection users
    final userQuery = await firestore
        .collection('users')
        .where('phoneNumber', isEqualTo: '01101787850')
        .limit(1)
        .get();

    if (userQuery.docs.isEmpty) {
      print('❌ لم يتم العثور على المشرف في collection "users"');
      print('\n📋 الحل:');
      print('1. اذهب إلى Firebase Console');
      print('2. افتح Firestore Database');
      print('3. أنشئ وثيقة جديدة في collection "users"');
      print('4. أضف الحقول التالية:');
      print('   {');
      print('     "phoneNumber": "01101787850",');
      print('     "displayName": "اسم المشرف",');
      print('     "email": "admin@example.com",');
      print('     "role": "organization-admin",');
      print('     "organizationUID": "org-123",');
      print('     "companyUID": "company-123",');
      print('     "password": "aya270aya",  ← أضف هذا الحقل');
      print('     "isActive": true');
      print('   }');
    } else {
      final userDoc = userQuery.docs.first;
      final userData = userDoc.data();

      print('✅ تم العثور على المشرف!');
      print('📄 Document ID: ${userDoc.id}');
      print('\n📊 البيانات:');
      print('   - phoneNumber: ${userData['phoneNumber']}');
      print('   - displayName: ${userData['displayName']}');
      print('   - email: ${userData['email']}');
      print('   - role: ${userData['role']}');
      print('   - organizationUID: ${userData['organizationUID']}');
      print('   - companyUID: ${userData['companyUID']}');

      // التحقق من وجود حقل password
      if (userData.containsKey('password')) {
        final password = userData['password'];
        print('   - password: $password ✅');

        if (password == 'aya270aya') {
          print('\n✅ كلمة المرور صحيحة! يجب أن يعمل الدخول الآن.');
        } else {
          print('\n⚠️ كلمة المرور المخزنة: "$password"');
          print('   كلمة المرور المتوقعة: "aya270aya"');
          print('   يجب تحديث كلمة المرور في Firebase Console');
        }
      } else {
        print('   - password: ❌ غير موجود!');
        print('\n📋 الحل:');
        print('1. اذهب إلى Firebase Console');
        print('2. افتح Firestore Database → users → ${userDoc.id}');
        print('3. اضغط "Add field"');
        print('4. أضف:');
        print('   Field name: password');
        print('   Type: string');
        print('   Value: aya270aya');
        print('5. احفظ التغييرات');
      }
    }
  } catch (e) {
    print('❌ حدث خطأ: $e');
  }
}
