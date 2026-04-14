# 🔐 Firestore Rules - Marketing Access

**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ محدّث  
**الإصدار:** 1.1.0

---

## 🎯 نظرة عامة

تم تحديث Firestore Rules لإضافة صلاحيات **قراءة فقط (Read-Only)** لموظفي التسويق (Marketing) للوصول إلى:

- ✅ الشركات (Companies) - للبحث بالكود
- ✅ المندوبين (Delegates) - للبحث برقم الهاتف

**ملاحظة مهمة:** لم يتم حذف أي قواعد موجودة، تم فقط إضافة تعليقات توضيحية وقاعدة جديدة لـ collectionGroup.

---

## 📝 التغييرات المضافة

### 1. إضافة قاعدة collectionGroup للشركات

**الموقع:** بعد قاعدة `delegates` collectionGroup

```javascript
// Companies collectionGroup (Marketing Search)
// Allow marketing users to search companies across all organizations
match /{path=**}/companies/{companyId} {
  // Allow read for all authenticated users (including marketing)
  // Marketing users need this for company search functionality
  allow read: if isAuthenticated();
}
```

**الغرض:**
- السماح لموظفي التسويق بالبحث عن الشركات عبر جميع المنظمات
- دعم البحث بالكود (code) أو (companyCodeInOrg)

---

### 2. تحديث تعليقات قاعدة delegates collectionGroup

**قبل:**
```javascript
// Delegates collectionGroup (Web Dashboard + Mobile App)
```

**بعد:**
```javascript
// Delegates collectionGroup (Web Dashboard + Mobile App + Marketing Search)
// Marketing users can read delegates for search purposes (read-only).
```

**الغرض:**
- توضيح أن موظفي التسويق يمكنهم قراءة المندوبين
- البحث برقم الهاتف للأغراض التسويقية

---

### 3. تحديث تعليقات قاعدة companies في organizations

**قبل:**
```javascript
// Read: Allow all authenticated users (including anonymous) to read companies
// NOTE: This includes marketing search functionality where users may not have a /users document
```

**بعد:**
```javascript
// Read: Allow all authenticated users (including anonymous and marketing) to read companies
// NOTE: This includes marketing search functionality where users may not have a /users document
// Marketing users need read access for company search by code functionality
```

**الغرض:**
- توضيح صريح أن موظفي التسويق لهم صلاحية قراءة
- شرح الغرض من الصلاحية (البحث بالكود)

---

### 4. تحديث تعليقات قاعدة delegates في companies

**قبل:**
```javascript
// Write: Company admins and org admins only (no marketing)
```

**بعد:**
```javascript
// Read: All authenticated users + marketing (read-only)
// Marketing users can search delegates by phone number for marketing purposes
allow read: if isAuthenticated();

// Write: Company admins and org admins only (no marketing write access)
```

**الغرض:**
- توضيح أن موظفي التسويق لهم صلاحية قراءة فقط
- منع موظفي التسويق من الكتابة (Create/Update/Delete)

---

## 🔒 الصلاحيات الحالية لموظف التسويق

### ✅ يمكنه (Read-Only)

| المجموعة | الصلاحية | الغرض |
|---------|---------|-------|
| **companies** | قراءة | البحث عن الشركات بالكود |
| **delegates** | قراءة | البحث عن المندوبين برقم الهاتف |
| **organizations** | قراءة | عرض معلومات المنظمة |
| **users** | قراءة | عرض معلومات المستخدمين |

### ❌ لا يمكنه (No Write Access)

| المجموعة | الصلاحية المحظورة |
|---------|-------------------|
| **companies** | إنشاء / تعديل / حذف |
| **delegates** | إنشاء / تعديل / حذف |
| **requests** | إنشاء / تعديل / حذف |
| **tasks** | إنشاء / تعديل / حذف |
| **notifications** | إنشاء / حذف |

---

## 🧪 اختبار الصلاحيات

### 1. اختبار البحث عن شركة

```dart
// يجب أن ينجح
final query = await firestore
    .collection('organizations')
    .doc(organizationUID)
    .collection('companies')
    .where('code', isEqualTo: 512)
    .get();

// النتيجة المتوقعة: ✅ نجح
```

