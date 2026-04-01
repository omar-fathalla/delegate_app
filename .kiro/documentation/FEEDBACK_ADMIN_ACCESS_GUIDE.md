# 🔍 دليل حل مشكلة وصول Super Admin للمقترحات

**التاريخ:** 1 أبريل 2026  
**المشكلة:** Super Admin يحصل على خطأ `permission-denied` عند محاولة عرض المقترحات

---

## 🎯 السبب الرئيسي

المستخدم يدخل على الصفحة **الخاطئة**!

### ❌ الصفحة الخاطئة (للمستخدمين العاديين)
- **المسار:** `/my-feedbacks`
- **الصفحة:** `MyFeedbacksScreen`
- **الوظيفة:** تعرض مقترحات المستخدم نفسه فقط
- **الاستعلام:** `where('userId', isEqualTo: userId)`

### ✅ الصفحة الصحيحة (للـ Super Admin)
- **المسار:** `/admin/feedbacks`
- **الصفحة:** `AdminFeedbacksScreen`
- **الوظيفة:** تعرض **جميع** المقترحات من كل المستخدمين
- **الاستعلام:** بدون فلتر userId

---

## 🔧 الحل السريع

### الخطوة 1: تحقق من المسار

عندما تضغط على "إدارة المقترحات" من قائمة الإدارة، يجب أن يكون المسار:

```
/admin/feedbacks  ✅ صحيح
```

وليس:

```
/my-feedbacks  ❌ خطأ
```

### الخطوة 2: تحقق من القائمة

في لوحة الإدارة، يجب أن يكون هناك عنصر قائمة:

```dart
// في admin_main_screen.dart أو settings_screen.dart
ListTile(
  leading: const Icon(Icons.feedback),
  title: Text(isArabic ? 'إدارة المقترحات' : 'Manage Feedbacks'),
  onTap: () {
    context.push('/admin/feedbacks');  // ✅ المسار الصحيح
  },
)
```

---

## 🔍 التحقق من الدور (Role)

إذا كنت متأكداً من استخدام المسار الصحيح ولا يزال الخطأ موجوداً، تحقق من دور المستخدم في Firestore:

### 1. افتح Firebase Console
```
https://console.firebase.google.com/project/practice-firebase-72df1/firestore
```

### 2. اذهب إلى Collection: `users`

### 3. ابحث عن وثيقة المستخدم باستخدام UID

### 4. تحقق من حقل `role`

يجب أن يكون:
```json
{
  "role": "super-admin"  // ✅ بالضبط هكذا
}
```

وليس:
```json
{
  "role": "Super Admin"  // ❌ خطأ (حرف كبير)
  "role": "superadmin"   // ❌ خطأ (بدون شرطة)
  "role": "admin"        // ❌ خطأ (ليس super-admin)
}
```

---

## 📊 الفرق بين الصفحتين

| الميزة | MyFeedbacksScreen | AdminFeedbacksScreen |
|--------|------------------|---------------------|
| **المسار** | `/my-feedbacks` | `/admin/feedbacks` |
| **الاستعلام** | `where('userId', isEqualTo: userId)` | بدون فلتر |
| **البيانات** | مقترحات المستخدم فقط | **جميع** المقترحات |
| **الصلاحية** | أي مستخدم مصادق | Super Admin فقط |
| **الإحصائيات** | ❌ لا توجد | ✅ موجودة |
| **تحديث الحالة** | ❌ لا يمكن | ✅ يمكن |
| **رد الإدارة** | ❌ لا يمكن | ✅ يمكن |

---

## 🧪 اختبار سريع

### 1. افتح التطبيق كـ Super Admin

### 2. اذهب إلى لوحة الإدارة

### 3. ابحث عن "إدارة المقترحات" في القائمة

### 4. اضغط عليها

### 5. تحقق من المسار في الـ URL أو الـ Debug Console

يجب أن يكون:
```
/admin/feedbacks  ✅
```

### 6. إذا ظهرت الصفحة بنجاح، يجب أن ترى:

- ✅ إحصائيات في الأعلى (الإجمالي، معلق، قيد التنفيذ، تم الحل)
- ✅ جميع المقترحات من كل المستخدمين
- ✅ زر الفلتر في الـ AppBar
- ✅ إمكانية الضغط على أي مقترح لتحديث حالته

---

## 🔐 Firestore Rules (للمرجع)

```javascript
match /feedbacks/{feedbackId} {
  // القراءة: المستخدم يقرأ مقترحاته، أو Super Admin يقرأ الكل
  allow read: if isAuthenticated() && (
    resource.data.userId == request.auth.uid ||  // المستخدم نفسه
    isSuperAdmin() ||                            // Super Admin
    isOrgAdmin()                                 // Org Admin
  );
  
  // الإنشاء: أي مستخدم مصادق
  allow create: if isAuthenticated() &&
    request.resource.data.userId == request.auth.uid &&
    request.resource.data.status == 'pending' &&
    request.resource.data.createdAt == request.time;
  
  // التحديث: Super Admin أو Org Admin فقط
  allow update: if isAuthenticated() && (isSuperAdmin() || isOrgAdmin());
  
  // الحذف: Super Admin فقط
  allow delete: if isAuthenticated() && isSuperAdmin();
}
```

---

## 📝 ملاحظات مهمة

### 1. MyFeedbacksScreen (للمستخدمين العاديين)
- تستخدم `LoadUserFeedbacksEvent(userId: delegate.uid)`
- تستدعي `getUserFeedbacks(userId)` في الـ DataSource
- الاستعلام: `where('userId', isEqualTo: userId)`
- **لا تعرض إحصائيات**
- **لا تسمح بتحديث الحالة**

### 2. AdminFeedbacksScreen (للـ Super Admin)
- تستخدم `LoadAllFeedbacksEvent()`
- تستدعي `getAllFeedbacks()` في الـ DataSource
- الاستعلام: بدون فلتر (تجلب الكل)
- **تعرض إحصائيات**
- **تسمح بتحديث الحالة ورد الإدارة**

---

## 🚀 الخطوات التالية

### إذا كان المسار صحيح (`/admin/feedbacks`) ولا يزال الخطأ موجوداً:

1. **تحقق من دور المستخدم في Firestore**
   - افتح Firebase Console
   - اذهب إلى `users` collection
   - ابحث عن وثيقة المستخدم
   - تأكد من أن `role` = `"super-admin"`

2. **تحقق من نشر Firestore Rules**
   ```bash
   firebase deploy --only firestore:rules --project practice-firebase-72df1
   ```

3. **تحقق من Firestore Rules في Firebase Console**
   - افتح Firebase Console
   - اذهب إلى Firestore → Rules
   - تأكد من وجود قواعد `feedbacks` collection

4. **أعد تشغيل التطبيق**
   ```bash
   flutter clean
   flutter pub get
   flutter run
   ```

---

## 📞 الدعم

إذا استمرت المشكلة بعد اتباع جميع الخطوات:

1. أرسل لقطة شاشة من:
   - المسار الحالي (URL أو Debug Console)
   - وثيقة المستخدم في Firestore (حقل `role`)
   - رسالة الخطأ الكاملة

2. تحقق من:
   - هل أنت متأكد من أنك Super Admin؟
   - هل تم نشر Firestore Rules بنجاح؟
   - هل المسار `/admin/feedbacks` وليس `/my-feedbacks`؟

---

**تم إنشاء هذا الدليل بواسطة:** Kiro AI Assistant  
**التاريخ:** 1 أبريل 2026  
**الحالة:** ✅ جاهز للاستخدام

