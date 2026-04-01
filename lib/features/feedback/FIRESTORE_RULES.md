# 🔐 Firestore Rules للمقترحات (Feedbacks)

## القواعد المطلوبة

أضف هذه القواعد إلى ملف `firestore.rules`:

```javascript
// ============================================
// Feedbacks Collection
// ============================================
match /feedbacks/{feedbackId} {
  // السماح بالقراءة فقط للمستخدم صاحب المقترح أو المسؤولين
  allow read: if isAuthenticated() && 
    (resource.data.userId == request.auth.uid || isSuperAdmin() || isOrgAdmin());
  
  // السماح بالإنشاء للمستخدمين المصادق عليهم فقط
  allow create: if isAuthenticated() && 
    request.resource.data.userId == request.auth.uid &&
    request.resource.data.status == 'pending' &&
    request.resource.data.createdAt == request.time;
  
  // السماح بالتحديث للمسؤولين فقط (لتغيير الحالة أو إضافة رد)
  allow update: if isAuthenticated() && (isSuperAdmin() || isOrgAdmin());
  
  // السماح بالحذف للمسؤولين فقط
  allow delete: if isAuthenticated() && isSuperAdmin();
}
```

## شرح القواعد

### القراءة (Read)
- المستخدم يمكنه قراءة مقترحاته فقط
- المسؤولون يمكنهم قراءة جميع المقترحات

### الإنشاء (Create)
- يجب أن يكون المستخدم مصادق عليه
- `userId` يجب أن يطابق `request.auth.uid`
- الحالة الأولية يجب أن تكون `pending`
- `createdAt` يجب أن يكون وقت الخادم

### التحديث (Update)
- المسؤولون فقط يمكنهم تحديث المقترحات
- لتغيير الحالة أو إضافة رد الإدارة

### الحذف (Delete)
- Super Admin فقط يمكنه حذف المقترحات

## هيكل البيانات المتوقع

```json
{
  "userId": "string",
  "userName": "string",
  "userEmail": "string",
  "type": "feature_request | bug_report | general_question | improvement | other",
  "content": "string",
  "screenshotUrl": "string | null",
  "status": "pending | reviewed | in_progress | resolved | rejected",
  "createdAt": "timestamp",
  "updatedAt": "timestamp | null",
  "adminResponse": "string | null"
}
```

## Storage Rules للصور

أضف هذه القواعد إلى `storage.rules`:

```javascript
match /feedback_screenshots/{fileName} {
  // السماح بالقراءة للجميع (الصور عامة)
  allow read: if true;
  
  // السماح بالكتابة للمستخدمين المصادق عليهم فقط
  allow write: if request.auth != null &&
    request.resource.size < 5 * 1024 * 1024 && // حد أقصى 5MB
    request.resource.contentType.matches('image/.*'); // صور فقط
}
```

## الفهارس المطلوبة (Indexes)

قد تحتاج إلى إنشاء هذه الفهارس في Firebase Console:

### Index 1: للحصول على مقترحات المستخدم
- Collection: `feedbacks`
- Fields:
  - `userId` (Ascending)
  - `createdAt` (Descending)

### Index 2: للمسؤولين - عرض حسب الحالة
- Collection: `feedbacks`
- Fields:
  - `status` (Ascending)
  - `createdAt` (Descending)

### Index 3: للمسؤولين - عرض حسب النوع
- Collection: `feedbacks`
- Fields:
  - `type` (Ascending)
  - `createdAt` (Descending)

## ملاحظات أمنية

1. ✅ المستخدمون يمكنهم فقط إنشاء مقترحات باسمهم
2. ✅ المستخدمون لا يمكنهم تعديل أو حذف مقترحاتهم بعد الإرسال
3. ✅ المسؤولون فقط يمكنهم تغيير الحالة أو إضافة ردود
4. ✅ الصور محدودة بـ 5MB وصيغ الصور فقط
5. ✅ استخدام Server Timestamp لمنع التلاعب بالتواريخ

## كيفية التطبيق

1. افتح Firebase Console
2. اذهب إلى Firestore Database > Rules
3. أضف القواعد أعلاه
4. اذهب إلى Storage > Rules
5. أضف قواعد Storage
6. انشر التغييرات

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 1 أبريل 2026
