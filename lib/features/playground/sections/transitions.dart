import 'dart:async';

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';

import '../../../core/design/motion.dart';
import '../../../core/design/tokens.dart';
import '../../../core/design/widgets/button_group.dart';
import '../sample_widgets.dart';
import 'common.dart';

/// Easing/duration pairs and the M3 transition patterns, each on a real
/// Tashil flow.
class TransitionsSection extends StatelessWidget {
  const TransitionsSection({super.key});

  @override
  Widget build(BuildContext context) {
    return const SectionList([
      SpecSection(
        title: 'أزواج الـ Easing والمدة',
        m3: 'Easing and duration',
        spec: 'styles/motion/easing-and-duration',
        rule:
            'للانتقالات بس. داخل الشاشة نستخدم springs. Emphasized 500ms '
            'لما الحاجة تبدأ وتخلص على الشاشة، Decelerate 400ms للدخول، '
            'Accelerate 200ms للخروج.',
        children: [_EasingDemo()],
      ),
      SpecSection(
        title: 'تحوّل الحاوية',
        m3: 'Container transform',
        spec: 'styles/motion/transitions/transition-patterns',
        rule: 'لما عنصر يفتح لتفاصيله: كارت الصنف بيكبر ويبقى شاشة الصنف.',
        children: [_ContainerTransformDemo()],
      ),
      SpecSection(
        title: 'للأمام وللخلف',
        m3: 'Forward and backward',
        spec: 'styles/motion/transitions/transition-patterns',
        rule:
            'التنقل في خطوات: السلة ثم الدفع ثم الإيصال. ده الانتقال '
            'الافتراضي لكل الشاشات (في الثيم)، وبيتعكس صح في العربي.',
        children: [_ForwardBackwardDemo()],
      ),
      SpecSection(
        title: 'جانبي',
        m3: 'Lateral',
        spec: 'styles/motion/transitions/transition-patterns',
        rule: 'بين صفحات في نفس المستوى، زي تابات التقرير.',
        children: [_LateralDemo()],
      ),
      SpecSection(
        title: 'المستوى الأعلى',
        m3: 'Top level',
        spec: 'styles/motion/transitions/transition-patterns',
        rule: 'تبديل الوجهات الرئيسية من شريط التنقل: Fade through.',
        children: [_TopLevelDemo()],
      ),
      SpecSection(
        title: 'دخول وخروج',
        m3: 'Enter and exit',
        spec: 'styles/motion/transitions/transition-patterns',
        rule: 'حوارات ومنيوهات جوه الشاشة: Fade + scale.',
        children: [_EnterExitDemo()],
      ),
      SpecSection(
        title: 'هيكل التحميل',
        m3: 'Skeleton loaders',
        spec: 'styles/motion/transitions/transition-patterns',
        rule:
            'وقت تحميل قائمة (مزامنة، تقرير): أشكال رمادية بنفس مكان '
            'المحتوى، وبعدين المحتوى يظهر بـ fade.',
        children: [_SkeletonDemo()],
      ),
    ]);
  }
}

Widget _frame(BuildContext context, Widget child, {double height = 260}) =>
    Container(
      height: height,
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        border: Border.all(color: Theme.of(context).colorScheme.outlineVariant),
        borderRadius: BorderRadius.circular(TashilRadius.medium),
      ),
      child: child,
    );

// ---------------------------------------------------------------- easing

class _EasingDemo extends StatefulWidget {
  const _EasingDemo();

  @override
  State<_EasingDemo> createState() => _EasingDemoState();
}

class _EasingDemoState extends State<_EasingDemo> {
  bool _shown = true;
  bool _wide = false;

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final enter = TashilEasing.emphasizedDecelerate;
    final exit = TashilEasing.emphasizedAccelerate;
    final both = TashilEasing.emphasized;

