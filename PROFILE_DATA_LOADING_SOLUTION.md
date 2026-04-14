# 🔧 حل مشكلة عدم تحميل بيانات المستخدم من Firebase

**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ تم تحديد الحل والبدء في التنفيذ  
**المشكلة:** بيانات المستخدم الشخصية تظهر "غير محدد" في صفحة الملف الشخصي

---

## 🎯 تحليل المشكلة

### السبب الجذري

البيانات الشخصية لا تُحمل من Firebase لأن:

1. **ProfileScreen** يتلقى كائن `Delegate` من `MainScreen`
2. هذا الكائن يأتي من عملية تسجيل الدخول (Login)
3. بيانات تسجيل الدخول قد لا تحتوي على جميع التفاصيل الشخصية
4. **ProfileScreen** لا يقوم بتحميل البيانات الكاملة من Firebase

### المسار الحالي (خاطئ)

```
Login → AuthBloc → Delegate Object (بيانات أساسية فقط)
                        ↓
                   MainScreen
                        ↓
                   ProfileScreen (عرض البيانات الناقصة)
```

### المسار الصحيح (الحل)

```
Login → AuthBloc → Delegate Object (بيانات أساسية)
                        ↓
                   MainScreen
                        ↓
                   ProfileScreen
                        ↓
                   ProfileBloc (تحميل البيانات الكاملة من Firebase)
                        ↓
                   Firebase (جلب البيانات الكاملة)
```

---

## ✅ الحل

### الخطوة 1: استخدام ProfileBloc في ProfileScreen

**الملف:** `lib/features/profile/presentation/pages/profile_screen.dart`

**التغيير:**
- تحويل `ProfileScreen` من `StatelessWidget` إلى `StatefulWidget`
- إضافة `ProfileBloc` لتحميل البيانات الكاملة
- عرض حالة التحميل أثناء جلب البيانات
- عرض البيانات الكاملة بعد التحميل

### الخطوة 2: تحديث MainScreen

**الملف:** `lib/features/home/presentation/pages/main_screen.dart`

**التغيير:**
- تسجيل `ProfileBloc` في DI عند الحاجة
- تمرير `uid` المستخدم إلى `ProfileScreen`

### الخطوة 3: التحقق من Firestore Rules

**الملف:** `firestore.rules`

**التحقق:**
- ✅ القراءة مسموحة للمستخدمين المصادقين
- ✅ المسار الصحيح: `organizations/{orgId}/companies/{compId}/delegates/{uid}`

---

## 🔍 التفاصيل التقنية

### ProfileBloc الموجود

```dart
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetDelegateProfile getDelegateProfile;

  ProfileBloc({required this.getDelegateProfile}) : super(ProfileInitial()) {
    on<LoadProfile>(_onLoadProfile);
  }

  Future<void> _onLoadProfile(
    LoadProfile event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());
    final result = await getDelegateProfile(
      GetDelegateProfileParams(uid: event.uid),
    );
    result.fold(
      (failure) => emit(ProfileError(message: failure.message)),
      (delegate) => emit(ProfileLoaded(delegate: delegate)),
    );
  }
}
```

### GetDelegateProfile UseCase

```dart
// يقوم بـ:
// 1. جلب بيانات المستخدم من users collection
// 2. التحقق من أن المستخدم delegate
// 3. الحصول على organizationUID و companyUID
// 4. جلب البيانات الكاملة من organizations/{orgId}/companies/{compId}/delegates/{uid}
```

### ProfileRemoteDataSource

```dart
// يقوم بـ:
// 1. الاتصال بـ Firestore
// 2. جلب البيانات من المسار الصحيح
// 3. تحويل البيانات إلى DelegateModel
```

---

## 📋 خطوات التنفيذ

### 1. تحديث ProfileScreen

