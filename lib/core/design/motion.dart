import 'dart:math' as math;

import 'package:animations/animations.dart';
import 'package:material_ui/material_ui.dart';

/// M3 motion (m3.material.io/styles/motion).
///
/// Two systems, each with its own job:
///
/// 1. **Motion physics system** (springs), for movement inside a screen:
///    components opening, pressing, morphing. See [TashilSpring].
/// 2. **Easing and duration**, for transitions between screens and
///    elements entering or leaving. See [TashilEasing].
///
/// Transition *patterns* (container transform, forward/backward, lateral,
/// top level, enter/exit) are built with Google's `animations` package and
/// the tokens below. See [TashilTransitions].

/// Spring tokens of the motion physics system
/// (m3.material.io/styles/motion/overview/specs).
///
/// * **spatial** springs move position, size and shape; they may overshoot.
/// * **effects** springs change colour and opacity; they never overshoot.
///
/// Each token carries the spring itself ([description], damping and
/// stiffness) and the official curve + duration that M3 publishes for
/// platforms that cannot run springs everywhere ("Convert springs to
/// curves"). Use the spring for explicit animations
/// (`controller.animateWith(...)`) and [curve] + [duration] for implicit
/// ones (`AnimatedContainer`, `AnimatedAlign`, ...).
enum TashilSpring {
  // Expressive scheme: Tashil's default.
  fastSpatial(0.6, 800, Cubic(0.42, 1.67, 0.21, 0.90), 350),
  defaultSpatial(0.8, 380, Cubic(0.38, 1.21, 0.22, 1.00), 500),
  slowSpatial(0.8, 200, Cubic(0.39, 1.29, 0.35, 0.98), 650),
  fastEffects(1.0, 3800, Cubic(0.31, 0.94, 0.34, 1.00), 150),
  defaultEffects(1.0, 1600, Cubic(0.34, 0.80, 0.34, 1.00), 200),
  slowEffects(1.0, 800, Cubic(0.34, 0.88, 0.34, 1.00), 300),
  // Standard scheme: calmer, no visible bounce. For dense data screens.
  standardFastSpatial(0.9, 1400, Cubic(0.27, 1.06, 0.18, 1.00), 350),
  standardDefaultSpatial(0.9, 700, Cubic(0.27, 1.06, 0.18, 1.00), 500),
  standardSlowSpatial(0.9, 300, Cubic(0.27, 1.06, 0.18, 1.00), 750);

  const TashilSpring(this.dampingRatio, this.stiffness, this.curve, this._ms);

  final double dampingRatio;
  final double stiffness;

  /// Official cubic-bezier equivalent of this spring.
  final Curve curve;
  final int _ms;

  /// Official duration paired with [curve].
  Duration get duration => Duration(milliseconds: _ms);

  SpringDescription get description => SpringDescription.withDampingRatio(
    mass: 1,
    stiffness: stiffness,
    ratio: dampingRatio,
  );
}

/// Easing + duration pairs for transitions
/// (m3.material.io/styles/motion/easing-and-duration, "Suggested easing and
/// duration pairs").
enum TashilEasing {
  /// Begins and ends on screen (a card expanding to full screen). 500ms.
  emphasized(Curves.easeInOutCubicEmphasized, Durations.long2),

  /// Enters the screen (bottom sheet sliding in). 400ms.
  emphasizedDecelerate(Easing.emphasizedDecelerate, Durations.medium4),

  /// Leaves the screen permanently. 200ms.
  emphasizedAccelerate(Easing.emphasizedAccelerate, Durations.short4),

  /// Small utility transitions (selection controls). 300ms.
  standard(Easing.standard, Durations.medium2),

  /// 250ms.
  standardDecelerate(Easing.standardDecelerate, Durations.medium1),

  /// 200ms.
  standardAccelerate(Easing.standardAccelerate, Durations.short4);

  const TashilEasing(this.curve, this.duration);

