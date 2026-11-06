# قواعد سير العمل في التطوير (Tashil Employee)

هذا الملف يوثّق قواعد العمل المعتمدة في مشروع `delegate_app`.
الغرض: أن تكون القواعد مكتوبة في الريبو بالعربية، واضحة لكل من يعمل على الكود.

---

## (أ) الشغل على فرع منفصل

- أي تغيير في الكود أو الإعدادات أو الوثائق يتم على **فرع منفصل** (أو worktree منفصل على الماك)، وليس مباشرة على `dev` أو `main`.
- الدمج إلى الفرع المشترك يكون عبر **Pull Request إلى `dev` فقط**.
- **ممنوع** عمل commit مباشرة على `dev` أو `main`.
- نسخ الإصدار/الرفع للمتاجر تُبنى من `main` فقط (انظر `.github/workflows/android-release.yml`: الوظيفة تعمل فقط عندما `github.ref == 'refs/heads/main'`).
- لا يُرفع (`git push`) إلى GitHub تلقائيًا؛ فقط عندما يطلب محمد ذلك صراحة (انظر أيضًا سياسة Git في `AGENTS.md`).

---

## (ب) الاختبار قبل الدمج

- الـ PR يُدمَج في **`dev` فقط بعد**:
  1. موافقة صريحة من **User Test** على الـ **SHA الدقيق** للفرع، و
  2. أن يكون **CI أخضر** (لا دمج مع CI أحمر).
- لا شيء يذهب إلى **`main` / الإنتاج** بدون:
  1. موافقة User Test على الـ **SHA الدقيق لـ `dev`**, و
  2. **موافقة منفصلة من محمد**.
- أي نشر إنتاج (prod deploy) أو إطلاق قواعد (rules release) يحتاج موافقة محمد **وسجل rollback**.
- للاختبارات المحلية والتحقق من التغييرات: استخدم فقط `flutter analyze` و `flutter test` ما لم يُطلب بناء صراحة (انظر `AGENTS.md`).

---

## (ج) فشل البيلد عند استخدام إعدادات Firebase غلط

### أندرويد — الحماية موجودة الآن

في `android/app/build.gradle.kts` يجب أن يتوافق الـ **flavor** مع **`--dart-define=ENV=...`**, وإلا يفشل البيلد بـ `GradleException` حتى لا تتصل حزمة Dev بـ Firestore الإنتاجي (أو العكس):

```kotlin
if (buildsDev && dartEnv != "dev") {
    throw GradleException("Flavor 'dev' requires --dart-define=ENV=dev (got ENV=$dartEnv).")
}
if (buildsProd && dartEnv != "prod") {
    throw GradleException("Flavor 'prod' requires ENV=prod or no ENV define (got ENV=$dartEnv).")
}
```

ملفات الإعداد:

| Flavor | ENV المطلوب | ملف Google Services | مشروع Firebase |
|--------|-------------|---------------------|----------------|
| `dev` | `--dart-define=ENV=dev` | `android/app/src/dev/google-services.json` | **tashil-dev** |
| `prod` | `ENV=prod` أو بدون تعريف ENV | `android/app/google-services.json` | **practice-firebase-72df1** (prod) |

أمثلة بناء صحيحة:

```bash
flutter build apk --flavor dev --dart-define=ENV=dev
flutter build apk --flavor prod
```

### iOS — لا توجد حماية مماثلة حتى الآن

- يوجد ملف واحد فقط: `ios/Runner/GoogleService-Info.plist` (إعدادات **prod**).
- لا يوجد flavor/scheme لـ `tashil-dev`، ولا build-phase يتحقق من `PROJECT_ID` ويفشل البيلد عند الإعداد الخطأ.
- الحماية المكافئة لأندرويد **مخططة** في فرع/خطة `feat/ios-dev-flavor` (تطبيق iOS dev: `com.tashil.delegate.dev` + فحص PROJECT_ID).

---

## مراجع سريعة

- سياسة Git المختصرة (منع الدفع التلقائي): `AGENTS.md` → قسم *Git & Version Control Policy*
- بيئة التطوير: `docs/DEV_ENVIRONMENT.md`
- سير إصدار أندرويد (من `main` فقط): `.github/workflows/android-release.yml`
