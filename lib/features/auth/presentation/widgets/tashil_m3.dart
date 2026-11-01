import 'dart:math' as math;

import 'package:flutter/material.dart';
import 'package:flutter/physics.dart';
import 'package:flutter/services.dart';
import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:package_info_plus/package_info_plus.dart';

/// Brand seed for the M3 splash/login redesign.
const kTashilSeed = Color(0xFF6750A4);

/// M3 Expressive motion tokens used by splash/login.
abstract final class M3Motion {
  static const short2 = Duration(milliseconds: 100);
  static const short4 = Duration(milliseconds: 200);
  static const medium2 = Duration(milliseconds: 300);
  static const medium4 = Duration(milliseconds: 400);
  static const long2 = Duration(milliseconds: 500);
  static const standard = Cubic(0.2, 0, 0, 1);
  static const emphasizedDecel = Cubic(0.05, 0.7, 0.1, 1);
  static const emphasizedAccel = Cubic(0.3, 0, 0.8, 0.15);
  static final spatialFast =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 800, ratio: 0.6);
  static final spatialDefault =
      SpringDescription.withDampingRatio(mass: 1, stiffness: 380, ratio: 0.8);
  static bool reduced(BuildContext c) => MediaQuery.disableAnimationsOf(c);
}

/// Theme for the auth screens: ColorScheme seeded from #6750A4 + Cairo.
ThemeData tashilAuthTheme(BuildContext context) {
  final dark = Theme.of(context).brightness == Brightness.dark;
  final base =
      dark ? AppTheme.darkTheme(kTashilSeed) : AppTheme.lightTheme(kTashilSeed);
  return base.copyWith(
    progressIndicatorTheme:
        // ignore: deprecated_member_use
        const ProgressIndicatorThemeData(year2023: false),
  );
}

/// Fixed light scheme used for the purple brand surfaces (header/splash) so
/// they match the native splash exactly in both light and dark mode.
final ColorScheme kTashilBrandScheme =
    ColorScheme.fromSeed(seedColor: kTashilSeed);

Future<PackageInfo>? _pkg;
Future<PackageInfo> tashilPackageInfo() => _pkg ??= PackageInfo.fromPlatform();

class TashilVersionText extends StatelessWidget {
  const TashilVersionText({super.key, required this.color, this.isArabic = true});
  final Color color;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<PackageInfo>(
      future: tashilPackageInfo(),
      builder: (context, snap) {
        final v = snap.data?.version;
        return Text(
          v == null ? ' ' : (isArabic ? 'الإصدار $v' : 'Version $v'),
          textAlign: TextAlign.center,
          style: Theme.of(context).textTheme.labelSmall?.copyWith(color: color),
        );
      },
    );
  }
}

/// The 'ت' logo tile in primaryContainer, shared by splash and login (Hero).
class TashilLogoTile extends StatelessWidget {
  const TashilLogoTile({super.key, required this.size});
  final double size;

  @override
  Widget build(BuildContext context) {
    final cs = kTashilBrandScheme;
    return Hero(
      tag: 'tashil_logo',
      flightShuttleBuilder: (_, anim, dir, from, to) => to.widget,
      child: _Tile(size: size, cs: cs),
    );
  }
}

class _Tile extends StatelessWidget {
  const _Tile({required this.size, required this.cs});
  final double size;
  final ColorScheme cs;
  @override
  Widget build(BuildContext context) {
    return Material(
      type: MaterialType.transparency,
      child: Container(
        width: size,
        height: size,
        alignment: Alignment.center,
        decoration: BoxDecoration(
          color: cs.primaryContainer,
          borderRadius: BorderRadius.circular(size * 0.29),
        ),
        child: Text(
          'ت',
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: size * 0.5,
            height: 1.2,
            fontWeight: FontWeight.w800,
            color: cs.onPrimaryContainer,
          ),
        ),
      ),
    );
  }
}

/// Option A button group: separate pills, 8dp gap. Selected = primary,
/// full radius + check. Unselected = secondaryContainer, radius 8.
/// Shape/width morph with the spatialFast spring; colour with standard 200ms.
class M3ButtonGroup<T> extends StatelessWidget {
  const M3ButtonGroup({
    super.key,
    required this.values,
    required this.labels,
    required this.icons,
    required this.selected,
    required this.onChanged,
  });
  final List<T> values;
  final List<String> labels;
  final List<IconData> icons;
  final T selected;
  final ValueChanged<T>? onChanged;

  @override
  Widget build(BuildContext context) {
    final children = <Widget>[];
    for (var i = 0; i < values.length; i++) {
      if (i > 0) children.add(const SizedBox(width: 8));
      children.add(Expanded(
        child: _GroupItem(
          key: ValueKey('group_item_${values[i]}'),
          label: labels[i],
          icon: icons[i],
          selected: values[i] == selected,
          onTap: onChanged == null ? null : () => onChanged!(values[i]),
        ),
      ));
    }
    return SizedBox(height: 48, child: Row(children: children));
  }
}

