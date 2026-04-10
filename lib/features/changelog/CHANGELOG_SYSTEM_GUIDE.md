# 📋 دليل نظام سجل التحديثات (Changelog System)

**الإصدار:** 2.0.0  
**تاريخ التحديث:** 1 أبريل 2026  
**الحالة:** ✅ نشط ومحدّث

---

## 🎯 نظرة عامة

نظام احترافي لعرض تحديثات التطبيق بطريقة منظمة وجذابة، مع إمكانية التوسيع/الطي للتحديثات.

---

## ✨ الميزات الرئيسية

### 1. ✅ عرض ذكي للتحديثات
- **آخر تحديث مفتوح افتراضياً** (index = 0)
- **باقي التحديثات مغلقة** بشكل افتراضي
- إمكانية فتح/إغلاق أي تحديث بالضغط عليه

### 2. ✅ عناوين ديناميكية
- **عند الفتح:** يظهر العنوان الأصلي للتحديث
- **عند الإغلاق:** يظهر "إصدارات التحديث - التاريخ"
- التاريخ بصيغة `dd MMM yyyy` (مثال: 01 Apr 2026)

### 3. ✅ أنواع التحديثات (Update Types)
- 🚀 **New Feature** (ميزة جديدة) - لون أزرق
- 🔧 **Bug Fix** (إصلاح) - لون بنفسجي
- 📈 **Improvement** (تحسين) - لون ثانوي

### 4. ✅ مستويات الأولوية (Priority Levels)
- ⚪ **Normal** (عادي) - بدون badge
- 🟠 **Important** (مهم) - badge برتقالي
- 🔴 **Critical** (حرج) - badge أحمر + border

### 5. ✅ رقم الإصدار (Version Number)
- يظهر في الزاوية العلوية اليمنى
- صيغة: `v1.0.0`, `v1.0.1`, إلخ
- يتم جلبه من Firestore

---

## 🏗️ البنية المعمارية

### Clean Architecture

```
lib/features/changelog/
├── domain/
│   ├── entities/
│   │   └── app_update.dart          # Entity الأساسي
│   ├── repositories/
│   │   └── changelog_repository.dart # Repository Interface
│   └── usecases/
│       ├── get_all_updates.dart      # جلب كل التحديثات
│       └── get_new_updates.dart      # جلب التحديثات الجديدة فقط
├── data/
│   ├── models/
│   │   └── app_update_model.dart     # Firestore Model
│   ├── datasources/
│   │   └── changelog_remote_datasource.dart
│   └── repositories/
│       └── changelog_repository_impl.dart
└── presentation/
    ├── bloc/
    │   ├── changelog_bloc.dart
    │   ├── changelog_event.dart
    │   └── changelog_state.dart
    ├── pages/
    │   └── changelog_screen.dart     # الصفحة الرئيسية
    └── widgets/
        └── whats_new_dialog.dart     # Dialog عند فتح التطبيق
```

---

## 📊 Firestore Schema

### Collection: `app_updates`

```json
{
  "id": "auto-generated",
  "title": "تحديث النظام",
  "titleEn": "System Update",
  "description": "وصف التحديث بالعربية",
  "descriptionEn": "Update description in English",
  "version": "1.0.0",
  "type": "feature | fix | improvement",
  "priority": "normal | important | critical",
  "createdAt": Timestamp,
  "isActive": true,
  "highlights": ["نقطة 1", "نقطة 2"],
  "highlightsEn": ["Point 1", "Point 2"]
}
```

### Firestore Index المطلوب

```
Collection: app_updates
Fields:
  - isActive (ASC)
  - createdAt (DESC)
```

---

## 🎨 التصميم (UI/UX)

### الألوان والثيمات

```dart
// Card Background
colorScheme.surfaceContainerHighest.withValues(alpha: 0.35)

// Border (عند الفتح)
colorScheme.primary.withValues(alpha: 0.2)

// Border (Critical Priority)
colorScheme.error.withValues(alpha: 0.3)

// Type Chips
- Feature: primaryContainer / onPrimaryContainer
- Fix: tertiaryContainer / onTertiaryContainer
- Improvement: secondaryContainer / onSecondaryContainer
```

### الأيقونات

