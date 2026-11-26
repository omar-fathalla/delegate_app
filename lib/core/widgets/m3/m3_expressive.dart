import 'package:flutter/rendering.dart' show ScrollDirection;
// M3 Expressive building blocks for the delegate home and tabs (home_v2).
// Spec: M3_Design_System.md §37–39 and tashil-loading-spec.md.
import 'dart:async';
import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/physics.dart';

import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';

export 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart'
    show M3Motion;

/// Mirrors a horizontal directional icon (chevron/back) for RTL.
class M3DirIcon extends StatelessWidget {
  const M3DirIcon(this.icon, {super.key, this.size, this.color});
  final IconData icon;
  final double? size;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final i = Icon(icon, size: size, color: color);
    return rtl ? Transform.flip(flipX: true, child: i) : i;
  }
}

// ───────────────────────── Loading ─────────────────────────

/// M3 Expressive LoadingIndicator (no Flutter API yet): 38dp shape inside a
/// 48dp container, morphing between rounded polygons every 650ms with a
/// 0.6/200 spring while rotating. Reduced motion → static circular indicator.
class M3LoadingIndicator extends StatefulWidget {
  const M3LoadingIndicator({super.key, this.contained = false, this.color});
  final bool contained;
  final Color? color;
  @override
  State<M3LoadingIndicator> createState() => _M3LoadingIndicatorState();
}

class _M3LoadingIndicatorState extends State<M3LoadingIndicator>
    with TickerProviderStateMixin {
  // (lobes, amplitude) — circle-ish, soft-burst, pentagon, pill-ish, cookie...
  static const _shapes = <(int, double)>[
    (8, 0.10), (4, 0.16), (5, 0.12), (2, 0.18), (9, 0.08), (6, 0.12), (3, 0.14)
  ];
  static final _spring =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 200, ratio: 0.6);
  late final AnimationController _rot = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 4666));
  late final AnimationController _morph = AnimationController.unbounded(vsync: this);
  Timer? _timer;
  int _from = 0;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (M3Motion.reduced(context)) {
      _rot.stop();
      _timer?.cancel();
      _timer = null;
    } else if (_timer == null) {
      _rot.repeat();
      _timer = Timer.periodic(const Duration(milliseconds: 650), (_) {
        if (!mounted) return;
        _from = (_from + 1) % _shapes.length;
        _morph.value = 0;
        _morph.animateWith(SpringSimulation(_spring, 0, 1, 0));
      });
    }
  }

  @override
  void dispose() {
    _timer?.cancel();
    _rot.dispose();
    _morph.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final color = widget.color ??
        (widget.contained ? cs.onPrimaryContainer : cs.primary);
    Widget child;
    if (M3Motion.reduced(context)) {
      child = SizedBox(
          width: 32,
          height: 32,
          child: CircularProgressIndicator(strokeWidth: 4, color: color));
    } else {
      child = AnimatedBuilder(
        animation: Listenable.merge([_rot, _morph]),
        builder: (_, _) {
          final a = _shapes[_from];
          final b = _shapes[(_from + 1) % _shapes.length];
          return CustomPaint(
            size: const Size.square(38),
            painter: _MorphPainter(
              a: a,
              b: b,
              t: _morph.value,
              rotation: _rot.value * 2 * math.pi + _morph.value * math.pi / 2,
              color: color,
            ),
          );
        },
      );
    }
    return Semantics(
      label: 'Loading',
      child: Container(
        width: 48,
        height: 48,
        alignment: Alignment.center,
        decoration: widget.contained
            ? BoxDecoration(color: cs.primaryContainer, shape: BoxShape.circle)
            : null,
        child: child,
      ),
    );
  }
}

class _MorphPainter extends CustomPainter {
  _MorphPainter(
      {required this.a,
      required this.b,
      required this.t,
      required this.rotation,
      required this.color});
  final (int, double) a, b;
  final double t, rotation;
  final Color color;

  double _r(double th, (int, double) s) => 1 + s.$2 * math.cos(s.$1 * th);

  @override
  void paint(Canvas canvas, Size size) {
    final c = size.center(Offset.zero);
    final base = size.width / 2 / 1.18;
    final path = Path();
    const n = 120;
    for (var i = 0; i <= n; i++) {
      final th = i / n * 2 * math.pi;
      final r = base * (_r(th, a) * (1 - t) + _r(th, b) * t);
      final p = c + Offset(math.cos(th + rotation), math.sin(th + rotation)) * r;
      i == 0 ? path.moveTo(p.dx, p.dy) : path.lineTo(p.dx, p.dy);
    }
    canvas.drawPath(path..close(), Paint()..color = color);
  }

