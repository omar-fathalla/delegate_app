# 🔍 تشخيص المشكلة - بيانات المستخدم لا تُحمل من Firebase

**التاريخ:** 12 أبريل 2026  
**الحالة:** 🔴 مشكلة تحتاج حل  
**الملف:** `lib/features/profile/presentation/pages/profile_screen.dart`

---

## 🔴 المشكلة

البيانات الشخصية تظهر **"غير محدد"** (Not Set):
- ❌ الاسم: غير محدد
- ❌ البريد الإلكتروني: غير محدد
- ❌ رقم الموبايل: غير محدد

---

## 🔍 تحليل السبب الجذري

### المسار الذي تتبعه البيانات:

```
ProfileScreen
    ↓
ProfileBloc (LoadProfile event)
    ↓
GetDelegateProfile UseCase
    ↓
ProfileRepository
    ↓
ProfileRemoteDataSource
    ↓
Firebase Firestore
```

### الخطوات التي يتبعها الكود:

```dart
// 1. جلب بيانات المستخدم من users collection
final userDoc = await firestore.collection('users').doc(uid).get();

// 2. التحقق من أن المستخدم delegate
if (role != 'delegate') {
  throw ServerException('User is not a delegate');
}

// 3. الحصول على organizationUID و companyUID
String? organizationUID = userData['organizationUID'];
String? companyUID = userData['companyUID'];

// 4. جلب بيانات المندوب من المسار الصحيح
final delegateRef = firestore
    .collection('organizations')
    .doc(organizationUID)
    .collection('companies')
    .doc(companyUID)
    .collection('delegates')
    .doc(uid);
```

---

## 🎯 الأسباب المحتملة

### السبب 1: ❌ عدم وجود بيانات المستخدم في Firestore

**المشكلة:**
```
users collection
├── uid1 ✅ موجود
├── uid2 ✅ موجود
└── uid3 ❌ غير موجود (المستخدم الحالي)
```

**الحل:**
```dart
// تحقق من وجود المستخدم في Firebase Console
// أو أنشئ بيانات المستخدم يدوياً
```

### السبب 2: ❌ عدم وجود organizationUID أو companyUID

**المشكلة:**
```json
{
  "uid": "user123",
  "role": "delegate",
  "organizationUID": null,  // ❌ غير موجود
  "companyUID": null        // ❌ غير موجود
}
```

**الحل:**
```json
{
  "uid": "user123",
  "role": "delegate",
  "organizationUID": "org123",  // ✅ يجب أن يكون موجود
  "companyUID": "comp123"       // ✅ يجب أن يكون موجود
}
```

### السبب 3: ❌ عدم وجود بيانات المندوب في المسار الصحيح

**المشكلة:**
```
organizations/org123/companies/comp123/delegates/uid
❌ غير موجود
```

**الحل:**
```
organizations/org123/companies/comp123/delegates/uid
✅ يجب أن يكون موجود مع البيانات الكاملة
```

### السبب 4: ❌ عدم وجود Firestore Rules الصحيحة

**المشكلة:**
```javascript
// ❌ Rules تمنع القراءة
match /organizations/{orgId}/companies/{compId}/delegates/{delegateId} {
  allow read: if false;  // ❌ منع القراءة
}
```

**الحل:**
```javascript
// ✅ Rules تسمح بالقراءة
match /organizations/{orgId}/companies/{compId}/delegates/{delegateId} {
  allow read: if isAuthenticated();  // ✅ السماح بالقراءة
}
```

---

## 🛠️ خطوات التشخيص

### الخطوة 1: تحقق من وجود المستخدم في Firebase

```bash
# في Firebase Console
1. اذهب إلى Firestore Database
2. اذهب إلى collection "users"
3. ابحث عن uid المستخدم الحالي
4. تحقق من وجود البيانات
```

### الخطوة 2: تحقق من وجود organizationUID و companyUID

```json
// يجب أن تكون البيانات مثل هذا:
{
  "uid": "user123",
  "role": "delegate",
  "organizationUID": "org123",
  "companyUID": "comp123",
  "email": "user@example.com",
  "displayName": "اسم المستخدم"
}
```

### الخطوة 3: تحقق من وجود بيانات المندوب

