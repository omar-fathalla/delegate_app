# 🔐 دليل ضبط التوقيع الرقمي (Signing) لـ iOS

**التاريخ:** 2 أبريل 2026  
**Team ID:** TX5G7GZL6T  
**Bundle ID:** io.flutter.delegate_app

---

## 📋 ما هو الـ Signing؟

الـ Signing هو "التوقيع الرقمي" اللي بيعرف أبل إنك أنت المطور الحقيقي للتطبيق.

### مكونات الـ Signing:
1. **Certificate** - شهادة المطور (بتثبت إنك أنت)
2. **Provisioning Profile** - ملف التصريح (بيربط التطبيق بالشهادة)
3. **Private Key** - المفتاح الخاص (موجود في Keychain)

---

## 🎯 الخطوة 1: إنشاء Certificate (الشهادة)

### A. إنشاء Certificate Signing Request (CSR)

1. افتح **Keychain Access** على Mac
2. من القائمة: **Keychain Access** → **Certificate Assistant** → **Request a Certificate from a Certificate Authority**
3. املأ البيانات:
   - **User Email Address:** بريدك الإلكتروني
   - **Common Name:** اسمك أو اسم الشركة
   - **CA Email Address:** اتركه فارغ
   - **Request is:** اختر **Saved to disk**
4. احفظ الملف: `CertificateSigningRequest.certSigningRequest`

### B. إنشاء Distribution Certificate

1. افتح: https://developer.apple.com/account/resources/certificates/list
2. اضغط **+** (Create a new certificate)
3. اختر **Apple Distribution**
4. ارفع ملف CSR اللي عملته
5. اضغط **Continue**
6. حمّل الـ Certificate: `distribution.cer`
7. اضغط مرتين على الملف لتثبيته في Keychain

### C. التحقق من التثبيت

افتح **Keychain Access** وابحث عن:
```
Apple Distribution: Your Name (TX5G7GZL6T)
```

يجب أن يكون معاه مفتاح خاص (🔑):
```
▼ Apple Distribution: Your Name (TX5G7GZL6T)
  🔑 Private Key
```

---

## 📱 الخطوة 2: إنشاء App ID

### A. تسجيل App ID

1. افتح: https://developer.apple.com/account/resources/identifiers/list
2. اضغط **+** (Register a new identifier)
3. اختر **App IDs** → **Continue**
4. اختر **App** → **Continue**
5. املأ البيانات:
   - **Description:** Tasheel Delegate App
   - **Bundle ID:** اختر **Explicit**
   - **Bundle ID:** `io.flutter.delegate_app`
6. **Capabilities:** اختر ما تحتاجه:
   - ✅ Push Notifications
   - ✅ Sign in with Apple (إذا كنت تستخدمه)
   - ✅ Associated Domains (إذا كنت تستخدمه)
7. اضغط **Continue** → **Register**

---

## 🎫 الخطوة 3: إنشاء Provisioning Profile

### A. App Store Profile (للنشر)

1. افتح: https://developer.apple.com/account/resources/profiles/list
2. اضغط **+** (Generate a profile)
3. اختر **App Store** → **Continue**
4. اختر App ID: `io.flutter.delegate_app` → **Continue**
5. اختر Certificate: `Apple Distribution: Your Name` → **Continue**
6. اكتب اسم: `Tasheel Delegate App Store` → **Generate**
7. حمّل الملف: `Tasheel_Delegate_App_Store.mobileprovision`
8. اضغط مرتين على الملف لتثبيته

### B. Development Profile (للتطوير - اختياري)

1. نفس الخطوات لكن اختر **iOS App Development**
2. اختر الأجهزة اللي هتختبر عليها
3. اسم: `Tasheel Delegate Development`

---

## 🔧 الخطوة 4: ضبط Xcode Project

### A. فتح المشروع

```bash
cd ios
open Runner.xcworkspace
```

### B. ضبط Signing في Xcode

1. اختر **Runner** من الـ Project Navigator
2. اختر **Target: Runner**
3. اذهب لـ **Signing & Capabilities**

#### للـ Debug (التطوير):
```
✅ Automatically manage signing
Team: Your Team (TX5G7GZL6T)
```

#### للـ Release (النشر):
```
❌ Automatically manage signing (أوقفه)
Provisioning Profile: Tasheel Delegate App Store
Signing Certificate: Apple Distribution: Your Name (TX5G7GZL6T)
```

### C. التحقق من Bundle ID

تأكد أن:
```
Bundle Identifier: io.flutter.delegate_app
```

---

