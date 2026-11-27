import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';

/// **Skeleton loader** (playground «هيكل التحميل», motion transition
/// patterns; TAS-387, user decision 2026-11-27). Grey shapes where the
/// content will be, a gentle pulse while it loads, then the content fades in
/// ([SkeletonSwitcher]). Use it when the layout is known (a list of cards,
/// the numbers of a summary); use `DelayedLoadingIndicator` when it is not.
///
/// One shape in `surfaceContainerHighest`, pulsing 0.5 → 1. With "remove
/// animations" on, it stays still.
class Skeleton extends StatefulWidget {
  const Skeleton({
    super.key,
    this.width,
    this.height = 14,
    this.radius = TashilRadius.small,
    this.circle = false,
  });

  /// A circle of [height] (avatars, card icons).
  const Skeleton.circle({super.key, required double size})
    : width = size,
      height = size,
      radius = 0,
      circle = true;

  final double? width;
  final double height;
  final double radius;
  final bool circle;

  @override
  State<Skeleton> createState() => _SkeletonState();
}

class _SkeletonState extends State<Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _pulse = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 900),
  );

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (MediaQuery.maybeDisableAnimationsOf(context) == true) {
      _pulse.value = 1;
      _pulse.stop();
    } else if (!_pulse.isAnimating) {
      _pulse.repeat(reverse: true);
    }
  }

  @override
  void dispose() {
    _pulse.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FadeTransition(
      opacity: Tween(begin: 0.5, end: 1.0).animate(_pulse),
      child: Container(
        width: widget.width,
        height: widget.height,
        decoration: BoxDecoration(
          color: cs.surfaceContainerHighest,
          shape: widget.circle ? BoxShape.circle : BoxShape.rectangle,
          borderRadius: widget.circle
              ? null
              : BorderRadius.circular(widget.radius),
        ),
      ),
    );
  }
}

/// The skeleton of a `SummaryCard` (P-07): icon circle, two lines, the
/// trailing value and, when [facts] is above zero, the facts row.
class SummaryCardSkeleton extends StatelessWidget {
  const SummaryCardSkeleton({
    super.key,
    this.facts = 2,
    this.margin = const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
  });

  final int facts;
  final EdgeInsetsGeometry margin;

  @override
  Widget build(BuildContext context) {
    return Card.filled(
      margin: margin,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            const Row(
              children: [
                Skeleton.circle(size: 36),
                SizedBox(width: TashilSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Skeleton(width: 140, height: 16),
                      SizedBox(height: TashilSpacing.sm),
                      Skeleton(width: 96, height: 12),
                    ],
                  ),
                ),
                SizedBox(width: TashilSpacing.md),
                Skeleton(width: 64, height: 28),
              ],
            ),
            if (facts > 0) ...[
              const Divider(height: TashilSpacing.xl),
              Row(
                children: [
                  for (var i = 0; i < facts; i++)
                    const Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Skeleton(width: 40, height: 10),
                          SizedBox(height: TashilSpacing.xs),
                          Skeleton(width: 72, height: 14),
                        ],
                      ),
                    ),
                ],
              ),
            ],
          ],
        ),
      ),
    );
  }
}

/// Shows [skeleton] while [loading], then fades to [child] (the effects
/// spring, scaled by the system animation setting).
class SkeletonSwitcher extends StatelessWidget {
  const SkeletonSwitcher({
    super.key,
    required this.loading,
    required this.skeleton,
    required this.child,
  });

  final bool loading;
  final Widget skeleton;
  final Widget child;

  @override
  Widget build(BuildContext context) {
    return AnimatedSwitcher(
      duration: TashilMotion.scaled(context, TashilMotion.fade.duration),
      switchInCurve: TashilMotion.fade.curve,
      layoutBuilder: (current, previous) => Stack(
        alignment: AlignmentDirectional.topStart,
        children: [...previous, ?current],
      ),
      child: KeyedSubtree(
        key: ValueKey(loading),
        child: loading ? skeleton : child,
      ),
    );
  }
}
