import 'dart:math' as math;
import 'package:flutter/material.dart';
import 'package:go_router/go_router.dart';
import 'package:animations/animations.dart';

/// Material Design 3 (M3) Motion Duration Tokens
///
/// Follows official specifications from:
/// https://m3.material.io/styles/motion/easing-and-duration/tokens-specs
abstract final class AppMotionDurations {
  // Short Durations
  static const Duration short1 = Duration(milliseconds: 50);
  static const Duration short2 = Duration(milliseconds: 100);
  static const Duration short3 = Duration(milliseconds: 150);
  static const Duration short4 = Duration(milliseconds: 200);

  // Medium Durations
  static const Duration medium1 = Duration(milliseconds: 250);
  static const Duration medium2 = Duration(milliseconds: 300);
  static const Duration medium3 = Duration(milliseconds: 350);
  static const Duration medium4 = Duration(milliseconds: 400);

  // Long Durations
  static const Duration long1 = Duration(milliseconds: 450);
  static const Duration long2 = Duration(milliseconds: 500);
  static const Duration long3 = Duration(milliseconds: 550);
  static const Duration long4 = Duration(milliseconds: 600);

  // Extra-Long Durations
  static const Duration extraLong1 = Duration(milliseconds: 700);
  static const Duration extraLong2 = Duration(milliseconds: 800);
  static const Duration extraLong3 = Duration(milliseconds: 900);
  static const Duration extraLong4 = Duration(milliseconds: 1000);
}

/// Material Design 3 (M3) Motion Curve & Easing Tokens
///
/// Converts official spring physics and cubic-bezier curves from:
/// https://m3.material.io/styles/motion/overview/specs
abstract final class AppMotionCurves {
  // --- Emphasized Easing (Heroic, High-Attention) ---
  /// Elements that begin and end on screen (e.g. Card expansion, reordering).
  static const Curve emphasized = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Incoming elements entering from off-screen (e.g. Bottom Sheets, Dialogs).
  static const Curve emphasizedDecelerate = Cubic(0.05, 0.7, 0.1, 1.0);

  /// Outgoing elements exiting off-screen (e.g. Dismiss, Sheet Close).
  static const Curve emphasizedAccelerate = Cubic(0.3, 0.0, 0.8, 0.15);

  // --- Standard Easing (Utility, Low-Attention) ---
  /// Standard element movement within screen bounds.
  static const Curve standard = Cubic(0.2, 0.0, 0.0, 1.0);

  /// Small incoming utility elements.
  static const Curve standardDecelerate = Cubic(0.0, 0.0, 0.2, 1.0);

  /// Small exiting utility elements.
  static const Curve standardAccelerate = Cubic(0.3, 0.0, 1.0, 1.0);

  // --- Expressive Spatial Curves (Position, Bounds, Translation, Scale) ---
  /// Expressive Fast Spatial (Spring: damping=0.6, stiffness=800, duration=350ms)
  static const Curve expressiveFastSpatial = Cubic(0.43, 1.47, 0.21, 0.90);

  /// Expressive Default Spatial (Spring: damping=0.8, stiffness=380, duration=500ms)
  static const Curve expressiveDefaultSpatial = Cubic(0.38, 1.21, 0.22, 1.00);

  /// Expressive Slow Spatial (Spring: damping=0.8, stiffness=200, duration=650ms)
  static const Curve expressiveSlowSpatial = Cubic(0.39, 1.19, 0.18, 0.99);

  // --- Standard Spatial Curves (Position, Bounds, Translation, Scale) ---
  /// Standard Fast Spatial (Spring: damping=0.9, stiffness=1400, duration=350ms)
  static const Curve standardFastSpatial = Cubic(0.22, 1.00, 0.41, 1.00);

  /// Standard Default Spatial (Spring: damping=0.9, stiffness=700, duration=500ms)
  static const Curve standardDefaultSpatial = Cubic(0.20, 1.04, 0.38, 1.00);