## 📦 الخطوة 5: تصدير Certificate للـ CI/CD

### A. تصدير من Keychain

1. افتح **Keychain Access**
2. ابحث عن: `Apple Distribution: Your Name (TX5G7GZL6T)`
3. كليك يمين → **Export "Apple Distribution: Your Name"**
4. احفظ كـ: `certificate.p12`
5. اختر كلمة مرور قوية (مثال: `MySecurePassword123!`)
6. احفظ كلمة المرور في مكان آمن

### B. تحويل لـ Base64

```bash
# تحويل Certificate
base64 -i certificate.p12 -o certificate_base64.txt

# تحويل Provisioning Profile
base64 -i Tasheel_Delegate_App_Store.mobileprovision -o profile_base64.txt
```

---

## 🔑 الخطوة 6: إنشاء App Store Connect API Key

### A. إنشاء API Key

1. افتح: https://appstoreconnect.apple.com/access/api
2. اضغط **+** (Generate API Key)
3. املأ:
   - **Name:** GitHub Actions Deploy
   - **Access:** App Manager
4. اضغط **Generate**
5. احفظ:
   - ✅ **Key ID** (مثال: `ABC123XYZ`)
   - ✅ **Issuer ID** (UUID طويل)
6. حمّل ملف `.p8` (مرة واحدة فقط!)

### B. تحويل API Key لـ Base64

```bash
base64 -i AuthKey_ABC123XYZ.p8 -o api_key_base64.txt
```

---

## 🔐 الخطوة 7: إضافة Secrets في GitHub

### A. افتح GitHub Secrets

https://github.com/omar-fathalla/delegate_app/settings/secrets/actions

### B. أضف الـ Secrets التالية

| Secret Name | القيمة | كيف تحصل عليها |
|-------------|--------|----------------|
| `IOS_CERTIFICATE_BASE64` | محتوى `certificate_base64.txt` | من الخطوة 5B |
| `IOS_CERTIFICATE_PASSWORD` | كلمة مرور P12 | اللي اخترتها في الخطوة 5A |
| `IOS_PROVISIONING_PROFILE_BASE64` | محتوى `profile_base64.txt` | من الخطوة 5B |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID | من الخطوة 6A |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID | من الخطوة 6A |
| `APP_STORE_CONNECT_API_KEY_BASE64` | محتوى `api_key_base64.txt` | من الخطوة 6B |
| `KEYCHAIN_PASSWORD` | أي كلمة مرور قوية | اختر واحدة جديدة |

### C. كيفية إضافة Secret

1. اضغط **New repository secret**
2. **Name:** اسم الـ Secret (مثال: `IOS_CERTIFICATE_BASE64`)
3. **Value:** القيمة (انسخ من الملف)
4. اضغط **Add secret**
5. كرر لكل الـ 7 secrets

---

## 🧪 الخطوة 8: اختبار الـ Signing محلياً

### A. بناء IPA محلياً

```bash
# 1. نظف المشروع
flutter clean
flutter pub get

# 2. بناء iOS
cd ios
pod install
cd ..

flutter build ios --release

# 3. Archive
cd ios
xcodebuild -workspace Runner.xcworkspace \
  -scheme Runner \
  -sdk iphoneos \
  -configuration Release \
  -archivePath $PWD/build/Runner.xcarchive \
  archive \
  -allowProvisioningUpdates \
  DEVELOPMENT_TEAM=TX5G7GZL6T

# 4. Export IPA
xcodebuild -exportArchive \
  -archivePath $PWD/build/Runner.xcarchive \
  -exportPath $PWD/build \
  -exportOptionsPlist ExportOptions.plist
```

### B. التحقق من النجاح

إذا نجح، ستجد:
```
ios/build/Runner.ipa
```

---

## 📝 الخطوة 9: تحديث ExportOptions.plist

تأكد من أن الملف `ios/ExportOptions.plist` يحتوي على:

```xml
<?xml version="1.0" encoding="UTF-8"?>
<!DOCTYPE plist PUBLIC "-//Apple//DTD PLIST 1.0//EN" "http://www.apple.com/DTDs/PropertyList-1.0.dtd">
<plist version="1.0">
<dict>
    <key>method</key>
    <string>app-store</string>
    <key>teamID</key>
    <string>TX5G7GZL6T</string>
    <key>uploadBitcode</key>
    <false/>
    <key>uploadSymbols</key>
    <true/>
    <key>compileBitcode</key>
    <false/>
    <key>signingStyle</key>
    <string>manual</string>
    <key>provisioningProfiles</key>
    <dict>
        <key>io.flutter.delegate_app</key>
        <string>Tasheel Delegate App Store</string>
    </dict>
</dict>
</plist>
```

