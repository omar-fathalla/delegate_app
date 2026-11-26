import 'package:material_ui/material_ui.dart';

import '../../../core/design/tokens.dart';

/// The M3 colour roles grouped like m3.material.io/styles/color/roles:
/// each swatch shows a fill with its "on" colour and their contrast ratio,
/// so switching light/dark and the three contrast levels (app bar) shows
/// every pair staying readable.
class ColorRolesDemo extends StatelessWidget {
  const ColorRolesDemo({super.key});

  @override
  Widget build(BuildContext context) {
    final s = Theme.of(context).colorScheme;
    final sem = TashilSemanticColors.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _Group(
          title: 'الأساسي (Primary)',
          use: 'أهم حاجة في الشاشة: الـ FAB، الزرار الأساسي، الحالة النشطة.',
          swatches: [
            _S('primary', s.primary, s.onPrimary),
            _S('primaryContainer', s.primaryContainer, s.onPrimaryContainer),
          ],
        ),
        _Group(
          title: 'الثانوي (Secondary)',
          use:
              'أقل بروز: شرايح الفلترة، الزرار الـ tonal، العنصر المختار '
              'في شريط التنقل.',
          swatches: [
            _S('secondary', s.secondary, s.onSecondary),
            _S(
              'secondaryContainer',
              s.secondaryContainer,
              s.onSecondaryContainer,
            ),
          ],
        ),
        _Group(
          title: 'الثالث (Tertiary)',
          use: 'لمسات صغيرة تلفت النظر من غير استعجال: badge، اقتراح.',
          swatches: [
            _S('tertiary', s.tertiary, s.onTertiary),
            _S('tertiaryContainer', s.tertiaryContainer, s.onTertiaryContainer),
          ],
        ),
        _Group(
          title: 'الخطأ (Error)',
          use: 'للأخطاء بس. ثابت: مش بيتغير مع لون البذرة.',
          swatches: [
            _S('error', s.error, s.onError),
            _S('errorContainer', s.errorContainer, s.onErrorContainer),
          ],
        ),
        _Group(
          title: 'نجاح وتحذير (خاص بتسهيل)',
          use:
              'ألوان ثابتة زي الخطأ: أخضر متوفر، برتقالي قرب يخلص. '
              'بتتولد لكل وضع ومستوى تباين.',
          swatches: [
            _S('success', sem.success, sem.onSuccess),
            _S(
              'successContainer',
              sem.successContainer,
              sem.onSuccessContainer,
            ),
            _S('warning', sem.warning, sem.onWarning),
            _S(
              'warningContainer',
              sem.warningContainer,
              sem.onWarningContainer,
            ),
          ],
        ),
        _Group(
          title: 'الأسطح (Surface)',
          use:
              'الخلفية surface، والتنقل surfaceContainer، في كل المقاسات. '
              'الكلام onSurface، والأقل أهمية onSurfaceVariant.',
          swatches: [
            _S('surface', s.surface, s.onSurface),
            _S('surfaceContainerLowest', s.surfaceContainerLowest, s.onSurface),
            _S('surfaceContainerLow', s.surfaceContainerLow, s.onSurface),
            _S('surfaceContainer', s.surfaceContainer, s.onSurface),
            _S('surfaceContainerHigh', s.surfaceContainerHigh, s.onSurface),
            _S(
              'surfaceContainerHighest · onSurfaceVariant',
              s.surfaceContainerHighest,
              s.onSurfaceVariant,
            ),
          ],
        ),
        _Group(
          title: 'المعكوس (Inverse)',
          use: 'عكس اللي حواليه، زي السنيك بار: الزرار inversePrimary.',
          swatches: [
            _S('inverseSurface', s.inverseSurface, s.onInverseSurface),
            _S(
              'inverseSurface · inversePrimary',
              s.inverseSurface,
              s.inversePrimary,
            ),
          ],
        ),
        _Group(
          title: 'الحدود (Outline)',
          use:
              'outline للحدود المهمة (حقل النص). outlineVariant للفواصل '
              'والكروت وحدود فيها كلام واضح. الرقم هو التباين مع surface.',
          swatches: [
            _S('outline', s.surface, s.outline, line: true),
            _S('outlineVariant', s.surface, s.outlineVariant, line: true),
          ],
        ),
        _Group(
          title: 'إضافي (Add-on)',
          use:
              'نادراً: fixed نفس اللون في الفاتح والداكن، وsurfaceDim/Bright '
              'بيحافظوا على إضاءتهم. مش للأماكن اللي محتاجة تباين.',
          swatches: [
            _S('primaryFixed', s.primaryFixed, s.onPrimaryFixed),
            _S('primaryFixedDim', s.primaryFixedDim, s.onPrimaryFixedVariant),
            _S('secondaryFixed', s.secondaryFixed, s.onSecondaryFixed),
            _S('tertiaryFixed', s.tertiaryFixed, s.onTertiaryFixed),
            _S('surfaceDim', s.surfaceDim, s.onSurface),
            _S('surfaceBright', s.surfaceBright, s.onSurface),
          ],
        ),
      ],
    );
  }
}

class _S {
  const _S(this.name, this.bg, this.fg, {this.line = false});

  final String name;
  final Color bg;
  final Color fg;

  /// Show [fg] as a line on [bg] (outline roles) instead of text.
  final bool line;
}

class _Group extends StatelessWidget {
  const _Group({
    required this.title,
    required this.use,
    required this.swatches,
  });

  final String title;
  final String use;
  final List<_S> swatches;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    final scheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.only(bottom: TashilSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Text(title, style: text.titleSmall),
          Text(
            use,
            style: text.bodySmall?.copyWith(color: scheme.onSurfaceVariant),
          ),
          const SizedBox(height: TashilSpacing.sm),
          ClipRRect(
            borderRadius: BorderRadius.circular(TashilRadius.medium),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [for (final w in swatches) _row(text, w)],
            ),
          ),
        ],
      ),
    );
  }

  Widget _row(TextTheme text, _S w) {
    final _S(:name, :bg, :fg, :line) = w;
    final ratio = '${contrastRatio(bg, fg).toStringAsFixed(1)}:1';
    final style = text.labelLarge?.copyWith(
      color: line ? null : fg,
      fontFeatures: const [FontFeature.tabularFigures()],
    );
    return Container(
      height: 44,
      padding: const EdgeInsets.symmetric(horizontal: TashilSpacing.md),
      color: bg,
      child: Row(
        textDirection: TextDirection.ltr,
        children: [
          if (line) ...[
            Container(width: 32, height: 2, color: fg),
            const SizedBox(width: TashilSpacing.sm),
          ],
          Expanded(
            child: Text(
              name,
              style: style,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ),
          Text(ratio, style: style),
        ],
      ),
    );
  }
}
