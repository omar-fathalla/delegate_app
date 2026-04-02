# ⚡ إصلاح سريع - مشكلة الفروع على iOS

## 🎯 المشكلة
عند فتح التطبيق على iOS، لا تظهر بيانات الفروع (رسالة خطأ: "فشل في جلب بيانات الفروع")

## ✅ الحل (تم تطبيقه)
أضفنا `signInAnonymously()` عند تسجيل الدخول كـ Super Admin لضمان المصادقة في Firebase.

## 🚀 خطوات الاختبار

### 1. إعادة بناء التطبيق
```bash
./rebuild_ios.sh
```

أو يدوياً:
```bash
flutter clean
flutter pub get
cd ios && pod install && cd ..
flutter run
```

### 2. اختبار التطبيق
1. احذف التطبيق من iPhone (إن وجد)
2. شغل التطبيق: `flutter run`
3. سجل دخول:
   - رقم: `01508899965`
   - كلمة المرور: `01508899965000`
4. اذهب إلى "الفروع"
5. يجب أن تظهر البيانات ✅

### 3. اختبار متقدم (اختياري)
```bash
flutter run -t test_firestore_ios.dart
```

## 📊 ما تم تغييره

**الملف:** `lib/features/auth/data/datasources/auth_remote_data_source.dart`

```dart
// قبل
if (normalizedPhone == '01508899965') {
  return [DelegateModel(...)];
}

// بعد
if (normalizedPhone == '01508899965') {
  await signInAnonymously();  // ← إضافة هذا السطر
  return [DelegateModel(...)];
}
```

## 🔍 التحقق من النجاح

### في التطبيق
- ✅ تسجيل الدخول يعمل
- ✅ صفحة الفروع تظهر البيانات
- ✅ لا توجد رسائل خطأ

### في Firebase Console
1. افتح: https://console.firebase.google.com/project/practice-firebase-72df1/authentication/users
2. يجب أن ترى مستخدم Anonymous جديد

## ❓ لماذا حدثت المشكلة؟

Firestore Rules تتطلب مصادقة:
```javascript
match /branches/{branchId} {
  allow read: if isAuthenticated();  // ← يتطلب مصادقة
}
```

Super Admin كان يُنشأ بدون مصادقة → الوصول مرفوض ❌

## 📝 ملاحظات

- ✅ الحل آمن (Anonymous Auth مسموح به في Firestore Rules)
- ✅ لا يؤثر على الـ Admins العاديين (يستخدمون Email/Password Auth)
- ✅ لا يؤثر على المندوبين (يستخدمون Anonymous Auth بالفعل)

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026
