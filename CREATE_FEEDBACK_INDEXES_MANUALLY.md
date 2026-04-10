# 📝 إنشاء Indexes نظام المقترحات يدوياً

**التاريخ:** 2 أبريل 2026  
**السبب:** تجاوز حد الـ 200 index في Firebase

---

## 🎯 الخطوات

### 1. افتح Firebase Console

اذهب إلى:
```
https://console.firebase.google.com/project/practice-firebase-72df1/firestore/indexes
```

### 2. أنشئ الـ Indexes التالية

#### Index 1: userId + createdAt
```
Collection ID: feedbacks
Fields indexed:
  - userId (Ascending)
  - createdAt (Descending)
Query scope: Collection
```

**كيفية الإنشاء:**
1. اضغط "Create Index"
2. Collection ID: `feedbacks`
3. أضف Field: `userId` → Ascending
4. أضف Field: `createdAt` → Descending
5. Query scope: Collection
6. اضغط "Create"

---

#### Index 2: status + createdAt
```
Collection ID: feedbacks
Fields indexed:
  - status (Ascending)
  - createdAt (Descending)
Query scope: Collection
```

**كيفية الإنشاء:**
1. اضغط "Create Index"
2. Collection ID: `feedbacks`
3. أضف Field: `status` → Ascending
4. أضف Field: `createdAt` → Descending
5. Query scope: Collection
6. اضغط "Create"

---

#### Index 3: type + createdAt
```
Collection ID: feedbacks
Fields indexed:
  - type (Ascending)
  - createdAt (Descending)
Query scope: Collection
```

**كيفية الإنشاء:**
1. اضغط "Create Index"
2. Collection ID: `feedbacks`
3. أضف Field: `type` → Ascending
4. أضف Field: `createdAt` → Descending
5. Query scope: Collection
6. اضغط "Create"

---

#### Index 4: userId + status + createdAt
```
Collection ID: feedbacks
Fields indexed:
  - userId (Ascending)
  - status (Ascending)
  - createdAt (Descending)
Query scope: Collection
```

**كيفية الإنشاء:**
1. اضغط "Create Index"
2. Collection ID: `feedbacks`
3. أضف Field: `userId` → Ascending
4. أضف Field: `status` → Ascending
5. أضف Field: `createdAt` → Descending
6. Query scope: Collection
7. اضغط "Create"

---

#### Index 5: userId + type + createdAt
```
Collection ID: feedbacks
Fields indexed:
  - userId (Ascending)
  - type (Ascending)
  - createdAt (Descending)
Query scope: Collection
```

**كيفية الإنشاء:**
1. اضغط "Create Index"
2. Collection ID: `feedbacks`
3. أضف Field: `userId` → Ascending
4. أضف Field: `type` → Ascending
5. أضف Field: `createdAt` → Descending
6. Query scope: Collection
7. اضغط "Create"

---

## ⏱️ وقت البناء

- كل index يستغرق **5-10 دقائق** للبناء
- إجمالي الوقت: **25-50 دقيقة**
- يمكنك إنشاء كل الـ indexes مرة واحدة وانتظار البناء

---

## ✅ التحقق

بعد البناء، تحقق من:
1. جميع الـ indexes في حالة "Enabled" (خضراء)
2. لا توجد أخطاء
3. جرب التطبيق وتأكد من عمل الفلاتر

---

## 🔄 البديل: استخدام Firebase CLI

إذا أردت استخدام CLI بدلاً من Console:

```bash
# استخدم الملف المخصص
firebase deploy --only firestore:indexes --config firestore.indexes.feedback-only.json --project practice-firebase-72df1
```

**ملاحظة:** هذا سيضيف الـ indexes الجديدة فقط بدون المساس بالموجودة.

---

## 📞 الدعم

إذا واجهت مشاكل:
1. تحقق من Firebase Console → Indexes
2. ابحث عن رسائل الخطأ
3. تأكد من أن Collection `feedbacks` موجودة
4. جرب إنشاء index واحد أولاً للاختبار

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026
