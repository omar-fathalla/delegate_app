# 👀 كيف تراقب GitHub Actions

**دليل سريع للمبتدئين**

---

## 🎯 الخطوة 1: افتح GitHub Actions

### الطريقة الأولى (مباشرة):
```
https://github.com/omar-fathalla/delegate_app/actions
```

### الطريقة الثانية (من الموقع):
1. افتح https://github.com/omar-fathalla/delegate_app
2. اضغط على تبويب **"Actions"** في الأعلى

---

## 🎯 الخطوة 2: ابحث عن آخر Workflow

ستجد قائمة بجميع الـ Workflows. ابحث عن:

```
✅ Fix Dart SDK version requirement
   770297e
   main
   منذ X دقيقة
```

---

## 🎯 الخطوة 3: افتح الـ Workflow

اضغط على الـ Workflow لترى التفاصيل.

ستجد:
- **Deploy Android to Google Play** (Android)
- **Deploy iOS to App Store** (iOS)

---

## 🎯 الخطوة 4: راقب التقدم

### ✅ إذا كان يعمل (Running):
```
🔵 Deploy Android to Google Play
   Running...
   
🔵 Deploy iOS to App Store
   Running...
```

**انتظر 15-20 دقيقة**

### ✅ إذا نجح (Success):
```
✅ Deploy Android to Google Play
   Completed in 12m 34s
   
✅ Deploy iOS to App Store
   Completed in 18m 45s
```

**🎉 مبروك! التطبيق تم رفعه بنجاح!**

### ❌ إذا فشل (Failed):
```
❌ Deploy Android to Google Play
   Failed in 5m 12s
   
❌ Deploy iOS to App Store
   Failed in 8m 23s
```

**اضغط على الـ Workflow الفاشل لترى الخطأ**

---

## 🔍 كيف تقرأ الأخطاء

### 1. اضغط على الـ Workflow الفاشل
### 2. اضغط على الـ Job الفاشل (deploy-android أو deploy-ios)
### 3. ابحث عن الخطوة الحمراء ❌
### 4. اقرأ الخطأ

### مثال:
```
❌ Install dependencies
   
   Error: Because delegate_app requires SDK version ^3.10.7,
   version solving failed.
```

---

## 📸 خذ Screenshot

إذا لم تفهم الخطأ:

1. **خذ screenshot للخطأ**
2. **أرسله لي**
3. **سأساعدك فوراً**

---

## 🎉 بعد النجاح

### Android (Google Play)
1. افتح https://play.google.com/console
2. اذهب إلى **Internal Testing**
3. ستجد Build جديد (1.0.0+23)

### iOS (TestFlight)
1. افتح https://appstoreconnect.apple.com
2. اذهب إلى **TestFlight**
3. ستجد Build جديد (1.0.0+23)

---

## ⏰ الوقت المتوقع

| المرحلة | الوقت |
|---------|-------|
| Checkout code | 10 ثانية |
| Setup Flutter | 1-2 دقيقة |
| Install dependencies | 1-2 دقيقة |
| Run tests | 1-2 دقيقة |
| Build | 5-10 دقائق |
| Upload | 2-5 دقائق |
| **الإجمالي** | **15-20 دقيقة** |

---

## 🔔 الإشعارات

GitHub سيرسل لك إشعار عبر البريد الإلكتروني عند:
- ✅ نجاح الـ Workflow
- ❌ فشل الـ Workflow

---

## 🆘 مشاكل شائعة

### 1. "Workflow is waiting"
**السبب:** GitHub Actions مشغول  
**الحل:** انتظر قليلاً

### 2. "No workflows found"
**السبب:** لم يتم push الـ workflows  
**الحل:** تأكد من push الملفات

### 3. "Secrets not found"
**السبب:** الـ Secrets غير مضافة  
**الحل:** أضف الـ Secrets في Settings

---

## 📱 تطبيق GitHub Mobile

يمكنك متابعة الـ Workflows من الموبايل:

1. حمّل تطبيق **GitHub** من App Store أو Google Play
2. سجل دخول
3. افتح Repository
4. اذهب إلى **Actions**

---

## 🎯 الخلاصة

```
1. افتح: https://github.com/omar-fathalla/delegate_app/actions
2. ابحث عن: "Fix Dart SDK version requirement"
3. راقب: التقدم (15-20 دقيقة)
4. إذا نجح: 🎉 مبروك!
5. إذا فشل: خذ screenshot وأرسله لي
```

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026