  @override
  bool shouldRepaint(_MorphPainter o) =>
      o.t != t || o.rotation != rotation || o.a != a || o.color != color;
}

/// Shows [child] only after [delay] (400ms) so fast loads never flash.
class M3DelayedLoading extends StatefulWidget {
  const M3DelayedLoading(
      {super.key,
      this.child = const M3LoadingIndicator(),
      this.delay = const Duration(milliseconds: 400)});
  final Widget child;
  final Duration delay;
  @override
  State<M3DelayedLoading> createState() => _M3DelayedLoadingState();
}

class _M3DelayedLoadingState extends State<M3DelayedLoading> {
  bool _show = false;
  Timer? _t;
  @override
  void initState() {
    super.initState();
    _t = Timer(widget.delay, () {
      if (mounted) setState(() => _show = true);
    });
  }

  @override
  void dispose() {
    _t?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => AnimatedOpacity(
        opacity: _show ? 1 : 0,
        duration: M3Motion.short4,
        curve: M3Motion.standard,
        child: _show ? widget.child : const SizedBox(width: 48, height: 48),
      );
}

/// Wavy linear progress (M3 Expressive): 4dp wavy active indicator, 4dp gap,
/// flat 4dp track in secondaryContainer, end stop dot. Indeterminate when
/// [value] is null. Reduced motion → flat linear bar.
class M3WavyLinearProgress extends StatefulWidget {
  const M3WavyLinearProgress({super.key, this.value});
  final double? value;
  @override
  State<M3WavyLinearProgress> createState() => _M3WavyLinearProgressState();
}

class _M3WavyLinearProgressState extends State<M3WavyLinearProgress>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1750))
    ..repeat();
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    if (M3Motion.reduced(context)) {
      return LinearProgressIndicator(
        value: widget.value,
        minHeight: 4,
        color: cs.primary,
        backgroundColor: cs.secondaryContainer,
      );
    }
    final rtl = Directionality.of(context) == TextDirection.rtl;
    return Semantics(
      label: 'Loading',
      child: SizedBox(
        height: 10,
        width: double.infinity,
        child: AnimatedBuilder(
          animation: _c,
          builder: (_, _) => CustomPaint(
            painter: _WavyPainter(
              phase: _c.value,
              value: widget.value,
              rtl: rtl,
              active: cs.primary,
              track: cs.secondaryContainer,
            ),
          ),
        ),
      ),
    );
  }
}

class _WavyPainter extends CustomPainter {
  _WavyPainter(
      {required this.phase,
      required this.value,
      required this.rtl,
      required this.active,
      required this.track});
  final double phase;
  final double? value;
  final bool rtl;
  final Color active, track;

  @override
  void paint(Canvas canvas, Size size) {
    if (rtl) {
      canvas.translate(size.width, 0);
      canvas.scale(-1, 1);
    }
    const stroke = 4.0, gap = 4.0, amp = 2.0, wl = 20.0;
    final cy = size.height / 2;
    double start, end;
    if (value != null) {
      start = 0;
      end = size.width * value!.clamp(0.0, 1.0);
    } else {
      // two-phase head/tail like M3 indeterminate
      final h = Curves.easeInOut.transform((phase * 1.2).clamp(0.0, 1.0));
      final tl = Curves.easeInOut.transform(((phase - 0.2) * 1.25).clamp(0.0, 1.0));
      end = size.width * h;
      start = size.width * tl;
    }
    final ap = Paint()
      ..color = active
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round
      ..style = PaintingStyle.stroke;
    final tp = Paint()
      ..color = track
      ..strokeWidth = stroke
      ..strokeCap = StrokeCap.round;
    // track segments (around the active part, separated by the gap)
    if (start - gap > stroke / 2) {
      canvas.drawLine(Offset(stroke / 2, cy), Offset(start - gap - stroke, cy), tp);
    }
    if (end + gap + stroke < size.width - stroke / 2) {
      canvas.drawLine(
          Offset(end + gap + stroke, cy), Offset(size.width - stroke * 2, cy), tp);
    }
    // stop indicator dot at the end
    canvas.drawCircle(
        Offset(size.width - stroke / 2, cy), stroke / 2, Paint()..color = active);
    if (end - start > 1) {
      final path = Path();
      for (var x = start; x <= end; x += 1) {
        final y = cy + amp * math.sin((x / wl + phase * 4) * 2 * math.pi);
        x == start ? path.moveTo(x, y) : path.lineTo(x, y);
      }
      canvas.drawPath(path, ap);
    }
  }

