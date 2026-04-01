# 🚀 دليل البدء السريع - نظام المقترحات

## ✅ ما تم إنجازه

تم إنشاء نظام متكامل للمقترحات والملاحظات يتضمن:

### 1. البنية الكاملة (Clean Architecture)
- ✅ Domain Layer (Entities, Repositories, UseCases)
- ✅ Data Layer (Models, DataSources, Repository Implementation)
- ✅ Presentation Layer (BLoC, Pages, Widgets)

### 2. الميزات
- ✅ إرسال مقترحات بـ 5 أنواع مختلفة
- ✅ إرفاق صور (اختياري)
- ✅ عرض المقترحات السابقة
- ✅ تتبع حالة المقترح
- ✅ عرض ردود الإدارة
- ✅ دعم اللغتين العربية والإنجليزية
- ✅ Material Design 3

### 3. التكامل
- ✅ إضافة روابط في صفحة الإعدادات
- ✅ تسجيل Dependencies
- ✅ إضافة Routes
- ✅ إضافة BlocProviders

## 📋 خطوات التفعيل

### الخطوة 1: تحديث Firestore Rules

افتح `firestore.rules` وأضف القواعد من ملف `FIRESTORE_RULES.md`

```bash
# في Firebase Console
Firestore Database > Rules > تحرير القواعد
```

### الخطوة 2: تحديث Storage Rules

افتح `storage.rules` وأضف:

```javascript
match /feedback_screenshots/{fileName} {
  allow read: if true;
  allow write: if request.auth != null &&
    request.resource.size < 5 * 1024 * 1024 &&
    request.resource.contentType.matches('image/.*');
}
```

### الخطوة 3: إنشاء Firestore Indexes

في Firebase Console:

```
Firestore Database > Indexes > إنشاء فهرس
```

**Index 1:**
- Collection: `feedbacks`
- Fields: `userId` (Ascending), `createdAt` (Descending)

**Index 2:**
- Collection: `feedbacks`
- Fields: `status` (Ascending), `createdAt` (Descending)

### الخطوة 4: تشغيل التطبيق

```bash
flutter pub get
flutter run
```

## 🎯 كيفية الاستخدام

### للمستخدمين

1. افتح التطبيق
2. اذهب إلى **الإعدادات**
3. اضغط على **إرسال مقترح**
4. اختر نوع المقترح
5. اكتب رسالتك
6. (اختياري) أرفق صورة
7. اضغط **إرسال**

### لعرض المقترحات السابقة

1. اذهب إلى **الإعدادات**
2. اضغط على **مقترحاتي**
3. شاهد جميع مقترحاتك مع حالاتها

### للمسؤولين (Firebase Console)

1. افتح Firebase Console
2. اذهب إلى Firestore Database
3. افتح Collection: `feedbacks`
4. لتحديث حالة مقترح:
   - افتح المستند
   - عدّل حقل `status`
   - أضف `adminResponse` إذا أردت

## 🎨 أنواع المقترحات

| الرمز | النوع | الاستخدام |
|------|------|----------|
| 💡 | فكرة تطويرية | اقتراح ميزة جديدة |
| 🐛 | الإبلاغ عن مشكلة | الإبلاغ عن خطأ |
| ❓ | استفسار عام | سؤال أو استفسار |
| ⭐ | تحسين | تحسين ميزة موجودة |
| 📝 | أخرى | أي نوع آخر |

## 🎨 حالات المقترح

| الحالة | اللون | الوصف |
|-------|------|-------|
| قيد المراجعة | 🟠 | تم استلام المقترح |
| تمت المراجعة | 🔵 | تمت مراجعة المقترح |
| قيد التنفيذ | 🟣 | جاري العمل عليه |
| تم الحل | 🟢 | تم تنفيذ المقترح |
| مرفوض | 🔴 | تم رفض المقترح |

## 📧 استقبال الإشعارات (اختياري)

### الطريقة 1: Cloud Function

أنشئ Cloud Function لإرسال بريد إلكتروني عند استلام مقترح جديد:

```typescript
// functions/src/index.ts
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
        `,
      },
    });
  });
```

### الطريقة 2: Firebase Extension

استخدم Extension: **Trigger Email from Firestore**

## 🐛 استكشاف الأخطاء

### المقترح لا يُرسل
```bash
# تحقق من:
1. Firestore Rules صحيحة
2. اتصال الإنترنت
3. Console للأخطاء
```

### الصورة لا تُرفع
```bash
# تحقق من:
1. Storage Rules صحيحة
2. حجم الصورة < 5MB
3. صيغة الصورة صحيحة
```

### لا تظهر المقترحات
```bash
# تحقق من:
1. Firestore Indexes تم إنشاؤها
2. userId صحيح
3. Firestore Rules تسمح بالقراءة
```

## 📱 لقطات الشاشة

### صفحة إرسال مقترح
- رسالة ترحيبية مع أيقونة
- Choice Chips لاختيار النوع
- حقل نص كبير (8 أسطر)
- زر إرفاق صورة
- معاينة الصورة مع زر حذف
- زر إرسال كبير
- Dialog نجاح

### صفحة مقترحاتي
- قائمة بجميع المقترحات
- كل مقترح في Card
- عرض النوع مع أيقونة
- عرض الحالة مع لون
- عرض المحتوى (3 أسطر)
- عرض الصورة إن وجدت
- عرض رد الإدارة إن وجد
- عرض التاريخ
- Pull to Refresh

## 🎯 التحسينات المستقبلية

- [ ] إشعارات عند تغيير الحالة
- [ ] تقييم المقترحات (Upvote/Downvote)
- [ ] تعليقات على المقترحات
- [ ] بحث وتصفية
- [ ] لوحة تحكم للمسؤولين
- [ ] إحصائيات

## 📞 الدعم

للمساعدة:
- البريد: support@sw-point.com
- Firebase Console

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 1 أبريل 2026  
**الإصدار:** 1.0.0
