# تطبيق مندوبي تسهيل - Tashil Delegate App

تطبيق موبايل لإدارة حضور وانصراف المندوبين عبر مسح أكواد QR والتحقق من الموقع الجغرافي (Geofencing).

## التقنيات المستخدمة

- **Flutter 3.44.5** + Dart **3.12.2** (انظر `.fvmrc` و CI)
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

**تطوير أندرويد (tashil-dev):** بناء وتوزيع يدوي على Firebase App Distribution وبصمات SHA-1 لإعدادات Firebase — انظر [`android/README_DEV_FLAVOR.md`](android/README_DEV_FLAVOR.md).

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

## حسابات وهمية لبوابة الموارد البشرية على tashil-dev

Fake accounts for the HR / company-supervisor web build. The script only talks to Firebase project `tashil-dev`. It refuses `practice-firebase-72df1` and every other project, including when the credentials file or `GOOGLE_CLOUD_PROJECT` names a different project. The default is a dry run. `--apply` is the only mode that writes. Passwords are created at runtime and written only to `functions/scripts/.hr-web-fake-accounts.local.json` (gitignored). The script never prints them and never sends mail or SMS.

الحسابات وهمية لاختبار نسخة الويب لموارد البشرية ومشرف الشركة. السكربت يرفض أي مشروع غير `tashil-dev`، بما في ذلك الإنتاج `practice-firebase-72df1`، وحتى لو كانت بيانات الاعتماد تشير إلى مشروع آخر. الوضع الافتراضي عرض فقط. `--apply` هو الذي يكتب. كلمات السر تُنشأ وقت التشغيل وتُحفظ فقط في ملف محلي متجاهَل من git، ولا تُطبع ولا تُرسل.

```bash
cd functions
node scripts/hr-web-fake-accounts.js --project tashil-dev
node scripts/hr-web-fake-accounts.js --project tashil-dev --apply
node scripts/hr-web-fake-accounts.js --project tashil-dev --cleanup
node scripts/hr-web-fake-accounts.js --project tashil-dev --cleanup --apply
```

Re-running `--apply` updates the same documents and does not change passwords. `--rotate-passwords` replaces them. `--cleanup` deletes only documents this script tagged with `seedTag` `tashil-dev-hr-web-fake-v1` and `fake: true`, and only Auth users whose email is still the planned `@example.com` address.

إعادة التشغيل لا تغيّر كلمات السر. `--cleanup` يحذف فقط ما وسمه السكربت.

Web HR login is the fake phone plus the password from the local file. Company scoping uses organization `seed-fake-hr-org` and companies `seed-fake-co-alpha` / `seed-fake-co-beta`. Each company has four active delegates and one suspended delegate (`*.5`). Every HR account belongs to a company; `fake.nocompany@example.com` is a second HR user under `seed-fake-co-alpha`. Delegate national IDs are unique, clearly fake 14-digit ASCII values such as `00000000000101`.

تسجيل الدخول في بوابة الموارد البشرية: رقم الهاتف الوهمي ثم كلمة السر من الملف المحلي. لكل شركة أربعة مندوبين نشطين ومندوب موقوف (`*.5`). كل حساب موارد بشرية تابع لشركة؛ الحساب `fake.nocompany@example.com` موارد بشرية إضافي تحت `seed-fake-co-alpha`. أرقام الهوية القومية للمندوبين الوهميين 14 رقمًا إنجليزيًا واضحة أنها تجريبية.

| Role / الدور | Email | Phone | companyUID |
| --- | --- | --- | --- |
| super-admin / سوبر أدمن | fake.superadmin@example.com | 01000000001 | (none) |
| technical_support / دعم فني | fake.techsupport@example.com | 01000000002 | (none) |
| organization-admin / مسؤول المنظمة | fake.orgadmin@example.com | 01000000003 | (none) |
| hr / موارد بشرية ألف (حساب إضافي) | fake.nocompany@example.com | 01000000004 | seed-fake-co-alpha |
| supervisor / مشرف الشركة ألف | fake.supervisor.alpha@example.com | 01000000005 | seed-fake-co-alpha |
| hr / موارد بشرية ألف | fake.hr.alpha@example.com | 01000000006 | seed-fake-co-alpha |
| marketing / تسويق فرع ألف | fake.marketing.alpha@example.com | 01000000007 | seed-fake-co-alpha |
| branches_marketing / مسؤول تسويق الفروع ألف | fake.branches-marketing.alpha@example.com | 01000000008 | seed-fake-co-alpha |
| delegate active / مندوب نشط | fake.delegate.alpha.1@example.com | 01000000009 | seed-fake-co-alpha |
| delegate active / مندوب نشط | fake.delegate.alpha.2@example.com | 01000000010 | seed-fake-co-alpha |
| delegate active / مندوب نشط | fake.delegate.alpha.3@example.com | 01000000011 | seed-fake-co-alpha |
| delegate active / مندوب نشط | fake.delegate.alpha.4@example.com | 01000000012 | seed-fake-co-alpha |
| delegate suspended / مندوب موقوف | fake.delegate.alpha.5@example.com | 01000000013 | seed-fake-co-alpha |
| supervisor / مشرف الشركة باء | fake.supervisor.beta@example.com | 01000000014 | seed-fake-co-beta |
| hr / موارد بشرية باء | fake.hr.beta@example.com | 01000000015 | seed-fake-co-beta |
| marketing / تسويق فرع باء | fake.marketing.beta@example.com | 01000000016 | seed-fake-co-beta |
| branches_marketing / مسؤول تسويق الفروع باء | fake.branches-marketing.beta@example.com | 01000000017 | seed-fake-co-beta |
| delegate active / مندوب نشط | fake.delegate.beta.1@example.com | 01000000018 | seed-fake-co-beta |
| delegate active / مندوب نشط | fake.delegate.beta.2@example.com | 01000000019 | seed-fake-co-beta |
| delegate active / مندوب نشط | fake.delegate.beta.3@example.com | 01000000020 | seed-fake-co-beta |
| delegate active / مندوب نشط | fake.delegate.beta.4@example.com | 01000000021 | seed-fake-co-beta |
| delegate suspended / مندوب موقوف | fake.delegate.beta.5@example.com | 01000000022 | seed-fake-co-beta |

Phones are a fake `01000000xxx` block, not real numbers. More detail: [`functions/scripts/README-hr-web-fake-accounts.md`](functions/scripts/README-hr-web-fake-accounts.md).

أرقام الهاتف من نطاق وهمي `01000000xxx` وليست أرقامًا حقيقية.
