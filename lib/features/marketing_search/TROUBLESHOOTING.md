# 🔧 حل المشاكل - Marketing Search

## 🐛 المشاكل الشائعة

### 1. خطأ: "حدث خطأ غير متوقع أثناء البحث عن الشركة"

**السبب:**
- Firestore Rules لم يتم نشرها بعد
- أو المستخدم ليس لديه صلاحيات القراءة

**الحل:**
```bash
./deploy_firestore_rules.sh
```

---

### 2. لا تظهر أي نتائج

**الأسباب المحتملة:**

#### أ) الشركة غير موجودة
- تحقق من أن رقم الشركة صحيح
- جرب البحث في Firebase Console

#### ب) المستخدم في منظمة خاطئة
- تحقق من `organizationUID` في الكود
- تحقق من أن المستخدم مسجل دخول بشكل صحيح

#### ج) البحث يبحث في حقل خاطئ
- الكود يبحث في حقلين:
  - `code` (رقم)
  - `companyCodeInOrg` (نص)

**الحل:**
```dart
// في marketing_search_remote_datasource.dart
// تحقق من أن الحقول صحيحة
.where('code', isEqualTo: codeAsNumber)
.where('companyCodeInOrg', isEqualTo: companyCode)
```

---

### 3. خطأ: "ليس لديك صلاحية للوصول إلى هذه البيانات"

**السبب:**
- Firestore Rules تمنع القراءة
- المستخدم غير مصادق

**الحل:**
1. تحقق من أن المستخدم مسجل دخول
2. تحقق من Firestore Rules:
```javascript
match /companies/{compId} {
  allow read: if isAuthenticated();
}
```

---

### 4. البحث بطيء جداً

**السبب:**
- لا يوجد Firestore Index

**الحل:**
```bash
firebase deploy --only firestore:indexes --project practice-firebase-72df1
```

**Indexes المطلوبة:**
```json
{
  "collectionGroup": "companies",
  "queryScope": "COLLECTION",
  "fields": [
    { "fieldPath": "organizationUID", "order": "ASCENDING" },
    { "fieldPath": "code", "order": "ASCENDING" }
  ]
}
```

---

### 5. البحث عن مندوب لا يعمل

**الأسباب المحتملة:**

#### أ) رقم الهاتف بصيغة خاطئة
- الكود يطبع رقم الهاتف تلقائياً
- يدعم: `+20`, `0020`, `002`, `01X`

**مثال:**
```
Input: +201234567890
Normalized: 01234567890
```

#### ب) المندوب غير موجود
- تحقق من Firebase Console
- تحقق من أن `phoneNumber` مخزن بنفس الصيغة

#### ج) collectionGroup query لا يعمل
- تحقق من Firestore Index:
```json
{
  "collectionGroup": "delegates",
  "queryScope": "COLLECTION_GROUP",
  "fields": [
    { "fieldPath": "organizationUID", "order": "ASCENDING" },
    { "fieldPath": "phoneNumber", "order": "ASCENDING" }
  ]
}
```

---

## 🔍 التشخيص

### تفعيل Logs

في `marketing_search_remote_datasource.dart`، الـ logs مفعلة بالفعل:

```dart
developer.log('🔍 [Marketing] البحث عن شركة');
developer.log('Organization UID: $organizationUID');
developer.log('Company Code: "$companyCode"');
```

### فحص Logs

```bash
# في Android Studio / VS Code
# افتح Debug Console وابحث عن:
[Marketing]
```

---

## 🧪 الاختبار اليدوي

### 1. اختبار البحث عن شركة

```dart
// في Dart DevTools Console
final datasource = MarketingSearchRemoteDataSourceImpl(
  firestore: FirebaseFirestore.instance,
);

final result = await datasource.searchCompanyByCode(
  organizationUID: 'YOUR_ORG_UID',
  companyCode: '1048',
);

print('Results: ${result.items.length}');
```

### 2. اختبار البحث عن مندوب

```dart
final result = await datasource.searchDelegateByPhone(
  organizationUID: 'YOUR_ORG_UID',
  phoneNumber: '01234567890',
);

print('Results: ${result.items.length}');
```

---

## 📋 قائمة التحقق

عند حدوث مشكلة، تحقق من:

- [ ] المستخدم مسجل دخول (authenticated)
- [ ] `organizationUID` صحيح
- [ ] Firestore Rules منشورة
- [ ] Firestore Indexes منشورة
- [ ] البيانات موجودة في Firebase Console
- [ ] الحقول المستخدمة في البحث صحيحة
- [ ] رقم الهاتف بالصيغة الصحيحة (للمندوبين)

---

## 🆘 الدعم

إذا استمرت المشكلة:

1. راجع `MARKETING_SEARCH_FIX.md`
2. راجع `README.md` في نفس المجلد
3. تحقق من Firebase Console → Firestore → Rules
4. تحقق من Firebase Console → Firestore → Indexes
5. اطلب من Kiro AI Assistant

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 12 أبريل 2026
