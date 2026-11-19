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

توزيع يدوي لنسخة dev على Firebase App Distribution وبصمات SHA-1 لمحمد: `android/README_DEV_FLAVOR.md`.

### iOS — لا توجد حماية مماثلة حتى الآن

- يوجد ملف واحد فقط: `ios/Runner/GoogleService-Info.plist` (إعدادات **prod**).
- لا يوجد flavor/scheme لـ `tashil-dev`، ولا build-phase يتحقق من `PROJECT_ID` ويفشل البيلد عند الإعداد الخطأ.
- الحماية المكافئة لأندرويد **مخططة** في فرع/خطة `feat/ios-dev-flavor` (تطبيق iOS dev: `com.tashil.delegate.dev` + فحص PROJECT_ID).

---

## (د) دورة التنفيذ والاختبار

- **المساعد الصوتي** (Tashil App) هو **العقل المدبر** للدورة دي: بينظّم الشغل ويبعت **التاسكات** لمشروع **Cursor** (مشروع Tashil Employee) عشان يتنفَّذ اللازم في الريبو.
- بعد ما **Cursor** يخلّص ويقول إن الشغل **تمام**، المساعد يبعت لـ **User Test** الريبو واللي اتعمل (الفيتشرز/الحاجات اللي خلصت في الفرع) ويطلب منه **تيست بكل الصلاحيات** **ضمن نطاق الاختبار وببيانات تجريبية، مع بقاء بوابات الـ rules والدمج والنشر كما هي** على الوضع الفعلي.
- **User Test** يبعت **نتائج الاختبار** وأي **اقتراحات للإصلاح**؛ حلقة المعالجة كالتالي: *يرسل User Test الأخطاء ومقترحات الحل إلى الأيجنت الذي طلب الاختبار. ينفّذ الأيجنت التحسينات ضمن النطاق المصرّح ويختبرها ويعيد النتائج وSHA الجديد؛ يعيد User Test الاختبار، ويرسل النجاح والملاحظات المتبقية أو يكرر الدورة حتى النجاح، مع بقاء الموافقات المستقلة سارية.*
- تنفيذ الإصلاحات والتعديلات يفضل يبقى **داخل النطاق المصرّح به للتاسك**؛ أي **توسيع** في الشغل أو أي تغيير يمس **الإنتاج** أو **القواعد (rules)** أو **النشر (deploy)** لازم ياخد **موافقة منفصلة من محمد** (والمرجع التفصيلي لشروط الموافقة والدمج: **قسم (ب)**).
- قبل اعتبار الشغل **جاهز لموافقة الدمج في `dev`**:
  - إذا كان التغيير **يشمل التطبيق** (كود سلوك/واجهة): لازم تكون متاحة **معاينة (preview)** أو **بنْاء/أرتيفاكت اختبار** يطابق **نفس الـ SHA** اللي هيتطلب اعتماده.
  - إذا كان المراجعة **وثائق فقط** (بدون تغيير سلوك التطبيق): **لا** يُشترَط في (د) بنْاء تطبيق للمعاينة؛ تظل **شروط (ب)** (وموافقة User Test على الـ SHA + CI) سارية.
- المساعد (**Tashil App**) يقدر **يذكّر أو ينسّق** التواصل و**يبلّغ**؛ **لا** يستبدل مسار التصحيح المباشر بين **User Test** والأيجنت المنفّذ.
- بعد **إعادة التسليم** على الفرع، يتكرّر الاختبار لحد ما User Test **ما يلاقيش أخطاء**؛ بعدها يتطبَّق **قسم (ب)** بالظبط (موافقة على الـ **SHA** المحدّد + **CI أخضر**) قبل أي دمج — **من غير ما نستبدل** خطوات الدمج المرسومة في (ب).
- المساعد يبعت **ملخّص ما وصلوا له في الدورة** لـ **محمد في الشات** (إشعار/تنسيق)، من غير ما يكون هو قناة الإصلاح الأساسية بين User Test والمنفّذ.

---

## مراجع سريعة

- سياسة Git المختصرة (منع الدفع التلقائي): `AGENTS.md` → قسم *Git & Version Control Policy*
- بيئة التطوير: `docs/DEV_ENVIRONMENT.md`
- سير إصدار أندرويد (من `main` فقط): `.github/workflows/android-release.yml`

---

## (هـ) دورة كل تعديل: من أول branch لحد الـ merge

أي شغل، سواء إنسان أو agent، بيمشي بالترتيب ده. الأدوات اللي بتطبّق كل خطوة مكتوبة جنبها.

| الخطوة | القاعدة | اللي بيطبّقها |
|---|---|---|
| 1. البداية | branch جديد من `origin/dev` في worktree لوحده، والاسم `<type>/<name>` (`feat` / `fix` / `test` / `chore` / `docs`)، وموضوع واحد في كل branch | skill `start-work` |
| 2. الـ commit | ممنوع commit على `dev` أو `main` | hook `pre-commit` |
| 3. الشغل | كل تغيير في السلوك لازم يبقى معاه test في نفس الـ branch (Dart → `test/`، rules → `test/rules/`، functions → `functions/test/`، رحلة مستخدم → Maestro أو Patrol). dev و `tashil-dev` بس، وبالحسابات الوهمية | المراجعة في `pr-gate` |
| 4. الفحص | `bash scripts/local_ci.sh --changed --no-apk HEAD` بيشغّل بس الـ jobs اللي الملفات المتغيرة محتاجاها | يدوي في أي وقت |
| 5. الـ push | بإذن صريح بس. الـ push بيشغّل نفس الفحص، ولو فشل الـ push بيتمنع. والـ push على `dev` أو `main` ممنوع | hook `pre-push` |
| 6. الـ PR | PR على `dev`، يبدأ draft ويتعمله ready لما الشغل يخلص | — |
| 7. البوابة | analyze، tests، guards، backend، CI، والـ Mac gate (APK و Maestro و Patrol)، وفي الآخر تقرير | skill `pr-gate` |
| 8. الـ merge | بموافقة صريحة بس، ومن خلال `bash scripts/ci/merge_guard.sh <pr> --merge`، اللي بيتأكد إن كل الـ jobs المطلوبة خضرا | `merge_guard.sh` |
| 9. بعد الـ merge | الـ mac-agent بيشغّل الـ mac-gate لوحده على dev الجديد، وبيعمل run كامل كل ليلة | `scripts/ci/mac_agent.sh` |

**تشغيل الـ hooks** (مرة واحدة لكل clone، وبتشتغل على كل الـ worktrees): `bash scripts/ci/install_git_hooks.sh`.

**تخطّي الفحص وقت الـ push** (لما تكون متأكد، زي تعديل في الوثائق بس): `TASHIL_SKIP_PREPUSH=1 git push ...`. منع الـ push على `dev` و `main` مش بيتخطّى بالطريقة دي.

**حسابات الاختبار**: فيه 34 حساب وهمي على `tashil-dev` بتغطي الـ 10 أدوار (`functions/scripts/README-hr-web-fake-accounts.md`). الباسوردات موجودة بس في `functions/scripts/.hr-web-fake-accounts.local.json` على الماك، وما بتتطبعش ولا بتتعملها commit.
