# 🍎 دليل نشر التطبيق على App Store

**التاريخ:** 2 أبريل 2026  
**Team ID:** TX5G7GZL6T

---

## 📋 المتطلبات الأساسية

### 1. حساب Apple Developer
- ✅ حساب Apple Developer نشط ($99/سنة)
- ✅ Team ID: `TX5G7GZL6T`
- ✅ Bundle ID: `io.flutter.delegate_app`

---

## 🔐 الخطوة 1: إنشاء App Store Connect API Key

1. افتح: https://appstoreconnect.apple.com/access/api
2. اضغط **+** (Generate API Key)
3. املأ:
   - **Name:** GitHub Actions Deploy
   - **Access:** App Manager
4. احفظ:
   - ✅ **Key ID** (مثال: `ABC123XYZ`)
   - ✅ **Issuer ID** (UUID)
   - ✅ **Download** ملف `.p8`

---

## 🔑 الخطوة 2: إعداد GitHub Secrets

افتح: https://github.com/omar-fathalla/delegate_app/settings/secrets/actions

### A. تحويل الملفات لـ Base64

```bash
# 1. Certificate
base64 -i certificate.p12 -o cert_base64.txt

# 2. Provisioning Profile
base64 -i profile.mobileprovision -o profile_base64.txt

# 3. API Key
base64 -i AuthKey_ABC123XYZ.p8 -o api_key_base64.txt
```

### B. إضافة Secrets

| Secret Name | القيمة |
|-------------|--------|
| `IOS_CERTIFICATE_BASE64` | محتوى cert_base64.txt |
| `IOS_CERTIFICATE_PASSWORD` | كلمة مرور P12 |
| `IOS_PROVISIONING_PROFILE_BASE64` | محتوى profile_base64.txt |
| `APP_STORE_CONNECT_API_KEY_ID` | Key ID |
| `APP_STORE_CONNECT_API_ISSUER_ID` | Issuer ID |
| `APP_STORE_CONNECT_API_KEY_BASE64` | محتوى api_key_base64.txt |
| `KEYCHAIN_PASSWORD` | أي كلمة مرور |

---

## 🚀 الخطوة 3: Push والنشر

```bash
git add .
git commit -m "Setup iOS deployment"
git push origin main
```

راقب: https://github.com/omar-fathalla/delegate_app/actions

---

## ✅ النتيجة

- ✅ كل push للـ main = build جديد على TestFlight
- ✅ نشر تلقائي بدون تدخل يدوي

---

**للتفاصيل الكاملة:** راجع الملف الكامل في المشروع
غير مفعّل