class _GroupItem extends StatefulWidget {
  const _GroupItem({
    super.key,
    required this.label,
    required this.icon,
    required this.selected,
    required this.onTap,
  });
  final String label;
  final IconData icon;
  final bool selected;
  final VoidCallback? onTap;

  @override
  State<_GroupItem> createState() => _GroupItemState();
}

class _GroupItemState extends State<_GroupItem>
    with SingleTickerProviderStateMixin {
  // 0 = unselected shape (r8), 1 = selected (full); press pushes toward r4.
  late final AnimationController _shape = AnimationController.unbounded(
    vsync: this,
    value: widget.selected ? 1 : 0,
  );
  bool _pressed = false;

  void _animateTo(double t) {
    if (M3Motion.reduced(context)) {
      _shape.value = t;
    } else {
      _shape.animateWith(SpringSimulation(M3Motion.spatialFast, _shape.value, t, 0));
    }
  }

  @override
  void didUpdateWidget(covariant _GroupItem old) {
    super.didUpdateWidget(old);
    if (old.selected != widget.selected) _animateTo(widget.selected ? 1 : 0);
  }

  @override
  void dispose() {
    _shape.dispose();
    super.dispose();
  }

  void _setPressed(bool p) {
    if (_pressed == p) return;
    _pressed = p;
    _animateTo(p ? -0.5 : (widget.selected ? 1 : 0));
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final reduce = M3Motion.reduced(context);
    final bg = widget.selected ? cs.primary : cs.secondaryContainer;
    final fg = widget.selected ? cs.onPrimary : cs.onSecondaryContainer;
    return Semantics(
      button: true,
      selected: widget.selected,
      child: Listener(
        onPointerDown: widget.onTap == null ? null : (_) => _setPressed(true),
        onPointerCancel: (_) => _setPressed(false),
        onPointerUp: (_) => _setPressed(false),
        child: AnimatedBuilder(
          animation: _shape,
          builder: (context, child) {
            final t = _shape.value;
            // t: -0.5 → r4, 0 → r8, 1 → r24 (full for 48dp)
            final r = t < 0 ? 8 + t * 8 : 8 + t * 16;
            final scaleX = 1 + (t < 0 ? -t * 0.08 : 0.0);
            return Transform.scale(
              scaleX: scaleX.clamp(0.9, 1.1),
              child: AnimatedContainer(
                duration: reduce ? Duration.zero : M3Motion.short4,
                curve: M3Motion.standard,
                decoration: BoxDecoration(
                  color: bg,
                  borderRadius: BorderRadius.circular(r.clamp(2.0, 24.0)),
                ),
                child: child,
              ),
            );
          },
          child: Material(
            type: MaterialType.transparency,
            child: InkWell(
              customBorder: const StadiumBorder(),
              onTap: widget.onTap == null
                  ? null
                  : () {
                      HapticFeedback.selectionClick();
                      widget.onTap!();
                    },
              child: Center(
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    AnimatedSwitcher(
                      duration: reduce ? Duration.zero : M3Motion.short4,
                      switchInCurve: M3Motion.emphasizedDecel,
                      transitionBuilder: (c, a) =>
                          ScaleTransition(scale: a, child: c),
                      child: Icon(
                        widget.selected ? Icons.check_rounded : widget.icon,
                        key: ValueKey(widget.selected),
                        size: 18,
                        color: fg,
                      ),
                    ),
                    const SizedBox(width: 8),
                    Flexible(
                      child: AnimatedDefaultTextStyle(
                        duration: reduce ? Duration.zero : M3Motion.short4,
                        curve: M3Motion.standard,
                        style: Theme.of(context).textTheme.labelLarge!.copyWith(
                              color: fg,
                              fontWeight: FontWeight.w600,
                              fontSize: 15,
                            ),
                        child: Text(widget.label,
                            maxLines: 1, overflow: TextOverflow.ellipsis),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

/// Horizontal 3-cycle, 8px shake over 400ms. Call [ShakeState.shake].
class Shake extends StatefulWidget {
  const Shake({super.key, required this.child});
  final Widget child;
  @override
  State<Shake> createState() => ShakeState();
}

class ShakeState extends State<Shake> with SingleTickerProviderStateMixin {
  late final AnimationController _c = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 400),
  );

  void shake() {
    if (M3Motion.reduced(context)) return;
    _c.forward(from: 0);
  }

  @override
  void dispose() {
    _c.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: _c,
      builder: (_, child) {
        final v = _c.value;
        return Transform.translate(
          offset: Offset(math.sin(v * math.pi * 6) * 8 * (1 - v), 0),
          child: child,
        );
      },
      child: widget.child,
    );
  }
}
