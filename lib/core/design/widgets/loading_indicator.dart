import 'dart:async';
import 'dart:math' as math;

import 'package:flutter/physics.dart';
import 'package:material_ui/material_ui.dart';

/// M3 Expressive **loading indicator**
/// (m3.material.io/components/loading-indicator/guidelines).
///
/// Flutter ships the parts (the official [MaterialShapes] and
/// [MaterialShapeBorder], which morphs one shape into another) but not the
/// widget yet, so this one only arranges them the way Compose's
/// `LoadingIndicator` does: it morphs through seven Material shapes while
/// it rotates. Replace with Flutter's widget once it ships.
///
/// When to use (from the guidelines):
/// * under 200ms: show nothing (see [DelayedLoadingIndicator]);
/// * 200ms to 5s: this;
/// * longer, or when progress is known: a progress indicator.
///
/// [contained] puts it on a `primaryContainer` circle, for use on top of
/// content (pull to refresh, over images).
class LoadingIndicator extends StatefulWidget {
  const LoadingIndicator({
    super.key,
    this.size = 48,
    this.contained = false,
    this.semanticsLabel = 'جاري التحميل',
  }) : assert(size >= 24 && size <= 240);

  /// Container size, 24 to 240dp (M3). The shape is 38/48 of it.
  final double size;
  final bool contained;
  final String semanticsLabel;

  @override
  State<LoadingIndicator> createState() => _LoadingIndicatorState();
}

class _LoadingIndicatorState extends State<LoadingIndicator>
    with TickerProviderStateMixin {
  // Same order as Compose's LoadingIndicatorDefaults.IndeterminateIndicatorPolygons.
  static final _shapes = [
    MaterialShapes.softBurst,
    MaterialShapes.cookie9Sided,
    MaterialShapes.pentagon,
    MaterialShapes.pill,
    MaterialShapes.sunny,
    MaterialShapes.cookie4Sided,
    MaterialShapes.oval,
  ];

  /// One morph every 650ms, with a bouncy spring, as in Compose.
  static const _morphInterval = Duration(milliseconds: 650);
  static final _spring = SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: 200,
    ratio: 0.6,
  );

  /// Slow constant spin; each morph adds a quarter turn on top.
  static const _spin = Duration(milliseconds: 4666);

  late final AnimationController _morph = AnimationController.unbounded(
    vsync: this,
  );
  late final AnimationController _rotation = AnimationController(
    vsync: this,
    duration: _spin,
  );
  Timer? _timer;
  int _count = 0;
  int get _index => _count % _shapes.length;
  bool _reduce = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    final reduce = MediaQuery.maybeDisableAnimationsOf(context) ?? false;
    if (_timer == null || reduce != _reduce) {
      _reduce = reduce;
      _start();
    }
  }

  void _start() {
    _timer?.cancel();
    if (_reduce) {
      // Reduced motion: a slow spin only, no morphing.
      _morph.value = 0;
      _rotation.repeat();
      _timer = Timer(Duration.zero, () {});
      return;
    }
    _rotation.repeat();
    _next();
    _timer = Timer.periodic(_morphInterval, (_) => _next());
  }

  void _next() {
    if (!mounted) return;
    setState(() => _count++);
    _morph.animateWith(SpringSimulation(_spring, 0, 1, 0, snapToEnd: true));
  }

  @override
  void dispose() {
    _timer?.cancel();
    _morph.dispose();
    _rotation.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final scheme = Theme.of(context).colorScheme;
    final color = widget.contained ? scheme.onPrimaryContainer : scheme.primary;
    final shapeSize = widget.size * 38 / 48;
    final from = _shapes[(_index - 1) % _shapes.length];
    final to = _shapes[_index];
    final tween = ShapeBorderTween(
      begin: MaterialShapeBorder(shape: from),
      end: MaterialShapeBorder(shape: to),
    );

    final indicator = AnimatedBuilder(
      animation: Listenable.merge([_morph, _rotation]),
      builder: (context, _) {
        final p = _morph.value;
        final turns = _rotation.value + (_count + p.clamp(0.0, 1.2)) * 0.25;
        return Transform.rotate(
          angle: turns * 2 * math.pi,
          child: DecoratedBox(
            decoration: ShapeDecoration(
              color: color,
              shape: _reduce ? MaterialShapeBorder(shape: to) : tween.lerp(p)!,
            ),
            child: SizedBox.square(dimension: shapeSize),
          ),
        );
      },
    );

    return Semantics(
      label: widget.semanticsLabel,
      liveRegion: true,
      child: ExcludeSemantics(
        child: SizedBox.square(
          dimension: widget.size,
          child: DecoratedBox(
            decoration: widget.contained
                ? ShapeDecoration(
                    color: scheme.primaryContainer,
                    shape: const CircleBorder(),
                  )
                : const BoxDecoration(),
            child: Center(child: indicator),
          ),
        ),
      ),
    );
  }
}

/// Shows nothing for the first [delay] (200ms, M3: "under 200ms, no
/// indicator"), then a [LoadingIndicator]. Use it for any wait whose length
/// is unknown, so quick loads don't flash an indicator.
class DelayedLoadingIndicator extends StatefulWidget {
  const DelayedLoadingIndicator({
    super.key,
    this.delay = const Duration(milliseconds: 200),
    this.size = 48,
    this.contained = false,
  });

  final Duration delay;
  final double size;
  final bool contained;

  @override
  State<DelayedLoadingIndicator> createState() =>
      _DelayedLoadingIndicatorState();
}

class _DelayedLoadingIndicatorState extends State<DelayedLoadingIndicator> {
  late final Timer _timer = Timer(
    widget.delay,
    () => setState(() => _visible = true),
  );
  bool _visible = false;

  @override
  void initState() {
    super.initState();
    _timer;
  }

  @override
  void dispose() {
    _timer.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => _visible
      ? LoadingIndicator(size: widget.size, contained: widget.contained)
      : SizedBox.square(dimension: widget.size);
}
