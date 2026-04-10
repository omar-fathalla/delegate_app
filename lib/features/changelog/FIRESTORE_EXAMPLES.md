# 🔥 أمثلة Firestore للتحديثات

**الغرض:** أمثلة عملية لإضافة تحديثات في Firestore

---

## 📋 جدول المحتويات

1. [إضافة تحديث عبر Firebase Console](#إضافة-تحديث-عبر-firebase-console)
2. [إضافة تحديث عبر Cloud Functions](#إضافة-تحديث-عبر-cloud-functions)
3. [إضافة تحديث عبر Flutter Admin Panel](#إضافة-تحديث-عبر-flutter-admin-panel)
4. [أمثلة متنوعة](#أمثلة-متنوعة)

---

## إضافة تحديث عبر Firebase Console

### الخطوات:

1. افتح Firebase Console
2. اذهب إلى Firestore Database
3. افتح Collection `app_updates`
4. اضغط على "Add document"
5. اترك Document ID فارغاً (سيتم توليده تلقائياً)
6. أضف الحقول التالية:

### مثال 1: ميزة جديدة (New Feature)

```
Field: title
Type: string
Value: نظام الحضور المحسّن

Field: titleEn
Type: string
Value: Enhanced Attendance System

Field: description
Type: string
Value: تم تحسين نظام الحضور مع إضافة ميزات جديدة للتحقق من الموقع

Field: descriptionEn
Type: string
Value: Enhanced attendance system with new location verification features

Field: version
Type: string
Value: 1.2.0

Field: type
Type: string
Value: feature

Field: priority
Type: string
Value: important

Field: createdAt
Type: timestamp
Value: [اضغط على "Set to current time"]

Field: isActive
Type: boolean
Value: true

Field: highlights
Type: array
Values:
  - تحسين دقة تحديد الموقع
  - إضافة كشف الموقع الوهمي
  - تحسين واجهة المستخدم
  - إضافة إشعارات فورية

Field: highlightsEn
Type: array
Values:
  - Improved location accuracy
  - Added mock location detection
  - Enhanced user interface
  - Added real-time notifications
```

---

## إضافة تحديث عبر Cloud Functions

### إنشاء Cloud Function

```typescript
// functions/src/index.ts

import * as admin from 'firebase-admin';
import * as functions from 'firebase-functions';

admin.initializeApp();

/**
 * Cloud Function لإضافة تحديث جديد
 * يمكن استدعاؤها من Admin Panel أو من CLI
 */
export const addAppUpdate = functions.https.onCall(async (data, context) => {
  // التحقق من الصلاحيات (فقط Super Admin)
  if (!context.auth || context.auth.token.role !== 'super-admin') {
    throw new functions.https.HttpsError(
      'permission-denied',
      'Only super admins can add updates'
    );
  }

  const {
    title,
    titleEn,
    description,
    descriptionEn,
    version,
    type,
    priority,
    highlights,
    highlightsEn,
  } = data;

  // التحقق من البيانات المطلوبة
  if (!title || !titleEn || !version || !type) {
    throw new functions.https.HttpsError(
      'invalid-argument',
      'Missing required fields'
    );
  }

  // إضافة التحديث
  const updateRef = await admin.firestore().collection('app_updates').add({
    title,
    titleEn,
    description: description || '',
    descriptionEn: descriptionEn || '',
    version,
    type, // 'feature' | 'fix' | 'improvement'
    priority: priority || 'normal', // 'normal' | 'important' | 'critical'
    createdAt: admin.firestore.FieldValue.serverTimestamp(),
    isActive: true,
    highlights: highlights || [],
    highlightsEn: highlightsEn || [],
  });

  return {
    success: true,
    updateId: updateRef.id,
    message: 'Update added successfully',
  };
});
```

### استدعاء Cloud Function من Flutter

```dart
// في Admin Panel
Future<void> addUpdate() async {
  try {
    final callable = FirebaseFunctions.instance.httpsCallable('addAppUpdate');
    
    final result = await callable.call({
      'title': 'تحسينات الأداء',
      'titleEn': 'Performance Improvements',
      'description': 'تم تحسين سرعة التطبيق بنسبة 50%',
      'descriptionEn': 'App speed improved by 50%',
      'version': '1.1.5',
      'type': 'improvement',
      'priority': 'normal',
      'highlights': [
        'تحسين سرعة التحميل',
        'تقليل استهلاك البطارية',
        'إصلاح مشاكل الذاكرة',
      ],
      'highlightsEn': [
        'Faster loading times',
        'Reduced battery consumption',
        'Fixed memory issues',
      ],
    });

    print('Update added: ${result.data['updateId']}');
  } catch (e) {
    print('Error adding update: $e');
  }
}
```

---

## إضافة تحديث عبر Flutter Admin Panel

### إنشاء صفحة Admin

```dart
// lib/features/admin/presentation/pages/add_update_page.dart

class AddUpdatePage extends StatefulWidget {
  const AddUpdatePage({super.key});

  @override
  State<AddUpdatePage> createState() => _AddUpdatePageState();
}

class _AddUpdatePageState extends State<AddUpdatePage> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _titleEnController = TextEditingController();
  final _descriptionController = TextEditingController();
  final _descriptionEnController = TextEditingController();
  final _versionController = TextEditingController();
  
  UpdateType _selectedType = UpdateType.feature;
  UpdatePriority _selectedPriority = UpdatePriority.normal;
  
  final List<String> _highlights = [];
  final List<String> _highlightsEn = [];

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(
        title: const Text('إضافة تحديث جديد'),
      ),
      body: Form(
        key: _formKey,
        child: ListView(
          padding: const EdgeInsets.all(16),
          children: [
            // العنوان بالعربية
            TextFormField(
              controller: _titleController,
              decoration: const InputDecoration(
                labelText: 'العنوان (عربي)',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            
            // العنوان بالإنجليزية
            TextFormField(
              controller: _titleEnController,
              decoration: const InputDecoration(
                labelText: 'Title (English)',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'Required' : null,
            ),
            const SizedBox(height: 16),
            
            // الوصف بالعربية
            TextFormField(
              controller: _descriptionController,
              decoration: const InputDecoration(
                labelText: 'الوصف (عربي)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            // الوصف بالإنجليزية
            TextFormField(
              controller: _descriptionEnController,
              decoration: const InputDecoration(
                labelText: 'Description (English)',
                border: OutlineInputBorder(),
              ),
              maxLines: 3,
            ),
            const SizedBox(height: 16),
            
            // رقم الإصدار
            TextFormField(
              controller: _versionController,
              decoration: const InputDecoration(
                labelText: 'رقم الإصدار (مثال: 1.0.0)',
                border: OutlineInputBorder(),
              ),
              validator: (value) =>
                  value?.isEmpty ?? true ? 'مطلوب' : null,
            ),
            const SizedBox(height: 16),
            
            // نوع التحديث
            DropdownButtonFormField<UpdateType>(
              value: _selectedType,
              decoration: const InputDecoration(
                labelText: 'نوع التحديث',
                border: OutlineInputBorder(),
              ),
              items: UpdateType.values.map((type) {
                return DropdownMenuItem(
                  value: type,
                  child: Text(_getTypeLabel(type)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedType = value!;
                });
              },
            ),
            const SizedBox(height: 16),
            
            // الأولوية
            DropdownButtonFormField<UpdatePriority>(
              value: _selectedPriority,
              decoration: const InputDecoration(
                labelText: 'الأولوية',
                border: OutlineInputBorder(),
              ),
              items: UpdatePriority.values.map((priority) {
                return DropdownMenuItem(
                  value: priority,
                  child: Text(_getPriorityLabel(priority)),
                );
              }).toList(),
              onChanged: (value) {
                setState(() {
                  _selectedPriority = value!;
                });
              },
            ),
            const SizedBox(height: 24),
            
            // زر الحفظ
            FilledButton(
              onPressed: _saveUpdate,
              child: const Text('حفظ التحديث'),
            ),
          ],
        ),
      ),
    );
  }

  String _getTypeLabel(UpdateType type) {
    switch (type) {
      case UpdateType.feature:
        return 'ميزة جديدة';
      case UpdateType.fix:
        return 'إصلاح';
      case UpdateType.improvement:
        return 'تحسين';
    }
  }

  String _getPriorityLabel(UpdatePriority priority) {
    switch (priority) {
      case UpdatePriority.normal:
        return 'عادي';
      case UpdatePriority.important:
        return 'مهم';
      case UpdatePriority.critical:
        return 'حرج';
    }
  }

  Future<void> _saveUpdate() async {
    if (!_formKey.currentState!.validate()) return;

    try {
      await FirebaseFirestore.instance.collection('app_updates').add({
        'title': _titleController.text,
        'titleEn': _titleEnController.text,
        'description': _descriptionController.text,
        'descriptionEn': _descriptionEnController.text,
        'version': _versionController.text,
        'type': _selectedType.name,
        'priority': _selectedPriority.name,
        'createdAt': FieldValue.serverTimestamp(),
        'isActive': true,
        'highlights': _highlights,
        'highlightsEn': _highlightsEn,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          const SnackBar(content: Text('تم إضافة التحديث بنجاح')),
        );
        Navigator.pop(context);
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('خطأ: $e')),
        );
      }
    }
  }

  @override
  void dispose() {
    _titleController.dispose();
    _titleEnController.dispose();
    _descriptionController.dispose();
    _descriptionEnController.dispose();
    _versionController.dispose();
    super.dispose();
  }
}
```

---

## أمثلة متنوعة

### مثال 1: تحديث ميزة جديدة (Feature)

```json
{
  "title": "نظام المهام الجديد",
  "titleEn": "New Task System",
  "description": "تم إضافة نظام مهام متقدم مع إمكانية تعيين المهام للمندوبين",
  "descriptionEn": "Added advanced task system with delegate assignment",
  "version": "1.3.0",
  "type": "feature",
  "priority": "important",
  "createdAt": "2026-04-01T10:00:00Z",
  "isActive": true,
  "highlights": [
    "إنشاء مهام جديدة",
    "تعيين المهام للمندوبين",
    "تتبع حالة المهام",
    "إشعارات فورية عند إنشاء مهمة"
  ],
  "highlightsEn": [
    "Create new tasks",
    "Assign tasks to delegates",
    "Track task status",
    "Real-time notifications for new tasks"
  ]
}
```

### مثال 2: إصلاح خطأ (Bug Fix)

```json
{
  "title": "إصلاح مشكلة الحضور",
  "titleEn": "Attendance Issue Fixed",
  "description": "تم إصلاح مشكلة منعت بعض المندوبين من تسجيل الحضور",
  "descriptionEn": "Fixed an issue that prevented some delegates from checking in",
  "version": "1.2.3",
  "type": "fix",
  "priority": "critical",
  "createdAt": "2026-04-01T11:00:00Z",
  "isActive": true,
  "highlights": [
    "إصلاح مشكلة تسجيل الحضور",
    "تحسين دقة تحديد الموقع",
    "إضافة معالجة أخطاء أفضل"
  ],
  "highlightsEn": [
    "Fixed check-in issue",
    "Improved location accuracy",
    "Added better error handling"
  ]
}
```

### مثال 3: تحسين (Improvement)

```json
{
  "title": "تحسينات الأداء",
  "titleEn": "Performance Improvements",
  "description": "تم تحسين سرعة التطبيق وتقليل استهلاك البطارية",
  "descriptionEn": "Improved app speed and reduced battery consumption",
  "version": "1.2.1",
  "type": "improvement",
  "priority": "normal",
  "createdAt": "2026-04-01T09:00:00Z",
  "isActive": true,
  "highlights": [
    "تحسين سرعة التحميل بنسبة 40%",
    "تقليل استهلاك البطارية بنسبة 25%",
    "تحسين استقرار التطبيق",
    "إصلاح مشاكل الذاكرة"
  ],
  "highlightsEn": [
    "40% faster loading times",
    "25% reduced battery consumption",
    "Improved app stability",
    "Fixed memory issues"
  ]
}
```

### مثال 4: تحديث أمني (Security Update)

```json
{
  "title": "تحديث أمني مهم",
  "titleEn": "Important Security Update",
  "description": "تم تحسين أمان التطبيق وإضافة طبقات حماية إضافية",
  "descriptionEn": "Enhanced app security with additional protection layers",
  "version": "1.2.5",
  "type": "improvement",
  "priority": "critical",
  "createdAt": "2026-04-01T14:00:00Z",
  "isActive": true,
  "highlights": [
    "تفعيل Firebase App Check",
    "إضافة Biometric Authentication",
    "تشفير البيانات الحساسة",
    "تحسين قواعد Firestore Security"
  ],
  "highlightsEn": [
    "Enabled Firebase App Check",
    "Added Biometric Authentication",
    "Encrypted sensitive data",
    "Enhanced Firestore Security Rules"
  ]
}
```

### مثال 5: تحديث واجهة المستخدم (UI Update)

```json
{
  "title": "تحديث واجهة المستخدم",
  "titleEn": "UI Update",
  "description": "تم تحديث واجهة المستخدم لتكون أكثر جمالاً وسهولة في الاستخدام",
  "descriptionEn": "Updated user interface for better aesthetics and usability",
  "version": "1.4.0",
  "type": "improvement",
  "priority": "normal",
  "createdAt": "2026-04-01T15:00:00Z",
  "isActive": true,
  "highlights": [
    "تصميم جديد مع Material Design 3",
    "دعم الوضع الداكن المحسّن",
    "أيقونات جديدة",
    "تحسين تجربة المستخدم"
  ],
  "highlightsEn": [
    "New design with Material Design 3",
    "Enhanced dark mode support",
    "New icons",
    "Improved user experience"
  ]
}
```

---

## 🔧 سكريبت Python لإضافة تحديثات

```python
# add_update.py
import firebase_admin
from firebase_admin import credentials, firestore
from datetime import datetime

# تهيئة Firebase
cred = credentials.Certificate('path/to/serviceAccountKey.json')
firebase_admin.initialize_app(cred)

db = firestore.client()

def add_update(
    title: str,
    title_en: str,
    description: str,
    description_en: str,
    version: str,
    update_type: str,  # 'feature', 'fix', 'improvement'
    priority: str = 'normal',  # 'normal', 'important', 'critical'
    highlights: list = None,
    highlights_en: list = None,
):
    """إضافة تحديث جديد إلى Firestore"""
    
    if highlights is None:
        highlights = []
    if highlights_en is None:
        highlights_en = []
    
    update_data = {
        'title': title,
        'titleEn': title_en,
        'description': description,
        'descriptionEn': description_en,
        'version': version,
        'type': update_type,
        'priority': priority,
        'createdAt': firestore.SERVER_TIMESTAMP,
        'isActive': True,
        'highlights': highlights,
        'highlightsEn': highlights_en,
    }
    
    doc_ref = db.collection('app_updates').add(update_data)
    print(f'✅ تم إضافة التحديث بنجاح: {doc_ref[1].id}')

# مثال على الاستخدام
if __name__ == '__main__':
    add_update(
        title='نظام الإشعارات الجديد',
        title_en='New Notification System',
        description='تم إضافة نظام إشعارات متقدم',
        description_en='Added advanced notification system',
        version='1.5.0',
        update_type='feature',
        priority='important',
        highlights=[
            'إشعارات فورية',
            'تخصيص الإشعارات',
            'إشعارات صوتية',
        ],
        highlights_en=[
            'Real-time notifications',
            'Customizable notifications',
            'Sound notifications',
        ],
    )
```

---

## 📊 إحصائيات التحديثات

### استعلام لعرض عدد التحديثات حسب النوع

```dart
Future<Map<String, int>> getUpdateStats() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('app_updates')
      .where('isActive', isEqualTo: true)
      .get();

  final stats = <String, int>{
    'feature': 0,
    'fix': 0,
    'improvement': 0,
  };

  for (final doc in snapshot.docs) {
    final type = doc.data()['type'] as String;
    stats[type] = (stats[type] ?? 0) + 1;
  }

  return stats;
}
```

### استعلام لعرض آخر 5 تحديثات

```dart
Future<List<AppUpdate>> getLatestUpdates() async {
  final snapshot = await FirebaseFirestore.instance
      .collection('app_updates')
      .where('isActive', isEqualTo: true)
      .orderBy('createdAt', descending: true)
      .limit(5)
      .get();

  return snapshot.docs
      .map((doc) => AppUpdateModel.fromJson(doc.data(), doc.id))
      .toList();
}
```

---

## 🎯 نصائح مهمة

### 1. رقم الإصدار (Semantic Versioning)

```
MAJOR.MINOR.PATCH

MAJOR: تغييرات كبيرة (Breaking Changes)
MINOR: ميزات جديدة (New Features)
PATCH: إصلاحات (Bug Fixes)

أمثلة:
- 1.0.0 → 1.0.1 (إصلاح خطأ)
- 1.0.1 → 1.1.0 (ميزة جديدة)
- 1.1.0 → 2.0.0 (تغيير كبير)
```

### 2. متى تستخدم كل أولوية؟

```
normal: تحديثات عادية (تحسينات، ميزات صغيرة)
important: تحديثات مهمة (ميزات كبيرة، إصلاحات مهمة)
critical: تحديثات حرجة (إصلاحات أمنية، أخطاء خطيرة)
```

### 3. متى تستخدم كل نوع؟

```
feature: ميزات جديدة
fix: إصلاح أخطاء
improvement: تحسينات على ميزات موجودة
```

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**آخر تحديث:** 1 أبريل 2026  
**الحالة:** ✅ نشط وجاهز للاستخدام