  final Curve curve;
  final Duration duration;
}

/// Shortcuts and helpers.
abstract final class TashilMotion {
  static const fast = TashilSpring.fastSpatial;
  static const normal = TashilSpring.defaultSpatial;
  static const slow = TashilSpring.slowSpatial;
  static const fade = TashilSpring.defaultEffects;

  /// Delay between items that enter one after another (FAB menu, lists).
  static const stagger = Duration(milliseconds: 30);

  /// Honour the system "remove animations" setting
  /// (m3.material.io/styles/motion/transitions/applying-transitions).
  static Duration scaled(BuildContext context, Duration d) =>
      MediaQuery.maybeDisableAnimationsOf(context) ?? false ? Duration.zero : d;

  /// Clamp helper for overshooting springs driving values that must stay
  /// in range (opacity).
  static double unit(double v) => math.min(1, math.max(0, v));
}

/// M3 transition patterns
/// (m3.material.io/styles/motion/transitions/transition-patterns).
///
/// | Pattern | When | Widget |
/// | --- | --- | --- |
/// | Container transform | an element opens into its details | [OpenContainer] |
/// | Forward and backward | deeper or back in a flow (cart, pay, receipt) | page transition (shared X axis) |
/// | Lateral | siblings on one level (tabs) | [SharedAxisTransition] horizontal |
/// | Top level | switching main destinations (navigation bar) | [FadeThroughTransition] |
/// | Enter and exit | dialogs and menus inside the screen | [FadeScaleTransition] |
abstract final class TashilTransitions {
  static const _sharedX = _DirectionalSharedAxisBuilder();

  /// Page transitions for the whole app: forward/backward on a shared X axis.
  static const pageTransitionsTheme = PageTransitionsTheme(
    builders: {
      TargetPlatform.android: _sharedX,
      TargetPlatform.iOS: _sharedX,
      TargetPlatform.linux: _sharedX,
      TargetPlatform.macOS: _sharedX,
      TargetPlatform.windows: _sharedX,
      TargetPlatform.fuchsia: _sharedX,
    },
  );

  /// Horizontal shared-axis transition that moves the right way in RTL:
  /// forward slides in from the left in Arabic. Use for lateral switches
  /// inside a screen (with [PageTransitionSwitcher]).
  static Widget sharedX(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _mirrorInRtl(
    context,
    (c) => SharedAxisTransition(
      animation: animation,
      secondaryAnimation: secondaryAnimation,
      transitionType: SharedAxisTransitionType.horizontal,
      fillColor: Colors.transparent,
      child: c,
    ),
    child,
  );

  /// Container transform: begins and ends on screen.
  static Duration containerTransform(BuildContext context) =>
      TashilMotion.scaled(context, TashilEasing.emphasized.duration);

  /// Lateral and top-level switches inside a screen.
  static Duration switcher(BuildContext context) =>
      TashilMotion.scaled(context, TashilEasing.standard.duration);
}

/// Mirrors a left-to-right transition for RTL: the motion is flipped, the
/// content is flipped back so it reads normally.
Widget _mirrorInRtl(
  BuildContext context,
  Widget Function(Widget child) transition,
  Widget child,
) {
  if (Directionality.of(context) == TextDirection.ltr) {
    return transition(child);
  }
  return Transform.flip(
    flipX: true,
    child: transition(Transform.flip(flipX: true, child: child)),
  );
}

class _DirectionalSharedAxisBuilder extends PageTransitionsBuilder {
  const _DirectionalSharedAxisBuilder();

  static const _inner = SharedAxisPageTransitionsBuilder(
    transitionType: SharedAxisTransitionType.horizontal,
  );

  @override
  Widget buildTransitions<T>(
    PageRoute<T> route,
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) => _mirrorInRtl(
    context,
    (c) => _inner.buildTransitions(
      route,
      context,
      animation,
      secondaryAnimation,
      c,
    ),
    child,
  );
}
