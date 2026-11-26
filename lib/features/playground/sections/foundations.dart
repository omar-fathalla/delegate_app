import 'package:material_ui/material_ui.dart';

import '../../../core/design/motion.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/color_scheme_picker.dart';
import 'color_roles_demo.dart';
import 'common.dart';
import 'content_color_demo.dart';
import 'typography_demo.dart';
import 'density_rtl_demo.dart';
import 'layout_demo.dart';

class FoundationsSection extends StatelessWidget {
  const FoundationsSection({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    return SectionList([
      const SpecSection(
        title: 'الألوان',
        m3: 'Color roles · color system',
        spec: 'styles/color/roles',
        rule:
            'كل الألوان أدوار من ColorScheme المتولد من لون البذرة، ومفيش '
            'لون hex في أي شاشة. استخدم كل دور مع الـ on بتاعه بس (ده اللي '
            'بيضمن التباين). الـ container للخلفيات مش للكلام. 3 مستويات '
            'تباين (زرار التباين فوق): عادي، متوسط، عالي، والعالي بيشتغل '
            'لوحده لو الجهاز طالبه. الرقم جنب كل لون هو التباين.',
        children: [ColorRolesDemo()],
      ),
      const SpecSection(
        title: 'نظام الألوان: المصدر',
        m3: 'Color schemes · static and dynamic',
        spec: 'styles/color/choosing-a-scheme',
        rule:
            'ثابت (الافتراضي): ألوان تسهيل أو لون المحل، نفس الشكل على كل '
            'جهاز. ديناميك: من خلفية الجهاز (أندرويد 12+). ألوان M3 '
            'الأساسية للمقارنة. التغيير بيلوّن البلاي جراوند كله. الأدوار '
            'نفسها في كل الحالات، اللي بيتغير الألوان بس.',
        children: [ColorSchemePicker()],
      ),
      const SpecSection(
        title: 'ألوان من المحتوى',
        m3: 'Content-based color',
        spec: 'styles/color/dynamic/content-based-source',
        rule:
            'جزء محدد من الشاشة (كارت المنتج) بياخد ألوانه من صورته، '
            'والباقي زي ما هو. اختار منتج تاني تشوف الكارت بيتلوّن.',
        children: [ContentColorDemo()],
      ),
      const SpecSection(
        title: 'الخطوط',
        m3: 'Typography · type scale & tokens',
        spec: 'styles/typography/applying-type',
        rule:
            'خط Cairo مضمّن (أوفلاين)، ومعاه بدائل Roboto ثم Noto Sans. 5 '
            'أدوار × 3 مقاسات: 15 Baseline و15 Emphasized. الـ Emphasized '
            'للمختار وغير المقروء والإجراء الأهم. العربي "ارتفاع متوسط" فالسطر '
            'أطول 7%. استخدم textTheme بس، ممنوع fontSize يدوي. الأرقام بنفس '
            'العرض. الروابط primary وتحتها خط. المعالجة التحريرية للحظات '
            'المميزة بس.',
        children: [TypographyDemo()],
      ),
      SpecSection(
        title: 'الأشكال',
        m3: 'Corner radius',
        spec: 'styles/shape/corner-radius-scale',
        children: [
          Demo([
            for (final (n, r) in const [
              ('xs 4', TashilRadius.extraSmall),
              ('sm 8', TashilRadius.small),
              ('md 12', TashilRadius.medium),
              ('lg 16', TashilRadius.large),
              ('xl 28', TashilRadius.extraLarge),
            ])
              Container(
                width: 72,
                height: 56,
                alignment: Alignment.center,
                decoration: BoxDecoration(
                  color: s.secondaryContainer,
                  borderRadius: BorderRadius.circular(r),
                ),
                child: Text(n, style: text.labelMedium),
              ),
          ]),
        ],
      ),
      const SpecSection(
        title: 'التخطيط ونقاط التوقف',
        m3: 'Layout · breakpoints · panes',
        spec: 'foundations/layout/layout-overview/overview',
        rule:
            '5 نقاط توقف: مضغوط تحت 600، متوسط 600–839، موسّع 840–1199، '
            'كبير 1200–1599، كبير جداً من 1600. كل المحتوى جوه أجزاء (panes): '
            'جزء واحد لحد المتوسط، اتنين من الموسّع، وتلاتة بحد أقصى في الكبير '
            'جداً. الهامش 16 في المضغوط و24 من المتوسط، وبين الأجزاء 24. '
            'المقبض بين الجزأين بيغيّر العرض، ولو سحبته للآخر بيقفل جزء.',
        children: [LayoutDemo()],
      ),
      const SpecSection(
        title: 'الكثافة',
        spec: 'foundations/layout/grids-spacing/density',
        rule:
            'اختيارية: صاحب المحل يختارها من الإعدادات، ومش بتتغير لوحدها مع '
            'حجم الشاشة. كل درجة بتشيل 4dp من فوق وتحت. للقوايم والجداول '
            'والفورمات الطويلة بس، مش للقوايم المنسدلة والحوارات والتنبيهات. '
            'الأزرار ومساحة اللمس 48 زي ما هي، وحجم الخط مش بيتغير.',
        children: [DensityDemo()],
      ),
      const SpecSection(
        title: 'من اليمين للشمال',
        spec: 'foundations/layout/bidirectionality-rtl',
        rule:
            'الأسهم وزرار الإرسال والخروج والشارة والتقدم الخطي والسحب بتتعكس. '
            'الساعة والتحديث والدوائر وأزرار الميديا بتفضل زي ما هي. الموبايل '
            'والإيميل والباركود بيتكتبوا من الشمال لليمين جوه الكلام العربي.',
        children: [RtlDemo()],
      ),
      SpecSection(
        title: 'المسافات',
        spec: 'foundations/layout/understanding-layout/spacing',
        rule:
            'الوحدة الأساسية 8dp وبنستخدم أنصافها (4). الـ padding جوه العنصر، '
            'والـ gap بين العناصر، ونحطهم على الأب بدل margin على الأولاد. '
            'هامش الصفحة 16 في المضغوط و24 من المتوسط. أقل مساحة لمس 48.',
        children: [
          for (final (n, v) in const [
            ('xs', TashilSpacing.xs),
            ('sm', TashilSpacing.sm),
            ('md', TashilSpacing.md),
            ('lg', TashilSpacing.lg),
            ('xl', TashilSpacing.xl),
            ('xxl', TashilSpacing.xxl),
          ])
            Padding(
              padding: const EdgeInsets.only(bottom: TashilSpacing.xs),
              child: Row(
                children: [
                  SizedBox(
                    width: 64,
                    child: Text('$n ${v.toInt()}', style: text.labelMedium),
                  ),
                  Container(width: v * 4, height: 12, color: s.primary),
                ],
              ),
            ),
        ],
      ),
      const SpecSection(
        title: 'الحركة',
        m3: 'Motion · springs (M3 Expressive)',
        spec: 'styles/motion/overview',
        rule:
            'كل حركة داخل الشاشة spring من TashilSpring. Spatial للمكان '
            'والحجم والشكل (بيعمل نطّة)، Effects للون والشفافية (من غير '
            'نطّة). الانتقال بين الشاشات Durations + Easing.',
        children: [_MotionDemo()],
      ),
    ]);
  }
}

class _MotionDemo extends StatefulWidget {
  const _MotionDemo();

