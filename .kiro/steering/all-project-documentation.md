# 📚 التوثيق الشامل لمشروع Delegate App

**تاريخ الإنشاء:** 1 أبريل 2026  
**الحالة:** نشط ومحدّث  
**الإصدار:** 2.0.0

---

## 📋 جدول المحتويات

1. [نظرة عامة على المشروع](#نظرة-عامة-على-المشروع)
2. [Firebase - البحث الشامل](#firebase---البحث-الشامل)
3. [Firebase - التحليل المتقدم](#firebase---التحليل-المتقدم)
4. [Firebase - أمثلة الأكواد](#firebase---أمثلة-الأكواد)
5. [Cloud Functions - التقرير الكامل](#cloud-functions---التقرير-الكامل)
6. [خطة الإصلاح](#خطة-الإصلاح)
7. [دليل الـ AI Agents](#دليل-الـ-ai-agents)
8. [نظام الإشعارات](#نظام-الإشعارات)
9. [Workflows - إضافة Firebase Service](#workflows---إضافة-firebase-service)
10. [Workflows - إضافة Localization](#workflows---إضافة-localization)
11. [Workflows - إضافة صفحة جديدة](#workflows---إضافة-صفحة-جديدة)
12. [Workflows - نظام الحضور](#workflows---نظام-الحضور)
13. [Workflows - إنشاء BLoC](#workflows---إنشاء-bloc)
14. [Workflows - إنشاء Feature](#workflows---إنشاء-feature)
15. [Workflows - إنشاء Firestore Model](#workflows---إنشاء-firestore-model)
16. [Workflows - إنشاء Use Case](#workflows---إنشاء-use-case)
17. [Workflows - نشر التطبيق](#workflows---نشر-التطبيق)
18. [Workflows - معالجة الأخطاء](#workflows---معالجة-الأخطاء)
19. [Workflows - تشغيل Code Generation](#workflows---تشغيل-code-generation)
20. [Workflows - تأمين التطبيق](#workflows---تأمين-التطبيق)
21. [Workflows - إعداد DI](#workflows---إعداد-di)
22. [Workflows - التحقق من المشروع](#workflows---التحقق-من-المشروع)
23. [Workflows - كتابة الاختبارات](#workflows---كتابة-الاختبارات)
24. [Workflows - بناء iOS](#workflows---بناء-ios)

---


# نظرة عامة على المشروع

## تطبيق مندوبي تسهيل - Tashil Delegate App

تطبيق موبايل لإدارة حضور وانصراف المندوبين عبر مسح أكواد QR والتحقق من الموقع الجغرافي (Geofencing).

### التقنيات المستخدمة

- **Flutter 3.x** + Dart 3.10
- **Firebase:** Firestore, Authentication, Storage
- **البنية:** Clean Architecture + BLoC + GetIt (DI)
- **المنصات:** Android, iOS, Web, macOS
- **اللغات:** العربية + الإنجليزية

### الميزات الرئيسية

- تسجيل الحضور والانصراف عبر QR Code
- التحقق من الموقع الجغرافي (Geofencing)
- دعم العمل بدون اتصال (Offline-First)
- لوحة إدارة الفروع مع خرائط Google
- دعم الوضع الداكن وMaterial Design 3
- نظام أدوار (مندوب / مشرف / مسؤول)

### هيكل المشروع

```
lib/
├── features/          # الميزات (كل ميزة بها Domain, Data, Presentation)
│   ├── attendance/    # الحضور والانصراف
│   ├── auth/          # المصادقة
│   ├── profile/       # الملف الشخصي
│   ├── admin/         # لوحة الإدارة
│   ├── home/          # الشاشة الرئيسية
│   └── settings/      # الإعدادات
├── core/              # الأدوات المشتركة
│   ├── config/        # إعدادات التطبيق
│   ├── storage/       # خدمات التخزين
│   ├── error/         # معالجة الأخطاء
│   └── widgets/       # مكونات UI مشتركة
├── config/            # إعدادات عامة (ثيمات، مسارات)
└── l10n/              # ملفات الترجمة
```

---

# Firebase - البحث الشامل

## معرّف المشروع
- **Project ID:** `practice-firebase-72df1`
- **Messaging Sender ID:** `564223619997`
- **Storage Bucket:** `practice-firebase-72df1.firebasestorage.app`

## قواعس الأمان (Firestore Rules)

### دوال مساعدة (Helper Functions)

```javascript
// التحقق من المصادقة
function isAuthenticated() {
  return request.auth != null;
}

// الحصول على بيانات المستخدم
function getUserData() {
  return get(/databases/$(database)/documents/users/$(request.auth.uid)).data;
}

// التحقق من كون المستخدم super admin
function isSuperAdmin() {
  return isAuthenticated() && getUserData().role == 'super-admin';
}

// التحقق من انتماء المستخدم للمنظمة
function belongsToOrganization(orgId) {
  return isAuthenticated() && getUserData().organizationUID == orgId;
}
```

### قواعس المجموعات الرئيسية

#### Users Collection
```javascript
match /users/{userId} {
  allow read: if isAuthenticated();
  allow create, update: if isAuthenticated();
  allow delete: if isAuthenticated();
}
```

#### Organizations Collection
```javascript
match /organizations/{orgId} {
  allow read: if isAuthenticated() && canAccessOrganization(orgId);
  allow create: if isAuthenticated() && isSuperAdmin();
  allow update: if isAuthenticated() && (isSuperAdmin() || (isOrgAdmin() && belongsToOrganization(orgId)));
  allow delete: if isAuthenticated() && isSuperAdmin();
}
```

#### Tasks Collection
```javascript
match /organizations/{orgId}/tasks/{taskId} {
  allow read: if isAuthenticated();
  allow create, update, delete: if isAuthenticated();
}
```

#### Notifications Collection
```javascript
match /notifications/{notificationId} {
  allow read: if isAuthenticated();
  allow create: if isAuthenticated();
  allow update: if isAuthenticated() && request.resource.data.diff(resource.data).affectedKeys().hasOnly(['isRead']);
  allow delete: if isAuthenticated() && isSuperAdmin();
}
```

## Cloud Functions

### 1. onTaskCreated
**الغرض:** إرسال إشعارات FCM للمندوبين المعينين

**المحفز:** `onCreate` على `organizations/{organizationId}/tasks/{taskId}`

**الخطوات:**
1. الحصول على قائمة المندوبين المعينين
2. إنشاء وثائق إشعارات في Firestore
3. الحصول على رموز FCM
4. إرسال رسائل FCM
5. تنظيف الرموز غير الصالحة

### 2. onTaskUpdated
**الغرض:** إرسال إشعارات عند تغيير الحالة أو تعيين مندوبين جدد

**المحفز:** `onUpdate` على `organizations/{organizationId}/tasks/{taskId}`

### 3. generatePendingPublicId
**الغرض:** إنشاء معرّفات فريدة للمندوبين الجدد (مثل DEL-0001)

**نوع الدالة:** HTTP Cloud Function

## خدمات Firebase المستخدمة

| الخدمة | الإصدار | الاستخدام |
|--------|--------|----------|
| firebase_core | ^4.4.0 | تهيئة Firebase |
| cloud_firestore | ^6.1.2 | قاعدة البيانات |
| firebase_auth | ^6.1.4 | المصادقة |
| firebase_storage | 13.0.6 | تخزين الملفات |
| firebase_messaging | ^16.1.2 | الإشعارات |
| firebase_crashlytics | ^5.0.8 | تتبع الأخطاء |

## المشاكل الأمنية والتوصيات

### ⚠️ المشاكل الحالية

1. **Anonymous Authentication**
   - أي شخص يمكنه الوصول
   - **الحل:** Phone Auth + OTP

2. **عدم وجود Firebase App Check**
   - لا حماية من التطبيقات المزيفة
   - **الحل:** تفعيل App Check

3. **عدم وجود Rate Limiting**
   - لا حماية من الهجمات الآلية
   - **الحل:** إضافة في Cloud Functions

4. **SharedPreferences غير آمن**
   - البيانات غير مشفرة
   - **الحل:** flutter_secure_storage

---

# Firebase - التحليل المتقدم

## جدول مقارنة: الحالة الحالية vs الحالة المثالية

| الميزة | الحالة الحالية | الحالة المثالية | الفجوة | الأولوية |
|--------|-----------------|-----------------|--------|---------|
| **المصادقة** | Anonymous Auth | Phone Auth + OTP | عالية | 🔴 Critical |
| **Firestore Rules** | Role-Based | Role-Based + Attribute-Based | منخفضة | ✅ تم |
| **التخزين الآمن** | SharedPreferences | flutter_secure_storage | متوسطة | 🟡 Medium |
| **Rate Limiting** | غير موجود | في Cloud Functions | عالية | 🔴 Critical |
| **Firebase App Check** | غير مفعل | مفعل | عالية | 🔴 Critical |
| **Crashlytics** | مفعل | مفعل + Custom Logging | منخفضة | ✅ تم |
| **Firestore Indexes** | 60+ فهرس | محسّن | منخفضة | ✅ تم |

## معمارية الأمان الموصى بها

```
┌─────────────────────────────────────────────────────────┐
│                    Flutter App                          │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Presentation Layer (UI)                         │  │
│  └──────────────────────────────────────────────────┘  │
│                        ↓                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Domain Layer (Business Logic)                   │  │
│  └──────────────────────────────────────────────────┘  │
│                        ↓                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Data Layer (Repositories)                       │  │
│  └──────────────────────────────────────────────────┘  │
│                        ↓                                │
│  ┌──────────────────────────────────────────────────┐  │
│  │  Firebase Services                               │  │
│  │  - Phone Auth + OTP                              │  │
│  │  - App Check                                     │  │
│  │  - Firestore (مع Rules)                          │  │
│  │  - Cloud Functions (مع Rate Limiting)            │  │
│  └──────────────────────────────────────────────────┘  │
└─────────────────────────────────────────────────────────┘
```

## خطة التحسين (Roadmap)

### المرحلة 1: الأمان الأساسي (أسبوع 1-2)
- [ ] تفعيل Firebase App Check
- [ ] إضافة Rate Limiting في Cloud Functions
- [ ] استبدال SharedPreferences بـ flutter_secure_storage

### المرحلة 2: المصادقة المحسّنة (أسبوع 3-4)
- [ ] تطبيق Phone Authentication
- [ ] إضافة OTP Verification
- [ ] تحديث Firestore Rules

### المرحلة 3: الأداء والموثوقية (أسبوع 5-6)
- [ ] تحسين Offline Support
- [ ] إضافة Retry Logic
- [ ] تحسين Caching Strategy

### المرحلة 4: المراقبة والتحليل (أسبوع 7-8)
- [ ] تحسين Crashlytics Logging
- [ ] إضافة Custom Analytics
- [ ] إنشاء Dashboard للمراقبة

---

# Firebase - أمثلة الأكواد

## أمثلة Firestore Rules

### Rule بسيط - قراءة فقط للمستخدم نفسه

```javascript
match /users/{userId} {
  allow read: if request.auth.uid == userId;
  allow update: if request.auth.uid == userId;
  allow delete: if false;
}
```

### Rule متقدم - Role-Based Access

```javascript
match /organizations/{orgId} {
  function getUserRole() {
    return get(/databases/$(database)/documents/users/$(request.auth.uid)).data.role;
  }

  allow read, write: if getUserRole() == 'super-admin';
  allow read, update: if getUserRole() == 'org-admin' &&
                         get(/databases/$(database)/documents/users/$(request.auth.uid)).data.organizationUID == orgId;
}
```

## أمثلة Cloud Functions

### Function بسيط - إرسال بريد إلكتروني

```typescript
export const sendWelcomeEmail = functions.auth.user().onCreate(async (user) => {
  const email = user.email;
  const displayName = user.displayName || "المستخدم";

  await admin.firestore().collection("mail").add({
    to: email,
    message: {
      subject: "أهلاً وسهلاً",
      html: `<h1>مرحباً ${displayName}</h1>`,
    },
  });
});
```

### Function مع Firestore Trigger

```typescript
export const onUserCreated = functions.firestore
  .document("users/{userId}")
  .onCreate(async (snap, context) => {
    const userId = context.params.userId;
    const userData = snap.data();

    await admin.firestore()
      .collection("user_profiles")
      .doc(userId)
      .set({
        displayName: userData.displayName,
        email: userData.email,
        createdAt: admin.firestore.FieldValue.serverTimestamp(),
      });
  });
```

## أمثلة Dart/Flutter

### مثال بسيط - قراءة البيانات

```dart
Future<List<Task>> getTasks(String delegateId) async {
  final snapshot = await _firestore
    .collection('tasks')
    .where('assignedTo', arrayContains: delegateId)
    .orderBy('createdAt', descending: true)
    .get();

  return snapshot.docs
    .map((doc) => Task.fromJson(doc.data()))
    .toList();
}
```

### مثال متقدم - Pagination

```dart
Future<PaginationResponse<Task>> getTasks(
  String delegateId, {
  DocumentSnapshot? lastDocument,
}) async {
  Query query = _firestore
    .collection('tasks')
    .where('assignedTo', arrayContains: delegateId)
    .orderBy('createdAt', descending: true)
    .limit(pageSize + 1);

  if (lastDocument != null) {
    query = query.startAfterDocument(lastDocument);
  }

  final snapshot = await query.get();
  final hasMore = snapshot.docs.length > pageSize;
  final docs = hasMore ? snapshot.docs.take(pageSize).toList() : snapshot.docs;

  return PaginationResponse(
    data: docs.map((doc) => Task.fromJson(doc.data())).toList(),
    hasMore: hasMore,
    lastDocument: docs.isNotEmpty ? docs.last : null,
  );
}
```

## أمثلة معالجة الأخطاء

```dart
Future<Either<Failure, List<Task>>> getTasks(String delegateId) async {
  try {
    final tasks = await _remoteDataSource.getTasks(delegateId);
    return Right(tasks);
  } on FirebaseException catch (e) {
    return Left(ServerFailure(_mapFirebaseException(e)));
  } on SocketException {
    return Left(ServerFailure('لا يوجد اتصال بالإنترنت'));
  } on TimeoutException {
    return Left(ServerFailure('انتهت مهلة الاتصال'));
  } catch (e) {
    return Left(ServerFailure('حدث خطأ غير متوقع'));
  }
}
```

---

# Cloud Functions - التقرير الكامل

## جدول الدوال

| # | اسم الدالة | النوع | الذاكرة | الحالة |
|---|-----------|------|--------|--------|
| 1 | `onTaskCreated` | Firestore Trigger | 256 MB | ✅ نشطة |
| 2 | `onTaskUpdated` | Firestore Trigger | 256 MB | ✅ نشطة |
| 3 | `generatePendingPublicId` | Callable | 512 MB | ✅ نشطة |

## تفاصيل الدوال

### onTaskCreated
- **المسار:** `organizations/{organizationId}/tasks/{taskId}`
- **الحدث:** `onCreate`
- **الوظيفة:** إرسال إشعارات FCM للمندوبين المعينين

### onTaskUpdated
- **المسار:** `organizations/{organizationId}/tasks/{taskId}`
- **الحدث:** `onUpdate`
- **الوظيفة:** إرسال إشعارات عند تعيين مندوبين جدد

### generatePendingPublicId
- **النوع:** HTTP Function
- **الوظيفة:** توليد معرفات فريدة (DEL-0001)

---

# خطة الإصلاح

## المرحلة ١: إصلاح الثغرات الأمنية (أسبوع 1-2)

### ✅ تم التنفيذ
- إزالة بيانات Admin المكتوبة في الكود
- تشديد Firestore Rules
- إنشاء Secure Storage Service

### ⏳ لم يبدأ بعد
- تفعيل Firebase Phone Authentication
- تفعيل Firebase App Check
- إضافة Rate Limiting

## المرحلة ٢: كتابة الاختبارات (أسبوع 3-4)

### ✅ تم التنفيذ
- اختبارات وحدة للـ UseCases (25+ اختبار)
- اختبارات الـ BLoCs (18+ اختبار)

### ⏳ لم يبدأ بعد
- اختبارات الـ Repositories

## المرحلة ٣: التحسينات التقنية (أسبوع 5-6)

### ✅ تم التنفيذ
- Firebase Crashlytics
- BLoC Observer

### ⚠️ يحتاج تشغيل
- build_runner

---

# دليل الـ AI Agents

## Workflows المتاحة

### /create-feature
إنشاء feature كامل بـ Clean Architecture (Domain, Data, Presentation)

### /add-page
إنشاء صفحة جديدة مع go_router و Material 3

### /create-bloc
إنشاء BLoC جديد مع Events و States

### /create-usecase
إنشاء Use Case مع Params و Either

### /create-firestore-model
إنشاء Dart model متوافق مع Firestore

### /setup-di
تسجيل dependencies في GetIt

### /run-codegen
تشغيل build_runner لـ freezed و json_serializable

### /handle-errors
إنشاء Failure classes ومعالجة أخطاء Firebase

### /add-firebase-service
إضافة خدمة Firebase جديدة

### /secure-app
تطبيق Biometric Auth و App Check

### /attendance-checkin
تطبيق نظام الحضور مع Geo-fencing

### /verify-project
فحص المشروع (analysis, schema, anti-fraud)

### /write-tests
كتابة Unit و Widget tests

### /build-ios
بناء iOS IPA مع signing

### /deploy-app
نشر التطبيق عبر CI/CD

## Skills المتاحة

### notebook_reader
جلب محتوى نصي من URLs

---

# نظام الإشعارات

## الحالة الحالية

✅ نظام الإشعارات مكتمل وجاهز

## ما تم إنجازه

1. **Cloud Functions**
   - onTaskCreated - إرسال إشعارات عند إنشاء مهمة
   - onTaskUpdated - إرسال إشعارات عند تعيين مندوبين جدد

2. **Firestore Rules**
   - قواعد تسمح بالوصول للإشعارات
   - قواعد تسمح بحفظ FCM tokens

3. **Flutter App**
   - PushNotificationService
   - NotificationBloc
   - NotificationsPage
   - Bell Icon مع Badge

## كيفية الاختبار

1. أنشئ مهمة جديدة من Web Dashboard
2. عيّن المهمة لمندوب
3. يجب أن يظهر:
   - إشعار push على الموبايل
   - Badge على أيقونة الجرس
   - الإشعار في صفحة Notifications

---


# Workflows - إضافة Firebase Service

## قبل البدء

1. Firebase يجب أن يكون مهيأ في `main.dart`
2. خيارات Firebase في `lib/firebase_options.dart`
3. لا تكتب API keys في الكود

## الخطوات

### 1. إضافة الحزمة

```bash
flutter pub add <firebase_package>
```

الحزم الشائعة:
- Auth: `firebase_auth`
- Firestore: `cloud_firestore`
- Storage: `firebase_storage`
- Crashlytics: `firebase_crashlytics`

### 2. إعداد المنصات

- **Android:** تأكد من `google-services.json` في `android/app/`
- **iOS:** تأكد من `GoogleService-Info.plist` في `ios/Runner/`

### 3. التهيئة في main.dart

```dart
void main() async {
  WidgetsFlutterBinding.ensureInitialized();
  await Firebase.initializeApp(
    options: DefaultFirebaseOptions.currentPlatform,
  );
  runApp(const MyApp());
}
```

### 4. التسجيل في DI

```dart
// Firebase Auth
sl.registerLazySingleton(() => FirebaseAuth.instance);

// Firebase Storage
sl.registerLazySingleton(() => FirebaseStorage.instance);
```

---

# Workflows - إضافة Localization

## الخطوات

### 1. إضافة التبعيات

```bash
flutter pub add flutter_localizations --sdk=flutter
flutter pub add intl
```

### 2. تفعيل التوليد في pubspec.yaml

```yaml
flutter:
  generate: true
```

### 3. إنشاء l10n.yaml

```yaml
arb-dir: lib/l10n
template-arb-file: app_ar.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
```

### 4. إنشاء ملفات ARB

**app_ar.arb (العربية):**
```json
{
  "@@locale": "ar",
  "appTitle": "تسهيل - المندوب",
  "login": "تسجيل الدخول",
  "logout": "تسجيل الخروج",
  "errorGeneral": "حدث خطأ. يرجى المحاولة مرة أخرى."
}
```

**app_en.arb (الإنجليزية):**
```json
{
  "@@locale": "en",
  "appTitle": "Tashil - Delegate",
  "login": "Login",
  "logout": "Logout",
  "errorGeneral": "An error occurred. Please try again."
}
```

### 5. إعداد MaterialApp

```dart
MaterialApp(
  locale: const Locale('ar'),
  supportedLocales: const [Locale('ar'), Locale('en')],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
  ],
)
```

### 6. الاستخدام في Widgets

```dart
final l10n = AppLocalizations.of(context)!;
Text(l10n.login);
```

---

# Workflows - إضافة صفحة جديدة

## الخطوات

### 1. إنشاء Page Widget

```dart
class FeaturePage extends StatelessWidget {
  const FeaturePage({super.key});

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      appBar: AppBar(title: const Text('Page Title')),
      body: BlocProvider(
        create: (_) => sl<FeatureBloc>()..add(const LoadRequested()),
        child: BlocBuilder<FeatureBloc, FeatureState>(
          builder: (context, state) {
            return switch (state) {
              FeatureLoading() => const Center(child: CircularProgressIndicator()),
              FeatureLoaded(:final data) => _buildContent(data),
              FeatureError(:final message) => Center(child: Text(message)),
              _ => const SizedBox.shrink(),
            };
          },
        ),
      ),
    );
  }
}
```

### 2. تعريف المسار

```dart
GoRoute(
  path: '/feature',
  name: 'feature',
  builder: (context, state) => const FeaturePage(),
),
```

### 3. التنقل للصفحة

```dart
context.goNamed('feature');
```

---

# Workflows - نظام الحضور

## قواعد Anti-Fraud (إلزامية)

1. **Server Timestamp فقط:** استخدم `FieldValue.serverTimestamp()` دائماً
2. **التحقق من الموقع:** تحقق من GPS قبل الإرسال لـ Firestore
3. **كشف Mock Location:** ارفض إذا تم اكتشاف موقع وهمي

## التحقق من الموقع

```dart
// 1. فحص الأذونات
final permission = await Geolocator.checkPermission();

// 2. الحصول على الموقع
final position = await Geolocator.getCurrentPosition(
  desiredAccuracy: LocationAccuracy.high,
);

// 3. كشف Mock Location
if (position.isMocked) {
  return Left(LocationFraudFailure());
}

// 4. حساب المسافة
final distance = Geolocator.distanceBetween(
  position.latitude, position.longitude,
  worksite.latitude, worksite.longitude,
);

// 5. التحقق من النطاق
if (distance > allowedRadius) {
  return Left(OutOfRangeFailure());
}
```

## إرسال Check-In

```dart
// ✅ صحيح
await firestore
  .collection('organizations').doc(orgId)
  .collection('companies').doc(compId)
  .collection('delegates').doc(uid)
  .collection('attendance').add({
    'checkInTime': FieldValue.serverTimestamp(),
    'latitude': position.latitude,
    'longitude': position.longitude,
    'status': 'checkedIn',
  });

// ❌ خطأ
// 'checkInTime': DateTime.now().toIso8601String(),
```

---

# Workflows - إنشاء BLoC

## الخطوات

### 1. إنشاء Event

```dart
abstract class FeatureEvent extends Equatable {
  const FeatureEvent();
  @override
  List<Object?> get props => [];
}

class LoadFeatureRequested extends FeatureEvent {
  const LoadFeatureRequested();
}
```

### 2. إنشاء State

```dart
abstract class FeatureState extends Equatable {
  const FeatureState();
  @override
  List<Object?> get props => [];
}

class FeatureInitial extends FeatureState {}
class FeatureLoading extends FeatureState {}
class FeatureLoaded extends FeatureState {
  final EntityType data;
  const FeatureLoaded({required this.data});
  @override
  List<Object?> get props => [data];
}
class FeatureError extends FeatureState {
  final String message;
  const FeatureError({required this.message});
  @override
  List<Object?> get props => [message];
}
```

### 3. إنشاء Bloc

```dart
class FeatureBloc extends Bloc<FeatureEvent, FeatureState> {
  final UseCaseName useCase;

  FeatureBloc({required this.useCase}) : super(FeatureInitial()) {
    on<LoadFeatureRequested>(_onLoadRequested);
  }

  Future<void> _onLoadRequested(
    LoadFeatureRequested event,
    Emitter<FeatureState> emit,
  ) async {
    emit(FeatureLoading());
    final result = await useCase();
    result.fold(
      (failure) => emit(FeatureError(message: failure.message)),
      (data) => emit(FeatureLoaded(data: data)),
    );
  }
}
```

### 4. التسجيل في DI

```dart
sl.registerFactory(() => FeatureBloc(useCase: sl()));
```

---

# Workflows - إنشاء Feature

## هيكل المجلدات

```
lib/features/<feature_name>/
├── data/
│   ├── datasources/
│   ├── models/
│   └── repositories/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
└── presentation/
    ├── bloc/
    ├── pages/
    └── widgets/
```

## الخطوات

### 1. Domain Layer - Entity

```dart
class EntityName extends Equatable {
  final String uid;
  const EntityName({required this.uid});
  @override
  List<Object?> get props => [uid];
}
```

### 2. Domain Layer - Repository

```dart
abstract class FeatureRepository {
  Future<Either<Failure, Entity>> getEntity(String id);
}
```

### 3. Data Layer - Model

```dart
class EntityModel extends Entity {
  const EntityModel({required super.uid});

  factory EntityModel.fromJson(Map<String, dynamic> json) {
    return EntityModel(uid: json['uid']);
  }

  Map<String, dynamic> toJson() => {'uid': uid};
}
```

### 4. Data Layer - Remote Data Source

```dart
abstract class FeatureRemoteDataSource {
  Future<EntityModel> getEntity(String id);
}

class FeatureRemoteDataSourceImpl implements FeatureRemoteDataSource {
  final FirebaseFirestore firestore;
  FeatureRemoteDataSourceImpl({required this.firestore});

  @override
  Future<EntityModel> getEntity(String id) async {
    final doc = await firestore
      .collection('organizations').doc(orgId)
      .collection('entities').doc(id)
      .get();
    return EntityModel.fromJson(doc.data()!);
  }
}
```

### 5. التسجيل في DI

```dart
// Bloc
sl.registerFactory(() => FeatureBloc(useCase: sl()));

// Use cases
sl.registerLazySingleton(() => UseCaseName(sl()));

// Repository
sl.registerLazySingleton<FeatureRepository>(
  () => FeatureRepositoryImpl(remoteDataSource: sl()),
);

// Data sources
sl.registerLazySingleton<FeatureRemoteDataSource>(
  () => FeatureRemoteDataSourceImpl(firestore: sl()),
);
```

---

# Workflows - إنشاء Firestore Model

## ⚠️ مهم جداً

جميع مفاتيح JSON يجب أن تستخدم **camelCase** مطابقة لـ schema الموجود.

## الخطوات

### 1. فحص Schema الموجود

تحقق من:
- ملفات TypeScript/Angular
- ملف `firestore.rules`
- Firestore Console

### 2. إنشاء Domain Entity

```dart
class DelegatePerson extends Equatable {
  final String uid;
  final String firstName;
  final String nationalityID;  // Capital 'ID'
  final DateTime birthDate;
  final String organizationUID;
  final String companyUID;

  const DelegatePerson({...});

  @override
  List<Object?> get props => [...];
}
```

### 3. إنشاء Data Model

```dart
class DelegateModel extends DelegatePerson {
  const DelegateModel({...}) : super(...);

  factory DelegateModel.fromJson(Map<String, dynamic> json) {
    return DelegateModel(
      uid: json['uid'],
      firstName: json['firstName'],
      nationalityID: json['nationalityID'],  // Capital 'ID'
      birthDate: (json['birthDate'] as Timestamp).toDate(),
      organizationUID: json['organizationUID'],
      companyUID: json['companyUID'],
    );
  }

  Map<String, dynamic> toJson() {
    return {
      'uid': uid,
      'firstName': firstName,
      'nationalityID': nationalityID,
      'birthDate': Timestamp.fromDate(birthDate),
      'organizationUID': organizationUID,
      'companyUID': companyUID,
    };
  }
}
```

### 4. قواعد Firestore Path

```dart
// ✅ صحيح
firestore
  .collection('organizations').doc(orgId)
  .collection('companies').doc(compId)
  .collection('delegates').doc(uid);

// ❌ خطأ
firestore.collection('delegates').doc(uid);
```

---

# Workflows - إنشاء Use Case

## الخطوات

### 1. Base UseCase Class

```dart
abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

class NoParams extends Equatable {
  @override
  List<Object?> get props => [];
}
```

### 2. إنشاء Use Case مع Params

```dart
class GetDelegateProfile extends UseCase<DelegatePerson, GetDelegateProfileParams> {
  final ProfileRepository repository;

  GetDelegateProfile(this.repository);

  @override
  Future<Either<Failure, DelegatePerson>> call(GetDelegateProfileParams params) {
    return repository.getDelegateProfile(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      uid: params.uid,
    );
  }
}

class GetDelegateProfileParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String uid;

  const GetDelegateProfileParams({
    required this.organizationUID,
    required this.companyUID,
    required this.uid,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, uid];
}
```

### 3. التسجيل في DI

```dart
sl.registerLazySingleton(() => GetDelegateProfile(sl()));
```

### 4. الاستخدام في Bloc

```dart
final result = await getDelegateProfile(
  GetDelegateProfileParams(
    organizationUID: event.organizationUID,
    companyUID: event.companyUID,
    uid: event.uid,
  ),
);
```

---

# Workflows - نشر التطبيق

## البناء المحلي

### Debug
```bash
flutter build apk --debug
```

### Release
```bash
flutter build apk --release
flutter build appbundle --release  # للـ Play Store
flutter build ipa --release  # لـ iOS
```

## GitHub Actions CI/CD

```yaml
name: CI/CD Pipeline

on:
  push:
    branches: [develop, main]

jobs:
  build-android:
    runs-on: ubuntu-latest
    steps:
      - uses: actions/checkout@v4
      - uses: subosito/flutter-action@v2
      - run: flutter pub get
      - run: flutter build appbundle --release
```

## قائمة التحقق قبل النشر

- [ ] جميع الاختبارات تعمل: `flutter test`
- [ ] لا توجد مشاكل: `flutter analyze`
- [ ] تحديث الإصدار في `pubspec.yaml`
- [ ] لا توجد `print()` في الكود
- [ ] لا توجد API keys مكتوبة
- [ ] Firebase configuration صحيح

---

# Workflows - معالجة الأخطاء

## إنشاء Failure Classes

```dart
abstract class Failure extends Equatable {
  final String message;
  final String? code;

  const Failure({required this.message, this.code});

  @override
  List<Object?> get props => [message, code];
}

class ServerFailure extends Failure {
  const ServerFailure({required super.message, super.code});
}

class AuthFailure extends Failure {
  const AuthFailure({required super.message, super.code});
}

class LocationFailure extends Failure {
  const LocationFailure({required super.message, super.code});
}
```

## Firebase Error Mapper

```dart
class FirebaseErrorMapper {
  static String mapAuthError(FirebaseAuthException e) {
    switch (e.code) {
      case 'user-not-found':
        return 'المستخدم غير موجود';
      case 'wrong-password':
        return 'كلمة المرور غير صحيحة';
      case 'invalid-email':
        return 'البريد الإلكتروني غير صالح';
      default:
        return 'خطأ في المصادقة';
    }
  }

  static String mapFirestoreError(FirebaseException e) {
    switch (e.code) {
      case 'permission-denied':
        return 'ليس لديك صلاحية للوصول';
      case 'not-found':
        return 'البيانات غير موجودة';
      default:
        return 'حدث خطأ غير متوقع';
    }
  }
}
```

## الاستخدام في Repository

```dart
@override
Future<Either<Failure, Entity>> getEntity(String uid) async {
  try {
    final doc = await remoteDataSource.getEntity(uid);
    return Right(doc);
  } on FirebaseException catch (e) {
    return Left(ServerFailure(
      message: FirebaseErrorMapper.mapFirestoreError(e),
      code: e.code,
    ));
  } catch (e) {
    return Left(const ServerFailure(
      message: 'حدث خطأ غير متوقع',
    ));
  }
}
```

---

# Workflows - تشغيل Code Generation

## متى تستخدم

بعد تعديل ملفات تحتوي على:
- `@freezed` / `@Freezed`
- `@JsonSerializable()`
- `@injectable` / `@lazySingleton`

## الأوامر

### تشغيل build_runner

```bash
dart run build_runner build --delete-conflicting-outputs
```

### Watch mode (للتطوير)

```bash
dart run build_runner watch --delete-conflicting-outputs
```

### تنظيف الملفات المولدة

```bash
dart run build_runner clean
```

## مثال Freezed Model

```dart
import 'package:freezed_annotation/freezed_annotation.dart';

part 'delegate_model.freezed.dart';
part 'delegate_model.g.dart';

@freezed
class DelegateModel with _$DelegateModel {
  const factory DelegateModel({
    required String uid,
    required String firstName,
    required String nationalityID,
    required String organizationUID,
    required String companyUID,
  }) = _DelegateModel;

  factory DelegateModel.fromJson(Map<String, dynamic> json)
      => _$DelegateModelFromJson(json);
}
```

---

# Workflows - تأمين التطبيق

## 1. Biometric Authentication

### إضافة التبعية

```bash
flutter pub add local_auth
```

### التطبيق

```dart
class BiometricService {
  final LocalAuthentication _localAuth = LocalAuthentication();

  Future<bool> authenticate() async {
    return await _localAuth.authenticate(
      localizedReason: 'يرجى التحقق من هويتك',
      options: const AuthenticationOptions(
        stickyAuth: true,
        biometricOnly: false,
      ),
    );
  }
}
```

## 2. Firebase App Check

```bash
flutter pub add firebase_app_check
```

```dart
await FirebaseAppCheck.instance.activate(
  androidProvider: AndroidProvider.playIntegrity,
  appleProvider: AppleProvider.deviceCheck,
);
```

## 3. Secure Storage

```bash
flutter pub add flutter_secure_storage
```

```dart
final secureStorage = FlutterSecureStorage();
await secureStorage.write(key: 'auth_token', value: token);
final token = await secureStorage.read(key: 'auth_token');
```

## قائمة التحقق الأمني

- [ ] local_auth مفعل
- [ ] Firebase App Check مفعل
- [ ] لا توجد `print()` في الكود
- [ ] لا توجد مفاتيح مكتوبة
- [ ] flutter_secure_storage للبيانات الحساسة
- [ ] كشف Mock Location نشط
- [ ] Firestore Rules تفرض `uid == request.auth.uid`

---

# Workflows - إعداد DI

## ترتيب التسجيل

```dart
// ! Features - <FeatureName>

// 1. Bloc (registerFactory)
sl.registerFactory(() => FeatureBloc(useCaseA: sl(), useCaseB: sl()));

// 2. Use Cases (registerLazySingleton)
sl.registerLazySingleton(() => UseCaseA(sl()));
sl.registerLazySingleton(() => UseCaseB(sl()));

// 3. Repository (registerLazySingleton مع abstract type)
sl.registerLazySingleton<FeatureRepository>(
  () => FeatureRepositoryImpl(remoteDataSource: sl()),
);

// 4. Data Sources (registerLazySingleton مع abstract type)
sl.registerLazySingleton<FeatureRemoteDataSource>(
  () => FeatureRemoteDataSourceImpl(firestore: sl()),
);
```

## القواعد

1. **Blocs** → `registerFactory`
2. **كل شيء آخر** → `registerLazySingleton`
3. **Abstract type** → دائماً للـ Repositories و DataSources
4. **استخدم `sl()`** لحل التبعيات

---

# Workflows - التحقق من المشروع

## 1. Static Analysis

```bash
flutter analyze
```

## 2. تشغيل الاختبارات

```bash
flutter test
```

## 3. فحص Schema Consistency

- [ ] جميع مفاتيح JSON تستخدم camelCase
- [ ] `nationalityID` يستخدم "ID" كبيرة
- [ ] `organizationUID` و `companyUID` يستخدمون "UID"
- [ ] `birthDate` يستخدم `Timestamp`

## 4. Anti-Fraud Compliance

```bash
# يجب أن يكون النتيجة صفر
grep -r "DateTime.now()" lib/features/attendance/
```

- [ ] جميع timestamps تستخدم `FieldValue.serverTimestamp()`
- [ ] التحقق من الموقع قبل check-in
- [ ] كشف Mock Location نشط

## 5. فحص Collection Paths

- [ ] لا يوجد وصول لـ `/delegates` مباشرة
- [ ] جميع المسارات: `/organizations/{orgId}/companies/{compId}/delegates/{uid}`

## 6. فحص الأمان

- [ ] لا توجد API keys مكتوبة
- [ ] لا توجد `print()` statements
- [ ] المندوبون يصلون لبياناتهم فقط

---

# Workflows - كتابة الاختبارات

## إضافة التبعيات

```bash
flutter pub add --dev mocktail bloc_test
```

## هيكل المجلدات

```
test/
├── features/
│   ├── auth/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   └── attendance/
└── core/
```

## Unit Test - Use Case

```dart
class MockFeatureRepository extends Mock implements FeatureRepository {}

void main() {
  late UseCaseName useCase;
  late MockFeatureRepository mockRepository;

  setUp(() {
    mockRepository = MockFeatureRepository();
    useCase = UseCaseName(mockRepository);
  });

  test('should return data when repository succeeds', () async {
    when(() => mockRepository.getData(any()))
        .thenAnswer((_) async => const Right(expectedData));

    final result = await useCase(params);

    expect(result, const Right(expectedData));
    verify(() => mockRepository.getData(any())).called(1);
  });
}
```

## Bloc Test

```dart
class MockUseCase extends Mock implements UseCaseName {}

void main() {
  late FeatureBloc bloc;
  late MockUseCase mockUseCase;

  setUp(() {
    mockUseCase = MockUseCase();
    bloc = FeatureBloc(useCase: mockUseCase);
  });

  blocTest<FeatureBloc, FeatureState>(
    'emits [Loading, Loaded] when data is fetched successfully',
    build: () {
      when(() => mockUseCase(any()))
          .thenAnswer((_) async => const Right(testData));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadRequested()),
    expect: () => [
      FeatureLoading(),
      FeatureLoaded(data: testData),
    ],
  );
}
```

## تشغيل الاختبارات

```bash
flutter test
flutter test --coverage  # مع coverage
```

---

# Workflows - بناء iOS

## تشغيل سريع (أمر واحد)

```bash
./scripts/auto_build_ios.sh
```

هذا السكريبت يقوم بـ:
- ✅ زيادة Build Number
- ✅ تشغيل `flutter clean` و `flutter pub get`
- ✅ بناء iOS Release
- ✅ إنشاء Xcode Archive موقع
- ✅ تصدير IPA
- ✅ رفع لـ Firebase App Distribution

## الخطوات اليدوية

### 1. زيادة build number

```bash
# في pubspec.yaml
# من: version: 1.0.0+N
# إلى: version: 1.0.0+(N+1)
```

### 2. تنظيف وتثبيت

```bash
flutter clean && flutter pub get
```

### 3. بناء iOS

```bash
flutter build ios --release --no-codesign
```

### 4. Archive مع التوقيع

```bash
xcodebuild -workspace ios/Runner.xcworkspace \
  -scheme Runner -sdk iphoneos -configuration Release \
  archive -archivePath build/ios/Runner.xcarchive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TX5G7GZL6T
```

### 5. تصدير IPA

```bash
xcodebuild -exportArchive \
  -archivePath build/ios/Runner.xcarchive \
  -exportPath build/ios/ipa \
  -exportOptionsPlist ios/ExportOptions.plist
```

### 6. رفع لـ Firebase

```bash
firebase appdistribution:distribute build/ios/ipa/delegate_app.ipa \
  --app 1:564223619997:ios:6a342f9eb34ad80f233574 \
  --project practice-firebase-72df1
```

---

# الخلاصة

هذا الملف يحتوي على التوثيق الشامل لمشروع Delegate App، بما في ذلك:

- ✅ نظرة عامة على المشروع
- ✅ Firebase - البحث الشامل والتحليل المتقدم
- ✅ أمثلة أكواد عملية
- ✅ Cloud Functions - التقرير الكامل
- ✅ خطة الإصلاح والتحسينات
- ✅ دليل الـ AI Agents والـ Workflows
- ✅ نظام الإشعارات
- ✅ جميع الـ Workflows (16 workflow)

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**آخر تحديث:** 1 أبريل 2026  
**الحالة:** ✅ نشط وجاهز للاستخدام

