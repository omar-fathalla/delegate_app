# ✅ التحقق من ربط GitHub Secrets

**الحالة:** جاهز للتحقق

---

## 🔍 كيف تتحقق أن الـ Secrets مربوطة صح؟

### الخطوة 1: تحقق من وجود Secrets في GitHub

1. افتح: https://github.com/omar-fathalla/delegate_app/settings/secrets/actions

2. يجب أن ترى **7 Secrets للـ iOS:**

```
✅ IOS_CERTIFICATE_BASE64
✅ IOS_CERTIFICATE_PASSWORD
✅ IOS_PROVISIONING_PROFILE_BASE64
✅ APP_STORE_CONNECT_API_KEY_ID
✅ APP_STORE_CONNECT_API_ISSUER_ID
✅ APP_STORE_CONNECT_API_KEY_BASE64
✅ KEYCHAIN_PASSWORD
```

**ملاحظة:** GitHub لا يعرض قيم الـ Secrets (للأمان)، فقط الأسماء.

---

### الخطوة 2: تحقق من ربط Secrets في Workflow

الـ workflow يستخدم الـ Secrets في 3 أماكن:

#### A. Import Certificates (خطوة 7)
```yaml
env:
  CERTIFICATE_BASE64: ${{ secrets.IOS_CERTIFICATE_BASE64 }}
  P12_PASSWORD: ${{ secrets.IOS_CERTIFICATE_PASSWORD }}
  KEYCHAIN_PASSWORD: ${{ secrets.KEYCHAIN_PASSWORD }}
```

✅ **مربوط صح** - يستخدم 3 secrets

#### B. Import Provisioning Profile (خطوة 8)
```yaml
env:
  PROVISIONING_PROFILE_BASE64: ${{ secrets.IOS_PROVISIONING_PROFILE_BASE64 }}
```

✅ **مربوط صح** - يستخدم 1 secret

#### C. Upload to TestFlight (خطوة 11)
```yaml
env:
  APP_STORE_CONNECT_API_KEY_ID: ${{ secrets.APP_STORE_CONNECT_API_KEY_ID }}
  APP_STORE_CONNECT_API_ISSUER_ID: ${{ secrets.APP_STORE_CONNECT_API_ISSUER_ID }}
  APP_STORE_CONNECT_API_KEY_BASE64: ${{ secrets.APP_STORE_CONNECT_API_KEY_BASE64 }}
```

✅ **مربوط صح** - يستخدم 3 secrets

**الإجمالي:** 7 secrets ✅

---

## 🧪 اختبار الربط

### الطريقة 1: Push للـ main branch

```bash
git push origin main
```

**النتيجة المتوقعة:**

```
┌─────────────────────────────────────────────────────────────┐
│ GitHub Actions - Deploy iOS to App Store                   │
├─────────────────────────────────────────────────────────────┤
│                                                             │
│ ✅ Checkout code                                            │
│ ✅ Setup Flutter                                            │
│ ✅ Install dependencies                                     │
│ ✅ Run tests                                                │
│ ✅ Setup Xcode                                              │
│ ✅ Install CocoaPods                                        │
│ ✅ Import certificates                                      │
│    ✅ Create keychain                                       │
│    ✅ Import certificate.p12                                │
│    ✅ Set key partition list                                │
│ ✅ Import provisioning profile                              │
│    ✅ Create Provisioning Profiles directory                │
│    ✅ Decode and save profile                               │
│ ✅ Build iOS                                                │
│    ✅ flutter build ios --release --no-codesign             │
│    ✅ xcodebuild archive                                    │
│ ✅ Export IPA                                               │
│    ✅ xcodebuild -exportArchive                             │
│ ✅ Upload to TestFlight                                     │
│    ✅ Decode API Key                                        │
│    ✅ xcrun altool --upload-app                             │
│ ✅ Upload IPA artifact                                      │
│                                                             │
│ ✅ Workflow completed successfully!                         │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

### الطريقة 2: Manual Trigger (اختبار يدوي)

1. افتح: https://github.com/omar-fathalla/delegate_app/actions
2. اختر **Deploy iOS to App Store**
3. اضغط **Run workflow**
4. اختر branch: `main`
5. اضغط **Run workflow**

**الفائدة:** يمكنك اختبار الـ workflow بدون push

---

## 🔍 كيف تعرف إذا Secrets صحيحة؟

### إذا كانت Secrets صحيحة:

```
✅ Import certificates
   Creating keychain...
   Importing certificate...
   Certificate imported successfully
   