    Widget caption(String t) => Text(
      t,
      style: text.labelSmall?.copyWith(color: s.onSurfaceVariant),
      textDirection: TextDirection.ltr,
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Wrap(
          spacing: TashilSpacing.sm,
          children: [
            OutlinedButton(
              onPressed: () => setState(() => _shown = !_shown),
              child: Text(_shown ? 'خروج' : 'دخول'),
            ),
            OutlinedButton(
              onPressed: () => setState(() => _wide = !_wide),
              child: const Text('تكبير'),
            ),
          ],
        ),
        const SizedBox(height: TashilSpacing.md),
        caption(
          _shown
              ? 'enter · emphasized decelerate · ${enter.duration.inMilliseconds}ms'
              : 'exit · emphasized accelerate · ${exit.duration.inMilliseconds}ms',
        ),
        SizedBox(
          height: 56,
          child: ClipRect(
            child: AnimatedSlide(
              offset: _shown ? Offset.zero : const Offset(0, 1.2),
              duration: TashilMotion.scaled(
                context,
                (_shown ? enter : exit).duration,
              ),
              curve: (_shown ? enter : exit).curve,
              child: Container(
                height: 48,
                alignment: AlignmentDirectional.centerStart,
                padding: const EdgeInsets.symmetric(
                  horizontal: TashilSpacing.lg,
                ),
                decoration: BoxDecoration(
                  color: s.inverseSurface,
                  borderRadius: BorderRadius.circular(TashilRadius.small),
                ),
                child: Text(
                  'تم حفظ الفاتورة',
                  style: TextStyle(color: s.onInverseSurface),
                ),
              ),
            ),
          ),
        ),
        const SizedBox(height: TashilSpacing.sm),
        caption(
          'begin and end on screen · emphasized · '
          '${both.duration.inMilliseconds}ms',
        ),
        AnimatedContainer(
          duration: TashilMotion.scaled(context, both.duration),
          curve: both.curve,
          height: _wide ? 120 : 56,
          width: _wide ? double.infinity : 120,
          decoration: BoxDecoration(
            color: s.primaryContainer,
            borderRadius: BorderRadius.circular(
              _wide ? TashilRadius.extraLarge : TashilRadius.medium,
            ),
          ),
        ),
      ],
    );
  }
}

// ------------------------------------------------------ container transform

class _ContainerTransformDemo extends StatelessWidget {
  const _ContainerTransformDemo();