```bash
# المسار الصحيح:
organizations/org123/companies/comp123/delegates/user123

# يجب أن تكون البيانات موجودة هناك
```

### الخطوة 4: تحقق من Firestore Rules

```bash
# في Firebase Console
1. اذهب إلى Firestore Rules
2. تحقق من أن القراءة مسموحة للمندوبين
3. تأكد من عدم وجود قيود تمنع القراءة
```

---

## 📊 جدول التشخيص

| الخطوة | التحقق | الحالة | الحل |
|-------|--------|--------|------|
| 1 | هل المستخدم موجود في `users` collection؟ | ❌ | أنشئ بيانات المستخدم |
| 2 | هل `organizationUID` موجود؟ | ❌ | أضف `organizationUID` |
| 3 | هل `companyUID` موجود؟ | ❌ | أضف `companyUID` |
| 4 | هل بيانات المندوب موجودة في المسار الصحيح؟ | ❌ | أنشئ بيانات المندوب |
| 5 | هل Firestore Rules تسمح بالقراءة؟ | ❌ | حدّث Firestore Rules |

---

## 🔧 الحل الكامل

### الخطوة 1: تحقق من بيانات المستخدم

```dart
// في Firebase Console أو عبر Cloud Functions
// تأكد من وجود هذه البيانات:
{
  "uid": "user123",
  "role": "delegate",
  "organizationUID": "org123",
  "companyUID": "comp123",
  "email": "user@example.com",
  "displayName": "اسم المستخدم",
  "createdAt": Timestamp.now()
}
```

### الخطوة 2: تحقق من بيانات المندوب

```dart
// في المسار: organizations/org123/companies/comp123/delegates/user123
// تأكد من وجود هذه البيانات:
{
  "uid": "user123",
  "firstName": "اسم",
  "lastName": "العائلة",
  "fullName": "اسم العائلة",
  "phoneNumber": "01234567890",
  "email": "user@example.com",
  "organizationUID": "org123",
  "companyUID": "comp123",
  "status": "active",
  "position": "promoter"
}
```

### الخطوة 3: تحقق من Firestore Rules

```javascript
// في firestore.rules
match /organizations/{orgId}/companies/{compId}/delegates/{delegateId} {
  // ✅ السماح بالقراءة للمستخدمين المصادقين
  allow read: if isAuthenticated();
  
  // ✅ السماح بالكتابة للمسؤولين فقط
  allow write: if isAuthenticated() && canAccessCompany(orgId, compId);
}
```

---

## 📝 ملاحظات مهمة

### 1. تسلسل البيانات
```
users/uid
    ↓ (يحتوي على organizationUID و companyUID)
organizations/orgId/companies/compId/delegates/uid
    ↓ (يحتوي على البيانات الكاملة للمندوب)
```

### 2. الأخطاء الشائعة
- ❌ عدم وجود `organizationUID` في `users` collection
- ❌ عدم وجود `companyUID` في `users` collection
- ❌ عدم وجود بيانات المندوب في المسار الصحيح
- ❌ Firestore Rules تمنع القراءة

### 3. الحل السريع
```dart
// إذا كنت تريد اختبار سريع، أضف بيانات وهمية:
// 1. في Firebase Console
// 2. أنشئ users/uid مع organizationUID و companyUID
// 3. أنشئ organizations/orgId/companies/compId/delegates/uid
// 4. أعد تحميل التطبيق
```

---

## 🎯 الخطوات التالية

### 1. تشخيص المشكلة
- [ ] تحقق من وجود المستخدم في `users` collection
- [ ] تحقق من وجود `organizationUID` و `companyUID`
- [ ] تحقق من وجود بيانات المندوب في المسار الصحيح
- [ ] تحقق من Firestore Rules

### 2. إصلاح المشكلة
- [ ] أنشئ بيانات المستخدم إذا لم تكن موجودة
- [ ] أضف `organizationUID` و `companyUID` إذا كانت ناقصة
- [ ] أنشئ بيانات المندوب في المسار الصحيح
- [ ] تحقق من Firestore Rules

### 3. اختبر الحل
- [ ] أعد تحميل التطبيق
- [ ] تحقق من ظهور البيانات
- [ ] اختبر جميع الحقول

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 12 أبريل 2026  
**الحالة:** 🔴 يحتاج تشخيص وحل

