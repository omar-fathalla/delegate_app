# 📝 نظام المقترحات والملاحظات (Feedback System)

## 🎯 نظرة عامة

نظام متكامل لاستقبال مقترحات وملاحظات المستخدمين مع إمكانية إرفاق صور وتتبع الحالة.

## ✨ الميزات

### للمستخدمين
- ✅ إرسال مقترحات بأنواع مختلفة (فكرة، مشكلة، استفسار، تحسين، أخرى)
- ✅ إرفاق لقطة شاشة (اختياري)
- ✅ عرض جميع المقترحات السابقة
- ✅ تتبع حالة كل مقترح
- ✅ قراءة ردود الإدارة
- ✅ واجهة مستخدم جميلة مع Material Design 3
- ✅ دعم اللغتين العربية والإنجليزية

### للمسؤولين (عبر Firebase Console)
- ✅ عرض جميع المقترحات
- ✅ تغيير حالة المقترح
- ✅ إضافة رد على المقترح
- ✅ حذف المقترحات غير المناسبة

## 📁 هيكل المشروع

```
lib/features/feedback/
├── domain/
│   ├── entities/
│   │   └── feedback_entity.dart          # كيان المقترح
│   ├── repositories/
│   │   └── feedback_repository.dart      # واجهة Repository
│   └── usecases/
│       ├── submit_feedback_usecase.dart  # إرسال مقترح
│       └── get_user_feedbacks_usecase.dart # جلب المقترحات
├── data/
│   ├── models/
│   │   └── feedback_model.dart           # نموذج البيانات
│   ├── datasources/
│   │   └── feedback_remote_datasource.dart # مصدر البيانات
│   └── repositories/
│       └── feedback_repository_impl.dart # تطبيق Repository
├── presentation/
│   ├── bloc/
│   │   ├── feedback_bloc.dart            # BLoC
│   │   ├── feedback_event.dart           # الأحداث
│   │   └── feedback_state.dart           # الحالات
│   └── pages/
│       ├── submit_feedback_screen.dart   # صفحة إرسال مقترح
│       └── my_feedbacks_screen.dart      # صفحة عرض المقترحات
├── feedback_injection.dart               # Dependency Injection
├── FIRESTORE_RULES.md                    # قواعد Firestore
└── README.md                             # هذا الملف
```

## 🚀 كيفية الاستخدام

### 1. إعداد Firebase

#### Firestore Rules
أضف القواعد من ملف `FIRESTORE_RULES.md` إلى `firestore.rules`

#### Storage Rules
أضف قواعد Storage للصور (موجودة في `FIRESTORE_RULES.md`)

#### Indexes
أنشئ الفهارس المطلوبة في Firebase Console

### 2. تسجيل Dependencies

في ملف `injection_container.dart`، أضف:

```dart
import 'package:delegate_app/features/feedback/feedback_injection.dart';

Future<void> init() async {
  // ... dependencies الأخرى
  
  // Feedback
  initFeedbackDependencies();
}
```

### 3. إضافة BlocProvider

في ملف `main.dart` أو حيث تستخدم MultiBlocProvider:

```dart
BlocProvider(
  create: (_) => sl<FeedbackBloc>(),
),
```

### 4. الوصول من الإعدادات

تم إضافة رابطين في صفحة الإعدادات:
- **إرسال مقترح**: للانتقال لصفحة إرسال مقترح جديد
- **مقترحاتي**: لعرض جميع المقترحات السابقة

## 📊 أنواع المقترحات

| النوع | الأيقونة | الوصف |
|------|---------|-------|
| **فكرة تطويرية** | 💡 | اقتراح ميزة جديدة |
| **الإبلاغ عن مشكلة** | 🐛 | الإبلاغ عن خطأ أو مشكلة |
| **استفسار عام** | ❓ | سؤال أو استفسار |
| **تحسين** | ⭐ | اقتراح تحسين لميزة موجودة |
| **أخرى** | 📝 | أي نوع آخر |

## 🎨 حالات المقترح

| الحالة | اللون | الوصف |
|-------|------|-------|
| **قيد المراجعة** | 🟠 برتقالي | تم استلام المقترح |
| **تمت المراجعة** | 🔵 أزرق | تمت مراجعة المقترح |
| **قيد التنفيذ** | 🟣 بنفسجي | جاري العمل على المقترح |
| **تم الحل** | 🟢 أخضر | تم تنفيذ المقترح |
| **مرفوض** | 🔴 أحمر | تم رفض المقترح |

## 🔒 الأمان

### للمستخدمين
- ✅ يمكن إنشاء مقترحات فقط
- ✅ يمكن قراءة مقترحاتهم فقط
- ❌ لا يمكن تعديل أو حذف المقترحات

### للمسؤولين
- ✅ قراءة جميع المقترحات
- ✅ تحديث الحالة وإضافة ردود
- ✅ حذف المقترحات (Super Admin فقط)

### للصور
- ✅ حد أقصى 5MB
- ✅ صيغ الصور فقط
- ✅ رفع آمن عبر Firebase Storage

## 📱 لقطات الشاشة

### صفحة إرسال مقترح
- رسالة ترحيبية
- اختيار نوع المقترح (Choice Chips)
- حقل نص كبير للمحتوى
- زر إرفاق صورة
- زر إرسال
- Dialog نجاح مع أنيميشن

### صفحة مقترحاتي
- قائمة بجميع المقترحات
- عرض النوع والحالة
- عرض المحتوى والصورة
- عرض رد الإدارة (إن وجد)
- عرض التاريخ
- Pull to Refresh

## 🎯 تحسينات مستقبلية

- [ ] إضافة إشعارات عند تغيير حالة المقترح
- [ ] إضافة تقييم للمقترحات (Upvote/Downvote)
- [ ] إضافة تعليقات على المقترحات
- [ ] إضافة بحث وتصفية
- [ ] إضافة لوحة تحكم للمسؤولين في التطبيق
- [ ] إضافة إحصائيات للمقترحات
- [ ] إرسال بريد إلكتروني تلقائي عند استلام مقترح جديد

## 📧 استقبال الإشعارات

حالياً، يتم حفظ المقترحات في Firestore. لاستقبال إشعارات على البريد الإلكتروني:

### الطريقة 1: Cloud Function (موصى بها)

```typescript
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
        `,
      },
    });
  });
```

### الطريقة 2: Firebase Extensions

استخدم Extension: **Trigger Email from Firestore**

## 🐛 استكشاف الأخطاء

### المقترح لا يُرسل
- تحقق من Firestore Rules
- تحقق من اتصال الإنترنت
- تحقق من Console للأخطاء

### الصورة لا تُرفع
- تحقق من Storage Rules
- تحقق من حجم الصورة (< 5MB)
- تحقق من صيغة الصورة

### لا تظهر المقترحات
- تحقق من Firestore Indexes
- تحقق من userId
- تحقق من Firestore Rules

## 📞 الدعم

للمساعدة أو الاستفسارات:
- البريد الإلكتروني: support@sw-point.com
- Firebase Console: للوصول للمقترحات

---

**تم إنشاء هذا النظام بواسطة:** Kiro AI Assistant  
**التاريخ:** 1 أبريل 2026  
**الإصدار:** 1.0.0
