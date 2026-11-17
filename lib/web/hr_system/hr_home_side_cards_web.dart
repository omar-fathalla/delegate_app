// WEB-ONLY: side column of the HR overview (chains, the company feature card
// and the duties guide) plus the shapes and tints the overview shares.
import 'dart:math' as math;

import 'package:flutter/material.dart';

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/admin/presentation/widgets/company_exclusive_card_intro.dart';

/// Tabular figures so times and counts do not shift while they update.
const List<FontFeature> kHrTabularFigures = [FontFeature.tabularFigures()];

/// M3 state layers: hover 0.08, focus and pressed 0.12.
WidgetStateProperty<Color?> hrStateLayer(Color color) =>
    WidgetStateProperty.resolveWith((states) {
      if (states.contains(WidgetState.pressed) ||
          states.contains(WidgetState.focused)) {
        return color.withValues(alpha: 0.12);
      }
      if (states.contains(WidgetState.hovered)) {
        return color.withValues(alpha: 0.08);
      }
      return null;
    });

/// Rounded "cookie" / flower outline from the M3 Expressive shape set,
/// drawn as a polar curve: r = 1 + amplitude * cos(lobes * θ).
class HrExpressiveShape extends StatelessWidget {
  final double size;
  final Color color;
  final int lobes;
  final double amplitude;
  final double rotation;
  final Widget? child;

  const HrExpressiveShape({
    super.key,
    required this.size,
    required this.color,
    this.lobes = 9,
    this.amplitude = 0.06,
    this.rotation = 0,
    this.child,
  });

  /// Nine-lobed cookie used for empty states.
  const HrExpressiveShape.cookie({
    super.key,
    required this.size,
    required this.color,
    this.child,
  }) : lobes = 9,
       amplitude = 0.06,
       rotation = 0;

  @override
  Widget build(BuildContext context) => SizedBox.square(
    dimension: size,
    child: CustomPaint(
      painter: _LobedShapePainter(
        color: color,
        lobes: lobes,
        amplitude: amplitude,
        rotation: rotation,
      ),
      child: child == null ? null : Center(child: child),
    ),
  );
}

class _LobedShapePainter extends CustomPainter {
  _LobedShapePainter({
    required this.color,
    required this.lobes,
    required this.amplitude,
    required this.rotation,
  });

  final Color color;
  final int lobes;
  final double amplitude;
  final double rotation;

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.shortestSide / 2 / (1 + amplitude);
    final path = Path();
    const steps = 180;
    for (var i = 0; i <= steps; i++) {
      final th = i / steps * 2 * math.pi;
      final r = base * (1 + amplitude * math.cos(lobes * th));
      final p =
          c + Offset(math.cos(th + rotation), math.sin(th + rotation)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_LobedShapePainter o) =>
      o.color != color ||
      o.lobes != lobes ||
      o.amplitude != amplitude ||
      o.rotation != rotation;
}

/// Soft container tint for a chain, stable per name.
class HrChainTint {
  final Color background;
  final Color foreground;

  const HrChainTint(this.background, this.foreground);

  static const List<Color> _seeds = [
    Color(0xFF6750A4),
    Color(0xFF006A6A),
    Color(0xFF8B5000),
    Color(0xFF3B6939),
    Color(0xFF00629D),
    Color(0xFF9C4146),
    Color(0xFF7D5260),
  ];
  static final Map<(int, Brightness), HrChainTint> _cache = {};

  static HrChainTint of(String chain, Brightness brightness) {
    var hash = 0;
    for (final unit in chain.trim().codeUnits) {
      hash = (hash * 31 + unit) & 0x7fffffff;
    }
    final seed = hash % _seeds.length;
    return _cache.putIfAbsent((seed, brightness), () {
      final scheme = ColorScheme.fromSeed(
        seedColor: _seeds[seed],
        brightness: brightness,
      );
      return HrChainTint(scheme.primaryContainer, scheme.onPrimaryContainer);
    });
  }
}

String hrChainLetter(String chain) {
  final t = chain.trim();
  return t.isEmpty ? '؟' : String.fromCharCode(t.runes.first);
}

/// Letter avatar for a chain with its soft tint.
class HrChainAvatar extends StatelessWidget {
  final String chain;
  final double size;

  const HrChainAvatar({super.key, required this.chain, this.size = 32});

