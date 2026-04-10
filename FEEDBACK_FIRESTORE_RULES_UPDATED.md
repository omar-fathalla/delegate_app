# ✅ تحديث Firestore Rules لنظام المقترحات

**التاريخ:** 2 أبريل 2026  
**الحالة:** ✅ مكتمل

---

## 📋 ما تم إنجازه

### 1. ✅ تحديث Firestore Rules

تم تحديث قواعد الـ `feedbacks` collection في ملف `firestore.rules` بدون حذف أي قواعد موجودة.

#### القواعد الجديدة:

```javascript
// ==================== FEEDBACKS COLLECTION ====================
// User feedbacks and suggestions system
// Delegates and supervisors can submit feedbacks
// Super Admin has full control over all feedbacks
match /feedbacks/{feedbackId} {
  // Read: Users can read their own feedbacks, Super Admin and Org Admin can read all
  allow read: if isAuthenticated() && 
    (resource.data.userId == request.auth.uid || isSuperAdmin() || isOrgAdmin());
  
  // Create: Authenticated users can create feedbacks with validation
  allow create: if isAuthenticated() &&
    request.resource.data.userId == request.auth.uid &&
    request.resource.data.status == 'pending' &&
    request.resource.data.createdAt == request.time;
  
  // Update: Only Super Admin and Org Admin can update (to change status or add admin response)
  allow update: if isAuthenticated() && (isSuperAdmin() || isOrgAdmin());
  
  // Delete: Only Super Admin can delete feedbacks
  allow delete: if isAuthenticated() && isSuperAdmin();
}
```

### 2. ✅ Storage Rules (موجودة بالفعل)

قواعد Storage للصور موجودة بالفعل في `storage.rules`:

```javascript
// ==================== FEEDBACK SCREENSHOTS ====================
// Screenshots attached to user feedbacks
match /feedback_screenshots/{fileName} {
  // Read: Authenticated users only
  allow read: if isAuthenticated();
  
  // Write: Only authenticated users can upload
  // Max size: 5MB
  // Only image files allowed
  allow write: if isAuthenticated() &&
    request.resource.size < 5 * 1024 * 1024 &&
    request.resource.contentType.matches('image/.*');
}
```

---

## 🔒 شرح القواعد الأمنية

### القراءة (Read)

| المستخدم | الصلاحية |
|---------|---------|
| **المستخدم العادي** | يمكنه قراءة مقترحاته فقط (`resource.data.userId == request.auth.uid`) |
| **Super Admin** | يمكنه قراءة جميع المقترحات |
| **Org Admin** | يمكنه قراءة جميع المقترحات |

### الإنشاء (Create)

**الشروط:**
1. ✅ المستخدم يجب أن يكون مصادق عليه (`isAuthenticated()`)
2. ✅ `userId` يجب أن يطابق `request.auth.uid`
3. ✅ الحالة الأولية يجب أن تكون `pending`
4. ✅ `createdAt` يجب أن يكون وقت الخادم (`request.time`)

**الفائدة:**
- منع المستخدمين من إنشاء مقترحات باسم مستخدمين آخرين
- منع التلاعب بالتواريخ
- ضمان أن جميع المقترحات تبدأ بحالة `pending`

### التحديث (Update)

**من يمكنه التحديث:**
- ✅ Super Admin
- ✅ Org Admin

**ما يمكن تحديثه:**
- تغيير الحالة (`status`)
- إضافة رد الإدارة (`adminResponse`)
- تحديث `updatedAt`

**الفائدة:**
- المستخدمون العاديون لا يمكنهم تعديل مقترحاتهم بعد الإرسال
- فقط المسؤولون يمكنهم تغيير الحالة أو إضافة ردود

### الحذف (Delete)

**من يمكنه الحذف:**
- ✅ Super Admin فقط

**الفائدة:**
- حماية المقترحات من الحذف غير المصرح به
- الحفاظ على سجل كامل للمقترحات

---

## 📊 مقارنة: قبل وبعد

| الميزة | قبل التحديث | بعد التحديث |
|--------|-------------|-------------|
| **القراءة** | أي مستخدم مصادق يمكنه قراءة جميع المقترحات | المستخدم يقرأ مقترحاته فقط، المسؤولون يقرأون الكل |
| **الإنشاء** | ✅ جيد (مع validation) | ✅ نفس الشيء (محافظ على الأمان) |
| **التحديث** | أي مستخدم مصادق يمكنه التحديث | فقط Super Admin و Org Admin |
| **الحذف** | أي مستخدم مصادق يمكنه الحذف | فقط Super Admin |
| **الأمان** | ⚠️ متوسط | ✅ عالي |

---

## 🚀 خطوات النشر

### الطريقة 1: Firebase CLI (موصى بها)

```bash
# نشر Firestore Rules فقط
firebase deploy --only firestore:rules --project practice-firebase-72df1

# نشر Storage Rules فقط (إذا لزم الأمر)
firebase deploy --only storage --project practice-firebase-72df1

# نشر كل شيء
firebase deploy --project practice-firebase-72df1
```

