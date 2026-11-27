import 'package:material_ui/material_ui.dart';

import '../motion.dart';
import '../tokens.dart';
import 'loading_indicator.dart';

/// **Pull to refresh** (playground «السحب للتحديث», loading-indicator
/// guidelines; TAS-387, user decision 2026-11-27): the official
/// [RefreshIndicator.noSpinner] with a contained [LoadingIndicator] that
/// scales in on top of the list while it refreshes. The child must be
/// scrollable with `AlwaysScrollableScrollPhysics`.
class PullToRefresh extends StatefulWidget {
  const PullToRefresh({
    super.key,
    required this.onRefresh,
    required this.child,
  });

  final Future<void> Function() onRefresh;
  final Widget child;

  @override
  State<PullToRefresh> createState() => _PullToRefreshState();
}

class _PullToRefreshState extends State<PullToRefresh> {
  RefreshIndicatorStatus? _status;

  @override
  Widget build(BuildContext context) {
    // Flutter reports `snap` and then never reports `refresh` (it sets it
    // without calling onStatusChange), so `snap` means "refreshing" until
    // `done` / `canceled` arrive.
    final showing =
        _status == RefreshIndicatorStatus.armed ||
        _status == RefreshIndicatorStatus.snap ||
        _status == RefreshIndicatorStatus.refresh;
    return Stack(
      children: [
        RefreshIndicator.noSpinner(
          onRefresh: widget.onRefresh,
          onStatusChange: (s) {
            if (mounted) setState(() => _status = s);
          },
          child: widget.child,
        ),
        PositionedDirectional(
          top: TashilSpacing.md,
          start: 0,
          end: 0,
          child: IgnorePointer(
            child: Center(
              child: AnimatedScale(
                key: const Key('pull_to_refresh_indicator'),
                scale: showing ? 1 : 0,
                duration: TashilMotion.scaled(
                  context,
                  TashilMotion.fast.duration,
                ),
                curve: TashilMotion.fast.curve,
                child: showing
                    ? const LoadingIndicator(contained: true)
                    : const SizedBox.square(dimension: 48),
              ),
            ),
          ),
        ),
      ],
    );
  }
}
