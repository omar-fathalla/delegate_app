# 🔐 Firestore Indexes Agent Rules

**الإصدار:** 1.0.0  
**آخر تحديث:** 1 أبريل 2026  
**الحالة:** نشط وفعال

---

## 📋 الغرض

هذا الملف يحدد قواعس صارمة للـ Agent عند التعامل مع Firestore Indexes. الهدف هو حماية الـ Indexes المستخدمة فعلاً في التطبيق من الحذف أو التعديل غير المقصود، مع السماح بالعمل على الـ Indexes غير المستخدمة فقط.

---

## ✅ Firestore Indexes المستخدمة (PROTECTED)

هذه الـ Indexes **نشطة وتُستخدم فعلاً** في التطبيق. **لا يجب حذفها أو تعديل وظيفتها الأساسية**.

### 📌 Indexes الحرجة (CRITICAL) ⭐

#### 1. **attendance** - Indexes الحضور
```
Collection: attendance
Index 1: userId (ASC) + checkInTime (DESC)
```
- **الاستخدام:** تتبع سجلات الحضور والانصراف
- **الوظيفة:** استعلام أحدث سجلات الحضور لكل مندوب
- **المجموعات المتأثرة:** `attendance` (قراءة)
- **الأهمية:** حرجة جداً - تطبيق الحضور يعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة للحضور
- ✅ يمكن تحسين الأداء
- ❌ **لا يجب حذف هذا الـ Index**
- ❌ **لا يجب تعديل ترتيب الحقول**
- ❌ **لا يجب تغيير نوع الترتيب (ASC/DESC)**

---

#### 2. **attendance_logs** - Indexes سجلات الحضور
```
Collection: attendance_logs
Index 1: delegateId (ASC) + timestamp (ASC)
Index 2: organizationId (ASC) + delegateId (ASC) + timestamp (DESC)
Index 3: delegateId (ASC) + timestamp (DESC)
```
- **الاستخدام:** تتبع سجلات الحضور التفصيلية
- **الوظيفة:** استعلام السجلات حسب المندوب والتاريخ
- **المجموعات المتأثرة:** `attendance_logs` (قراءة)
- **الأهمية:** حرجة جداً - تقارير الحضور تعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة
- ✅ يمكن تحسين الأداء
- ❌ **لا يجب حذف أي من هذه الـ Indexes**
- ❌ **لا يجب تعديل ترتيب الحقول**

---

#### 3. **delegates** - Indexes المندوبين
```
Collection: delegates (COLLECTION_GROUP)
Index 1-27: مجموعة متنوعة من الـ Indexes للتصفية والترتيب
- organizationUID + status
- organizationUID + status + fullName
- companyUID + status
- isPrinted + organizationUID + status
- وغيرها...

Collection: delegates (COLLECTION)
Index 28-58: indexes إضافية للتصفية حسب المدينة والموضع
- city + companyUID + position + status
- companyUID + position + status
- وغيرها...
```
- **الاستخدام:** تصفية وترتيب المندوبين
- **الوظيفة:** البحث والتصفية المتقدمة للمندوبين
- **المجموعات المتأثرة:** `delegates` (قراءة)
- **الأهمية:** حرجة جداً - واجهة المندوبين تعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة للتصفية
- ✅ يمكن تحسين الأداء
- ❌ **لا يجب حذف أي من هذه الـ Indexes**
- ❌ **لا يجب تعديل ترتيب الحقول**

---

#### 4. **companies** - Indexes الشركات
```
Collection: companies
Index 1-38: مجموعة متنوعة من الـ Indexes
- organizationUID + createdAt
- organizationUID + status + name
- organizationUID + type + deferredPayment
- وغيرها...
```
- **الاستخدام:** تصفية وترتيب الشركات
- **الوظيفة:** البحث والتصفية المتقدمة للشركات
- **المجموعات المتأثرة:** `companies` (قراءة)
- **الأهمية:** حرجة جداً - واجهة الشركات تعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة
- ✅ يمكن تحسين الأداء
- ❌ **لا يجب حذف أي من هذه الـ Indexes**
- ❌ **لا يجب تعديل ترتيب الحقول**

---

