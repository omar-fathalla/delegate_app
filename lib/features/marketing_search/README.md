# 🔍 Marketing Search Feature

## نظرة عامة

صفحة بحث موحدة لموظفي التسويق تجمع البحث عن الشركات والمندوبين في مكان واحد.

---

## ✨ الميزات

### 1. البحث عن الشركات
- إدخال رقم الشركة فقط
- زر بحث مخصص
- البحث في كل قاعدة البيانات Firebase
- عرض النتائج في بطاقات Material Design 3

### 2. البحث عن المندوبين
- إدخال رقم الموبايل
- تطبيع تلقائي للأرقام المصرية
- زر بحث مخصص
- البحث في كل قاعدة البيانات Firebase
- عرض النتائج في بطاقات Material Design 3

### 3. عرض النتائج
- لا يتم عرض أي بيانات قبل البحث
- عرض النتائج فقط بعد الضغط على زر البحث
- بطاقات مفصلة لكل نتيجة
- تصميم Material Design 3 كامل

---

## 🏗️ البنية المعمارية

```
lib/features/marketing_search/
├── domain/
│   ├── repositories/
│   │   └── marketing_search_repository.dart
│   └── usecases/
│       ├── search_company_by_code.dart
│       └── search_delegate_by_phone.dart
├── data/
│   ├── datasources/
│   │   └── marketing_search_remote_datasource.dart
│   └── repositories/
│       └── marketing_search_repository_impl.dart
└── presentation/
    ├── bloc/
    │   ├── marketing_search_bloc.dart
    │   ├── marketing_search_event.dart
    │   └── marketing_search_state.dart
    ├── pages/
    │   └── marketing_search_screen.dart
    └── widgets/
        ├── company_search_section.dart
        ├── delegate_search_section.dart
        ├── search_results_section.dart
        ├── company_result_card.dart
        └── delegate_result_card.dart
```

---

## 🔄 كيفية العمل

### البحث عن شركة:
```
1. المستخدم يدخل رقم الشركة (مثال: 1048)
2. يضغط على زر "بحث عن الشركة"
3. البحث في Firebase:
   - محاولة 1: where('code', isEqualTo: 1048)
   - محاولة 2: where('companyCodeInOrg', isEqualTo: '1048')
4. عرض النتائج
```

### البحث عن مندوب:
```
1. المستخدم يدخل رقم الموبايل (مثال: 01012345678)
2. يضغط على زر "بحث عن المندوب"
3. تطبيع الرقم (إزالة +20، 0020، إلخ)
4. البحث في Firebase:
   - collectionGroup('delegates')
   - where('organizationUID', isEqualTo: orgId)
   - where('phoneNumber', isEqualTo: normalizedPhone)
5. عرض النتائج
```

---

## 📱 الاستخدام

### التنقل للصفحة:

```dart
context.go('/marketing/search', extra: organizationUID);
```

### من صفحة Marketing الرئيسية:
الصفحة متاحة في التبويب الثاني (Search) في NavigationBar.

---

## 🎨 التصميم

### Material Design 3
- ✅ FilledButton للأزرار الرئيسية
- ✅ OutlinedInputBorder للحقول
- ✅ Card مع elevation: 0
- ✅ ColorScheme كامل
- ✅ دعم الوضع الداكن

### الألوان:
- **Primary**: للشركات
- **Secondary**: للمندوبين
- **Surface**: الخلفية
- **SurfaceContainerHighest**: البطاقات

---

## 🔥 Firebase Queries

### بحث الشركات:
```dart
// المحاولة 1
firestore
  .collection('organizations')
  .doc(orgId)
  .collection('companies')
  .where('code', isEqualTo: int.parse(companyCode))
  .get()

// المحاولة 2
firestore
  .collection('organizations')
  .doc(orgId)
  .collection('companies')
  .where('companyCodeInOrg', isEqualTo: companyCode)
  .get()
```

### بحث المندوبين:
```dart
firestore
  .collectionGroup('delegates')
  .where('organizationUID', isEqualTo: orgId)
  .where('phoneNumber', isEqualTo: normalizedPhone)
  .get()
```

---

## 🧪 الاختبار

### اختبار البحث عن شركة:
1. افتح الصفحة
2. أدخل رقم شركة (مثال: 1048)
3. اضغط "بحث عن الشركة"
4. تحقق من ظهور النتائج

### اختبار البحث عن مندوب:
1. افتح الصفحة
2. أدخل رقم موبايل (مثال: 01012345678)
3. اضغط "بحث عن المندوب"
4. تحقق من ظهور النتائج

---

## 📝 ملاحظات

### تطبيع أرقام الهواتف:
يتم تطبيع الأرقام المصرية تلقائياً:
- `+201012345678` → `01012345678`
- `00201012345678` → `01012345678`
- `201012345678` → `01012345678`

### Firestore Indexes:
لا حاجة لـ indexes إضافية! الـ queries المستخدمة تعمل مع الـ indexes الموجودة.

---

## 🚀 التحسينات المستقبلية

- [ ] إضافة Infinite Scroll Pagination للنتائج
- [ ] إضافة فلاتر متقدمة
- [ ] إضافة تصدير النتائج
- [ ] إضافة حفظ البحث المفضل
- [ ] إضافة إحصائيات البحث

---

**تم إنشاء هذه الميزة بواسطة:** Kiro AI Assistant  
**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ جاهز للاستخدام
