import 'dart:async';

import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';
import '../../../core/design/typography.dart';
import '../../../core/design/widgets/button_group.dart';

/// The M3 type scale (baseline and emphasized), where emphasized styles
/// go, tabular figures, links and an editorial hero number.
class TypographyDemo extends StatefulWidget {
  const TypographyDemo({super.key});

  @override
  State<TypographyDemo> createState() => _TypographyDemoState();
}

class _TypographyDemoState extends State<TypographyDemo> {
  var _emphasized = false;

  Widget _caption(String s) => Padding(
    padding: const EdgeInsets.only(
      top: TashilSpacing.xl,
      bottom: TashilSpacing.sm,
    ),
    child: Text(s, style: Theme.of(context).textTheme.titleSmall),
  );

  @override
  Widget build(BuildContext context) {
    final base = Theme.of(context).textTheme;
    final emph = TashilType.emphasized(context);
    final scheme = Theme.of(context).colorScheme;
    final t = _emphasized ? emph : base;
    final styles = <(String, TextStyle?)>[
      ('displayLarge', t.displayLarge),
      ('displayMedium', t.displayMedium),
      ('displaySmall', t.displaySmall),
      ('headlineLarge', t.headlineLarge),
      ('headlineMedium', t.headlineMedium),
      ('headlineSmall', t.headlineSmall),
      ('titleLarge', t.titleLarge),
      ('titleMedium', t.titleMedium),
      ('titleSmall', t.titleSmall),
      ('bodyLarge', t.bodyLarge),
      ('bodyMedium', t.bodyMedium),
      ('bodySmall', t.bodySmall),
      ('labelLarge', t.labelLarge),
      ('labelMedium', t.labelMedium),
      ('labelSmall', t.labelSmall),
    ];
    String spec(TextStyle s) {
      final size = s.fontSize!;
      final line = (size * s.height!).round();
      return '${size.round()}/$line · ${s.fontWeight!.value}';
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        ButtonGroup<bool>(
          variant: ButtonGroupVariant.connected,
          expand: true,
          selected: {_emphasized},
          onSelectionChanged: (v) => setState(() => _emphasized = v.first),
          items: const [
            ButtonGroupItem(value: false, label: 'Baseline (15)'),
            ButtonGroupItem(value: true, label: 'Emphasized (15)'),
          ],
        ),
        const SizedBox(height: TashilSpacing.md),
        for (final (name, style) in styles)
          Padding(
            padding: const EdgeInsets.only(bottom: TashilSpacing.sm),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  '$name  ${spec(style!)}',
                  style: base.labelSmall?.copyWith(color: scheme.primary),
                  textDirection: TextDirection.ltr,
                ),
                Text(
                  name.startsWith('display') ? '45.50 ج.م' : 'سكر أبيض 1 كجم',
                  style: style,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        _caption('الـ Emphasized في المكونات: المختار، غير المقروء، الأهم'),
        Card.outlined(
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              ListTile(
                selected: true,
                title: Text('فاتورة 431', style: emph.bodyLarge),
                subtitle: const Text('مختارة: emphasized'),
              ),
              ListTile(
                title: Text('رسالة من المورد', style: emph.bodyLarge),
                subtitle: const Text('مش مقرية: emphasized'),
                trailing: Badge(label: Text('2', style: emph.labelSmall)),
              ),
              const ListTile(
                title: Text('فاتورة 430'),
                subtitle: Text('عادية: baseline'),
              ),
            ],
          ),
        ),
        _caption('أرقام بنفس العرض (tabular)'),
        const _TabularDemo(),
        _caption('روابط: primary أو tertiary، ودايماً تحتها خط'),
        Wrap(
          spacing: TashilSpacing.lg,
          children: [
            LinkText('شروط الاستخدام', onTap: () {}),
            LinkText('ساعدني', quiet: true, onTap: () {}),
          ],
        ),
        _caption('معالجة تحريرية: لحظة مميزة بالخط'),
        const _EditorialDemo(),
      ],
    );
  }
}

class _TabularDemo extends StatefulWidget {
  const _TabularDemo();

  @override
  State<_TabularDemo> createState() => _TabularDemoState();
}

class _TabularDemoState extends State<_TabularDemo> {
  Timer? _timer;
  var _seconds = 0;

  @override
  void dispose() {
    _timer?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final mm = (_seconds ~/ 60).toString().padLeft(2, '0');
    final ss = (_seconds % 60).toString().padLeft(2, '0');
    const prices = ['1,111.10', '888.80', '45.50', '10,000.00'];
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Expanded(
          // Right-aligned so units line up with units; the currency is
          // in the header, not repeated on every row.
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text('السعر (ج.م)', style: text.labelMedium),
              for (final p in prices)
                Text(
                  p,
                  style: text.bodyLarge,
                  textDirection: TextDirection.ltr,
                ),
            ],
          ),
        ),
        const SizedBox(width: TashilSpacing.xl),
        Column(
          children: [
            Text(
              '$mm:$ss',
              style: text.headlineMedium,
              textDirection: TextDirection.ltr,
            ),
            TextButton(
              onPressed: () => setState(() {
                if (_timer == null) {
                  _timer = Timer.periodic(
                    const Duration(seconds: 1),
                    (_) => setState(() => _seconds++),
                  );
                } else {
                  _timer!.cancel();
                  _timer = null;
                }
              }),
              child: Text(_timer == null ? 'شغّل العداد' : 'وقّف'),
            ),
          ],
        ),
      ],
    );
  }
}

class _EditorialDemo extends StatefulWidget {
  const _EditorialDemo();

  @override
  State<_EditorialDemo> createState() => _EditorialDemoState();
}

class _EditorialDemoState extends State<_EditorialDemo> {
  static const _target = 20000.0;
  var _sales = 12500.0;

  @override
  Widget build(BuildContext context) {
    final e = TashilType.editorial(context);
    final s = Theme.of(context).colorScheme;
    final progress = _sales / _target;
    return Card.filled(
      margin: EdgeInsets.zero,
      color: s.primaryContainer,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.xl),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'مبيعات النهارده',
              style: e.heroCaption.copyWith(color: s.onPrimaryContainer),
            ),
            // The weight follows progress towards the day's target.
            TweenAnimationBuilder<double>(
              tween: Tween(end: progress),
              duration: const Duration(milliseconds: 600),
              builder: (c, t, _) => FittedBox(
                fit: BoxFit.scaleDown,
                alignment: AlignmentDirectional.centerStart,
                child: Text(
                  (_sales).toStringAsFixed(0),
                  style: e
                      .heroNumberAt(t)
                      .copyWith(color: s.onPrimaryContainer),
                  textDirection: TextDirection.ltr,
                ),
              ),
            ),
            Text(
              'الهدف ${_target.toStringAsFixed(0)} ج.م',
              style: Theme.of(context).textTheme.bodyMedium
                  ?.copyWith(color: s.onPrimaryContainer),
            ),
            const SizedBox(height: TashilSpacing.sm),
            FilledButton.tonal(
              onPressed: () => setState(
                () => _sales = _sales >= _target ? 12500 : _sales + 2500,
              ),
              child: const Text('فاتورة جديدة'),
            ),
          ],
        ),
      ),
    );
  }
}
