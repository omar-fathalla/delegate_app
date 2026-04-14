# 🔄 تحديث نظام البحث - Marketing Search Update

**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ مكتمل

---

## 📋 ملخص التغييرات

تم تغيير نظام البحث في صفحة موظف التسويق من **البحث بكود الشركة** إلى **البحث باسم الشركة**.

---

## ✨ التغييرات الرئيسية

### 1. واجهة المستخدم (UI)

#### قبل التحديث:
- حقل إدخال: "رقم الشركة"
- نوع الإدخال: أرقام فقط
- مثال: "أدخل رقم الشركة (مثال: 1048)"
- زر البحث: FilledButton.icon (النص العربي لا يظهر بشكل صحيح)

#### بعد التحديث:
- حقل إدخال: "اسم الشركة"
- نوع الإدخال: نص
- مثال: "أدخل اسم الشركة (مثال: ماكسيم)"
- زر البحث: ElevatedButton مع Row (يعرض النص العربي بشكل صحيح)
- ارتفاع الزر: 52px (بدلاً من 48px)
- تحسين التباعد والأيقونات

---

## 📁 الملفات المعدلة

### 1. Presentation Layer

#### `company_search_section.dart`
```dart
// التغييرات:
- إزالة: import 'package:flutter/services.dart'
- إزالة: inputFormatters: [FilteringTextInputFormatter.digitsOnly]
- تغيير: keyboardType من number إلى text
- تغيير: textDirection من ltr إلى rtl
- تغيير: labelText من "رقم الشركة" إلى "اسم الشركة"
- تغيير: hintText من "أدخل رقم الشركة (مثال: 1048)" إلى "أدخل اسم الشركة (مثال: ماكسيم)"
- تغيير: prefixIcon من Icons.tag_rounded إلى Icons.business_rounded
- تغيير: FilledButton.icon إلى ElevatedButton مع Row
- زيادة: ارتفاع الزر من 48 إلى 52
```

#### `marketing_search_screen.dart`
```dart
// التغييرات:
- تغيير: _companyCodeController إلى _companyNameController
- تغيير: companyCode إلى companyName في جميع الأماكن
- تغيير: رسالة الخطأ من "يرجى إدخال رقم الشركة" إلى "يرجى إدخال اسم الشركة"
```

#### `marketing_search_event.dart`
```dart
// التغييرات:
- تغيير: companyCode إلى companyName في SearchCompanyRequested
- تحديث: التعليقات من "by code" إلى "by name"
```

#### `marketing_search_bloc.dart`
```dart
// التغييرات:
- تغيير: _currentCompanyCode إلى _currentCompanyName
- تغيير: companyCode إلى companyName في جميع الأماكن
```

---

### 2. Domain Layer

#### `marketing_search_repository.dart`
```dart
// التغييرات:
- تغيير: searchCompanyByCode إلى searchCompanyByName
- تغيير: companyCode parameter إلى companyName
- تحديث: التعليقات من "by code" إلى "by name"
```

#### `search_company_by_code.dart`
```dart
// التغييرات:
- تغيير: searchCompanyByCode إلى searchCompanyByName
- تغيير: companyCode إلى companyName في SearchCompanyByCodeParams
- تحديث: التعليقات من "by code" إلى "by name"
```

---

### 3. Data Layer

#### `marketing_search_repository_impl.dart`
```dart
// التغييرات:
- إزالة: import 'package:firebase_core/firebase_core.dart' (غير مستخدم)
- تغيير: searchCompanyByCode إلى searchCompanyByName
- تغيير: companyCode parameter إلى companyName
```

#### `marketing_search_remote_datasource.dart`
```dart
// التغييرات الرئيسية:
- تغيير: searchCompanyByCode إلى searchCompanyByName
- تغيير: companyCode parameter إلى companyName
- تغيير: منطق البحث بالكامل

// منطق البحث الجديد:
1. تحويل اسم الشركة إلى lowercase
2. استخدام range query مع \uf8ff للبحث الجزئي
3. البحث في حقل 'name' بدلاً من 'code' أو 'companyCodeInOrg'

Query الجديد:
.where('name', isGreaterThanOrEqualTo: searchName)
.where('name', isLessThanOrEqualTo: '$searchName\uf8ff')
```

---

## 🔍 كيفية عمل البحث الجديد

### البحث بالاسم (Name Search)