### الطريقة 2: Firebase Console

1. افتح [Firebase Console](https://console.firebase.google.com/project/practice-firebase-72df1)
2. اذهب إلى **Firestore Database** → **Rules**
3. انسخ محتوى `firestore.rules` والصقه
4. اضغط **Publish**

---

## 🧪 الاختبار

### اختبار 1: المستخدم العادي يقرأ مقترحاته فقط

```dart
// ✅ يجب أن ينجح
final myFeedbacks = await firestore
  .collection('feedbacks')
  .where('userId', isEqualTo: currentUserId)
  .get();

// ❌ يجب أن يفشل (لا يمكن قراءة مقترحات الآخرين)
final allFeedbacks = await firestore
  .collection('feedbacks')
  .get();
```

### اختبار 2: المستخدم العادي لا يمكنه التحديث

```dart
// ❌ يجب أن يفشل
await firestore
  .collection('feedbacks')
  .doc(feedbackId)
  .update({'status': 'resolved'});
```

### اختبار 3: Super Admin يمكنه قراءة الكل

```dart
// ✅ يجب أن ينجح (إذا كان المستخدم super admin)
final allFeedbacks = await firestore
  .collection('feedbacks')
  .get();
```

### اختبار 4: Super Admin يمكنه التحديث

```dart
// ✅ يجب أن ينجح (إذا كان المستخدم super admin)
await firestore
  .collection('feedbacks')
  .doc(feedbackId)
  .update({
    'status': 'resolved',
    'adminResponse': 'تم حل المشكلة',
    'updatedAt': FieldValue.serverTimestamp(),
  });
```

---

## 📝 ملاحظات مهمة

### ⚠️ تحذيرات

1. **لا تنسَ نشر القواعد:**
   - القواعد المحلية في `firestore.rules` لا تُطبق تلقائياً
   - يجب نشرها عبر `firebase deploy`

2. **اختبر في بيئة التطوير أولاً:**
   - استخدم Firebase Emulator للاختبار المحلي
   - تأكد من عمل جميع الوظائف قبل النشر للإنتاج

3. **راقب السجلات:**
   - بعد النشر، راقب Firebase Console للتأكد من عدم وجود أخطاء
   - تحقق من أن المستخدمين يمكنهم الوصول لمقترحاتهم

### ✅ أفضل الممارسات

1. **استخدم Server Timestamp دائماً:**
   ```dart
   'createdAt': FieldValue.serverTimestamp()
   ```

2. **تحقق من الصلاحيات في التطبيق أيضاً:**
   - القواعد في Firestore هي الخط الدفاعي الأخير
   - تحقق من الصلاحيات في التطبيق قبل إرسال الطلبات

3. **احتفظ بنسخة احتياطية:**
   - قبل نشر القواعد الجديدة، احتفظ بنسخة من القواعد القديمة
   - يمكنك الرجوع إليها في حالة حدوث مشاكل

---

## 🔍 التحقق من النشر

بعد نشر القواعد، تحقق من:

### 1. Firebase Console

```
https://console.firebase.google.com/project/practice-firebase-72df1/firestore/rules
```

- ✅ تأكد من أن القواعد الجديدة ظاهرة
- ✅ تأكد من عدم وجود أخطاء في الصياغة

### 2. اختبار في التطبيق

- ✅ سجل دخول كمندوب → أرسل مقترح → تحقق من أنه يظهر في "مقترحاتي"
- ✅ سجل دخول كـ Super Admin → تحقق من أنك ترى جميع المقترحات
- ✅ حاول تحديث مقترح كمندوب → يجب أن يفشل
- ✅ حاول تحديث مقترح كـ Super Admin → يجب أن ينجح

### 3. مراقبة الأخطاء

```
https://console.firebase.google.com/project/practice-firebase-72df1/firestore/usage
```

- ✅ تحقق من عدم وجود أخطاء في "Errors" tab
- ✅ تحقق من أن عدد القراءات/الكتابات طبيعي

---

## 📚 المراجع

### الملفات ذات الصلة

- `firestore.rules` - القواعد الرئيسية
- `storage.rules` - قواعد التخزين
- `lib/features/feedback/FIRESTORE_RULES.md` - التوثيق الأصلي
- `lib/features/feedback/README.md` - دليل نظام المقترحات

### روابط مفيدة

- [Firebase Security Rules](https://firebase.google.com/docs/firestore/security/get-started)
- [Firestore Rules Reference](https://firebase.google.com/docs/reference/security/firestore)
- [Storage Security Rules](https://firebase.google.com/docs/storage/security)

---

## 🎉 الخلاصة

تم تحديث Firestore Rules لنظام المقترحات بنجاح! القواعد الآن:

- ✅ أكثر أماناً
- ✅ تحمي خصوصية المستخدمين
- ✅ تمنع التعديلات غير المصرح بها
- ✅ تسمح للمسؤولين بإدارة المقترحات

**الخطوة التالية:**
```bash
firebase deploy --only firestore:rules --project practice-firebase-72df1
```

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026  
**الحالة:** ✅ جاهز للنشر