  /// Standard Slow Spatial (Spring: damping=0.9, stiffness=300, duration=750ms)
  static const Curve standardSlowSpatial = Cubic(0.20, 1.06, 0.36, 1.00);

  // --- Effects Curves (Opacity, Color Tint, Elevation - Strictly Monotonic) ---
  /// Expressive Fast Effects (Spring: damping=1.0, stiffness=3800, duration=150ms)
  static const Curve expressiveFastEffects = Cubic(0.28, 0.94, 0.34, 1.00);

  /// Expressive Default Effects (Spring: damping=1.0, stiffness=1600, duration=200ms)
  static const Curve expressiveDefaultEffects = Cubic(0.34, 0.83, 0.24, 1.00);

  /// Expressive Slow Effects (Spring: damping=1.0, stiffness=800, duration=300ms)
  static const Curve expressiveSlowEffects = Cubic(0.36, 0.85, 0.26, 1.00);

  /// Standard Fast Effects (Spring: damping=1.0, stiffness=3800, duration=150ms)
  static const Curve standardFastEffects = Cubic(0.38, 0.74, 0.34, 1.00);

  /// Standard Default Effects (Spring: damping=1.0, stiffness=1600, duration=200ms)
  static const Curve standardDefaultEffects = Cubic(0.34, 0.80, 0.34, 1.00);

  /// Standard Slow Effects (Spring: damping=1.0, stiffness=800, duration=300ms)
  static const Curve standardSlowEffects = Cubic(0.34, 0.83, 0.34, 1.00);
}

/// Helper for constructing physical SpringDescriptions according to M3 specifications.
abstract final class AppMotionSprings {
  /// Converts M3 damping ratio (ζ) and stiffness (k) into Flutter's [SpringDescription].
  static SpringDescription create({
    required double dampingRatio,
    required double stiffness,
    double mass = 1.0,
  }) {
    // Flutter SpringDescription requires damping coefficient c = 2 * ζ * sqrt(m * k)
    final dampingCoefficient = 2.0 * dampingRatio * math.sqrt(mass * stiffness);
    return SpringDescription(
      mass: mass,
      stiffness: stiffness,
      damping: dampingCoefficient,
    );
  }

  // Preset M3 Springs
  static final SpringDescription expressiveFastSpatial =
      create(dampingRatio: 0.6, stiffness: 800.0);
  static final SpringDescription expressiveDefaultSpatial =
      create(dampingRatio: 0.8, stiffness: 380.0);
  static final SpringDescription expressiveSlowSpatial =
      create(dampingRatio: 0.8, stiffness: 200.0);

  static final SpringDescription standardFastSpatial =
      create(dampingRatio: 0.9, stiffness: 1400.0);
  static final SpringDescription standardDefaultSpatial =
      create(dampingRatio: 0.9, stiffness: 700.0);
  static final SpringDescription standardSlowSpatial =
      create(dampingRatio: 0.9, stiffness: 300.0);

  static final SpringDescription effectsFast =
      create(dampingRatio: 1.0, stiffness: 3800.0);
  static final SpringDescription effectsDefault =
      create(dampingRatio: 1.0, stiffness: 1600.0);
  static final SpringDescription effectsSlow =
      create(dampingRatio: 1.0, stiffness: 800.0);
}

/// Direction for Shared Axis transitions
enum M3SharedAxisDirection {
  /// Horizontal (X-Axis) for wizard steps / sequential navigation.
  /// Automatically mirrors in RTL (Arabic).
  horizontal,

  /// Vertical (Y-Axis) for hierarchical drill-down or upward expansions.
  vertical,

  /// Depth (Z-Axis) for zoom transitions (parent -> child).
  depth,
}

