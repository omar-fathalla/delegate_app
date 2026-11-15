# تطبيق مندوبي تسهيل - Tashil Delegate App

تطبيق موبايل لإدارة حضور وانصراف المندوبين عبر مسح أكواد QR والتحقق من الموقع الجغرافي (Geofencing).

## التقنيات المستخدمة

- **Flutter 3.44.5** + Dart 3.11 (انظر `.fvmrc` و CI)
- **Firebase:** Firestore, Authentication, Storage
- **البنية:** Clean Architecture + BLoC + GetIt (DI)
- **المنصات:** Android, iOS, Web, macOS
- **اللغات:** العربية + الإنجليزية

## الميزات الرئيسية

- تسجيل الحضور والانصراف عبر QR Code
- التحقق من الموقع الجغرافي (Geofencing)
- دعم العمل بدون اتصال (Offline-First)
- لوحة إدارة الفروع مع خرائط Google
- دعم الوضع الداكن وMaterial Design 3
- نظام أدوار (مندوب / مشرف / مسؤول)

## التشغيل

**Flutter:** 3.44.5 (نفس نسخة CI — `.fvmrc` و `.github/workflows/ci.yml`).

```bash
# اختياري: fvm install && fvm use   # يقرأ .fvmrc

# تثبيت التبعيات
flutter pub get

# توليد الملفات (freezed, json_serializable)
dart run build_runner build --delete-conflicting-outputs
```

### أندرويد / iOS — flavors إلزامية

| الهدف | الأمر |
|--------|--------|
| إنتاج (متجر) | `flutter run --flavor prod` |
| تطوير (tashil-dev) | `flutter run --flavor dev --dart-define=ENV=dev` |

بدون `--flavor` يفشل بناء أندرويد برسالة واضحة من Gradle. التفاصيل: `docs/DEV_WORKFLOW_RULES_AR.md`.

### ويب / تشغيل مع بيانات Admin

```bash
flutter run -d chrome \
  --dart-define=ADMIN_PHONE=رقم_الموبايل \
  --dart-define=ADMIN_PASSWORD=كلمة_المرور
```

إعدادات VS Code: `.vscode/launch.json` (prod / dev).

## الاختبارات

```bash
flutter test
```

## هيكل المشروع

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

## متغيرات البيئة

| المتغير | الوصف |
|---------|-------|
| `ADMIN_PHONE` | رقم هاتف المسؤول |
| `ADMIN_PASSWORD` | كلمة مرور المسؤول |

يتم تمريرها عبر `--dart-define` عند البناء.