#### 5. **requests** - Indexes الطلبات
```
Collection: requests (COLLECTION_GROUP)
Index 1-47: indexes متنوعة للتصفية والترتيب
- actionType + organizationUID + status
- organizationUID + status + targetDelegateName
- companyUID + status + updatedAt
- وغيرها...

Collection: requests (COLLECTION)
Index 48-68: indexes إضافية
```
- **الاستخدام:** تصفية وترتيب الطلبات
- **الوظيفة:** البحث والتصفية المتقدمة للطلبات
- **المجموعات المتأثرة:** `requests` (قراءة)
- **الأهمية:** حرجة جداً - نظام الطلبات يعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة
- ✅ يمكن تحسين الأداء
- ❌ **لا يجب حذف أي من هذه الـ Indexes**
- ❌ **لا يجب تعديل ترتيب الحقول**

---

### 📌 Indexes المهمة (IMPORTANT) ⚠️

#### 6. **companyRequests** - Indexes طلبات الشركات
```
Collection: companyRequests
Index 1-19: indexes متنوعة
- organizationUID + status + targetCompanyName
- actionType + organizationUID + updatedAt
- وغيرها...
```
- **الاستخدام:** تصفية طلبات الشركات
- **الوظيفة:** البحث والتصفية لطلبات الشركات
- **المجموعات المتأثرة:** `companyRequests` (قراءة)
- **الأهمية:** مهمة - نظام طلبات الشركات يعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة
- ❌ **لا يجب حذف أي من هذه الـ Indexes**
- ❌ **لا يجب تعديل ترتيب الحقول**

---

#### 7. **users** - Indexes المستخدمين
```
Collection: users
Index 1-6: indexes متنوعة
- organizationUID + role + createdAt
- companyUID + organizationUID + role
- وغيرها...
```
- **الاستخدام:** تصفية المستخدمين حسب الدور والمنظمة
- **الوظيفة:** البحث والتصفية للمستخدمين
- **المجموعات المتأثرة:** `users` (قراءة)
- **الأهمية:** مهمة - إدارة المستخدمين تعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة
- ❌ **لا يجب حذف أي من هذه الـ Indexes**

---

#### 8. **tasks** - Indexes المهام
```
Collection: tasks
Index 1-3: indexes متنوعة
- companyId + createdAt
- companyId + status + createdAt
- assignedTo + companyId + createdAt
```
- **الاستخدام:** تصفية المهام
- **الوظيفة:** البحث والتصفية للمهام
- **المجموعات المتأثرة:** `tasks` (قراءة)
- **الأهمية:** مهمة - نظام المهام يعتمد عليها

**القواعس:**
- ✅ يمكن إضافة indexes جديدة
- ❌ **لا يجب حذف أي من هذه الـ Indexes**

---

### 📌 Indexes الإضافية (SECONDARY)

#### 9. **invites** - Indexes الدعوات
```
Collection: invites
Index 1-2: indexes متنوعة
- organizationId + roleToAssign + status + createdAt
- companyId + organizationId + roleToAssign + status + createdAt
```
- **الاستخدام:** تصفية الدعوات
- **الأهمية:** ثانوية - نظام الدعوات يعتمد عليها

**القواعس:**
- ❌ **لا يجب حذف أي من هذه الـ Indexes**

---

#### 10. **pendingAdmins** - Indexes المسؤولين المعلقين
```
Collection: pendingAdmins
Index 1-2: indexes متنوعة
- organizationUID + role + createdAt
- companyUID + organizationUID + role + createdAt
```
- **الاستخدام:** تصفية المسؤولين المعلقين
- **الأهمية:** ثانوية

**القواعس:**
- ❌ **لا يجب حذف أي من هذه الـ Indexes**

---

#### 11. **delegateRequests** - Indexes طلبات المندوبين
```
Collection: delegateRequests
Index 1: companyUID (ASC) + updatedAt (DESC)
```
- **الاستخدام:** تصفية طلبات المندوبين
- **الأهمية:** ثانوية

**القواعس:**
- ❌ **لا يجب حذف هذا الـ Index**

---

#### 12. **app_updates** - Indexes تحديثات التطبيق
```
Collection: app_updates
Index 1: isActive (ASC) + createdAt (DESC)
```
- **الاستخدام:** الحصول على آخر تحديثات التطبيق
- **الأهمية:** ثانوية

**القواعس:**
- ❌ **لا يجب حذف هذا الـ Index**

