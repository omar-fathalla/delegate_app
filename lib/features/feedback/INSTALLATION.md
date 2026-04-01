# 🔧 دليل التثبيت - نظام المقترحات

## ✅ ما تم إنجازه تلقائياً

تم إنشاء وتكامل النظام بالكامل:

- ✅ جميع ملفات الكود (Domain, Data, Presentation)
- ✅ التكامل مع صفحة الإعدادات
- ✅ إضافة Routes
- ✅ تسجيل Dependencies
- ✅ إضافة BlocProviders
- ✅ التوثيق الكامل

## 🚀 خطوات التفعيل (يدوية)

### الخطوة 1: تحديث Firestore Rules ⚠️ مهم جداً

1. افتح Firebase Console
2. اذهب إلى **Firestore Database** > **Rules**
3. أضف القواعد التالية:

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
  
  // السماح بالتحديث للمسؤولين فقط
  allow update: if isAuthenticated() && (isSuperAdmin() || isOrgAdmin());
  
  // السماح بالحذف للمسؤولين فقط
  allow delete: if isAuthenticated() && isSuperAdmin();
}
```

4. اضغط **Publish**

### الخطوة 2: تحديث Storage Rules ⚠️ مهم جداً

1. في Firebase Console
2. اذهب إلى **Storage** > **Rules**
3. أضف القواعد التالية:

```javascript
rules_version = '2';
service firebase.storage {
  match /b/{bucket}/o {
    // قواعد موجودة...
    
    // قواعد جديدة للمقترحات
    match /feedback_screenshots/{fileName} {
      // السماح بالقراءة للجميع
      allow read: if true;
      
      // السماح بالكتابة للمستخدمين المصادق عليهم فقط
      allow write: if request.auth != null &&
        request.resource.size < 5 * 1024 * 1024 && // حد أقصى 5MB
        request.resource.contentType.matches('image/.*'); // صور فقط
    }
  }
}
```

4. اضغط **Publish**

### الخطوة 3: إنشاء Firestore Indexes

Firebase سيطلب منك إنشاء الفهارس تلقائياً عند أول استخدام، أو يمكنك إنشاؤها يدوياً:

1. في Firebase Console
2. اذهب إلى **Firestore Database** > **Indexes**
3. اضغط **Create Index**

**Index 1: للحصول على مقترحات المستخدم**
- Collection ID: `feedbacks`
- Fields to index:
  - `userId` - Ascending
  - `createdAt` - Descending
- Query scope: Collection

**Index 2: للمسؤولين - عرض حسب الحالة**
- Collection ID: `feedbacks`
- Fields to index:
  - `status` - Ascending
  - `createdAt` - Descending
- Query scope: Collection

### الخطوة 4: تشغيل التطبيق

```bash
# تحديث التبعيات
flutter pub get