---

## 🚀 الخطوة 10: اختبار GitHub Actions

### A. Push للـ main branch

```bash
git add .
git commit -m "Setup iOS signing"
git push origin main
```

### B. مراقبة الـ Workflow

1. افتح: https://github.com/omar-fathalla/delegate_app/actions
2. اضغط على آخر workflow run
3. راقب الخطوات

---

## 🐛 حل المشاكل الشائعة

### 1. "No valid code signing identity found"

**السبب:** Certificate غير مثبت أو Private Key مفقود

**الحل:**
```bash
# تحقق من الـ Certificates
security find-identity -v -p codesigning

# يجب أن ترى:
# 1) ABC123... "Apple Distribution: Your Name (TX5G7GZL6T)"
```

### 2. "Provisioning profile doesn't match"

**السبب:** Bundle ID أو Team ID غير متطابق

**الحل:**
- تأكد من Bundle ID: `io.flutter.delegate_app`
- تأكد من Team ID: `TX5G7GZL6T`
- حمّل Provisioning Profile من جديد

### 3. "Private key not found in keychain"

**السبب:** تم تصدير Certificate بدون Private Key

**الحل:**
1. في Keychain، تأكد من وجود 🔑 تحت Certificate
2. إذا مفقود، احذف Certificate وأعد إنشاءه من البداية

### 4. "API authentication failed"

**السبب:** API Key غير صحيح

**الحل:**
- تأكد من Key ID صحيح
- تأكد من Issuer ID صحيح
- تأكد من Base64 صحيح (بدون مسافات أو أسطر جديدة)

### 5. "Certificate expired"

**السبب:** Certificate انتهت صلاحيته (سنة واحدة)

**الحل:**
- أعد إنشاء Certificate جديد
- حدّث Provisioning Profile
- حدّث GitHub Secrets

---

## 📊 ملخص الملفات المطلوبة

```
📁 Signing Files
├── 📄 certificate.p12 (من Keychain)
├── 📄 Tasheel_Delegate_App_Store.mobileprovision (من developer.apple.com)
├── 📄 AuthKey_ABC123XYZ.p8 (من App Store Connect)
└── 📄 ExportOptions.plist (في المشروع)

📁 Base64 Files (للـ GitHub)
├── 📄 certificate_base64.txt
├── 📄 profile_base64.txt
└── 📄 api_key_base64.txt
```

---

## ✅ قائمة التحقق النهائية

### قبل البناء
- [ ] Certificate مثبت في Keychain
- [ ] Private Key موجود مع Certificate
- [ ] Provisioning Profile مثبت
- [ ] Bundle ID صحيح: `io.flutter.delegate_app`
- [ ] Team ID صحيح: `TX5G7GZL6T`
- [ ] ExportOptions.plist محدّث

### للـ CI/CD
- [ ] Certificate تم تصديره كـ P12
- [ ] جميع الملفات تم تحويلها لـ Base64
- [ ] 7 Secrets تم إضافتها في GitHub
- [ ] Workflow file موجود

### الاختبار
- [ ] بناء محلي نجح
- [ ] IPA تم إنشاؤه
- [ ] GitHub Actions نجح
- [ ] Build ظهر في TestFlight

---

## 🎓 نصائح مهمة

### 1. احتفظ بنسخة احتياطية
```bash
# احفظ جميع الملفات في مكان آمن
mkdir ~/ios_signing_backup
cp certificate.p12 ~/ios_signing_backup/
cp *.mobileprovision ~/ios_signing_backup/
cp AuthKey_*.p8 ~/ios_signing_backup/
```

### 2. لا تشارك الملفات
- ❌ لا ترفع P12 على GitHub
- ❌ لا تشارك API Key
- ❌ لا تشارك كلمات المرور
- ✅ استخدم GitHub Secrets فقط

### 3. جدد قبل الانتهاء
- Certificate: صالح لمدة سنة
- Provisioning Profile: صالح لمدة سنة
- API Key: لا ينتهي (لكن يمكن إلغاؤه)

---

## 🎉 النتيجة النهائية

بعد اتباع هذه الخطوات:

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ✅ Signing مضبوط بالكامل                                  │
│  ✅ يمكنك البناء محلياً                                    │
│  ✅ يمكنك الرفع لـ TestFlight                               │
│  ✅ GitHub Actions يعمل تلقائياً                            │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026  
**Team ID:** TX5G7GZL6T  
**Bundle ID:** io.flutter.delegate_app
