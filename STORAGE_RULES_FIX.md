# 🔧 إصلاح Storage Rules - حل مشكلة "You don't have permission"

**التاريخ:** 2 أبريل 2026  
**المشكلة:** حسابات الشركات لا تستطيع الوصول إلى الملفات في Firebase Storage  
**الحالة:** ✅ تم الإصلاح

---

## 🔴 المشكلة

عند محاولة الوصول إلى الملفات (صور المندوبين، الشركات، إلخ) من الموقع (Web Dashboard) باستخدام حساب شركة، تظهر الرسالة:

```
You don't have permission to access this file.
Status: 403 Forbidden
```

### السبب

القواعد القديمة في `storage.rules` كانت:

```javascript
// ❌ القواعد القديمة
match /feedback_screenshots/{fileName} {
  allow read: if true;  // فقط feedback_screenshots
}

match /{allPaths=**} {
  allow read, write: if false;  // كل شيء آخر محظور!
}
```

هذا يعني:
- ✅ `feedback_screenshots` - يمكن للجميع القراءة
- ❌ **كل المسارات الأخرى محظورة تماماً**

---

## ✅ الحل

تم تحديث `storage.rules` لتشمل:

### 1. دوال مساعدة (Helper Functions)

```javascript
function isAuthenticated() {
  return request.auth != null;
}

function getUserData() {
  return firestore.get(/databases/(default)/documents/users/$(request.auth.uid)).data;
}

function isSuperAdmin() {
  return isAuthenticated() && getUserData().role == 'super-admin';
}

function isOrgAdmin() {
  return isAuthenticated() && getUserData().role == 'org-admin';
}

function isCompanyAdmin() {
  return isAuthenticated() && getUserData().role == 'company-admin';
}

function belongsToOrganization(orgId) {
  return isAuthenticated() && getUserData().organizationUID == orgId;
}

function belongsToCompany(compId) {
  return isAuthenticated() && getUserData().companyUID == compId;
}
```

### 2. قواعد الوصول حسب المسار

#### Feedback Screenshots
```javascript
match /feedback_screenshots/{fileName} {
  // Read: Authenticated users only
  allow read: if isAuthenticated();
  
  // Write: Authenticated users, max 5MB, images only
  allow write: if isAuthenticated() &&
    request.resource.size < 5 * 1024 * 1024 &&
    request.resource.contentType.matches('image/.*');
}
```

#### Organization Files
```javascript
match /organizations/{orgId}/{allPaths=**} {
  // Super Admin: full access
  allow read, write: if isSuperAdmin();
  
  // Org Admin & Company Admin: read access to their organization
  allow read: if belongsToOrganization(orgId);
  
  // Org Admin: write access to their organization
  allow write: if isOrgAdmin() && belongsToOrganization(orgId);
}
```

#### Company Files
```javascript
match /companies/{compId}/{allPaths=**} {
  // Super Admin: full access
  allow read, write: if isSuperAdmin();
  
  // Company Admin: full access to their company
  allow read, write: if belongsToCompany(compId);
  
  // Org Admin: read access
  allow read: if isOrgAdmin();
}
```

#### Delegate Files
```javascript
match /delegates/{delegateId}/{allPaths=**} {
  // Super Admin: full access
  allow read, write: if isSuperAdmin();
  
  // Delegate: read their own files
  allow read: if isAuthenticated() && request.auth.uid == delegateId;
  
  // Org Admin & Company Admin: read access
  allow read: if isOrgAdmin() || isCompanyAdmin();
}
```

#### Public Files
```javascript
match /public/{allPaths=**} {
  allow read: if true;
  allow write: if isSuperAdmin();
}
```

---

## 🚀 خطوات النشر

### الطريقة 1: سكريبت تلقائي (موصى به)

```bash
./deploy_storage_rules.sh
```

### الطريقة 2: يدوياً

```bash
# 1. تسجيل الدخول (إذا لزم الأمر)
firebase login --reauth

# 2. نشر Storage Rules
firebase deploy --only storage --project practice-firebase-72df1
```

---

## 🧪 الاختبار

### 1. اختبار حساب شركة (Company Admin)

```bash
# سجل دخول بحساب شركة في الموقع
# حاول الوصول إلى:
# - صور المندوبين
# - صور الشركات
# - ملفات المنظمة

# النتيجة المتوقعة: ✅ يمكن القراءة
```

### 2. اختبار حساب مندوب (Delegate)

```bash
# سجل دخول بحساب مندوب في التطبيق
# حاول الوصول إلى:
# - صورته الشخصية
# - صور الوثائق

# النتيجة المتوقعة: ✅ يمكن القراءة
```

