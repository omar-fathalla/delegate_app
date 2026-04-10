# 🔍 التحقق من دور المستخدم في Firestore

**المستخدم:** 01508899965  
**المشكلة:** خطأ `permission-denied` عند فتح "Manage Feedbacks"

---

## 🎯 السبب

المستخدم **ليس Super Admin في Firestore**!

Firestore Rules تتحقق من حقل `role` في وثيقة المستخدم، ويجب أن يكون:
```json
{
  "role": "super-admin"
}
```

---

## 🔍 كيفية التحقق

### الخطوة 1: افتح Firebase Console
```
https://console.firebase.google.com/project/practice-firebase-72df1/firestore
```

### الخطوة 2: اذهب إلى Collection: `users`

### الخطوة 3: ابحث عن وثيقة المستخدم

ابحث عن الوثيقة التي تحتوي على:
- `phoneNumber`: `"01508899965"` أو `"+201508899965"`
- أو `uid` الخاص بالمستخدم

### الخطوة 4: تحقق من حقل `role`

يجب أن يكون:
```json
{
  "role": "super-admin"
}
```

**ملاحظة مهمة:** يجب أن يكون بالضبط `"super-admin"` (بحروف صغيرة وشرطة)

---

## ❌ القيم الخاطئة

هذه القيم **لن تعمل**:

```json
"role": "Super Admin"     // ❌ خطأ (حرف كبير)
"role": "superadmin"      // ❌ خطأ (بدون شرطة)
"role": "super_admin"     // ❌ خطأ (شرطة سفلية)
"role": "admin"           // ❌ خطأ (ليس super-admin)
"role": "SUPER-ADMIN"     // ❌ خطأ (حروف كبيرة)
```

---

## ✅ القيمة الصحيحة

```json
{
  "role": "super-admin"
}
```

**بالضبط هكذا!** (حروف صغيرة + شرطة)

---

## 🔧 كيفية التعديل

### إذا كان الدور خاطئاً:

1. **افتح Firebase Console**
2. **اذهب إلى Firestore**
3. **افتح Collection: `users`**
4. **ابحث عن وثيقة المستخدم** (01508899965)
5. **اضغط على الوثيقة**
6. **عدّل حقل `role`** إلى `"super-admin"`
7. **احفظ التغييرات**

---

## 📊 مثال على الوثيقة الصحيحة

```json
{
  "uid": "abc123...",
  "phoneNumber": "+201508899965",
  "firstName": "Admin",
  "lastName": "User",
  "role": "super-admin",           // ✅ هذا هو المهم!
  "organizationUID": "org123",
  "companyUID": "comp123",
  "createdAt": "2026-01-01T00:00:00Z"
}
```

---

## 🔐 Firestore Rules (للمرجع)

```javascript
function isSuperAdmin() {
  return isAuthenticated() &&
         getUserData().role == 'super-admin';  // يتحقق من هذا الحقل
}

match /feedbacks/{feedbackId} {
  allow read: if isAuthenticated() && (
    resource.data.userId == request.auth.uid ||
    isSuperAdmin() ||  // ← يستدعي الدالة أعلاه
    isOrgAdmin()
  );
}
```

---

## 🧪 الاختبار بعد التعديل

1. **عدّل حقل `role`** في Firestore إلى `"super-admin"`
2. **أغلق التطبيق تماماً**
3. **افتح التطبيق مرة أخرى**
4. **سجل دخول** برقم 01508899965
5. **اذهب إلى Settings → إدارة المقترحات**
6. **يجب أن تعمل الآن!** ✅

---

## 📝 ملاحظات مهمة

### 1. يجب إعادة تشغيل التطبيق
بعد تعديل الدور في Firestore، يجب:
- إغلاق التطبيق تماماً
- فتحه مرة أخرى
- تسجيل الدخول

### 2. التحقق من المصادقة
تأكد من أن المستخدم مسجل دخول:
- يجب أن يكون `request.auth.uid` موجود
- يجب أن يكون مطابق لـ `uid` في وثيقة المستخدم

### 3. التحقق من organizationUID
تأكد من أن المستخدم لديه:
- `organizationUID` صحيح
- `companyUID` صحيح (إذا لزم الأمر)

---

## 🔍 كيفية معرفة UID المستخدم

### الطريقة 1: من Firebase Console
1. افتح Firebase Console
2. اذهب إلى Authentication
3. ابحث عن المستخدم برقم الهاتف: 01508899965
4. انسخ UID

### الطريقة 2: من التطبيق
أضف هذا الكود في `settings_screen.dart` مؤقتاً:
```dart
print('User UID: ${delegate.uid}');
print('User Role: ${delegate.role}');
```

---

## 🎯 الخلاصة

**المشكلة:** المستخدم ليس Super Admin في Firestore

**الحل:**
1. افتح Firebase Console
2. اذهب إلى Firestore → users
3. ابحث عن وثيقة المستخدم (01508899965)
4. عدّل `role` إلى `"super-admin"`
5. احفظ
6. أعد تشغيل التطبيق

**النتيجة:** ستعمل صفحة "Manage Feedbacks" بنجاح! ✅

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 1 أبريل 2026  
**الحالة:** ✅ جاهز للاستخدام