✅ Import provisioning profile
   Provisioning profile saved
   
✅ Upload to TestFlight
   Uploading to App Store Connect...
   Upload successful
```

### إذا كانت Secrets خاطئة:

```
❌ Import certificates
   Error: Unable to decode certificate
   أو
   Error: Invalid password for certificate
   
❌ Import provisioning profile
   Error: Unable to decode provisioning profile
   
❌ Upload to TestFlight
   Error: Invalid API Key
   أو
   Error: Authentication failed
```

---

## 🐛 حل المشاكل

### مشكلة 1: Certificate Base64 خاطئ

**الخطأ:**
```
Error: Unable to decode certificate
```

**الحل:**
```bash
# تأكد من التحويل الصحيح
base64 -i certificate.p12 -o certificate_base64.txt

# انسخ المحتوى بالكامل (بدون مسافات أو أسطر جديدة)
cat certificate_base64.txt | tr -d '\n' | pbcopy

# الصق في GitHub Secret
```

---

### مشكلة 2: Certificate Password خاطئ

**الخطأ:**
```
Error: Invalid password for certificate
```

**الحل:**
- تأكد من كلمة المرور اللي اخترتها عند تصدير P12
- جرب تصدير P12 من جديد بكلمة مرور جديدة

---

### مشكلة 3: Provisioning Profile خاطئ

**الخطأ:**
```
Error: Provisioning profile doesn't match
```

**الحل:**
- تأكد من Bundle ID: `io.flutter.delegate_app`
- تأكد من Team ID: `TX5G7GZL6T`
- حمّل Provisioning Profile من جديد

---

### مشكلة 4: API Key خاطئ

**الخطأ:**
```
Error: Authentication failed
```

**الحل:**
- تأكد من Key ID صحيح
- تأكد من Issuer ID صحيح
- تأكد من Base64 صحيح (بدون مسافات)

---

## 📊 قائمة التحقق النهائية

### قبل Push

- [ ] ✅ 7 Secrets موجودة في GitHub
- [ ] ✅ Workflow file موجود: `.github/workflows/deploy-ios.yml`
- [ ] ✅ ExportOptions.plist محدّث
- [ ] ✅ Bundle ID صحيح: `io.flutter.delegate_app`
- [ ] ✅ Team ID صحيح: `TX5G7GZL6T`

### بعد Push

- [ ] ✅ Workflow بدأ تلقائياً
- [ ] ✅ Import certificates نجح
- [ ] ✅ Import provisioning profile نجح
- [ ] ✅ Build iOS نجح
- [ ] ✅ Export IPA نجح
- [ ] ✅ Upload to TestFlight نجح

---

## 🎯 الخطوة التالية

### إذا كانت Secrets صحيحة:

```bash
# Push للـ main branch
git push origin main

# راقب GitHub Actions
# https://github.com/omar-fathalla/delegate_app/actions
```

**النتيجة المتوقعة:**
- ✅ Android workflow سيعمل
- ✅ iOS workflow سيعمل
- ✅ Build على TestFlight

---

### إذا كانت Secrets خاطئة:

1. راجع الأخطاء في GitHub Actions
2. صحح الـ Secret الخاطئ
3. Push مرة أخرى (أو استخدم Manual Trigger)

---

## 💡 نصائح مهمة

### 1. Base64 بدون مسافات

```bash
# ✅ صحيح
cat file.p12 | base64 | tr -d '\n' > output.txt

# ❌ خطأ (يحتوي على أسطر جديدة)
base64 -i file.p12 -o output.txt
```

### 2. نسخ من Terminal

```bash
# macOS
cat output.txt | pbcopy

# Linux
cat output.txt | xclip -selection clipboard
```

### 3. التحقق من Base64

```bash
# تحقق من أن الملف يمكن فك تشفيره
cat certificate_base64.txt | base64 --decode > test.p12

# إذا نجح، الـ Base64 صحيح
# إذا فشل، أعد التحويل
```

---

## ✅ الخلاصة

```
┌─────────────────────────────────────────────────────────────┐
│                                                             │
│  ✅ Workflow مربوط بـ 7 Secrets                            │
│  ✅ جميع الخطوات تستخدم Secrets الصحيحة                   │
│  ✅ جاهز للـ Push والاختبار                                │
│                                                             │
│  الخطوة التالية:                                           │
│  git push origin main                                       │
│                                                             │
└─────────────────────────────────────────────────────────────┘
```

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026