/// M3 Page & Widget Transition Helpers
abstract final class AppMotionTransitions {
  /// Builds a Material 3 Shared Axis transition widget.
  ///
  /// Respects RTL directionality: in Arabic, the X-axis motion is inverted
  /// so that "Forward / Next" moves right-to-left naturally.
  static Widget buildSharedAxis({
    required BuildContext context,
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
    M3SharedAxisDirection direction = M3SharedAxisDirection.horizontal,
  }) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;

    switch (direction) {
      case M3SharedAxisDirection.horizontal:
        final offsetSign = isRtl ? -1.0 : 1.0;
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: AppMotionCurves.emphasizedDecelerate,
          reverseCurve: AppMotionCurves.emphasizedAccelerate,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: Offset(offsetSign * 0.20, 0.0),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
            child: child,
          ),
        );

      case M3SharedAxisDirection.vertical:
        final curvedAnimation = CurvedAnimation(
          parent: animation,
          curve: AppMotionCurves.emphasizedDecelerate,
          reverseCurve: AppMotionCurves.emphasizedAccelerate,
        );

        return SlideTransition(
          position: Tween<Offset>(
            begin: const Offset(0.0, 0.15),
            end: Offset.zero,
          ).animate(curvedAnimation),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(curvedAnimation),
            child: child,
          ),
        );

      case M3SharedAxisDirection.depth:
        final enterCurve = CurvedAnimation(
          parent: animation,
          curve: AppMotionCurves.emphasizedDecelerate,
          reverseCurve: AppMotionCurves.emphasizedAccelerate,
        );

        return ScaleTransition(
          scale: Tween<double>(begin: 0.85, end: 1.0).animate(enterCurve),
          child: FadeTransition(
            opacity: Tween<double>(begin: 0.0, end: 1.0).animate(enterCurve),
            child: child,
          ),
        );
    }
  }

  /// Builds a Material 3 Fade Through transition widget.
  ///
  /// Designed for top-level navigation bar destinations where elements
  /// do not share a spatial relationship.
  static Widget buildFadeThrough({
    required Animation<double> animation,
    required Animation<double> secondaryAnimation,
    required Widget child,
  }) {
    // Fade in from 35% to 100% of progress
    final fadeIn = CurvedAnimation(
      parent: animation,
      curve: const Interval(0.35, 1.0, curve: AppMotionCurves.standardDecelerate),
    );

    // Subtle scale up from 92% to 100%
    final scaleIn = Tween<double>(begin: 0.92, end: 1.0).animate(
      CurvedAnimation(
        parent: animation,
        curve: AppMotionCurves.standardDecelerate,
      ),
    );

    return FadeTransition(
      opacity: fadeIn,
      child: ScaleTransition(
        scale: scaleIn,
        child: child,
      ),
    );
  }

  /// Builds a Material 3 Fade transition for dialogs, menus, and overlays.
  static Widget buildFade({
    required Animation<double> animation,
    required Widget child,
  }) {
    final curvedAnimation = CurvedAnimation(
      parent: animation,
      curve: AppMotionCurves.standardDecelerate,
      reverseCurve: AppMotionCurves.standardAccelerate,
    );

    return FadeTransition(
      opacity: curvedAnimation,
      child: ScaleTransition(
        scale: Tween<double>(begin: 0.90, end: 1.0).animate(curvedAnimation),
        child: child,
      ),
    );
  }
}