  @override
  Widget build(BuildContext context) {
    final tint = HrChainTint.of(chain, Theme.of(context).brightness);
    return Container(
      width: size,
      height: size,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: tint.background, shape: BoxShape.circle),
      child: Text(
        hrChainLetter(chain),
        style: TextStyle(
          fontSize: size * 0.44,
          fontWeight: FontWeight.w700,
          color: tint.foreground,
          height: 1.1,
        ),
      ),
    );
  }
}

/// Card surface of the overview: surface-container-low, 28 corners.
class HrOverviewCard extends StatelessWidget {
  final Widget child;
  final EdgeInsetsGeometry padding;

  const HrOverviewCard({
    super.key,
    required this.child,
    this.padding = const EdgeInsets.all(24),
  });

  @override
  Widget build(BuildContext context) => Container(
    padding: padding,
    clipBehavior: Clip.antiAlias,
    decoration: BoxDecoration(
      color: Theme.of(context).colorScheme.surfaceContainerLow,
      borderRadius: BorderRadius.circular(28),
    ),
    child: child,
  );
}

class HrCardTitle extends StatelessWidget {
  final IconData icon;
  final String text;
  final double fontSize;
  final Widget? trailing;

  const HrCardTitle({
    super.key,
    required this.icon,
    required this.text,
    this.fontSize = 17,
    this.trailing,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        Icon(icon, color: cs.primary, size: fontSize + 5),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            text,
            style: TextStyle(
              fontSize: fontSize,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        ?trailing,
      ],
    );
  }
}

/// Short title for the chains card.
///
/// «السلاسل التابع لها مناديبك» doesn't agree (السلاسل is plural, التابع is
/// singular). «سلاسل مناديبك» is the grammatical short form.
const String kHrHomeChainsTitle = 'سلاسل مناديبك';

/// Columns of equal-width chain chips for a card's inner width.
int hrChainGridColumns(double width) {
  if (width >= 720) return 4;
  if (width >= 480) return 3;
  return 2;
}

/// «سلاسل مناديبك»: one equal-width chip per chain; tapping filters the table.
class HrHomeChainsCard extends StatelessWidget {
  final List<String> chains;
  final String? selected;
  final bool enabled;
  final ValueChanged<String?> onSelected;

  const HrHomeChainsCard({
    super.key,
    required this.chains,
    required this.selected,
    required this.onSelected,
    this.enabled = true,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HrOverviewCard(
      key: const ValueKey('hr_home_chains_card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          const HrCardTitle(
            icon: Icons.storefront_rounded,
            text: kHrHomeChainsTitle,
          ),
          const SizedBox(height: 16),
          if (chains.isEmpty)
            Text(
              'لسه مفيش سلاسل مرتبطة بمناديبك',
              style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                const gap = 8.0;
                final columns = hrChainGridColumns(constraints.maxWidth);
                final itemWidth =
                    (constraints.maxWidth - gap * (columns - 1)) / columns;
                return Wrap(
                  key: const ValueKey('hr_home_chain_grid'),
                  spacing: gap,
                  runSpacing: gap,
                  children: [
                    for (final chain in chains)
                      _ChainGridChip(
                        chain: chain,
                        width: itemWidth,
                        selected: selected == chain,
                        enabled: enabled,
                        onSelected: onSelected,
                      ),
                  ],
                );
              },
            ),
        ],
      ),
    );
  }
}

class _ChainGridChip extends StatelessWidget {
  final String chain;
  final double width;
  final bool selected;
  final bool enabled;
  final ValueChanged<String?> onSelected;

