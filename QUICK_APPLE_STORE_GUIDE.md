# ⚡ دليل سريع - النشر على App Store

## 🎯 الخطوات (5 دقائق)

### 1️⃣ إنشاء API Key
https://appstoreconnect.apple.com/access/api
- اضغط **+**
- Name: GitHub Actions
- Access: App Manager
- احفظ: Key ID, Issuer ID, ملف .p8

### 2️⃣ تحويل لـ Base64
```bash
# Certificate (من Keychain)
base64 -i certificate.p12 > cert.txt

# Provisioning Profile (من developer.apple.com)
base64 -i profile.mobileprovision > profile.txt

# API Key
base64 -i AuthKey_XXX.p8 > api.txt
```

### 3️⃣ إضافة Secrets في GitHub
https://github.com/omar-fathalla/delegate_app/settings/secrets/actions

```
IOS_CERTIFICATE_BASE64 = محتوى cert.txt
IOS_CERTIFICATE_PASSWORD = كلمة مرور P12
IOS_PROVISIONING_PROFILE_BASE64 = محتوى profile.txt
APP_STORE_CONNECT_API_KEY_ID = Key ID
APP_STORE_CONNECT_API_ISSUER_ID = Issuer ID
APP_STORE_CONNECT_API_KEY_BASE64 = محتوى api.txt
KEYCHAIN_PASSWORD = أي كلمة مرور
```

### 4️⃣ Push
```bash
git push origin main
```

### 5️⃣ راقب
https://github.com/omar-fathalla/delegate_app/actions

---

## ✅ النتيجة
كل push = build جديد على TestFlight تلقائياً! 🎉

---

## 📞 مشاكل؟
راجع `APPLE_STORE_SETUP.md` للتفاصيل الكاملة