  static const _products = [
    ('سكر أبيض 1 كجم', 4550, 34.0),
    ('زيت عباد الشمس', 8500, 4.0),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Row(
      children: [
        for (final (i, p) in _products.indexed) ...[
          if (i > 0) const SizedBox(width: TashilSpacing.sm),
          Expanded(
            child: OpenContainer<void>(
              transitionDuration: TashilTransitions.containerTransform(context),
              closedColor: s.surfaceContainerHighest,
              openColor: s.surface,
              middleColor: s.surfaceContainer,
              closedElevation: 0,
              closedShape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(TashilRadius.medium),
              ),
              closedBuilder: (context, open) => InkWell(
                onTap: open,
                child: Padding(
                  padding: const EdgeInsets.all(TashilSpacing.md),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Icon(Icons.inventory_2_outlined, color: s.primary),
                      const SizedBox(height: TashilSpacing.sm),
                      Text(p.$1, style: text.titleSmall, maxLines: 1),
                      MoneyText(p.$2, style: text.bodyMedium),
                    ],
                  ),
                ),
              ),
              openBuilder: (context, close) => Scaffold(
                appBar: AppBar(
                  leading: CloseButton(onPressed: close),
                  title: Text(p.$1),
                ),
                body: ListView(
                  padding: const EdgeInsets.all(TashilSpacing.page),
                  children: [
                    Container(
                      height: 160,
                      decoration: BoxDecoration(
                        color: s.secondaryContainer,
                        borderRadius: BorderRadius.circular(TashilRadius.large),
                      ),
                      child: Icon(
                        Icons.inventory_2_outlined,
                        size: 64,
                        color: s.onSecondaryContainer,
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.lg),
                    MoneyText(p.$2, style: text.headlineMedium),
                    const SizedBox(height: TashilSpacing.sm),
                    Row(
                      children: [
                        const Text('الرصيد: '),
                        StockBadge(quantity: p.$3, minStock: 6, unit: 'قطعة'),
                      ],
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

// ------------------------------------------------------- forward/backward

class _ForwardBackwardDemo extends StatelessWidget {
  const _ForwardBackwardDemo();

  @override
  Widget build(BuildContext context) {
    void push(BuildContext context, int step) {
      Navigator.of(context)
          .push(MaterialPageRoute<void>(builder: (_) => _FlowStep(step: step)));
    }

    return FilledButton.icon(
      onPressed: () => push(context, 0),
      icon: const Icon(Icons.shopping_cart_outlined),
      label: const Text('افتح السلة'),
    );
  }
}

class _FlowStep extends StatelessWidget {
  const _FlowStep({required this.step});

  final int step;

  static const _titles = ['السلة', 'الدفع', 'الإيصال'];
  static const _icons = [
    Icons.shopping_cart_outlined,
    Icons.payments_outlined,
    Icons.receipt_long_outlined,
  ];

  @override
  Widget build(BuildContext context) {
    final last = step == _titles.length - 1;
    return Scaffold(
      appBar: AppBar(title: Text(_titles[step])),
      body: Center(
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(_icons[step], size: 64),
            const SizedBox(height: TashilSpacing.lg),
            Text(
              'خطوة ${step + 1} من ${_titles.length}',
              style: Theme.of(context).textTheme.titleMedium,
            ),
            const SizedBox(height: TashilSpacing.xl),
            FilledButton(
              onPressed: last
                  ? () => Navigator.of(context).popUntil((r) => r.isFirst)
                  : () => Navigator.of(context).push(
                      MaterialPageRoute<void>(
                        builder: (_) => _FlowStep(step: step + 1),
                      ),
                    ),
              child: Text(last ? 'إنهاء' : 'التالي: ${_titles[step + 1]}'),
            ),
          ],
        ),
      ),
    );
  }
}

// ---------------------------------------------------------------- lateral

class _LateralDemo extends StatefulWidget {
  const _LateralDemo();

  @override
  State<_LateralDemo> createState() => _LateralDemoState();
}

class _LateralDemoState extends State<_LateralDemo> {
  int _index = 0;
  bool _reverse = false;

  static const _pages = [
    ('المبيعات', Icons.point_of_sale_outlined, 345000),
    ('المرتجعات', Icons.undo, 12000),
    ('المصروفات', Icons.receipt_long_outlined, 45000),
  ];

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    return Column(
      children: [
        ButtonGroup<int>(
          variant: ButtonGroupVariant.connected,
          expand: true,
          selected: {_index},
          onSelectionChanged: (v) => setState(() {
            _reverse = v.first < _index;
            _index = v.first;
          }),
          items: [
            for (final (i, p) in _pages.indexed)
              ButtonGroupItem(value: i, label: p.$1),
          ],
        ),
        const SizedBox(height: TashilSpacing.sm),
        _frame(
          context,
          PageTransitionSwitcher(
            duration: TashilTransitions.switcher(context),
            reverse: _reverse,
            transitionBuilder: (child, a, b) =>
                TashilTransitions.sharedX(context, a, b, child),
            child: Center(
              key: ValueKey(_index),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(_pages[_index].$2, size: 40),
                  Text(_pages[_index].$1, style: text.titleMedium),
                  MoneyText(_pages[_index].$3, style: text.headlineSmall),
                ],
              ),
            ),
          ),
          height: 140,
        ),
      ],
    );
  }
}

// -------------------------------------------------------------- top level

class _TopLevelDemo extends StatefulWidget {
  const _TopLevelDemo();

  @override
  State<_TopLevelDemo> createState() => _TopLevelDemoState();
}

class _TopLevelDemoState extends State<_TopLevelDemo> {
  int _index = 0;

  static const _dest = [
    (Icons.point_of_sale, 'البيع'),
    (Icons.inventory_2, 'المخزون'),
    (Icons.bar_chart, 'التقارير'),
  ];

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    return _frame(
      context,
      Scaffold(
        body: PageTransitionSwitcher(
          duration: TashilTransitions.switcher(context),
          transitionBuilder: (child, a, b) => FadeThroughTransition(
            animation: a,
            secondaryAnimation: b,
            fillColor: s.surface,
            child: child,
          ),
          child: Center(
            key: ValueKey(_index),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(_dest[_index].$1, size: 48, color: s.primary),
                Text(_dest[_index].$2),
              ],
            ),
          ),
        ),
        bottomNavigationBar: NavigationBar(
          selectedIndex: _index,
          onDestinationSelected: (i) => setState(() => _index = i),
          destinations: [
            for (final (icon, label) in _dest)
              NavigationDestination(icon: Icon(icon), label: label),
          ],
        ),
      ),
      height: 240,
    );
  }
}

// ------------------------------------------------------------- enter/exit

class _EnterExitDemo extends StatelessWidget {
  const _EnterExitDemo();

