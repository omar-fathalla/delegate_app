# مستندات المناديب الفاضية (ghost delegate docs)

آخر تحديث: 18 نوفمبر 2026.

## المشكلة

على الإنتاج فيه 77 مستند تحت `organizations/{org}/companies/{company}/delegates/{id}` من غير اسم ولا تليفون ولا رقم قومي. بتظهر في الـ HR web كصفوف «؟» في المرتبات والحضور، وبتتحسب في عدد المناديب.

**السبب:**
- نسخ التطبيق القديمة، اللي قبل `1.14.1+80`، فيها `device_binding_service` بيكتب بيانات الجهاز بـ `set(..., merge: true)` على مسار المندوب. اتأكدنا من ده في `a4f3e76`، نسخة `1.11.0+69`.
- لو المندوب اتمسح قبل كده، الكتابة دي بتعمله تاني مستند فيه حقول الجهاز بس.
- قواعد الإنتاج دلوقتي `allow read, write: if isAuthenticated()`، فالكتابة دي بتعدي.

## الإصلاح

| الجزء | الملف | فين بيتنشر |
|---|---|---|
| منع إنشاء مستند مندوب من غير اسم أو تليفون أو رقم قومي | `firestore/interim-prod-hardening.rules` (= قواعد الإنتاج الحالية + الحماية دي بس) | rules على الإنتاج، بعد ما تتجرب على `tashil-dev` |
| نفس الحماية، والمندوب نفسه ممنوع ينشئ مستند | `firestore.rules` (القواعد الصارمة) | مع القواعد الصارمة لما تنزل |
| الدخول يرفض المستند الفاضي (`profile_missing`) والمحذوف (`account_deleted`)، والتحقق بيتكرر جوه الـ transaction، وكتابة الجهاز بقت `update()` | `functions/src/delegate_login*.ts`, `delegate_identity.ts` | `delegateLoginV2` |
| لما آخر مستند للمندوب يتمسح: نمسح `deviceBindings`، ونلغي طلبات فك الربط المفتوحة، ونلغي جلسات Firebase | `functions/src/delegate_link_deleted.ts` | `onDelegateLinkDeleted` (function جديدة) |
| الـ HR web مش بيعرض المستندات الفاضية (المرتبات، الحضور، الإجازات، تعديلات الحضور، الداشبورد) | `admin_remote_data_source.dart`, `admin_home_screen.dart`, `delegate_identity.dart` | hosting بتاع HR web |

## الحد الأدنى لنسخة التطبيق

- **مفيش أي آلية force-update في التطبيق**، لا في `1.11` ولا في `main` (1.14.2) ولا في `dev`.
- مجموعة `app_updates` معمولة لسجل التغييرات بس. حقولها `version, type, priority, isActive...`، ومفيش نسخة بتقرا منها حد أدنى.
- `firebase_remote_config` بيتستخدم لـ OTP بس.
- يعني مفيش قيمة نقدر نغيرها النهارده عشان نوقف نسخ ≤1.11 من التطبيق.

**المتاح دلوقتي:**
1. حماية الـ rules اللي فوق بتمنع الضرر نفسه، يعني إعادة الإنشاء، حتى من النسخ القديمة. والنسخة القديمة لسه تقدر تحدّث مستند موجود.
2. النسخ اللي قبل `delegateLoginV2` بتدخل بـ anonymous auth. لما القواعد الصارمة (`firestore.rules`) تنزل، الطريق ده هيتقفل لكل النسخ اللي مش بتستخدم V2.

**مقترح لنسخة جاية، مش موجود في الـ PR ده:**
- مفتاح Remote Config اسمه `min_supported_build` (int)، والتطبيق يقارنه بـ `buildNumber` وقت التشغيل، ويعرض شاشة تحديث إجبارية.
- بعد ما النسخة اللي فيها الفحص تنزل ويحدّث عليها معظم المناديب، نحط القيمة على build النسخة دي.
- النسخ الأقدم مش هتقرا المفتاح، فدي حماية للمستقبل بس.

## خطة النشر (كل خطوة محتاجة موافقة)

1. **functions، بالاسم بس:**
   `firebase deploy --project practice-firebase-72df1 --only functions:tashil-mobile-notifications:delegateLoginV2,functions:tashil-mobile-notifications:onDelegateLinkDeleted`
   - `onDelegateLinkDeleted` بيعتمد على collection-group index على `delegates.uid`، وده موجود على الإنتاج READY.
   - مش مطلوب أي index جديد.
2. **rules:**
   - نجرب `firestore/interim-prod-hardening.rules` على `tashil-dev` بتطبيق 1.14 والـ HR web. خصوصا: إضافة مندوب، الموافقة على طلب، الربط بسلسلة، والدخول.
   - وبنسخة 1.11 لو متاحة: الدخول لازم يكمل، وكتابة الجهاز على مستند محذوف تترفض. في الكود القديم الكتابة دي جوه `try` في `_updateDelegateDeviceInFirestore`، ولازم نتأكد على الجهاز إن الرفض ما يوقعش الدخول.
   - بعد كده نعمل diff مع القواعد اللي شغالة على الإنتاج، وننشر rules بس.
3. **hosting** بتاع HR web بعد ما الـ PR يتعمله merge، أو cherry-pick على نسخة الإنتاج.
4. **تنظيف البيانات** باستخدام سكريبت المعاينة والمسح، وده بيتعمل لوحده بموافقة.
