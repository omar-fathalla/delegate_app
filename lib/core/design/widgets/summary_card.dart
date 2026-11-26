import 'package:material_ui/material_ui.dart';

import '../tokens.dart';

/// One label / value pair in a [SummaryCard]'s bottom row.
@immutable
class SummaryFact {
  const SummaryFact({required this.label, required this.value, this.icon});

  /// Short name of the value ("الدخول"), shown small above it.
  final String label;

  /// The value itself ("11:14 م"). Wrap numbers, times and codes in
  /// `Bidi.ltr()` when they sit in Arabic text.
  final String value;

  /// Optional leading icon, drawn in `primary`.
  final IconData? icon;
}

/// **Summary card** (P-07, built from C-22 cards; TAS-387, user decision
/// 2026-11-27). A card whose content fills its width instead of stacking
/// short lines on one side:
///
/// * **Header:** a leading icon on `primary` / `onPrimary` (the card-icon
///   rule), a headline (`titleMedium`) with a subhead (`bodySmall`,
///   `onSurfaceVariant`) and optional compact status [labels] under them,
///   and on the end side one prominent value ([trailingValue],
///   `headlineSmall` in `primary`) with its caption.
/// * **Facts row:** label-over-value pairs ([facts]) sharing the full width
///   equally, under a divider.
///
/// Built only from the official [Card.filled], the text roles, the colour
/// roles and the spacing tokens; no hand-picked colours or sizes. Use it for
/// records the person scans in a list: an attendance session, a leave
/// request, a task, a penalty.
class SummaryCard extends StatelessWidget {
  const SummaryCard({
    super.key,
    required this.icon,
    required this.title,
    this.subtitle,
    this.labels = const [],
    this.trailingValue,
    this.trailingCaption,
    this.trailingIcon,
    this.trailingMuted = false,
    this.facts = const [],
    this.onTap,
    this.margin = const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
  });

  final IconData icon;
  final String title;
  final String? subtitle;

  /// Compact status labels under the subtitle (see [SummaryLabel]).
  final List<Widget> labels;

  /// The one number that matters most ("01:35", "5,000 ج.م").
  final String? trailingValue;
  final String? trailingCaption;
  final IconData? trailingIcon;

  /// Shows [trailingValue] in `onSurfaceVariant` (not started, zero).
  final bool trailingMuted;

  final List<SummaryFact> facts;
  final VoidCallback? onTap;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final header = Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Container(
          padding: const EdgeInsets.all(TashilSpacing.sm),
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
          child: Icon(icon, size: 20, color: cs.onPrimary),
        ),
        const SizedBox(width: TashilSpacing.md),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: tt.titleMedium,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null && subtitle!.isNotEmpty)
                Text(
                  subtitle!,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              if (labels.isNotEmpty) ...[
                const SizedBox(height: TashilSpacing.xs),
                Wrap(
                  spacing: TashilSpacing.sm,
                  runSpacing: TashilSpacing.xs,
                  children: labels,
                ),
              ],
            ],
          ),
        ),
        if (trailingValue != null) ...[
          const SizedBox(width: TashilSpacing.md),
          Column(
            crossAxisAlignment: CrossAxisAlignment.end,
            children: [
              Text(
                trailingValue!,
                key: const Key('summary_card_trailing_value'),
                style: tt.headlineSmall?.copyWith(
                  color: trailingMuted ? cs.onSurfaceVariant : cs.primary,
                  fontWeight: FontWeight.w700,
                ),
              ),
              if (trailingCaption != null)
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    if (trailingIcon != null) ...[
                      Icon(trailingIcon, size: 14, color: cs.onSurfaceVariant),
                      const SizedBox(width: TashilSpacing.xs),
                    ],
                    Text(
                      trailingCaption!,
                      style: tt.labelSmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
            ],
          ),
        ],
      ],
    );

    Widget fact(SummaryFact f) => Expanded(
      child: Row(
        children: [
          if (f.icon != null) ...[
            Icon(f.icon, size: 20, color: cs.primary),
            const SizedBox(width: TashilSpacing.sm),
          ],
          Flexible(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  f.label,
                  style: tt.labelSmall?.copyWith(color: cs.onSurfaceVariant),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
                Text(
                  f.value,
                  style: tt.titleSmall,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ],
      ),
    );

    return Card.filled(
      margin: margin,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              header,
              if (facts.isNotEmpty) ...[
                const Divider(height: TashilSpacing.xl),
                Row(children: [for (final f in facts) fact(f)]),
              ],
            ],
          ),
        ),
      ),
    );
  }
}

/// Compact read-only status label for a [SummaryCard] (a container role with
/// its `on` colour, never a tinted card or an alpha border).
class SummaryLabel extends StatelessWidget {
  const SummaryLabel(
    this.text, {
    super.key,
    required this.container,
    required this.onContainer,
  });

  final String text;
  final Color container;
  final Color onContainer;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: TashilSpacing.sm,
        vertical: TashilSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(TashilRadius.small),
      ),
      child: Text(
        text,
        style: Theme.of(
          context,
        ).textTheme.labelSmall?.copyWith(color: onContainer),
      ),
    );
  }
}