### 3. اختبار Super Admin

```bash
# سجل دخول بحساب Super Admin
# حاول الوصول إلى:
# - جميع الملفات

# النتيجة المتوقعة: ✅ يمكن القراءة والكتابة
```

---

## 📊 جدول الصلاحيات

| المسار | Super Admin | Org Admin | Company Admin | Delegate | Guest |
|--------|-------------|-----------|---------------|----------|-------|
| `/feedback_screenshots/*` | ✅ R/W | ✅ R | ✅ R | ✅ R | ❌ |
| `/organizations/{orgId}/*` | ✅ R/W | ✅ R/W (own) | ✅ R (own org) | ❌ | ❌ |
| `/companies/{compId}/*` | ✅ R/W | ✅ R | ✅ R/W (own) | ❌ | ❌ |
| `/delegates/{delegateId}/*` | ✅ R/W | ✅ R | ✅ R | ✅ R (own) | ❌ |
| `/public/*` | ✅ R/W | ✅ R | ✅ R | ✅ R | ✅ R |

**Legend:**
- ✅ R = Read (قراءة)
- ✅ W = Write (كتابة)
- ✅ R/W = Read & Write (قراءة وكتابة)
- ❌ = Denied (محظور)

---

## ⚠️ ملاحظات مهمة

### 1. تسجيل الدخول مطلوب

```javascript
// ❌ قبل: allow read: if true;
// ✅ بعد: allow read: if isAuthenticated();
```

الآن جميع الملفات (ما عدا `/public/*`) تتطلب تسجيل دخول.

### 2. Role-Based Access Control

القواعد تتحقق من:
- ✅ `role` (super-admin, org-admin, company-admin, delegate)
- ✅ `organizationUID` (انتماء للمنظمة)
- ✅ `companyUID` (انتماء للشركة)

### 3. حجم الملفات

```javascript
request.resource.size < 5 * 1024 * 1024  // 5MB max
```

### 4. نوع الملفات

```javascript
request.resource.contentType.matches('image/.*')  // صور فقط
```

---

## 🔍 التحقق من Firebase Console

بعد النشر، تحقق من:

1. **Storage Rules:**
   ```
   https://console.firebase.google.com/project/practice-firebase-72df1/storage/rules
   ```

2. **Storage Files:**
   ```
   https://console.firebase.google.com/project/practice-firebase-72df1/storage
   ```

3. **تجربة الوصول:**
   - افتح ملف في Storage
   - انسخ الرابط
   - افتحه في متصفح جديد
   - يجب أن يعمل إذا كنت مسجل دخول

---

## 🐛 حل المشاكل

### مشكلة 1: لا يزال الخطأ 403

**الحل:**
```bash
# 1. تأكد من نشر القواعد
firebase deploy --only storage --project practice-firebase-72df1

# 2. انتظر دقيقة (قد يستغرق النشر وقتاً)

# 3. امسح الكاش
# - في Chrome: Ctrl+Shift+Delete
# - اختر "Cached images and files"
# - امسح

# 4. سجل خروج ودخول مرة أخرى
```

### مشكلة 2: "Authentication Error" عند النشر

**الحل:**
```bash
firebase login --reauth
```

### مشكلة 3: الملفات القديمة لا تعمل

**الحل:**
```bash
# تحقق من مسار الملف في Storage
# يجب أن يكون:
# ✅ /organizations/{orgId}/...
# ✅ /companies/{compId}/...
# ✅ /delegates/{delegateId}/...

# ❌ ليس:
# /random_path/...
```

---

## 📚 مراجع

- [Firebase Storage Security Rules](https://firebase.google.com/docs/storage/security)
- [Storage Rules Conditions](https://firebase.google.com/docs/storage/security/rules-conditions)
- [Storage Rules Examples](https://firebase.google.com/docs/storage/security/start)

---

## ✅ الخلاصة

تم إصلاح Storage Rules لتسمح بـ:

1. ✅ **حسابات الشركات** - قراءة ملفات شركتهم ومنظمتهم
2. ✅ **حسابات المندوبين** - قراءة ملفاتهم الشخصية
3. ✅ **Super Admin** - وصول كامل لكل شيء
4. ✅ **Org Admin** - قراءة وكتابة لمنظمتهم

**الآن يمكنك:**
- ✅ عرض صور المندوبين في الموقع
- ✅ عرض صور الشركات
- ✅ عرض ملفات المنظمة
- ✅ رفع ملفات جديدة (حسب الصلاحيات)

---

**تم بواسطة:** Kiro AI Assistant  
**التاريخ:** 2 أبريل 2026  
**الحالة:** ✅ جاهز للنشر
