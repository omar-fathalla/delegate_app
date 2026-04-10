---
description: Add Arabic/English localization using flutter_localizations and .arb files with full RTL support.
---

# Add Localization (Arabic First)

## 1. Add dependencies

// turbo
```
flutter pub add flutter_localizations --sdk=flutter
flutter pub add intl
```

## 2. Enable generation in `pubspec.yaml`

Add under the `flutter:` section:

```yaml
flutter:
  generate: true
```

## 3. Create `l10n.yaml` config

Create `l10n.yaml` at the project root:

```yaml
arb-dir: lib/l10n
template-arb-file: app_ar.arb
output-localization-file: app_localizations.dart
output-class: AppLocalizations
```

## 4. Create ARB files

Create `lib/l10n/app_ar.arb` (Arabic — primary):

```json
{
  "@@locale": "ar",
  "appTitle": "تسهيل - المندوب",
  "login": "تسجيل الدخول",
  "logout": "تسجيل الخروج",
  "home": "الرئيسية",
  "profile": "الملف الشخصي",
  "attendance": "الحضور",
  "checkIn": "تسجيل الحضور",
  "checkOut": "تسجيل الانصراف",
  "requests": "الطلبات",
  "settings": "الإعدادات",
  "errorGeneral": "حدث خطأ. يرجى المحاولة مرة أخرى.",
  "errorNetwork": "لا يوجد اتصال بالإنترنت.",
  "errorLocation": "لم يتم العثور على موقعك.",
  "errorOutOfRange": "أنت خارج نطاق موقع العمل.",
  "errorMockLocation": "تم اكتشاف موقع وهمي. لا يمكن تسجيل الحضور.",
  "errorAuth": "بيانات الدخول غير صحيحة.",
  "success": "تمت العملية بنجاح",
  "loading": "جاري التحميل...",
  "offline": "أنت غير متصل بالإنترنت",
  "pendingSync": "في انتظار المزامنة"
}
```

Create `lib/l10n/app_en.arb` (English — secondary):

```json
{
  "@@locale": "en",
  "appTitle": "Tashil - Delegate",
  "login": "Login",
  "logout": "Logout",
  "home": "Home",
  "profile": "Profile",
  "attendance": "Attendance",
  "checkIn": "Check In",
  "checkOut": "Check Out",
  "requests": "Requests",
  "settings": "Settings",
  "errorGeneral": "An error occurred. Please try again.",
  "errorNetwork": "No internet connection.",
  "errorLocation": "Could not determine your location.",
  "errorOutOfRange": "You are outside the worksite range.",
  "errorMockLocation": "Mock location detected. Cannot check in.",
  "errorAuth": "Invalid credentials.",
  "success": "Operation completed successfully",
  "loading": "Loading...",
  "offline": "You are offline",
  "pendingSync": "Pending sync"
}
```

## 5. Configure MaterialApp

```dart
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_gen/gen_l10n/app_localizations.dart';

MaterialApp(
  locale: const Locale('ar'),  // Arabic first
  supportedLocales: const [
    Locale('ar'),
    Locale('en'),
  ],
  localizationsDelegates: const [
    AppLocalizations.delegate,
    GlobalMaterialLocalizations.delegate,
    GlobalWidgetsLocalizations.delegate,
    GlobalCupertinoLocalizations.delegate,
  ],
  // ...
)
```

## 6. Use in widgets

```dart
// Access localized strings
final l10n = AppLocalizations.of(context)!;
Text(l10n.checkIn);
Text(l10n.errorOutOfRange);
```

## 7. RTL Checklist

- ✅ `EdgeInsetsDirectional.only(start: 16)` — not `EdgeInsets.only(left: 16)`
- ✅ `AlignmentDirectional.centerStart` — not `Alignment.centerLeft`
- ✅ `TextAlign.start` — not `TextAlign.left`
- ✅ `CrossAxisAlignment.start` — not `CrossAxisAlignment.start` (same, but verify context)
- ✅ Icons with directional meaning use `Directionality` or mirrored icons

## 8. Adding a new localization key

1. Add the key to `lib/l10n/app_ar.arb` (Arabic first)
2. Add the same key to `lib/l10n/app_en.arb`
3. Run code generation:

// turbo
```
flutter gen-l10n
```

4. Use in code: `AppLocalizations.of(context)!.newKey`

## 9. Verify

// turbo
```
flutter analyze
```