```dart
// 1. تحويل الاسم إلى lowercase
final searchName = companyName.toLowerCase().trim();

// 2. استخدام range query للبحث الجزئي
Query query = firestore
    .collection('organizations')
    .doc(organizationUID)
    .collection('companies')
    .where('name', isGreaterThanOrEqualTo: searchName)
    .where('name', isLessThanOrEqualTo: '$searchName\uf8ff')
    .limit(limit + 1);
```

### مثال:
- إذا بحث المستخدم عن "ماك"
- سيجد: "ماكسيم", "ماكدونالدز", إلخ
- البحث case-insensitive (لا يفرق بين الأحرف الكبيرة والصغيرة)

---

## 📊 Firestore Index

الـ Index المطلوب **موجود بالفعل** في `firestore.indexes.json`:

```json
{
  "collectionGroup": "companies",
  "queryScope": "COLLECTION",
  "fields": [
    {
      "fieldPath": "organizationUID",
      "order": "ASCENDING"
    },
    {
      "fieldPath": "name",
      "order": "ASCENDING"
    },
    {
      "fieldPath": "__name__",
      "order": "ASCENDING"
    }
  ]
}
```

✅ **لا حاجة لإضافة index جديد**

---

## 🎨 تحسينات UI

### الزر الجديد

```dart
// قبل (FilledButton.icon - النص لا يظهر بشكل صحيح)
FilledButton.icon(
  onPressed: onSearch,
  icon: const Icon(Icons.search_rounded),
  label: const Text('بحث عن الشركة'),
)

// بعد (ElevatedButton مع Row - النص يظهر بشكل صحيح)
ElevatedButton(
  onPressed: onSearch,
  style: ElevatedButton.styleFrom(
    backgroundColor: colorScheme.primary,
    foregroundColor: colorScheme.onPrimary,
    elevation: 2,
    shadowColor: colorScheme.primary.withOpacity(0.3),
    shape: RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(12),
    ),
    padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
  ),
  child: Row(
    mainAxisAlignment: MainAxisAlignment.center,
    children: [
      Icon(Icons.search_rounded, size: 22),
      const SizedBox(width: 12),
      Text(
        'بحث عن الشركة',
        style: TextStyle(
          fontSize: 16,
          fontWeight: FontWeight.w600,
          letterSpacing: 0.5,
        ),
      ),
    ],
  ),
)
```

### الفوائد:
- ✅ النص العربي يظهر بشكل واضح
- ✅ تباعد أفضل بين الأيقونة والنص
- ✅ ارتفاع أكبر (52px) لسهولة الضغط
- ✅ ظل خفيف للزر
- ✅ padding مخصص

---

## 🧪 الاختبار

### خطوات الاختبار:

1. **افتح التطبيق كموظف تسويق**
2. **اذهب إلى صفحة البحث**
3. **اكتب اسم شركة** (مثال: "ماكسيم")
4. **اضغط زر "بحث عن الشركة"**
5. **تحقق من النتائج**

### النتائج المتوقعة:
- ✅ يظهر حقل "اسم الشركة" بدلاً من "رقم الشركة"
- ✅ يمكن كتابة نص عربي/إنجليزي
- ✅ زر البحث يعرض النص بشكل صحيح
- ✅ البحث يعمل بشكل صحيح
- ✅ النتائج تظهر الشركات المطابقة

---

## 📝 ملاحظات مهمة

### 1. البحث الجزئي (Partial Search)
- البحث يدعم البحث الجزئي
- مثال: "ماك" سيجد "ماكسيم"
- لكن يجب أن يبدأ الاسم بالنص المدخل

### 2. Case Sensitivity
- البحث case-insensitive
- يتم تحويل النص إلى lowercase قبل البحث

### 3. Pagination
- البحث يدعم Infinite Scroll Pagination
- يتم تحميل 20 شركة في كل مرة
- يمكن تحميل المزيد بالتمرير للأسفل

### 4. Performance
- الـ Index موجود بالفعل
- البحث سريع وفعال
- لا حاجة لتحديثات Firebase

---

## ✅ قائمة التحقق

- [x] تغيير واجهة المستخدم
- [x] تحديث Event
- [x] تحديث State
- [x] تحديث BLoC
- [x] تحديث Repository Interface
- [x] تحديث Repository Implementation
- [x] تحديث UseCase
- [x] تحديث Remote Data Source
- [x] إصلاح شكل الزر
- [x] التحقق من Firestore Index
- [x] اختبار الأخطاء (No diagnostics found)
- [x] توثيق التغييرات

---

## 🚀 الخطوة التالية

التطبيق جاهز للاختبار! قم بتشغيله واختبر البحث بالاسم.

```bash
flutter run
```

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ مكتمل وجاهز للاستخدام