  @override
  bool shouldRepaint(_WavyPainter o) => o.phase != phase || o.value != value;
}

/// Pull-to-refresh: no circular spinner; a wavy bar pinned to the top while
/// the refresh future runs (never shown together with a skeleton).
class M3Refresh extends StatefulWidget {
  const M3Refresh({super.key, required this.onRefresh, required this.child});
  final Future<void> Function() onRefresh;
  final Widget child;
  @override
  State<M3Refresh> createState() => _M3RefreshState();
}

class _M3RefreshState extends State<M3Refresh> {
  bool _busy = false;
  Future<void> _run() async {
    setState(() => _busy = true);
    try {
      await widget.onRefresh();
    } finally {
      if (mounted) setState(() => _busy = false);
    }
  }

  @override
  Widget build(BuildContext context) {
    return Stack(
      children: [
        RefreshIndicator.noSpinner(onRefresh: _run, child: widget.child),
        PositionedDirectional(
          top: 0,
          start: 0,
          end: 0,
          child: AnimatedSwitcher(
            duration: M3Motion.short4,
            child: _busy
                ? const Padding(
                    key: ValueKey('wavy'),
                    padding: EdgeInsets.symmetric(horizontal: 16, vertical: 2),
                    child: M3WavyLinearProgress())
                : const SizedBox.shrink(),
          ),
        ),
      ],
    );
  }
}

/// Skeleton block (surfaceContainerHighest, gentle pulse; static if reduced).
class M3Skeleton extends StatefulWidget {
  const M3Skeleton({super.key, this.height = 16, this.width, this.radius = 8});
  final double height;
  final double? width;
  final double radius;
  @override
  State<M3Skeleton> createState() => _M3SkeletonState();
}

class _M3SkeletonState extends State<M3Skeleton>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
      vsync: this, duration: const Duration(milliseconds: 1000))
    ..repeat(reverse: true);
  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final box = Container(
      height: widget.height,
      width: widget.width,
      decoration: BoxDecoration(
        color: cs.surfaceContainerHighest,
        borderRadius: BorderRadius.circular(widget.radius),
      ),
    );
    if (M3Motion.reduced(context)) return box;
    return FadeTransition(
        opacity: Tween(begin: 0.55, end: 1.0)
            .animate(CurvedAnimation(parent: _c, curve: M3Motion.standard)),
        child: box);
  }
}

// ───────────────────────── Interaction ─────────────────────────

/// Press-scale to 0.96 with the fast spatial spring (disabled when reduced).
class M3PressScale extends StatefulWidget {
  const M3PressScale({super.key, required this.child, this.scale = 0.96});
  final Widget child;
  final double scale;
  @override
  State<M3PressScale> createState() => _M3PressScaleState();
}

class _M3PressScaleState extends State<M3PressScale>
    with SingleTickerProviderStateMixin {
  late final AnimationController _s =
      AnimationController.unbounded(vsync: this, value: 1);
  void _to(double v) {
    if (M3Motion.reduced(context)) return;
    _s.animateWith(SpringSimulation(M3Motion.spatialFast, _s.value, v, 0));
  }

  @override
  void dispose() {
    _s.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) => Listener(
        onPointerDown: (_) => _to(widget.scale),
        onPointerUp: (_) => _to(1),
        onPointerCancel: (_) => _to(1),
        child: ScaleTransition(scale: _s, child: widget.child),
      );
}

/// Button label style that never clips Cairo (see recorded pitfall).
TextStyle m3ButtonLabel(BuildContext c) => Theme.of(c)
    .textTheme
    .labelLarge!
    .copyWith(fontWeight: FontWeight.w600, fontSize: 14, height: 1.4);

/// Extended FAB: primaryContainer, 56dp, 16dp radius, press-scale.
/// Extended FAB for a screen's main create action (C-04).
///
/// TAS-353: shape, elevation and press feedback come from the theme (no
/// hand-made shape or press scale). [extended] lets the screen shrink it to
/// an icon while its list scrolls down (see [ExtendedFabScroll]).
class M3ExtendedFab extends StatelessWidget {
  const M3ExtendedFab({
    super.key,
    required this.icon,
    required this.label,
    required this.onPressed,
    this.heroTag,
    this.extended = true,
  });
  final IconData icon;
  final String label;
  final VoidCallback? onPressed;
  final Object? heroTag;
  final bool extended;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FloatingActionButton.extended(
      heroTag: heroTag,
      onPressed: onPressed,
      isExtended: extended,
      tooltip: label,
      backgroundColor: cs.primaryContainer,
      foregroundColor: cs.onPrimaryContainer,
      icon: Icon(icon),
      label: Text(label),
    );
  }
}