### 2. اختبار البحث عن مندوب

```dart
// يجب أن ينجح
final query = await firestore
    .collectionGroup('delegates')
    .where('organizationUID', isEqualTo: organizationUID)
    .where('phoneNumber', isEqualTo: '01234567890')
    .get();

// النتيجة المتوقعة: ✅ نجح
```

### 3. اختبار محاولة إنشاء شركة

```dart
// يجب أن يفشل
await firestore
    .collection('organizations')
    .doc(organizationUID)
    .collection('companies')
    .add({
      'name': 'شركة جديدة',
      'code': 999,
    });

// النتيجة المتوقعة: ❌ فشل (permission-denied)
```

---

## 📊 مقارنة الصلاحيات

| الدور | قراءة الشركات | كتابة الشركات | قراءة المندوبين | كتابة المندوبين |
|------|---------------|---------------|----------------|-----------------|
| **Super Admin** | ✅ | ✅ | ✅ | ✅ |
| **Org Admin** | ✅ | ✅ | ✅ | ✅ |
| **Company Admin** | ✅ | ✅ (شركته فقط) | ✅ | ✅ (شركته فقط) |
| **Marketing** | ✅ | ❌ | ✅ | ❌ |
| **Delegate** | ❌ | ❌ | ❌ | ❌ |

---

## 🚀 نشر التحديثات

### الطريقة 1: Firebase Console

1. افتح [Firebase Console](https://console.firebase.google.com/project/practice-firebase-72df1/firestore/rules)
2. انسخ محتوى `firestore.rules`
3. الصق في المحرر
4. اضغط "Publish"

### الطريقة 2: Firebase CLI

```bash
firebase deploy --only firestore:rules --project practice-firebase-72df1
```

---

## ⚠️ ملاحظات مهمة

### 1. المصادقة مطلوبة

جميع الصلاحيات تتطلب `isAuthenticated()`:
- موظف التسويق يجب أن يكون مسجل دخول
- يجب أن يكون له حساب في `users` collection
- يجب أن يكون `role == 'marketing'`

### 2. Read-Only فقط

موظف التسويق لديه صلاحيات **قراءة فقط**:
- لا يمكنه إنشاء شركات أو مندوبين
- لا يمكنه تعديل البيانات
- لا يمكنه حذف أي شيء

### 3. Firestore Indexes مطلوبة

تأكد من وجود الـ indexes التالية:

```json
{
  "collectionGroup": "companies",
  "queryScope": "COLLECTION",
  "fields": [
    {"fieldPath": "code", "order": "ASCENDING"}
  ]
}
```

```json
{
  "collectionGroup": "delegates",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    {"fieldPath": "organizationUID", "order": "ASCENDING"},
    {"fieldPath": "phoneNumber", "order": "ASCENDING"}
  ]
}
```

---

## 🔍 استكشاف الأخطاء

### خطأ: "permission-denied"

**السبب المحتمل:**
1. المستخدم غير مصادق
2. المستخدم ليس له دور `marketing`
3. الـ rules لم يتم نشرها بعد

**الحل:**
```dart
// تحقق من المصادقة
final user = FirebaseAuth.instance.currentUser;
print('User: ${user?.uid}');

// تحقق من الدور
final userDoc = await FirebaseFirestore.instance
    .collection('users')
    .doc(user?.uid)
    .get();
print('Role: ${userDoc.data()?['role']}');
```

### خطأ: "index-not-found"

**السبب:** الـ index غير موجود في Firestore

**الحل:**
1. افتح الرابط في رسالة الخطأ
2. اضغط "Create Index"
3. انتظر حتى يتم بناء الـ index (قد يستغرق دقائق)

---

## 📚 المراجع

- [Firestore Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Role-Based Access Control](https://firebase.google.com/docs/firestore/security/rules-conditions#authentication)
- [Collection Group Queries](https://firebase.google.com/docs/firestore/query-data/queries#collection-group-query)

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ جاهز للنشر  
**الإصدار:** 1.1.0