  const _ChainGridChip({
    required this.chain,
    required this.width,
    required this.selected,
    required this.enabled,
    required this.onSelected,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final fg = selected ? cs.onSecondaryContainer : cs.onSurface;
    return Semantics(
      button: true,
      selected: selected,
      label: chain,
      child: SizedBox(
        key: ValueKey('hr_home_chain_chip_$chain'),
        width: width,
        height: 48,
        child: Material(
          color: selected ? cs.secondaryContainer : cs.surfaceContainerLowest,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(8),
            side: BorderSide(
              color: selected ? Colors.transparent : cs.outlineVariant,
            ),
          ),
          clipBehavior: Clip.antiAlias,
          child: InkWell(
            onTap: enabled ? () => onSelected(selected ? null : chain) : null,
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 10),
              child: Row(
                children: [
                  HrChainAvatar(chain: chain, size: 24),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      chain,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: TextStyle(
                        fontSize: 13,
                        fontWeight: FontWeight.w600,
                        color: enabled ? fg : fg.withValues(alpha: 0.38),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// «ميزة حصرية للشركات» as an M3 Expressive card.
class HrHomeFeatureCard extends StatelessWidget {
  final bool isFreePromotion;
  final VoidCallback onAddDelegate;
  final VoidCallback onHowToLink;

  const HrHomeFeatureCard({
    super.key,
    required this.isFreePromotion,
    required this.onAddDelegate,
    required this.onHowToLink,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const radius = BorderRadiusDirectional.only(
      topStart: Radius.circular(28),
      topEnd: Radius.circular(72),
      bottomStart: Radius.circular(28),
      bottomEnd: Radius.circular(28),
    );
    return Container(
      key: const ValueKey('hr_home_feature_card'),
      clipBehavior: Clip.antiAlias,
      decoration: ShapeDecoration(
        color: cs.primaryContainer,
        shape: const RoundedRectangleBorder(borderRadius: radius),
      ),
      child: Stack(
        children: [
          PositionedDirectional(
            top: -56,
            end: -48,
            child: HrExpressiveShape(
              size: 190,
              lobes: 8,
              amplitude: 0.12,
              color: cs.primary.withValues(alpha: 0.10),
            ),
          ),
          PositionedDirectional(
            bottom: -36,
            end: 40,
            child: HrExpressiveShape(
              size: 84,
              lobes: 4,
              amplitude: 0.16,
              rotation: math.pi / 4,
              color: cs.tertiary.withValues(alpha: 0.10),
            ),
          ),
          Padding(
            padding: const EdgeInsets.all(24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Expanded(
                      child: Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: [
                          Text(
                            CompanyExclusiveCardIntro.badgeAr,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: FontWeight.w700,
                              color: cs.onPrimaryContainer,
                            ),
                          ),
                          if (isFreePromotion)
                            Container(
                              key: const ValueKey('hr_home_free_chip'),
                              padding: const EdgeInsets.symmetric(
                                horizontal: 10,
                                vertical: 4,
                              ),
                              decoration: BoxDecoration(
                                color: cs.tertiaryContainer,
                                borderRadius: BorderRadius.circular(8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(
                                    Icons.local_offer_rounded,
                                    size: 14,
                                    color: cs.onTertiaryContainer,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    CompanyExclusiveCardIntro.freeUntilAr,
                                    style: TextStyle(
                                      fontSize: 12,
                                      fontWeight: FontWeight.w700,
                                      color: cs.onTertiaryContainer,
                                      fontFeatures: kHrTabularFigures,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 12),
                    HrExpressiveShape(
                      size: 56,
                      lobes: 7,
                      amplitude: 0.09,
                      color: cs.primary,
                      child: Icon(
                        Icons.hub_rounded,
                        color: cs.onPrimary,
                        size: 26,
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                Text(
                  CompanyExclusiveCardIntro.titleAr,
                  style: Theme.of(context).textTheme.titleSmall?.copyWith(
                    fontWeight: FontWeight.w700,
                    height: 1.35,
                    letterSpacing: 0,
                    color: cs.onPrimaryContainer,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  isFreePromotion
                      ? CompanyExclusiveCardIntro.bodyFreeAr
                      : CompanyExclusiveCardIntro.bodyAr,
                  style: TextStyle(
                    fontSize: 15,
                    height: 1.55,
                    color: cs.onPrimaryContainer.withValues(alpha: 0.86),
                  ),
                ),
                const SizedBox(height: 20),
                Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  children: [
                    FilledButton.icon(
                      key: const ValueKey('hr_home_add_delegate'),
                      onPressed: onAddDelegate,
                      icon: const Icon(Icons.person_add_alt_1_rounded),
                      label: const Text('إضافة مندوب'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(48, 48),
                        shape: const StadiumBorder(),
                        padding: const EdgeInsets.symmetric(horizontal: 20),
                        textStyle: Theme.of(context).textTheme.labelLarge
                            ?.copyWith(
                              fontSize: 14,
                              fontWeight: FontWeight.w700,
                            ),
                      ).copyWith(overlayColor: hrStateLayer(cs.onPrimary)),
                    ),
                    OutlinedButton.icon(
                      key: const ValueKey('hr_home_how_to_link'),
                      onPressed: onHowToLink,
                      icon: const Icon(Icons.info_outline_rounded),
                      label: const Text('كيفية الربط'),
                      style:
                          OutlinedButton.styleFrom(
                            minimumSize: const Size(48, 48),
                            shape: const StadiumBorder(),
                            foregroundColor: cs.onPrimaryContainer,
                            side: BorderSide(color: cs.outline),
                            padding: const EdgeInsets.symmetric(horizontal: 20),
                            textStyle: Theme.of(context).textTheme.labelLarge
                                ?.copyWith(
                                  fontSize: 14,
                                  fontWeight: FontWeight.w600,
                                ),
                          ).copyWith(
                            overlayColor: hrStateLayer(cs.onPrimaryContainer),
                          ),
                    ),
                  ],
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

/// «دليل المهام والمسؤوليات»: the existing duty texts as collapsed items.
class HrHomeDutiesCard extends StatelessWidget {
  final List<AdminHomeDuty> duties;

  const HrHomeDutiesCard({super.key, required this.duties});

  static String _cleanTitle(String title) {
    final t = title.trim();
    return t.endsWith(':') ? t.substring(0, t.length - 1) : t;
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    const tileShape = RoundedRectangleBorder(
      borderRadius: BorderRadius.all(Radius.circular(16)),
    );
    return HrOverviewCard(
      key: const ValueKey('hr_home_duties_card'),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          HrCardTitle(
            icon: Icons.checklist_rounded,
            text: 'دليل المهام والمسؤوليات',
            fontSize: Theme.of(context).textTheme.titleSmall?.fontSize ?? 14,
          ),
          const SizedBox(height: 12),
          for (var i = 0; i < duties.length; i++) ...[
            if (i > 0) const SizedBox(height: 8),
            Material(
              color: cs.surfaceContainerLowest,
              shape: tileShape,
              clipBehavior: Clip.antiAlias,
              child: ListTileTheme.merge(
                horizontalTitleGap: 10,
                child: ExpansionTile(
                  key: ValueKey('hr_home_duty_$i'),
                  shape: tileShape,
                  collapsedShape: tileShape,
                  minTileHeight: 56,
                  tilePadding: const EdgeInsetsDirectional.only(
                    start: 12,
                    end: 8,
                  ),
                  childrenPadding: const EdgeInsetsDirectional.fromSTEB(
                    60,
                    0,
                    16,
                    16,
                  ),
                  expandedCrossAxisAlignment: CrossAxisAlignment.start,
                  expansionAnimationStyle: AnimationStyle(
                    duration: AppMotionDurations.medium2,
                    reverseDuration: AppMotionDurations.short3,
                    curve: AppMotionCurves.emphasizedDecelerate,
                    reverseCurve: AppMotionCurves.emphasizedAccelerate,
                  ),
                  iconColor: cs.primary,
                  collapsedIconColor: cs.onSurfaceVariant,
                  leading: Container(
                    width: 36,
                    height: 36,
                    decoration: BoxDecoration(
                      color: cs.secondaryContainer,
                      shape: BoxShape.circle,
                    ),
                    child: Icon(
                      duties[i].icon,
                      size: 20,
                      color: cs.onSecondaryContainer,
                    ),
                  ),
                  title: _DutyLine(_cleanTitle(duties[i].title)),
                  children: [
                    Text(
                      duties[i].desc,
                      style: TextStyle(
                        fontSize: 13,
                        height: 1.55,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ],
      ),
    );
  }
}

/// One duty title on a single line. The tile centres it with the icon.
///
/// Ellipsis and a tooltip appear only when the line cannot fit.
class _DutyLine extends StatelessWidget {
  final String text;

  const _DutyLine(this.text);

  @override
  Widget build(BuildContext context) {
    final style = Theme.of(context).textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      letterSpacing: 0,
      color: Theme.of(context).colorScheme.onSurface,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        final painter = TextPainter(
          text: TextSpan(text: text, style: style),
          maxLines: 1,
          textDirection: Directionality.of(context),
          textScaler: MediaQuery.textScalerOf(context),
        )..layout(maxWidth: constraints.maxWidth);
        final overflows = painter.didExceedMaxLines;
        painter.dispose();
        final label = Text(
          text,
          maxLines: 1,
          softWrap: false,
          overflow: TextOverflow.ellipsis,
          style: style,
        );
        if (!overflows) return label;
        return Tooltip(message: text, child: label);
      },
    );
  }
}