/// Mixin for a screen whose extended FAB shrinks while its list scrolls
/// down and comes back on scroll up (TAS-352 / TAS-353). Wrap the body in
/// `NotificationListener<UserScrollNotification>(onNotification:
/// onFabScroll, ...)` and pass [fabExtended] to the FAB.
mixin ExtendedFabScroll<T extends StatefulWidget> on State<T> {
  bool fabExtended = true;

  bool onFabScroll(UserScrollNotification n) {
    if (n.metrics.axis != Axis.vertical) return false;
    if (n.direction == ScrollDirection.idle) return false;
    final extend = n.direction == ScrollDirection.forward;
    if (extend != fabExtended) setState(() => fabExtended = extend);
    return false;
  }
}

/// Filled button with in-button loading (spinner replaces label, width kept).
class M3LoadingButton extends StatelessWidget {
  const M3LoadingButton(
      {super.key,
      required this.label,
      required this.onPressed,
      this.loading = false,
      this.icon});
  final String label;
  final VoidCallback? onPressed;
  final bool loading;
  final IconData? icon;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return M3PressScale(
      child: FilledButton(
        onPressed: loading ? null : onPressed,
        style: FilledButton.styleFrom(
          minimumSize: const Size(64, 48),
          padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
          textStyle: m3ButtonLabel(context),
        ),
        child: AnimatedSwitcher(
          duration: M3Motion.reduced(context) ? Duration.zero : M3Motion.short4,
          child: loading
              ? SizedBox(
                  key: const ValueKey('l'),
                  width: 20,
                  height: 20,
                  child: CircularProgressIndicator(
                      strokeWidth: 2.5, color: cs.onSurface.withValues(alpha: .6)))
              : Row(key: const ValueKey('t'), mainAxisSize: MainAxisSize.min, children: [
                  if (icon != null) ...[Icon(icon, size: 18), const SizedBox(width: 8)],
                  Text(label),
                ]),
        ),
      ),
    );
  }
}

/// Animated success check: circle scales in (spring), tick draws (standard).
class M3AnimatedCheck extends StatefulWidget {
  const M3AnimatedCheck({super.key, this.size = 64});
  final double size;
  @override
  State<M3AnimatedCheck> createState() => _M3AnimatedCheckState();
}

class _M3AnimatedCheckState extends State<M3AnimatedCheck>
    with SingleTickerProviderStateMixin {
  late final AnimationController _c =
      AnimationController(vsync: this, duration: M3Motion.long2);
  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (M3Motion.reduced(context)) {
      _c.value = 1;
    } else if (!_c.isAnimating && _c.value == 0) {
      _c.forward();
    }
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return AnimatedBuilder(
      animation: _c,
      builder: (_, _) {
        final s = const Interval(0, .6, curve: Curves.elasticOut).transform(_c.value);
        final d = const Interval(.35, 1, curve: M3Motion.standard).transform(_c.value);
        return Transform.scale(
          scale: s,
          child: CustomPaint(
            size: Size.square(widget.size),
            painter: _CheckPainter(d, cs.primaryContainer, cs.onPrimaryContainer),
          ),
        );
      },
    );
  }
}

class _CheckPainter extends CustomPainter {
  _CheckPainter(this.t, this.bg, this.fg);
  final double t;
  final Color bg, fg;
  @override
  void paint(Canvas canvas, Size s) {
    canvas.drawCircle(s.center(Offset.zero), s.width / 2, Paint()..color = bg);
    final p = Path()
      ..moveTo(s.width * .28, s.height * .52)
      ..lineTo(s.width * .44, s.height * .67)
      ..lineTo(s.width * .73, s.height * .36);
    final m = p.computeMetrics().first;
    canvas.drawPath(
        m.extractPath(0, m.length * t),
        Paint()
          ..color = fg
          ..style = PaintingStyle.stroke
          ..strokeWidth = s.width * .09
          ..strokeCap = StrokeCap.round
          ..strokeJoin = StrokeJoin.round);
  }

  @override
  bool shouldRepaint(_CheckPainter o) => o.t != t;
}

