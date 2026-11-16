# Fake HR-web accounts (tashil-dev only)

# حسابات وهمية لبوابة الموارد البشرية (tashil-dev فقط)

Not part of deploy. Not imported by Cloud Functions. Creates obviously fake `@example.com` accounts so the HR / company-supervisor web build can be exercised on the dev project, including cross-company isolation (TA-8).

ليس جزءًا من النشر. ينشئ حسابات وهمية على `@example.com` لتجربة نسخة الويب لموارد البشرية ومشرف الشركة على مشروع التطوير، بما في ذلك عزل بيانات شركتين.

## Guard / الحماية

The script refuses to run unless `--project` is exactly `tashil-dev`. It also refuses `practice-firebase-72df1` and any other id. Before `--apply` or `--cleanup --apply` it checks the credentials' project (service-account `project_id`, `FIREBASE_CONFIG`, `GOOGLE_CLOUD_PROJECT` / `GCLOUD_PROJECT`, or Application Default Credentials). If that project is not `tashil-dev`, it writes nothing.

السكربت يرفض العمل إلا إذا كان `--project` هو `tashil-dev` حرفيًا. يرفض `practice-firebase-72df1` وأي مشروع آخر. قبل الكتابة يتحقق من مشروع بيانات الاعتماد، ولو لم يكن `tashil-dev` لا يكتب شيئًا.

Dry-run is the default and does not contact Firebase. `--apply` is the only write. Re-runs update the same ids and do not change passwords. `--rotate-passwords` replaces them. Passwords are written only to `functions/scripts/.hr-web-fake-accounts.local.json` (mode `0600`, gitignored) and are never printed. The script does not send email or SMS.

الوضع الافتراضي عرض فقط ولا يتصل بفايربيس. `--apply` وحده يكتب. إعادة التشغيل لا تغيّر كلمات السر. كلمات السر تُحفظ في الملف المحلي فقط ولا تُطبع.

`--cleanup` deletes only documents this script tagged with `seedTag: tashil-dev-hr-web-fake-v1` and `fake: true` under `seed-fake-*` ids. Auth users are deleted only when the email is still the planned `@example.com` address. A document or Auth user that no longer matches is left in place.

`--cleanup` يحذف فقط المستندات التي وسمها السكربت. مستخدم المصادقة يُحذف فقط إذا بقي بريده `@example.com` المخطط.

## Commands / الأوامر

From `functions/`, with Application Default Credentials for `tashil-dev` only when you pass `--apply`:

من مجلد `functions/`، ومع بيانات اعتماد مشروع `tashil-dev` فقط عند استخدام `--apply`:

```bash
node scripts/hr-web-fake-accounts.js --project tashil-dev
node scripts/hr-web-fake-accounts.js --project tashil-dev --apply
node scripts/hr-web-fake-accounts.js --project tashil-dev --rotate-passwords --apply
node scripts/hr-web-fake-accounts.js --project tashil-dev --cleanup
node scripts/hr-web-fake-accounts.js --project tashil-dev --cleanup --apply
```

If `--apply` stops before the password file is written, run again with `--rotate-passwords` so new passwords are stored. Do not point `GOOGLE_APPLICATION_CREDENTIALS` at production.

إذا توقف `--apply` قبل كتابة ملف كلمات السر، أعد التشغيل مع `--rotate-passwords`. لا تستخدم مفتاح الإنتاج.

## What it writes / ماذا يكتب

Shapes follow the fields the app reads today. Staff sign in on the web HR screen with the fake phone and the local password (`users/{uid}` holds `email`, `phoneNumber`, `role`, `organizationUID`, and `companyUID` when the role is company-scoped). Delegates are also written to `organizations/seed-fake-hr-org/companies/{company}/delegates/{uid}` so the HR list can show them. One branch per company is written both at `branches/{id}` and `organizations/{org}/branches/{id}`.

الأشكال تطابق ما يقرأه التطبيق اليوم. الدخول من شاشة الموارد البشرية برقم الهاتف الوهمي وكلمة السر المحلية. المندوبون يُكتبون أيضًا تحت `organizations/{org}/companies/{company}/delegates`.

Organization `seed-fake-hr-org` (Fake Test Organization / منظمة وهمية للاختبار). Companies `seed-fake-co-alpha` and `seed-fake-co-beta`.

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
| company-admin / مشرف شركة من دعوة الويب (Angular claimInvite) ألف | fake.companyadmin.invite.alpha@example.com | 01000000023 | seed-fake-co-alpha |
| company_admin / مشرف شركة (createStaffUser / قديم) ألف | fake.companyadmin.legacy.alpha@example.com | 01000000024 | seed-fake-co-alpha |
| companyadmin / مشرف شركة بالحقل القديم companyId فقط ألف | fake.companyadmin.companyid.alpha@example.com | 01000000025 | (none; companyId=seed-fake-co-alpha) |
| admin + position supervisor / مشرف ألف | fake.admin.position.alpha@example.com | 01000000026 | seed-fake-co-alpha |
| company_supervisor / مشرف الشركة باء | fake.company-supervisor.beta@example.com | 01000000027 | seed-fake-co-beta |
| admin + userType HR / مشرف بحقل userType قديم باء | fake.admin.usertype-hr.beta@example.com | 01000000028 | seed-fake-co-beta |
| company-hr / موارد بشرية (قديم) ألف | fake.company-hr.alpha@example.com | 01000000029 | seed-fake-co-alpha |
| company_hr / موارد بشرية باء | fake.company_hr.beta@example.com | 01000000030 | seed-fake-co-beta |
| human_resources / موارد بشرية باء | fake.human-resources.beta@example.com | 01000000031 | seed-fake-co-beta |
| admin / مشرف قديم بلا شركة | fake.admin.nocompany@example.com | 01000000032 | (none) |

Accounts `01000000023`–`01000000032` mirror the other supervisor / HR `users` shapes seen in production (the Angular invite's `company-admin`, `company_admin`, `companyadmin` with only the legacy `companyId` field, `admin` with `position` or a legacy `userType`, `company_supervisor`, the legacy HR spellings, and a legacy `admin` without a company). On web every one of them lands on the HR desktop system (`/hr/home`).

الحسابات من `01000000023` إلى `01000000032` تحاكي بقية أشكال مستندات المشرف والموارد البشرية الموجودة في الإنتاج، وكلها تفتح نظام الموارد البشرية المكتبي (`/hr/home`) على الويب.

Phones are the fake block `01000000xxx`. They are not real numbers. Every HR account belongs to a company; `fake.nocompany@example.com` is a second HR user under `seed-fake-co-alpha` (same phone `01000000004` as before). Delegate documents use deterministic, clearly fake 14-digit ASCII `nationalityID` / `nationalId` values such as `00000000000101` (alpha 1) and `00000000000205` (beta 5) so mobile delegate login works. Role `supervisor` is the company supervisor (the app maps it to the company-admin screens). Role `marketing` is branch marketing. Role `branches_marketing` is the branches marketing manager.

أرقام الهاتف من النطاق الوهمي `01000000xxx`. دور `supervisor` هو مشرف الشركة. دور `marketing` تسويق الفرع. دور `branches_marketing` مسؤول تسويق الفروع.
