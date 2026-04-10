# ⚡ البدء السريع - نظام سجل التحديثات

**الوقت المتوقع:** 5 دقائق

---

## 🎯 الهدف

إضافة تحديث جديد وعرضه في التطبيق.

---

## 📋 الخطوات

### 1️⃣ إضافة تحديث في Firebase Console

1. افتح [Firebase Console](https://console.firebase.google.com/)
2. اختر مشروع `practice-firebase-72df1`
3. اذهب إلى **Firestore Database**
4. افتح Collection `app_updates`
5. اضغط على **"Add document"**
6. اترك **Document ID** فارغاً
7. أضف الحقول التالية:

```
┌─────────────────┬──────────┬────────────────────────────────────┐
│ Field           │ Type     │ Value                              │
├─────────────────┼──────────┼────────────────────────────────────┤
│ title           │ string   │ تحديث تجريبي                      │
│ titleEn         │ string   │ Test Update                        │
│ description     │ string   │ هذا تحديث تجريبي للاختبار         │
│ descriptionEn   │ string   │ This is a test update              │
│ version         │ string   │ 1.0.0                              │
│ type            │ string   │ feature                            │
│ priority        │ string   │ normal                             │
│ createdAt       │ timestamp│ [اضغط "Set to current time"]      │
│ isActive        │ boolean  │ true                               │
│ highlights      │ array    │ ["نقطة 1", "نقطة 2"]              │
│ highlightsEn    │ array    │ ["Point 1", "Point 2"]             │
└─────────────────┴──────────┴────────────────────────────────────┘
```

8. اضغط **"Save"**

---

### 2️⃣ عرض الصفحة في التطبيق

#### الطريقة 1: من الإعدادات

```dart
// في settings_screen.dart أو أي صفحة أخرى

ListTile(
  leading: const Icon(Icons.history_rounded),
  title: const Text('سجل التحديثات'),
  subtitle: const Text('عرض آخر التحديثات'),
  onTap: () {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => const ChangelogScreen(),
      ),
    );
  },
)
```

#### الطريقة 2: من AppBar

```dart
AppBar(
  title: const Text('الرئيسية'),
  actions: [
    IconButton(
      icon: const Icon(Icons.info_outline_rounded),
      onPressed: () {
        Navigator.push(
          context,
          MaterialPageRoute(
            builder: (_) => const ChangelogScreen(),
          ),
        );
      },
    ),
  ],
)
```

#### الطريقة 3: باستخدام go_router

```dart
// في app_router.dart
GoRoute(
  path: '/changelog',
  name: 'changelog',
  builder: (context, state) => const ChangelogScreen(),
),

// الاستخدام
context.goNamed('changelog');
```

---

### 3️⃣ عرض Dialog عند فتح التطبيق

```dart
// في home_screen.dart أو main.dart

class HomeScreen extends StatefulWidget {
  const HomeScreen({super.key});

  @override
  State<HomeScreen> createState() => _HomeScreenState();
}

class _HomeScreenState extends State<HomeScreen> {
  @override
  void initState() {
    super.initState();
    // فحص التحديثات الجديدة عند فتح التطبيق
    WidgetsBinding.instance.addPostFrameCallback((_) {
      context.read<ChangelogBloc>().add(CheckForNewUpdates());
    });
  }

  @override
  Widget build(BuildContext context) {
    return BlocListener<ChangelogBloc, ChangelogState>(
      listener: (context, state) {
        if (state is ChangelogHasNewUpdates) {
          // عرض Dialog
          WhatsNewDialog.show(
            context,
            updates: state.updates,
            onDismiss: () {
              context.read<ChangelogBloc>().add(DismissNewUpdates());
            },
          );
        }
      },
      child: Scaffold(
        appBar: AppBar(title: const Text('الرئيسية')),
        body: // ...
      ),
    );
  }
}
```

---

### 4️⃣ التحقق من النتيجة

1. أعد تشغيل التطبيق
2. اذهب إلى صفحة Changelog
3. يجب أن ترى:
   - ✅ آخر تحديث مفتوح
   - ✅ العنوان: "تحديث تجريبي"
   - ✅ الوصف: "هذا تحديث تجريبي للاختبار"
   - ✅ النقاط: "نقطة 1", "نقطة 2"
   - ✅ رقم الإصدار: "v1.0.0"
   - ✅ Badge: "ميزة جديدة"

---

## 🎨 تخصيص التحديث

### إضافة تحديث "إصلاح" (Fix)

```
type: fix
priority: critical
```

النتيجة:
- 🔧 Badge: "إصلاح"
- 🔴 Border أحمر (لأن الأولوية critical)

### إضافة تحديث "تحسين" (Improvement)

```
type: improvement
priority: important
```

النتيجة:
- 📈 Badge: "تحسين"
- 🟠 Badge: "مهم"

---

## 🧪 اختبار سريع

### اختبار 1: إضافة 3 تحديثات

```bash
# في Firebase Console، أضف 3 تحديثات:

1. version: 1.0.0, type: feature, priority: normal
2. version: 1.0.1, type: fix, priority: critical
3. version: 1.1.0, type: improvement, priority: important
```

النتيجة المتوقعة:
- ✅ التحديث الأول (1.1.0) مفتوح
- ✅ التحديثان الآخران مغلقان
- ✅ العناوين المغلقة تعرض "إصدارات التحديث - التاريخ"

### اختبار 2: الضغط على تحديث مغلق

1. اضغط على تحديث مغلق
2. يجب أن يفتح ويظهر:
   - ✅ العنوان الأصلي
   - ✅ الوصف
   - ✅ النقاط المهمة
   - ✅ التاريخ

### اختبار 3: إغلاق تحديث مفتوح

1. اضغط على التحديث المفتوح
2. يجب أن يغلق ويظهر:
   - ✅ "إصدارات التحديث - التاريخ"

---

## 🔧 حل المشاكل

### المشكلة 1: لا تظهر التحديثات

**الحل:**
1. تحقق من أن `isActive: true`
2. تحقق من وجود Firestore Index
3. تحقق من الاتصال بالإنترنت

### المشكلة 2: خطأ في الاستعلام

**الحل:**
1. اذهب إلى Firebase Console
2. Firestore Database → Indexes
3. تأكد من وجود Index على:
   - `isActive` (ASC)
   - `createdAt` (DESC)

### المشكلة 3: التحديثات لا تظهر بالترتيب الصحيح

**الحل:**
- تأكد من استخدام `FieldValue.serverTimestamp()` في `createdAt`
- لا تستخدم `DateTime.now()`

---

## 📊 مثال كامل

### إضافة تحديث "نظام الإشعارات"

```json
{
  "title": "نظام الإشعارات الجديد",
  "titleEn": "New Notification System",
  "description": "تم إضافة نظام إشعارات متقدم مع دعم الإشعارات الفورية",
  "descriptionEn": "Added advanced notification system with real-time push notifications",
  "version": "1.2.0",
  "type": "feature",
  "priority": "important",
  "createdAt": [Server Timestamp],
  "isActive": true,
  "highlights": [
    "إشعارات فورية عند إنشاء مهمة جديدة",
    "إشعارات عند تعيين مندوبين جدد",
    "إمكانية تخصيص الإشعارات",
    "دعم الإشعارات الصوتية"
  ],
  "highlightsEn": [
    "Real-time notifications for new tasks",
    "Notifications when new delegates are assigned",
    "Customizable notification settings",
    "Sound notification support"
  ]
}
```

### النتيجة المتوقعة

```
┌─────────────────────────────────────────────────────────┐
│ 🚀 ميزة جديدة    🟠 مهم              v1.2.0    ▼     │
│                                                         │
│ نظام الإشعارات الجديد                                  │
│                                                         │
│ تم إضافة نظام إشعارات متقدم مع دعم الإشعارات الفورية  │
│                                                         │
│ ✓ إشعارات فورية عند إنشاء مهمة جديدة                  │
│ ✓ إشعارات عند تعيين مندوبين جدد                       │
│ ✓ إمكانية تخصيص الإشعارات                             │
│ ✓ دعم الإشعارات الصوتية                               │
│                                                         │
│ 01 Apr 2026                                             │
└─────────────────────────────────────────────────────────┘
```

---

## 🎯 الخطوات التالية

1. ✅ أضف تحديث تجريبي
2. ✅ تحقق من ظهوره في التطبيق
3. ✅ اختبر التوسيع/الطي
4. ✅ أضف تحديثات حقيقية
5. ✅ راجع [CHANGELOG_SYSTEM_GUIDE.md](./CHANGELOG_SYSTEM_GUIDE.md) للمزيد

---

## 📚 موارد إضافية

- [CHANGELOG_SYSTEM_GUIDE.md](./CHANGELOG_SYSTEM_GUIDE.md) - دليل شامل
- [FIRESTORE_EXAMPLES.md](./FIRESTORE_EXAMPLES.md) - أمثلة متقدمة
- [README.md](./README.md) - نظرة عامة

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**آخر تحديث:** 1 أبريل 2026  
**الحالة:** ✅ جاهز للاستخدام

---

## 💡 نصيحة أخيرة

ابدأ بتحديث تجريبي بسيط، ثم أضف تحديثات حقيقية تدريجياً. هذا سيساعدك على فهم النظام بشكل أفضل.

**حظاً موفقاً! 🚀**
