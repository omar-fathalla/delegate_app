import 'package:material_ui/material_ui.dart';

import '../color_schemes.dart';
import '../tokens.dart';
import 'button_group.dart';

/// Appearance settings for the colour scheme: source (Tashil, store
/// colour, wallpaper, M3 baseline), fidelity and contrast level. Changes
/// the [TashilColorController] above the app, so the whole app recolours
/// at once. Ready for the settings screen.
class ColorSchemePicker extends StatelessWidget {
  const ColorSchemePicker({super.key});

  static const _contrastLabels = {
    TashilContrast.standard: 'عادي',
    TashilContrast.medium: 'متوسط',
    TashilContrast.high: 'عالي',
  };

  @override
  Widget build(BuildContext context) {
    final controller = TashilColorController.of(context);
    final s = controller.value;
    final text = Theme.of(context).textTheme;
    final wallpaper = controller.wallpaperAvailable;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Text('مصدر الألوان', style: text.titleSmall),
        RadioGroup<TashilColorSource>(
          groupValue: s.source,
          onChanged: (v) => controller.update((c) => c.copyWith(source: v)),
          child: Column(
            children: [
              const RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: TashilColorSource.brand,
                title: Text('ألوان تسهيل'),
                subtitle: Text('ثابتة ونفس الشكل على كل جهاز (الافتراضي)'),
              ),
              const RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: TashilColorSource.store,
                title: Text('لون المحل'),
                subtitle: Text('ثابتة من لون البراند بتاع المحل'),
              ),
              RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: TashilColorSource.wallpaper,
                title: const Text('من خلفية الجهاز'),
                subtitle: Text(
                  wallpaper
                      ? 'بتتغير مع خلفية الشاشة'
                      : 'الجهاز ده مش بيدعمها (محتاجة أندرويد 12)، '
                            'فهتظهر ألوان تسهيل',
                ),
              ),
              const RadioListTile(
                contentPadding: EdgeInsets.zero,
                value: TashilColorSource.baseline,
                title: Text('ألوان M3 الأساسية'),
                subtitle: Text('البنفسجي الافتراضي، للمقارنة بمراجع M3'),
              ),
            ],
          ),
        ),
        if (s.source == TashilColorSource.store) ...[
          const SizedBox(height: TashilSpacing.sm),
          Text('لون المحل', style: text.titleSmall),
          const SizedBox(height: TashilSpacing.sm),
          Wrap(
            spacing: TashilSpacing.xs,
            children: [
              for (final c in storeColorPresets)
                _ColorDot(
                  color: c,
                  selected: c == s.storeColor,
                  onTap: () =>
                      controller.update((x) => x.copyWith(storeColor: c)),
                ),
            ],
          ),
        ],
        if (s.source != TashilColorSource.baseline)
          SwitchListTile(
            contentPadding: EdgeInsets.zero,
            title: const Text('قريب من اللون الأصلي'),
            subtitle: const Text(
              'الألوان تفضل أقرب للون المصدر بدل النسخة الهادية',
            ),
            value: s.fidelity,
            onChanged: (v) => controller.update((c) => c.copyWith(fidelity: v)),
          ),
        const SizedBox(height: TashilSpacing.sm),
        Text('التباين', style: text.titleSmall),
        const SizedBox(height: TashilSpacing.sm),
        ButtonGroup<TashilContrast>(
          variant: ButtonGroupVariant.connected,
          expand: true,
          selected: {s.contrast},
          onSelectionChanged: (v) =>
              controller.update((c) => c.copyWith(contrast: v.first)),
          items: [
            for (final c in TashilContrast.values)
              ButtonGroupItem(value: c, label: _contrastLabels[c]),
          ],
        ),
      ],
    );
  }
}

class _ColorDot extends StatelessWidget {
  const _ColorDot({
    required this.color,
    required this.selected,
    required this.onTap,
  });

  final Color color;
  final bool selected;
  final VoidCallback onTap;

  @override
  Widget build(BuildContext context) {
    final hex = color.toARGB32().toRadixString(16).substring(2).toUpperCase();
    return Semantics(
      button: true,
      selected: selected,
      label: 'لون #$hex',
      child: InkResponse(
        onTap: onTap,
        radius: 24,
        child: SizedBox.square(
          dimension: TashilSizes.minTouch,
          child: Center(
            child: Container(
              width: 36,
              height: 36,
              decoration: BoxDecoration(
                color: color,
                shape: BoxShape.circle,
                border: selected
                    ? Border.all(
                        color: Theme.of(context).colorScheme.onSurface,
                        width: 3,
                      )
                    : null,
              ),
              child: selected
                  ? Icon(
                      Icons.check,
                      size: 20,
                      color: color.computeLuminance() > 0.4
                          ? Colors.black
                          : Colors.white,
                    )
                  : null,
            ),
          ),
        ),
      ),
    );
  }
}