# تشغيل التطبيق
flutter run
```

## 🧪 اختبار النظام

### 1. اختبار إرسال مقترح

1. افتح التطبيق
2. اذهب إلى **الإعدادات** (Settings)
3. اضغط على **إرسال مقترح** (Submit Feedback)
4. اختر نوع المقترح
5. اكتب رسالتك (10 أحرف على الأقل)
6. (اختياري) أرفق صورة
7. اضغط **إرسال المقترح**
8. يجب أن تظهر رسالة نجاح ✓

### 2. اختبار عرض المقترحات

1. اذهب إلى **الإعدادات**
2. اضغط على **مقترحاتي** (My Feedbacks)
3. يجب أن تظهر قائمة بمقترحاتك
4. اسحب للأسفل للتحديث (Pull to Refresh)

### 3. التحقق من Firebase

1. افتح Firebase Console
2. اذهب إلى **Firestore Database**
3. يجب أن تجد Collection جديد: `feedbacks`
4. افتح أي مستند لرؤية البيانات

### 4. اختبار الصور

1. أرسل مقترح مع صورة
2. في Firebase Console
3. اذهب إلى **Storage**
4. يجب أن تجد مجلد: `feedback_screenshots`
5. يجب أن تجد الصورة بداخله

## 🔍 استكشاف الأخطاء

### خطأ: "Permission denied"

**السبب:** Firestore Rules غير محدثة

**الحل:**
1. تحقق من Firestore Rules
2. تأكد من إضافة قواعد `feedbacks`
3. تأكد من نشر التغييرات

### خطأ: "Index not found"

**السبب:** Firestore Indexes غير موجودة

**الحل:**
1. انقر على الرابط في رسالة الخطأ
2. سيفتح Firebase Console
3. اضغط **Create Index**
4. انتظر حتى يكتمل الإنشاء (قد يستغرق دقائق)

### خطأ: "Image upload failed"

**السبب:** Storage Rules غير محدثة أو حجم الصورة كبير

**الحل:**
1. تحقق من Storage Rules
2. تأكد من حجم الصورة < 5MB
3. تأكد من صيغة الصورة (jpg, png, etc.)

### المقترحات لا تظهر

**السبب:** userId غير صحيح أو Firestore Rules

**الحل:**
1. تحقق من تسجيل الدخول
2. تحقق من Firestore Rules
3. تحقق من Console للأخطاء

## 📧 إضافة إشعارات البريد الإلكتروني (اختياري)

### باستخدام Cloud Functions

1. أنشئ ملف `functions/src/feedback.ts`:

```typescript
import * as functions from 'firebase-functions';
import * as admin from 'firebase-admin';

export const onFeedbackCreated = functions.firestore
  .document('feedbacks/{feedbackId}')
  .onCreate(async (snap, context) => {
    const feedback = snap.data();
    
    // إرسال بريد إلكتروني
    await admin.firestore().collection('mail').add({
      to: 'support@sw-point.com',
      message: {
        subject: `مقترح جديد: ${feedback.type}`,
        html: `
          <h2>مقترح جديد من ${feedback.userName}</h2>
          <p><strong>النوع:</strong> ${feedback.type}</p>
          <p><strong>المحتوى:</strong> ${feedback.content}</p>
          <p><strong>البريد:</strong> ${feedback.userEmail}</p>
          ${feedback.screenshotUrl ? `<p><strong>الصورة:</strong> <a href="${feedback.screenshotUrl}">عرض</a></p>` : ''}
          <p><strong>التاريخ:</strong> ${feedback.createdAt.toDate()}</p>
        `,
      },
    });
  });
```

2. نشر Cloud Function:

```bash
cd functions
npm run deploy
```

### باستخدام Firebase Extension

1. في Firebase Console
2. اذهب إلى **Extensions**
3. ابحث عن **Trigger Email from Firestore**
4. اضغط **Install**
5. اتبع التعليمات

## 📱 الوصول من التطبيق

### من صفحة الإعدادات

```
الإعدادات (Settings)
  ├── إرسال مقترح (Submit Feedback)
  └── مقترحاتي (My Feedbacks)
```

### من الكود

```dart
// الانتقال لصفحة إرسال مقترح
context.push('/submit-feedback', extra: delegate);

// الانتقال لصفحة عرض المقترحات
context.push('/my-feedbacks', extra: delegate);
```

## 🎯 الخطوات التالية

بعد التفعيل، يمكنك:

1. ✅ اختبار النظام بالكامل
2. ✅ تخصيص الألوان والتصميم
3. ✅ إضافة إشعارات البريد الإلكتروني
4. ✅ إضافة لوحة تحكم للمسؤولين
5. ✅ إضافة إحصائيات

## 📚 ملفات التوثيق

- `README.md` - دليل شامل
- `FIRESTORE_RULES.md` - قواعد Firebase
- `QUICK_START.md` - دليل البدء السريع
- `SUMMARY.md` - ملخص النظام
- `INSTALLATION.md` - هذا الملف

## 📞 الدعم

للمساعدة أو الاستفسارات:
- البريد الإلكتروني: support@sw-point.com
- Firebase Console: للوصول للمقترحات

---

**تم إنشاء هذا الدليل بواسطة:** Kiro AI Assistant  
**التاريخ:** 1 أبريل 2026  
**الإصدار:** 1.0.0  
**الحالة:** ✅ جاهز للتطبيق