  @override
  State<_MotionDemo> createState() => _MotionDemoState();
}

class _MotionDemoState extends State<_MotionDemo> {
  bool _on = false;

  static const _spatial = [
    (TashilSpring.fastSpatial, 'fast spatial'),
    (TashilSpring.defaultSpatial, 'default spatial'),
    (TashilSpring.slowSpatial, 'slow spatial'),
    (TashilSpring.standardDefaultSpatial, 'standard default'),
  ];

  static const _effects = [
    (TashilSpring.fastEffects, 'fast effects'),
    (TashilSpring.defaultEffects, 'default effects'),
    (TashilSpring.slowEffects, 'slow effects'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;

    Widget label(TashilSpring sp, String name) => Text(
      '$name · damping ${sp.dampingRatio} · stiffness '
      '${sp.stiffness.toInt()} · ${sp.duration.inMilliseconds}ms',
      style: text.labelSmall?.copyWith(color: s.onSurfaceVariant),
      textDirection: TextDirection.ltr,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        FilledButton.icon(
          onPressed: () => setState(() => _on = !_on),
          icon: const Icon(Icons.play_arrow),
          label: const Text('شغّل الحركة'),
        ),
        const SizedBox(height: TashilSpacing.md),
        for (final (sp, name) in _spatial) ...[
          label(sp, name),
          Container(
            height: 40,
            margin: const EdgeInsets.only(bottom: TashilSpacing.sm),
            decoration: BoxDecoration(
              color: s.surfaceContainerHighest,
              borderRadius: BorderRadius.circular(TashilRadius.full),
            ),
            child: AnimatedAlign(
              duration: TashilMotion.scaled(context, sp.duration),
              curve: sp.curve,
              alignment: _on
                  ? AlignmentDirectional.centerEnd
                  : AlignmentDirectional.centerStart,
              child: Container(
                width: 40,
                height: 40,
                decoration: BoxDecoration(
                  color: s.primary,
                  shape: BoxShape.circle,
                ),
              ),
            ),
          ),
        ],
        const SizedBox(height: TashilSpacing.sm),
        for (final (sp, name) in _effects) ...[
          label(sp, name),
          AnimatedContainer(
            duration: TashilMotion.scaled(context, sp.duration),
            curve: sp.curve,
            height: 32,
            margin: const EdgeInsets.only(bottom: TashilSpacing.sm),
            decoration: BoxDecoration(
              color: _on ? s.tertiary : s.tertiaryContainer,
              borderRadius: BorderRadius.circular(TashilRadius.small),
            ),
          ),
        ],
      ],
    );
  }
}