  @override
  Widget build(BuildContext context) {
    return OutlinedButton(
      onPressed: () => showModal<void>(
        context: context,
        configuration: FadeScaleTransitionConfiguration(
          transitionDuration: TashilMotion.scaled(
            context,
            TashilEasing.emphasizedDecelerate.duration,
          ),
          reverseTransitionDuration: TashilMotion.scaled(
            context,
            TashilEasing.emphasizedAccelerate.duration,
          ),
        ),
        builder: (c) => AlertDialog(
          title: const Text('خصم على الفاتورة'),
          content: const Text('الخصم هيتطبق على كل الأصناف في السلة.'),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('رجوع'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(c),
              child: const Text('تطبيق'),
            ),
          ],
        ),
      ),
      child: const Text('افتح حوار بـ Fade + scale'),
    );
  }
}

// --------------------------------------------------------------- skeleton

class _SkeletonDemo extends StatefulWidget {
  const _SkeletonDemo();

  @override
  State<_SkeletonDemo> createState() => _SkeletonDemoState();
}

class _SkeletonDemoState extends State<_SkeletonDemo>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );
  bool _loading = false;
  Timer? _timer;

  @override
  void dispose() {
    _timer?.cancel();
    _pulse.dispose();
    super.dispose();
  }

  void _reload() {
    _timer?.cancel();
    setState(() => _loading = true);
    _pulse.repeat(reverse: true);
    _timer = Timer(const Duration(milliseconds: 1800), () {
      if (!mounted) return;
      _pulse.stop();
      setState(() => _loading = false);
    });
  }

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    Widget bar(double w, double h) => Container(
      width: w,
      height: h,
      decoration: BoxDecoration(
        color: s.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(TashilRadius.small),
      ),
    );

    final skeleton = FadeTransition(
      key: const ValueKey('skeleton'),
      opacity: Tween(begin: 0.5, end: 1.0).animate(_pulse),
      child: Column(
        children: [
          for (var i = 0; i < 3; i++)
            Padding(
              padding: const EdgeInsets.all(TashilSpacing.md),
              child: Row(
                children: [
                  bar(TashilSizes.thumbnail, TashilSizes.thumbnail),
                  const SizedBox(width: TashilSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        bar(160, 14),
                        const SizedBox(height: TashilSpacing.sm),
                        bar(90, 12),
                      ],
                    ),
                  ),
                ],
              ),
            ),
        ],
      ),
    );

    const content = Column(
      key: ValueKey('content'),
      children: [
        ProductTile(
          name: 'سكر أبيض 1 كجم',
          pricePiastres: 4550,
          stock: 34,
          minStock: 10,
        ),
        ProductTile(
          name: 'زيت عباد الشمس',
          pricePiastres: 8500,
          stock: 4,
          minStock: 6,
        ),
        ProductTile(
          name: 'أرز مصري 5 كجم',
          pricePiastres: 19500,
          stock: 12,
          minStock: 5,
        ),
      ],
    );

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        OutlinedButton.icon(
          onPressed: _loading ? null : _reload,
          icon: const Icon(Icons.sync),
          label: const Text('مزامنة الأصناف'),
        ),
        const SizedBox(height: TashilSpacing.sm),
        Card.outlined(
          clipBehavior: Clip.antiAlias,
          child: AnimatedSwitcher(
            duration: TashilMotion.scaled(context, TashilMotion.fade.duration),
            switchInCurve: TashilMotion.fade.curve,
            child: _loading ? skeleton : content,
          ),
        ),
      ],
    );
  }
}