/// GoRouter CustomTransitionPage helpers adhering to M3 Motion
abstract final class AppMotionPage {
  /// Returns a [CustomTransitionPage] implementing M3 Shared Axis transition.
  static CustomTransitionPage<T> sharedAxis<T>({
    required GoRouterState state,
    required Widget child,
    M3SharedAxisDirection direction = M3SharedAxisDirection.horizontal,
    Duration duration = AppMotionDurations.medium3, // 350ms
    Duration reverseDuration = AppMotionDurations.short4, // 200ms
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        return AppMotionTransitions.buildSharedAxis(
          context: context,
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          child: pageChild,
          direction: direction,
        );
      },
    );
  }

  /// Returns a [CustomTransitionPage] implementing M3 Fade Through transition.
  static CustomTransitionPage<T> fadeThrough<T>({
    required GoRouterState state,
    required Widget child,
    Duration duration = AppMotionDurations.medium2, // 300ms
    Duration reverseDuration = AppMotionDurations.short4, // 200ms
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        // animations package FadeThroughTransition (used for login → home).
        return FadeThroughTransition(
          animation: animation,
          secondaryAnimation: secondaryAnimation,
          fillColor: Theme.of(context).colorScheme.surface,
          child: pageChild,
        );
      },
    );
  }

  /// Returns a [CustomTransitionPage] implementing M3 Fade transition.
  static CustomTransitionPage<T> fade<T>({
    required GoRouterState state,
    required Widget child,
    Duration duration = AppMotionDurations.medium1, // 250ms
    Duration reverseDuration = AppMotionDurations.short3, // 150ms
  }) {
    return CustomTransitionPage<T>(
      key: state.pageKey,
      child: child,
      transitionDuration: duration,
      reverseTransitionDuration: reverseDuration,
      transitionsBuilder: (context, animation, secondaryAnimation, pageChild) {
        return AppMotionTransitions.buildFade(
          animation: animation,
          child: pageChild,
        );
      },
    );
  }
}

/// Displays an M3-compliant modal dialog with Fade and Scale transition.
Future<T?> showM3Dialog<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  bool barrierDismissible = true,
  Color barrierColor = Colors.black54,
  String? barrierLabel,
}) {
  return showGeneralDialog<T>(
    context: context,
    barrierDismissible: barrierDismissible,
    barrierColor: barrierColor,
    barrierLabel: barrierLabel ??
        MaterialLocalizations.of(context).modalBarrierDismissLabel,
    transitionDuration: AppMotionDurations.medium1, // 250ms enter
    pageBuilder: (dialogContext, animation, secondaryAnimation) =>
        builder(dialogContext),
    transitionBuilder: (dialogContext, animation, secondaryAnimation, child) {
      final curvedAnimation = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurves.standardDecelerate,
        reverseCurve: AppMotionCurves.standardAccelerate,
      );

      return FadeTransition(
        opacity: curvedAnimation,
        child: ScaleTransition(
          scale: Tween<double>(begin: 0.90, end: 1.0).animate(curvedAnimation),
          child: child,
        ),
      );
    },
  );
}

/// Displays an M3-compliant modal bottom sheet with standard M3 transitions and shapes.
Future<T?> showM3ModalBottomSheet<T>({
  required BuildContext context,
  required WidgetBuilder builder,
  Color? backgroundColor,
  bool isScrollControlled = false,
  ShapeBorder? shape,
  Clip? clipBehavior,
  bool isDismissible = true,
  bool enableDrag = true,
}) {
  return showModalBottomSheet<T>(
    context: context,
    builder: builder,
    sheetAnimationStyle: const AnimationStyle(
      duration: AppMotionDurations.long1,
      curve: AppMotionCurves.expressiveDefaultSpatial,
      reverseDuration: AppMotionDurations.short4,
      reverseCurve: AppMotionCurves.emphasizedAccelerate,
    ),
    backgroundColor: backgroundColor,
    isScrollControlled: isScrollControlled,
    shape: shape ??
        const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
    clipBehavior: clipBehavior ?? Clip.antiAlias,
    isDismissible: isDismissible,
    enableDrag: enableDrag,
  );
}

/// An [IndexedStack] with the M3 Fade Through pattern (home_v2 / §37):
/// outgoing child fades out for 90ms (emphasized-accelerate), then the
/// incoming child fades in over 210ms while scaling 0.92→1 (emphasized-
/// decelerate). Reduced motion → 150ms cross-fade. Visited children stay alive.
class M3FadeThroughIndexedStack extends StatefulWidget {
  final int index;
  final List<Widget> children;
  final Duration duration;