```dart
// من StatelessWidget إلى StatefulWidget
class ProfileScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showBackButton;

  const ProfileScreen({
    super.key,
    required this.delegate,
    this.showBackButton = false,
  });

  @override
  State<ProfileScreen> createState() => _ProfileScreenState();
}

class _ProfileScreenState extends State<ProfileScreen> {
  @override
  void initState() {
    super.initState();
    // تحميل البيانات الكاملة من Firebase
    context.read<ProfileBloc>().add(LoadProfile(uid: widget.delegate.uid));
  }

  @override
  Widget build(BuildContext context) {
    return BlocBuilder<ProfileBloc, ProfileState>(
      builder: (context, state) {
        if (state is ProfileLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is ProfileError) {
          return Center(child: Text('خطأ: ${state.message}'));
        } else if (state is ProfileLoaded) {
          // عرض البيانات الكاملة
          return _buildProfileContent(state.delegate);
        }
        return _buildProfileContent(widget.delegate);
      },
    );
  }
}
```

### 2. تسجيل ProfileBloc في DI

```dart
// في injection_container.dart
sl.registerFactory(() => ProfileBloc(getDelegateProfile: sl()));
```

### 3. تحديث MainScreen

```dart
// إضافة ProfileBloc عند الحاجة
BlocProvider(
  create: (_) => di.sl<ProfileBloc>(),
  child: ProfileScreen(delegate: delegate),
)
```

---

## 🧪 الاختبار

### اختبار 1: التحقق من تحميل البيانات

1. سجل دخول كمندوب
2. اذهب إلى صفحة الملف الشخصي
3. تحقق من ظهور جميع البيانات:
   - ✅ الاسم الكامل
   - ✅ رقم الهوية الوطنية
   - ✅ اسم الأم
   - ✅ رقم الموبايل
   - ✅ تاريخ الميلاد
   - ✅ المدينة
   - ✅ المنظمة
   - ✅ الشركة

### اختبار 2: التحقق من معالجة الأخطاء

1. قطع الاتصال بالإنترنت
2. اذهب إلى صفحة الملف الشخصي
3. تحقق من ظهور رسالة خطأ مناسبة

### اختبار 3: التحقق من حالة التحميل

1. سجل دخول كمندوب
2. اذهب إلى صفحة الملف الشخصي
3. تحقق من ظهور مؤشر التحميل أثناء جلب البيانات

---

## 🔐 التحقق من Firestore Rules

### القاعدة الحالية

```javascript
match /organizations/{orgId}/companies/{compId}/delegates/{delegateId} {
  // Read: All authenticated users + marketing (read-only)
  allow read: if isAuthenticated();

  // Write: Company admins and org admins only (no marketing write access)
  allow create: if isAuthenticated() && canAccessCompany(orgId, compId);
  allow update: if isAuthenticated() && canAccessCompany(orgId, compId);
  allow delete: if isAuthenticated() && canAccessCompany(orgId, compId);
}
```

### التحقق

✅ القراءة مسموحة للمستخدمين المصادقين  
✅ المسار صحيح  
✅ لا توجد قيود تمنع القراءة

---

## 📊 الملفات المتأثرة

| الملف | التغيير | الأولوية |
|------|---------|---------|
| `lib/features/profile/presentation/pages/profile_screen.dart` | تحديث لاستخدام ProfileBloc | 🔴 عالية |
| `lib/features/home/presentation/pages/main_screen.dart` | إضافة ProfileBloc | 🟡 متوسطة |
| `lib/injection_container.dart` | تسجيل ProfileBloc | 🟡 متوسطة |

---

## ✨ الفوائد

### للمستخدم
- ✅ عرض البيانات الشخصية الكاملة
- ✅ تحديث البيانات من Firebase
- ✅ رسائل خطأ واضحة عند الفشل

### للمطور
- ✅ استخدام BLoC Pattern
- ✅ فصل المنطق عن الواجهة
- ✅ سهولة الاختبار والصيانة

---

## 🚀 الخطوات التالية

1. ✅ تحديث ProfileScreen لاستخدام ProfileBloc
2. ✅ تسجيل ProfileBloc في DI
3. ✅ تحديث MainScreen
4. ✅ الاختبار الشامل
5. ✅ التحقق من Firestore Rules

---

**تم إنشاء هذا الملف بواسطة:** Kiro AI Assistant  
**التاريخ:** 12 أبريل 2026  
**الحالة:** ✅ جاهز للتنفيذ