```dart
// Update Types
- Feature: Icons.rocket_launch_rounded
- Fix: Icons.build_rounded
- Improvement: Icons.trending_up_rounded

// Expand/Collapse
- Expanded: Icons.keyboard_arrow_up_rounded
- Collapsed: Icons.keyboard_arrow_down_rounded

// Highlights
- Icons.check_circle_rounded
```

---

## 🔄 كيفية العمل

### 1. عند فتح الصفحة

```dart
// في ChangelogScreen
BlocProvider(
  create: (_) => di.sl<ChangelogBloc>()..add(LoadAllUpdates()),
  child: const _ChangelogView(),
)
```

### 2. جلب البيانات من Firestore

```dart
// في ChangelogRemoteDataSource
firestore
  .collection('app_updates')
  .where('isActive', isEqualTo: true)
  .orderBy('createdAt', descending: true)  // الأحدث أولاً
  .get()
```

### 3. عرض التحديثات

```dart
// في _ChangelogViewState
int? _expandedIndex = 0;  // آخر تحديث مفتوح افتراضياً

ListView.separated(
  itemCount: state.updates.length,
  itemBuilder: (context, index) =>
    _buildUpdateCard(context, state.updates[index], index),
)
```

### 4. التوسيع/الطي

```dart
InkWell(
  onTap: () {
    setState(() {
      _expandedIndex = isExpanded ? null : index;
    });
  },
  child: AnimatedContainer(
    duration: const Duration(milliseconds: 300),
    // ...
  ),
)
```

---

## 📱 الاستخدام

### إضافة تحديث جديد في Firestore

```javascript
// في Firebase Console أو Cloud Functions
db.collection('app_updates').add({
  title: 'تحسينات الأداء',
  titleEn: 'Performance Improvements',
  description: 'تم تحسين سرعة التطبيق بنسبة 50%',
  descriptionEn: 'App speed improved by 50%',
  version: '1.0.1',
  type: 'improvement',
  priority: 'normal',
  createdAt: admin.firestore.FieldValue.serverTimestamp(),
  isActive: true,
  highlights: [
    'تحسين سرعة التحميل',
    'تقليل استهلاك البطارية',
    'إصلاح مشاكل الذاكرة'
  ],
  highlightsEn: [
    'Faster loading times',
    'Reduced battery consumption',
    'Fixed memory issues'
  ]
});
```

### عرض Dialog عند فتح التطبيق

```dart
// في main.dart أو home_screen.dart
BlocListener<ChangelogBloc, ChangelogState>(
  listener: (context, state) {
    if (state is ChangelogHasNewUpdates) {
      WhatsNewDialog.show(
        context,
        updates: state.updates,
        onDismiss: () {
          context.read<ChangelogBloc>().add(DismissNewUpdates());
        },
      );
    }
  },
  child: // ...
)
```

---

## 🧪 الاختبار

### Unit Tests

```dart
// test/features/changelog/domain/usecases/get_all_updates_test.dart
test('should return list of updates from repository', () async {
  when(() => mockRepository.getAllUpdates())
      .thenAnswer((_) async => Right(tUpdates));

  final result = await useCase(NoParams());

  expect(result, Right(tUpdates));
  verify(() => mockRepository.getAllUpdates()).called(1);
});
```

### Widget Tests

```dart
// test/features/changelog/presentation/pages/changelog_screen_test.dart
testWidgets('should display first update as expanded', (tester) async {
  await tester.pumpWidget(makeTestableWidget(ChangelogScreen()));
  await tester.pumpAndSettle();

  expect(find.byType(AnimatedContainer), findsWidgets);
  // التحقق من أن أول تحديث مفتوح
});
```

---

## 🔧 التخصيص

### تغيير عدد التحديثات المفتوحة افتراضياً

```dart
// في _ChangelogViewState
int? _expandedIndex = 0;  // 0 = أول تحديث
// int? _expandedIndex = null;  // كل التحديثات مغلقة
// int? _expandedIndex = 1;  // ثاني تحديث مفتوح
```

### تغيير صيغة التاريخ

```dart
final formattedDate = DateFormat(
  'dd MMM yyyy',  // 01 Apr 2026
  // 'dd/MM/yyyy',  // 01/04/2026
  // 'MMMM dd, yyyy',  // April 01, 2026
  isArabic ? 'ar' : 'en',
).format(update.createdAt);
```

### تغيير نص العنوان المغلق

