# نظام الديزاين (Material 3) في delegate_app

ده المرجع الوحيد للديزاين في التطبيق (موبايل المندوب وويب الـ HR والأدمن). اعتمده المستخدم يوم 26 نوفمبر 2026 ([TAS-345](https://linear.app/sw-point/issue/TAS-345)). وأي قاعدة ديزاين قديمة في `AGENTS.md` أو `.agent/skills/` بتتعارض معاه اتشالت.

| الملف | فيه إيه |
| --- | --- |
| [`m3-catalog.md`](m3-catalog.md) | الفهرس: كل بند من M3 برقم ثابت (F الأساسيات، C المكونات، P مكونات خاصة)، ومكان الكود والتيست، وخطوات مراجعة أي صفحة من m3.material.io |
| [`design-system.md`](design-system.md) | القواعد نفسها: الألوان، والخطوط، والمسافات، والمكونات، والحركة، والوصول، والـ RTL |
| `lib/core/design/` | الكود: tokens، وtypography، وmotion، وbidi، وmoney، وlayout، وwidgets الـ M3 Expressive |
| `test/design/` | تيستات نظام الديزاين، ومعاها `no_new_raw_styles_test.dart` (ratchet) |
| `.claude/skills/m3-review/` | إجراء مراجعة صفحة أو مكون على الكتالوج |
| `lib/features/playground/` | الـ playground: أمثلة حية لكل مكون، بالفاتح والغامق وRTL والخط الكبير والتباين |

## الفرق بين الملفين دول ونسختهم الأصلية (`m3-kit`، من Tashil ERP)
- **لون البراند:** بنفسجي `0xFF6750A4` (`TashilColors.seed`)، مش أخضر. وكل الأدوار متولّدة منه، **ومفيش أي لون بيتختار بالإيد**.
- **مالهمش علاقة بالتطبيق:** بنود P (‏ProductTile وCartLine وNumericKeypad وReceiptPreview) مش جزء من نظام التطبيق. ونسخة منهم موجودة في `lib/features/playground/sample_widgets.dart` علشان أمثلة الـ playground بس، وممنوع تتستخدم في الشاشات. وأقسام SUNMI/POS في `design-system.md` بتنطبق على أي موبايل بمقاس compact.
- **الـ playground (TAS-383):** `lib/features/playground/` و`lib/main_playground.dart`، من غير تاب الـ POS. ونفتحه من الإعدادات في نسخ الـ dev بس («مكونات التصميم (نسخة المطورين)»)، أو بـ `flutter run -t lib/main_playground.dart`. وفيه أمثلة كل مكون زي ما اتبنت في الـ kit، فأي صفحة بتتصلح على المثال بتاعها هنا.
- **`material_ui`:** التطبيق على `material_ui` و`cupertino_ui` من TAS-374، مش على `package:flutter/material.dart` (اللي بقى deprecated).
- **الـ theme:** `lib/config/theme/app_theme.dart` بيبني على `TashilTheme`. وفضل منه حاجتين للتطبيق كله: حركة صفحات واحدة (`M3PageTransitionsBuilder`)، ومقبض الـ bottom sheet.
- **الحركة:** `lib/config/theme/app_motion.dart` (‏`AppMotionDurations` و`AppMotionCurves` و`AppMotionPage`) لسه مستخدم في الـ routes والشاشات القديمة. وأي شغل جديد بياخد من `TashilSpring` و`TashilEasing` في `lib/core/design/motion.dart`. والاتنين على tokens M3، فمفيش تعارض.

## قواعد سريعة
- الألوان من `Theme.of(context).colorScheme` أو `TashilSemanticColors.of(context)` بس. والنصوص من `textTheme` بس. ومفيش hex ولا `fontSize` جديد، والـ ratchet بيمنعهم.
- المسافات من `TashilSpacing`، والأشكال من `TashilRadius`، والـ padding من `EdgeInsetsDirectional`.
- المكون الرسمي من Flutter أو Google الأول. ولو مفيش، المكون اللي في `lib/core/design/widgets/`. ومفيش مكون جديد بيتبني بالإيد إلا لو مش موجود خالص، ويتسجل في الكتالوج.
- أي تعديل في الديزاين: نحدّث سطر البند في `m3-catalog.md` (الكود والتيست والتاريخ)، ونحط صور قبل وبعد على تيكت Linear.