---

## 🚫 Indexes غير المستخدمة (CANDIDATES FOR REVIEW)

**ملاحظة مهمة:** قبل حذف أي index من هذه القائمة، يجب:
1. التحقق من عدم استخدامه في الكود
2. مراجعة Firebase Console للتأكد من عدم استخدامه
3. الحصول على موافقة من فريق التطوير

---

## ⚠️ تحذيرات مهمة

### 1. **الـ Indexes المحمية (PROTECTED):**
- جميع الـ Indexes المذكورة أعلاه **محمية**
- حذفها سيؤدي إلى توقف الاستعلامات
- قد تظهر رسائل خطأ في التطبيق

### 2. **التأثير على الأداء:**
- حذف index قد يؤدي إلى استعلامات بطيئة
- قد يزيد من استهلاك الموارد

### 3. **التأثير على المستخدمين:**
- قد يؤدي إلى توقف الميزات
- قد يؤثر على تجربة المستخدم

### 4. **اختبر قبل النشر:**
- اختبر الاستعلامات محلياً قبل أي تغيير
- استخدم Firebase Emulator

### 5. **احتفظ بنسخة احتياطية:**
- احتفظ بنسخة من الـ indexes قبل أي تغيير
- استخدم Git للتحكم في الإصدارات

---

## 📊 ملخص الحالة

| المجموعة | عدد الـ Indexes | الحالة | الإجراء |
|---------|-----------------|--------|--------|
| **attendance** | 1 | ✅ حرجة | لا تحذف |
| **attendance_logs** | 3 | ✅ حرجة | لا تحذف |
| **delegates** | 58 | ✅ حرجة | لا تحذف |
| **companies** | 38 | ✅ حرجة | لا تحذف |
| **requests** | 68 | ✅ حرجة | لا تحذف |
| **companyRequests** | 19 | ⚠️ مهمة | لا تحذف |
| **users** | 6 | ⚠️ مهمة | لا تحذف |
| **tasks** | 3 | ⚠️ مهمة | لا تحذف |
| **invites** | 2 | 📌 ثانوية | لا تحذف |
| **pendingAdmins** | 2 | 📌 ثانوية | لا تحذف |
| **delegateRequests** | 1 | 📌 ثانوية | لا تحذف |
| **app_updates** | 1 | 📌 ثانوية | لا تحذف |
| **الإجمالي** | **202** | 🔒 محمية | **لا تحذف أي منها** |

**النتيجة:** جميع الـ 202 index محمية ولا يجب التعامل معها من ناحية الحذف أو التعديل

---

## 🔄 عملية المراجعة الدورية

يجب مراجعة هذا الملف كل شهر:

1. **مراقبة الـ Indexes المستخدمة:**
   - تحقق من Firebase Console
   - تأكد من عمل الاستعلامات بشكل صحيح

2. **مراقبة الأداء:**
   - تحقق من سرعة الاستعلامات
   - تأكد من عدم وجود استعلامات بطيئة

3. **تحديث القواعس:**
   - أضف قواعس جديدة إذا لزم الأمر
   - حدّث القواعس الموجودة

---

## 📞 الاتصال والدعم

إذا كان لديك أسئلة حول هذه القواعس:

1. اطلب من Kiro AI Assistant
2. راجع ملف `firebase_indexes_analysis.md`
3. تحقق من Firebase Console

---

## 🎯 القواعس الذهبية للـ Agent

### ✅ يمكنك:
- ✅ قراءة الـ Indexes وتحليلها
- ✅ إنشاء تقارير عن الـ Indexes
- ✅ اقتراح تحسينات للأداء
- ✅ مراقبة استخدام الـ Indexes
- ✅ إضافة indexes جديدة (بعد التحقق من الحاجة)

### ❌ لا يمكنك:
- ❌ حذف أي index من الـ Indexes المذكورة
- ❌ تعديل ترتيب الحقول في أي index
- ❌ تغيير نوع الترتيب (ASC/DESC)
- ❌ تعديل Query Scope (COLLECTION/COLLECTION_GROUP)
- ❌ حذف أي مجموعة من المجموعات المذكورة

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**آخر تحديث:** 1 أبريل 2026  
**الحالة:** نشط وجاهز للاستخدام  
**الإصدار:** 1.0.0