/// Shows a dialog with the animated check and a message.
Future<void> showM3Success(BuildContext context, String message) {
  return showDialog<void>(
    context: context,
    builder: (c) => AlertDialog(
      icon: const M3AnimatedCheck(),
      content: Text(message, textAlign: TextAlign.center),
      actions: [
        TextButton(
            onPressed: () => Navigator.pop(c),
            child: Text(MaterialLocalizations.of(c).okButtonLabel)),
      ],
    ),
  );
}

// ───────────────────────── Transitions ─────────────────────────

/// Shared axis X, 300ms, 30dp slide + fade; forward moves toward reading
/// direction end (left in RTL). Reduced motion → 150ms cross-fade.
class M3SharedAxisRoute<T> extends PageRouteBuilder<T> {
  M3SharedAxisRoute({required WidgetBuilder builder, super.settings})
      : super(
          transitionDuration: M3Motion.medium2,
          reverseTransitionDuration: M3Motion.medium2,
          pageBuilder: (c, _, _) => builder(c),
          transitionsBuilder: (c, a, s, child) {
            if (M3Motion.reduced(c)) {
              return FadeTransition(
                  opacity: CurvedAnimation(
                      parent: a, curve: const Interval(0, .5)), // 150 of 300
                  child: child);
            }
            final dir = Directionality.of(c) == TextDirection.rtl ? -1.0 : 1.0;
            Widget slide(Animation<double> anim, double from, double to,
                    Curve curve, Widget w) =>
                AnimatedBuilder(
                  animation: anim,
                  builder: (_, w) => Transform.translate(
                    offset: Offset(
                        dir * (from + (to - from) * curve.transform(anim.value)),
                        0),
                    child: w,
                  ),
                  child: w,
                );
            // enter: +30 → 0 ; when covered by next: 0 → -30
            return slide(
              s,
              0,
              -30,
              M3Motion.emphasizedAccel,
              FadeTransition(
                opacity: ReverseAnimation(CurvedAnimation(
                    parent: s, curve: const Interval(0, .3))),
                child: slide(
                  a,
                  30,
                  0,
                  M3Motion.emphasizedDecel,
                  FadeTransition(
                    opacity: CurvedAnimation(
                        parent: a, curve: const Interval(.3, 1)),
                    child: child,
                  ),
                ),
              ),
            );
          },
        );
}

/// Container transform (card → details), 500ms emphasized.
class M3ContainerTransform extends StatelessWidget {
  const M3ContainerTransform({
    super.key,
    required this.closedBuilder,
    required this.openBuilder,
    this.radius = 16,
    this.closedColor,
  });
  final Widget Function(BuildContext, VoidCallback open) closedBuilder;
  final WidgetBuilder openBuilder;
  final double radius;
  final Color? closedColor;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduced = M3Motion.reduced(context);
    return OpenContainer(
      transitionType: reduced
          ? ContainerTransitionType.fade
          : ContainerTransitionType.fadeThrough,
      transitionDuration: reduced ? const Duration(milliseconds: 150) : M3Motion.long2,
      closedElevation: 0,
      openElevation: 0,
      closedColor: closedColor ?? cs.surfaceContainer,
      openColor: cs.surface,
      middleColor: cs.surfaceContainer,
      closedShape:
          RoundedRectangleBorder(borderRadius: BorderRadius.circular(radius)),
      closedBuilder: (c, open) => closedBuilder(c, open),
      openBuilder: (c, _) => openBuilder(c),
    );
  }
}

/// Card surface per home_v2: surfaceContainerLow, 16dp radius, no shadow.
class M3Card extends StatelessWidget {
  const M3Card(
      {super.key,
      required this.child,
      this.padding = const EdgeInsets.all(16),
      this.onTap,
      this.color});
  final Widget child;
  final EdgeInsetsGeometry padding;
  final VoidCallback? onTap;
  final Color? color;
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final card = Material(
      color: color ?? cs.surfaceContainer,
      borderRadius: BorderRadius.circular(16),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: onTap,
        child: Padding(padding: padding, child: child),
      ),
    );
    return onTap == null ? card : M3PressScale(scale: 0.98, child: card);
  }
}

/// Bottom-sheet motion: enter with the expressive default-spatial spring
/// curve (≈ spring 0.8/380), exit emphasized-accelerate.
const AnimationStyle m3SheetAnimation = AnimationStyle(
  duration: Duration(milliseconds: 450),
  curve: Cubic(0.38, 1.21, 0.22, 1.00),
  reverseDuration: Duration(milliseconds: 200),
  reverseCurve: Cubic(0.3, 0, 0.8, 0.15),
);
