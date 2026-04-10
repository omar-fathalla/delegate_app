# 📱 دليل الرفع اليدوي لـ iOS

**التاريخ:** 2 أبريل 2026  
**الحالة:** ✅ تم إضافة الخيار

---

## 🎯 ما تم إضافته؟

الآن يمكنك اختيار **رفع التطبيق لـ App Store** أو **فقط بناء IPA** عند تشغيل الـ Workflow يدوياً.

**الافتراضي:** ❌ غير مفعّل (لا يرفع) - يجب تفعيله يدوياً

---

## 🚀 كيف تستخدم الخيار الجديد؟

### الطريقة 1: من GitHub Website

#### 1. افتح GitHub Actions
```
https://github.com/omar-fathalla/delegate_app/actions
```

#### 2. اختر "Deploy iOS to App Store"
من القائمة على اليسار

#### 3. اضغط "Run workflow"
ستجد زر أخضر في الأعلى

#### 4. اختر الخيارات:

```
┌─────────────────────────────────────────────────────────────┐
│  Use workflow from                                          │
│  Branch: main ▼                                             │
│                                                             │
│  ☐ Upload directly to App Store (TestFlight)?              │
│     ❌ غير مفعّل (الافتراضي) = فقط يبني IPA                │
│     ✅ مفعّل = يرفع للـ App Store                           │
│                                                             │
│  [Run workflow]                                             │
└─────────────────────────────────────────────────────────────┘
```

#### 5. اضغط "Run workflow" الأخضر

---

## 📊 الفرق بين الخيارين

### ✅ مع Upload (الافتراضي)
```
1. 📥 Checkout code
2. 🐦 Setup Flutter
3. 📦 Install dependencies
4. 🔍 Run tests
5. 🍎 Setup Xcode
6. 📦 Install CocoaPods
7. 🔐 Import certificates
8. 📱 Import provisioning profile
9. 🔨 Build iOS
10. 📦 Export IPA
11. 🚀 Upload to TestFlight  ← يرفع
12. 📤 Upload IPA artifact
```

**النتيجة:**
- ✅ IPA جاهز
- ✅ تم الرفع لـ TestFlight
- ✅ يمكنك الاختبار فوراً

### ❌ بدون Upload (الافتراضي)
```
1. 📥 Checkout code
2. 🐦 Setup Flutter
3. 📦 Install dependencies
4. 🔍 Run tests
5. 🍎 Setup Xcode
6. 📦 Install CocoaPods
7. 🔐 Import certificates
8. 📱 Import provisioning profile
9. 🔨 Build iOS
10. 📦 Export IPA
11. ⏭️ تخطي Upload  ← لا يرفع
12. 📤 Upload IPA artifact
```

**النتيجة:**
- ✅ IPA جاهز
- ❌ لم يتم الرفع
- 📥 يمكنك تحميل IPA من Artifacts

---

## 🎯 متى تستخدم كل خيار؟

### ✅ استخدم "Upload = Yes"

**متى:**
- تريد نشر التطبيق للمختبرين
- تريد اختبار التطبيق على TestFlight
- تريد إرسال التطبيق للمراجعة

**الفوائد:**
- سريع - يرفع تلقائياً
- سهل - لا تحتاج تحميل IPA
- مباشر - يظهر في TestFlight فوراً

### ❌ استخدم "Upload = No" (الافتراضي)

**متى:**
- تريد فقط بناء IPA للاختبار المحلي
- تريد التحقق من أن البناء ينجح
- تريد تحميل IPA يدوياً لاحقاً

**الفوائد:**
- أسرع - لا ينتظر الرفع
- مرن - يمكنك الرفع لاحقاً
- آمن - لا يرفع بدون تأكيد

---

## 📱 كيف تحمل IPA بعد البناء؟

### 1. افتح الـ Workflow Run
```
https://github.com/omar-fathalla/delegate_app/actions
```

### 2. اضغط على الـ Run الذي تريده

### 3. انزل للأسفل لـ "Artifacts"

### 4. اضغط على "ios-release"

### 5. سيتم تحميل IPA

---

## 🔄 السلوك التلقائي

### عند Push للـ main branch:
```
✅ يبني التطبيق
✅ يرفع لـ TestFlight تلقائياً
```

### عند Manual Run:
```
✅ يبني التطبيق
✅ أو ❌ يرفع لـ TestFlight (حسب اختيارك)
```

---

## 📊 مقارنة مع Android

| الميزة | Android | iOS |
|--------|---------|-----|
| **Manual Run** | ✅ نعم | ✅ نعم |
| **Upload Option** | ✅ نعم | ✅ نعم |
| **Default Upload** | ✅ نعم | ✅ نعم |
| **Artifact Download** | ✅ نعم | ✅ نعم |

---

## 🎨 مثال عملي

### السيناريو 1: نشر للمختبرين
```
1. افتح GitHub Actions
2. اختر "Deploy iOS to App Store"
3. اضغط "Run workflow"
4. ✅ Upload = Yes (الافتراضي)
5. اضغط "Run workflow"
6. انتظر 15-20 دقيقة
7. ✅ التطبيق في TestFlight
```

### السيناريو 2: اختبار البناء فقط
```
1. افتح GitHub Actions
2. اختر "Deploy iOS to App Store"
3. اضغط "Run workflow"
4. ❌ Upload = No
5. اضغط "Run workflow"
6. انتظر 15-20 دقيقة
7. 📥 حمّل IPA من Artifacts
```

---

## 🔍 كيف تتحقق من الخيار؟

### في الـ Workflow Run:

#### إذا كان Upload = Yes:
```
✅ 🚀 Upload to TestFlight
   Completed in 2m 34s
```

#### إذا كان Upload = No:
```
⏭️ 🚀 Upload to TestFlight
   Skipped
```

---

## 📝 ملاحظات مهمة

### 1. الافتراضي هو Upload = No
```
إذا لم تغير شيئاً، لن يرفع (فقط يبني IPA)
يجب تفعيل الخيار يدوياً للرفع
```

### 2. Push يرفع دائماً
```
عند push للـ main، يرفع تلقائياً
لا يمكن تعطيل الرفع عند push
```

### 3. Manual Run فقط
```
الخيار متاح فقط عند التشغيل اليدوي
ليس عند push
```

---

## 🎯 الخلاصة

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ✅ تم إضافة خيار "Upload to App Store"                    │
│  ✅ يمكنك اختيار رفع أو عدم رفع                            │
│  ❌ الافتراضي: لا يرفع (يجب تفعيله يدوياً)                │
│  ✅ مثل Android تماماً                                      │
│                                                             │
│  🎯 الآن يمكنك التحكم الكامل!                              │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

## 🔗 روابط مفيدة

- **GitHub Actions:** https://github.com/omar-fathalla/delegate_app/actions
- **App Store Connect:** https://appstoreconnect.apple.com
- **TestFlight:** https://appstoreconnect.apple.com/apps/testflight

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026  
**الحالة:** ✅ جاهز للاستخدام