```dart
Text(
  isExpanded
      ? title
      : '${isArabic ? 'إصدارات التحديث' : 'Update Releases'} - $formattedDate',
  // يمكن تغيير "إصدارات التحديث" إلى أي نص آخر
)
```

---

## 🚀 التحسينات المستقبلية

### 1. إضافة Pagination
```dart
// جلب 10 تحديثات في كل مرة
.limit(10)
.startAfterDocument(lastDocument)
```

### 2. إضافة Search
```dart
// البحث في العناوين والأوصاف
.where('title', isGreaterThanOrEqualTo: searchQuery)
```

### 3. إضافة Filters
```dart
// تصفية حسب النوع
.where('type', isEqualTo: 'feature')

// تصفية حسب الأولوية
.where('priority', isEqualTo: 'critical')
```

### 4. إضافة Share
```dart
// مشاركة التحديث
Share.share('تحديث جديد: ${update.title}\n${update.description}');
```

---

## 📝 الملاحظات المهمة

### ⚠️ تحذيرات

1. **لا تحذف Firestore Index:**
   - Index على `isActive` و `createdAt` ضروري
   - بدونه، الاستعلامات ستفشل

2. **استخدم Server Timestamp:**
   ```dart
   // ✅ صحيح
   'createdAt': FieldValue.serverTimestamp()
   
   // ❌ خطأ
   'createdAt': DateTime.now()
   ```

3. **تفعيل isActive:**
   - فقط التحديثات مع `isActive: true` تظهر
   - لإخفاء تحديث، اجعل `isActive: false`

### ✅ أفضل الممارسات

1. **رقم الإصدار:**
   - استخدم Semantic Versioning: `MAJOR.MINOR.PATCH`
   - مثال: `1.0.0`, `1.0.1`, `1.1.0`, `2.0.0`

2. **الترجمة:**
   - دائماً أضف `title` و `titleEn`
   - دائماً أضف `description` و `descriptionEn`
   - دائماً أضف `highlights` و `highlightsEn`

3. **الأولوية:**
   - استخدم `critical` فقط للتحديثات الهامة جداً
   - استخدم `important` للتحديثات المهمة
   - استخدم `normal` للتحديثات العادية

---

## 🎓 أمثلة عملية

### مثال 1: تحديث ميزة جديدة

```json
{
  "title": "نظام الإشعارات الجديد",
  "titleEn": "New Notification System",
  "description": "تم إضافة نظام إشعارات متقدم مع دعم الإشعارات الفورية",
  "descriptionEn": "Added advanced notification system with real-time push notifications",
  "version": "1.1.0",
  "type": "feature",
  "priority": "important",
  "createdAt": "2026-04-01T10:00:00Z",
  "isActive": true,
  "highlights": [
    "إشعارات فورية عند إنشاء مهمة جديدة",
    "إشعارات عند تعيين مندوبين جدد",
    "إمكانية تخصيص الإشعارات"
  ],
  "highlightsEn": [
    "Real-time notifications for new tasks",
    "Notifications when new delegates are assigned",
    "Customizable notification settings"
  ]
}
```

### مثال 2: إصلاح خطأ حرج

```json
{
  "title": "إصلاح مشكلة تسجيل الدخول",
  "titleEn": "Login Issue Fixed",
  "description": "تم إصلاح مشكلة منعت بعض المستخدمين من تسجيل الدخول",
  "descriptionEn": "Fixed an issue that prevented some users from logging in",
  "version": "1.0.2",
  "type": "fix",
  "priority": "critical",
  "createdAt": "2026-04-01T12:00:00Z",
  "isActive": true,
  "highlights": [
    "إصلاح مشكلة المصادقة",
    "تحسين استقرار التطبيق",
    "إضافة معالجة أخطاء أفضل"
  ],
  "highlightsEn": [
    "Fixed authentication issue",
    "Improved app stability",
    "Added better error handling"
  ]
}
```

---

## 📞 الدعم والمساعدة

إذا كان لديك أسئلة أو مشاكل:

1. راجع هذا الدليل
2. تحقق من Firebase Console
3. راجع ملف `all-project-documentation.md`
4. اطلب من Kiro AI Assistant

---

**تم إنشاء هذا الدليل بواسطة:** Kiro AI Assistant  
**آخر تحديث:** 1 أبريل 2026  
**الحالة:** ✅ نشط وجاهز للاستخدام  
**الإصدار:** 2.0.0