  const M3FadeThroughIndexedStack({
    super.key,
    required this.index,
    required this.children,
    this.duration = AppMotionDurations.medium2, // 90 + 210
  });

  @override
  State<M3FadeThroughIndexedStack> createState() =>
      _M3FadeThroughIndexedStackState();
}

class _M3FadeThroughIndexedStackState extends State<M3FadeThroughIndexedStack>
    with SingleTickerProviderStateMixin {
  static const double _outFrac = 0.3; // 90 / 300
  late final AnimationController _controller;
  late int _currentIndex;
  late int _previousIndex;

  @override
  void initState() {
    super.initState();
    _currentIndex = widget.index;
    _previousIndex = widget.index;
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
      value: 1.0,
    );
  }

  @override
  void didUpdateWidget(covariant M3FadeThroughIndexedStack oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (oldWidget.index != widget.index) {
      _previousIndex = _currentIndex;
      _currentIndex = widget.index;
      final reduced = MediaQuery.of(context).disableAnimations;
      _controller.duration =
          reduced ? AppMotionDurations.short3 : widget.duration;
      _controller.forward(from: 0.0);
    }
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final reduced = MediaQuery.of(context).disableAnimations;
    return AnimatedBuilder(
      animation: _controller,
      builder: (context, _) {
        final t = _controller.value;
        if (reduced) {
          return Opacity(
            opacity: t,
            child: IndexedStack(index: _currentIndex, children: widget.children),
          );
        }
        final outgoing = t < _outFrac && _previousIndex != _currentIndex;
        final double opacity;
        final double scale;
        if (outgoing) {
          opacity = 1 -
              AppMotionCurves.emphasizedAccelerate.transform(t / _outFrac);
          scale = 1;
        } else {
          final u = ((t - _outFrac) / (1 - _outFrac)).clamp(0.0, 1.0);
          final e = AppMotionCurves.emphasizedDecelerate.transform(u);
          opacity = _controller.isCompleted ? 1 : e;
          scale = 0.92 + 0.08 * e;
        }
        return Opacity(
          opacity: opacity.clamp(0.0, 1.0),
          child: Transform.scale(
            scale: scale,
            child: IndexedStack(
              index: outgoing ? _previousIndex : _currentIndex,
              children: widget.children,
            ),
          ),
        );
      },
    );
  }
}

/// Applies a staggered slide-up and fade-in animation to list items.
class M3StaggeredItem extends StatefulWidget {
  final int index;
  final Widget child;
  final Duration delayStep;
  final Duration duration;
  final double slideOffset;

  const M3StaggeredItem({
    super.key,
    required this.index,
    required this.child,
    this.delayStep = const Duration(milliseconds: 40),
    this.duration = AppMotionDurations.medium1, // 250ms
    this.slideOffset = 0.10,
  });

  @override
  State<M3StaggeredItem> createState() => _M3StaggeredItemState();
}

class _M3StaggeredItemState extends State<M3StaggeredItem>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: widget.duration,
    );

    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.standardDecelerate,
    );

    _slideAnimation = Tween<Offset>(
      begin: Offset(0.0, widget.slideOffset),
      end: Offset.zero,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppMotionCurves.emphasizedDecelerate,
      ),
    );

    final delayMs =
        // Stagger capped at 5 items (index 0..4) so the entrance stays short.
        math.min(widget.index, 4) * widget.delayStep.inMilliseconds;
    Future.delayed(Duration(milliseconds: delayMs), () {
      if (mounted) {
        _controller.forward();
      }
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.of(context).disableAnimations) {
      return widget.child;
    }

    return FadeTransition(
      opacity: _fadeAnimation,
      child: SlideTransition(
        position: _slideAnimation,
        child: widget.child,
      ),
    );
  }
}
