import 'dart:io' show Platform;
import 'dart:math' as math;

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:flutter/foundation.dart' show kIsWeb, visibleForTesting;
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Brand map for the HR web login hero (TAS-188).
///
/// A light drawing of the Nile Delta from Cairo to Alexandria, painted in
/// tints of the theme purple, with Google-red pins on chain branches. The
/// geography uses real longitude/latitude projected into [box]; nothing is
/// loaded from the network.
///
/// Pins drop in one after another when the page opens, then bob up and down.
/// Both stop when the platform asks for reduced motion.

/// Longitude/latitude window shown by the map.
const double _lon0 = 29.3, _lon1 = 32.7, _lat0 = 29.7, _lat1 = 31.7;

/// Width / height of the map box (keeps the longitude scale at cos 30.5°).
const double kHrLoginMapAspect = 820 / 560;

/// Fraction of the box height where Cairo sits; callers keep it on screen.
const double kHrLoginMapCairoY = (_lat1 - 30.04) / (_lat1 - _lat0);

typedef _LL = (double lon, double lat);

const List<_LL> _coast = [
  (28.9, 30.85),
  (29.3, 30.93),
  (29.6, 31.03),
  (29.85, 31.15),
  (29.95, 31.23),
  (30.07, 31.32),
  (30.3, 31.4),
  (30.45, 31.46),
  (30.7, 31.52),
  (31.0, 31.6),
  (31.3, 31.58),
  (31.6, 31.52),
  (31.85, 31.53),
  (32.05, 31.4),
  (32.3, 31.28),
  (32.6, 31.1),
  (33.0, 31.15),
];
const List<_LL> _delta = [
  (31.18, 30.12),
  (30.95, 30.3),
  (30.5, 30.75),
  (30.1, 31.05),
  (29.95, 31.2),
  (30.07, 31.32),
  (30.3, 31.4),
  (30.45, 31.46),
  (30.7, 31.52),
  (31.0, 31.6),
  (31.3, 31.58),
  (31.6, 31.52),
  (31.85, 31.53),
  (32.05, 31.4),
  (32.2, 31.15),
  (32.15, 30.8),
  (31.95, 30.55),
  (31.5, 30.4),
];
const List<List<_LL>> _lakes = [
  [(31.85, 31.35), (32.2, 31.3), (32.25, 31.15), (32.0, 31.12), (31.85, 31.22)],
  [(30.55, 31.5), (31.1, 31.57), (31.15, 31.45), (30.7, 31.4)],
  [(29.8, 31.12), (30.0, 31.15), (29.97, 31.08), (29.8, 31.06)],
  [(30.15, 31.29), (30.33, 31.29), (30.3, 31.25), (30.17, 31.25)],
  [(32.33, 30.42), (32.45, 30.36), (32.5, 30.26), (32.38, 30.3)],
];
const List<_LL> _nile = [
  (31.26, 29.3),
  (31.25, 29.8),
  (31.23, 30.05),
  (31.18, 30.18),
];
const List<_LL> _rosetta = [
  (31.18, 30.18),
  (31.0, 30.4),
  (30.85, 30.65),
  (30.8, 30.9),
  (30.6, 31.15),
  (30.42, 31.45),
];
const List<_LL> _damietta = [
  (31.18, 30.18),
  (31.2, 30.45),
  (31.25, 30.75),
  (31.38, 31.04),
  (31.6, 31.3),
  (31.82, 31.52),
];
const List<_LL> _suezCanal = [
  (32.3, 31.27),
  (32.32, 30.9),
  (32.27, 30.6),
  (32.35, 30.3),
  (32.55, 29.95),
];
const List<List<_LL>> _canals = [
  [(31.25, 30.12), (31.6, 30.45), (31.9, 30.55), (32.27, 30.58)],
  [(30.82, 31.0), (30.6, 31.13), (30.25, 31.16), (29.95, 31.2)],
  [(31.15, 30.3), (31.4, 30.6), (31.6, 30.95), (31.9, 31.2)],
  [(31.05, 30.35), (30.75, 30.7), (30.6, 30.95)],
];
const List<List<_LL>> _highways = [
  [(31.05, 30.06), (30.6, 30.4), (30.2, 30.85), (29.97, 31.15)],
  [
    (31.23, 30.1),
    (31.18, 30.46),
    (31.0, 30.79),
    (30.82, 30.82),
    (30.47, 31.03),
    (29.97, 31.18),
  ],
  [(31.35, 30.1), (31.75, 30.3), (32.27, 30.6)],
  [(31.42, 30.03), (32.0, 30.0), (32.55, 29.97)],
  [(29.92, 31.24), (30.42, 31.42), (31.1, 31.57), (31.8, 31.47), (32.3, 31.26)],
  [(32.25, 30.6), (32.29, 30.95), (32.28, 31.24)],
  [(29.9, 31.13), (29.3, 30.93), (28.9, 30.83)],
];
const List<List<_LL>> _roads = [
  [(31.0, 30.79), (31.2, 30.9), (31.38, 31.04)],
  [(31.38, 31.04), (31.6, 31.3), (31.81, 31.42)],
  [(31.18, 30.46), (31.5, 30.58), (31.9, 30.6), (32.27, 30.6)],
  [(31.5, 30.58), (31.45, 30.8), (31.38, 31.04)],
  [(31.0, 30.79), (30.94, 31.11), (31.1, 31.4)],
  [(30.47, 31.03), (30.42, 31.4)],
  [(30.82, 30.82), (30.95, 30.55), (31.18, 30.46)],
  [(31.38, 31.04), (31.55, 31.1), (32.0, 31.15)],
  [(30.93, 29.96), (31.05, 30.06)],
  [(31.75, 30.3), (31.5, 30.58)],
  [(30.47, 31.03), (30.2, 30.85)],
  [(30.94, 31.11), (30.6, 31.13)],
  [(31.2, 30.9), (31.1, 31.1)],
];

/// Urban areas: centre and half-size in degrees.
const List<(double, double, double, double)> _urban = [
  (31.24, 30.05, .26, .13),
  (30.0, 31.22, .17, .05),
  (30.95, 29.97, .08, .06),
  (31.75, 30.3, .07, .05),
  (31.0, 30.79, .05, .04),
  (31.38, 31.04, .05, .035),
  (31.5, 30.58, .04, .03),
  (32.3, 31.25, .05, .03),
  (32.27, 30.6, .05, .03),
  (32.53, 29.98, .05, .03),
  (30.47, 31.03, .035, .03),
  (31.18, 30.46, .03, .025),
];

class _City {
  const _City(this.ar, this.en, this.lon, this.lat, {this.major = false});
  final String ar;
  final String en;
  final double lon;
  final double lat;
  final bool major;
}

const List<_City> _cities = [
  _City('القاهرة', 'Cairo', 31.24, 30.04, major: true),
  _City('الإسكندرية', 'Alexandria', 29.92, 31.2, major: true),
  _City('طنطا', 'Tanta', 31.0, 30.79),
  _City('المنصورة', 'Mansoura', 31.38, 31.04),
  _City('الزقازيق', 'Zagazig', 31.5, 30.58),
  _City('دمياط', 'Damietta', 31.81, 31.42),
  _City('بورسعيد', 'Port Said', 32.3, 31.26),
  _City('الإسماعيلية', 'Ismailia', 32.27, 30.6),
  _City('السويس', 'Suez', 32.55, 29.97),
  _City('دمنهور', 'Damanhur', 30.47, 31.03),
];

/// A chain branch pin.
class HrLoginMapPin {
  const HrLoginMapPin(
    this.ar,
    this.en,
    this.lon,
    this.lat, {
    this.featured = false,
  });
  final String ar;
  final String en;
  final double lon;
  final double lat;
  final bool featured;
}

/// Fathalla Market first (featured), then one branch per well-known chain.
const List<HrLoginMapPin> kHrLoginMapPins = [
  HrLoginMapPin(
    'فتح الله ماركت',
    'Fathalla Market',
    29.95,
    31.2,
    featured: true,
  ),
  HrLoginMapPin('Carrefour', 'Carrefour', 31.47, 30.03),
  HrLoginMapPin('HyperOne', 'HyperOne', 30.97, 30.06),
  HrLoginMapPin('سعودي', 'Seoudi', 31.0, 30.79),
  HrLoginMapPin('مترو', 'Metro', 31.38, 31.04),
  HrLoginMapPin('Spinneys', 'Spinneys', 32.3, 31.26),
  HrLoginMapPin('أولاد رجب', 'Awlad Ragab', 32.27, 30.6),
];

Offset _project(Rect box, double lon, double lat) => Offset(
  box.left + (lon - _lon0) / (_lon1 - _lon0) * box.width,
  box.top + (_lat1 - lat) / (_lat1 - _lat0) * box.height,
);

/// The hero map: painted geography plus animated pins.
class HrLoginMap extends StatelessWidget {
  const HrLoginMap({
    super.key,
    required this.box,
    required this.ink,
    required this.water,
    required this.isArabic,
  });

  /// Where the map window is drawn, in this widget's coordinates.
  final Rect box;

  /// Line and label color on the brand fill.
  final Color ink;

  /// Nile, canals and lakes.
  final Color water;
  final bool isArabic;

  @override
  Widget build(BuildContext context) {
    final text = Theme.of(context).textTheme;
    // Labels are widgets (not canvas text) so the web font loads for them.
    Widget label(
      String value,
      Offset at,
      TextStyle? style, {
      bool center = true,
    }) {
      return Positioned(
        left: at.dx,
        top: at.dy,
        child: FractionalTranslation(
          translation: Offset(center ? -.5 : 0, 0),
          child: Text(value, style: style, maxLines: 1, softWrap: false),
        ),
      );
    }

    return Stack(
      children: [
        Positioned.fill(
          child: RepaintBoundary(
            child: CustomPaint(
              painter: _MapPainter(box: box, ink: ink, water: water),
            ),
          ),
        ),
        label(
          isArabic ? 'البحر المتوسط' : 'Mediterranean Sea',
          _project(box, 29.55, 31.68),
          text.labelLarge?.copyWith(
            color: ink.withValues(alpha: .42),
            fontWeight: FontWeight.w500,
            fontSize: 13,
          ),
          center: false,
        ),
        for (final city in _cities)
          label(
            isArabic ? city.ar : city.en,
            _project(box, city.lon, city.lat) + Offset(0, city.major ? 6 : 4),
            text.labelMedium?.copyWith(
              color: ink.withValues(alpha: city.major ? .66 : .48),
              fontSize: 12,
              fontWeight: city.major ? FontWeight.w600 : FontWeight.w400,
              height: 1.2,
            ),
          ),
        Positioned.fill(
          child: _AnimatedPins(box: box, isArabic: isArabic, ink: ink),
        ),
      ],
    );
  }
}

class _MapPainter extends CustomPainter {
  _MapPainter({required this.box, required this.ink, required this.water});

  final Rect box;
  final Color ink;
  final Color water;

  Offset _p(_LL ll) => _project(box, ll.$1, ll.$2);

  Path _smooth(List<_LL> pts, {bool close = false}) {
    final q = pts.map(_p).toList();
    final path = Path()..moveTo(q.first.dx, q.first.dy);
    for (var i = 1; i < q.length; i++) {
      final m = (q[i - 1] + q[i]) / 2;
      path.quadraticBezierTo(q[i - 1].dx, q[i - 1].dy, m.dx, m.dy);
    }
    path.lineTo(q.last.dx, q.last.dy);
    if (close) path.close();
    return path;
  }

  Paint _stroke(Color c, double opacity, double width) => Paint()
    ..style = PaintingStyle.stroke
    ..color = c.withValues(alpha: opacity)
    ..strokeWidth = width
    ..strokeCap = StrokeCap.round
    ..strokeJoin = StrokeJoin.round;

  Paint _fill(Color c, double opacity) =>
      Paint()..color = c.withValues(alpha: opacity);

  @override
  void paint(Canvas canvas, Size size) {
    final k = box.width / 820;
    final uX = box.width / (_lon1 - _lon0);
    final uY = box.height / (_lat1 - _lat0);

    // Land below the coast, then the cultivated delta a little stronger.
    final land = Path()..moveTo(_p(_coast.first).dx, _p(_coast.first).dy);
    for (final c in _coast.skip(1)) {
      final o = _p(c);
      land.lineTo(o.dx, o.dy);
    }
    land
      ..lineTo(_p(_coast.last).dx, size.height + 40)
      ..lineTo(_p(_coast.first).dx, size.height + 40)
      ..close();
    canvas.drawPath(land, _fill(ink, .045));
    final deltaPx = _delta.map(_p).toList();
    final delta = Path()..addPolygon(deltaPx, true);
    canvas.drawPath(delta, _fill(ink, .05));

    // Field parcels and small irrigation ditches inside the delta.
    canvas.save();
    canvas.clipPath(delta);
    final rnd = math.Random(11);
    final fields = Path();
    final bounds = delta.getBounds();
    for (var i = 0; i < 260; i++) {
      final x = bounds.left + rnd.nextDouble() * bounds.width;
      final y = bounds.top + rnd.nextDouble() * bounds.height;
      final a = rnd.nextDouble() * math.pi;
      final l = (8 + rnd.nextDouble() * 26) * k;
      fields
        ..moveTo(x, y)
        ..quadraticBezierTo(
          x + math.cos(a + .8) * l * .4,
          y + math.sin(a + .8) * l * .4,
          x + math.cos(a) * l,
          y + math.sin(a) * l,
        );
    }
    canvas.drawPath(fields, _stroke(ink, .12, .6));
    canvas.restore();

    for (final lake in _lakes) {
      canvas.drawPath(
        _smooth([...lake, lake.first], close: true),
        _fill(water, .16),
      );
    }

    // Urban areas with a fine street grid.
    for (var i = 0; i < _urban.length; i++) {
      final (lon, lat, rx, ry) = _urban[i];
      final c = _project(box, lon, lat);
      final oval = Rect.fromCenter(
        center: c,
        width: rx * uX * 2,
        height: ry * uY * 2,
      );
      canvas.drawOval(oval, _fill(ink, .07));
      canvas.save();
      canvas.clipPath(Path()..addOval(oval));
      canvas.translate(c.dx, c.dy);
      canvas.rotate(((i * 37) % 60 - 30) * math.pi / 180);
      final r = math.max(oval.width, oval.height);
      final gap = math.max(4.0, 6 * k);
      final grid = Path();
      for (var t = -r; t <= r; t += gap) {
        grid
          ..moveTo(-r, t)
          ..lineTo(r, t)
          ..moveTo(t, -r)
          ..lineTo(t, r);
      }
      canvas.drawPath(grid, _stroke(ink, .16, .5));
      canvas.restore();
    }

    // Cairo ring road and regional ring road.
    final cairo = _project(box, 31.25, 30.05);
    canvas.drawOval(
      Rect.fromCenter(center: cairo, width: .26 * uX, height: .18 * uY),
      _stroke(ink, .3, 1.6),
    );
    canvas.drawOval(
      Rect.fromCenter(
        center: cairo + Offset(.02 * uX, 0),
        width: .72 * uX,
        height: .4 * uY,
      ),
      _stroke(ink, .18, 1.2),
    );

    canvas.drawPath(_smooth(_coast), _stroke(ink, .32, 1.4));
    for (final c in _canals) {
      canvas.drawPath(_smooth(c), _stroke(water, .32, 1));
    }
    canvas.drawPath(_smooth(_suezCanal), _stroke(water, .42, 2));
    canvas.drawPath(_smooth(_nile), _stroke(water, .5, 3.2));
    canvas.drawPath(_smooth(_rosetta), _stroke(water, .5, 2.2));
    canvas.drawPath(_smooth(_damietta), _stroke(water, .5, 2.2));

    for (final r in _roads) {
      canvas.drawPath(_smooth(r), _stroke(ink, .2, 1));
    }
    for (final h in _highways) {
      canvas.drawPath(_smooth(h), _stroke(ink, .32, 2));
    }

    for (final city in _cities) {
      canvas.drawCircle(
        _project(box, city.lon, city.lat),
        city.major ? 3 : 2.2,
        _fill(ink, .6),
      );
    }
  }

  @override
  bool shouldRepaint(_MapPainter old) =>
      old.box != box || old.ink != ink || old.water != water;
}

/// Turns the pin loop off; widget tests set it so `pumpAndSettle` settles.
@visibleForTesting
bool? debugHrLoginMapAnimate;

bool get _loopAllowed {
  if (debugHrLoginMapAnimate != null) return debugHrLoginMapAnimate!;
  // Widget tests run on the VM with FLUTTER_TEST set; the web build never does.
  return kIsWeb || !Platform.environment.containsKey('FLUTTER_TEST');
}

class _AnimatedPins extends StatefulWidget {
  const _AnimatedPins({
    required this.box,
    required this.isArabic,
    required this.ink,
  });

  final Rect box;
  final bool isArabic;
  final Color ink;

  @override
  State<_AnimatedPins> createState() => _AnimatedPinsState();
}

class _AnimatedPinsState extends State<_AnimatedPins>
    with TickerProviderStateMixin {
  static const _stagger = 0.16;
  static const _drop = 0.7;

  late final AnimationController _enter = AnimationController(
    vsync: this,
    duration: Duration(
      milliseconds:
          ((kHrLoginMapPins.length - 1) * _stagger * 1000 + _drop * 1000)
              .round(),
    ),
  );
  late final AnimationController _bob = AnimationController(
    vsync: this,
    duration: const Duration(milliseconds: 2800),
  );
  bool _started = false;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (_started) return;
    _started = true;
    if (MediaQuery.disableAnimationsOf(context)) {
      _enter.value = 1;
      return;
    }
    _enter.forward().whenComplete(() {
      if (mounted && _loopAllowed && !MediaQuery.disableAnimationsOf(context)) {
        _bob.repeat();
      }
    });
  }

  @override
  void dispose() {
    _enter.dispose();
    _bob.dispose();
    super.dispose();
  }

  /// 0 → 1 → 0 over the first half of the cycle, then rest.
  double _bump(double p) => p < .5 ? math.sin(p / .5 * math.pi) : 0;

  @override
  Widget build(BuildContext context) {
    return AnimatedBuilder(
      animation: Listenable.merge([_enter, _bob]),
      builder: (context, _) {
        final total = _enter.duration!.inMilliseconds / 1000;
        return Stack(
          clipBehavior: Clip.none,
          children: [
            for (var i = 0; i < kHrLoginMapPins.length; i++)
              _pin(context, i, total),
          ],
        );
      },
    );
  }

  Widget _pin(BuildContext context, int i, double total) {
    final pin = kHrLoginMapPins[i];
    final at = _project(widget.box, pin.lon, pin.lat);
    final start = i * _stagger / total;
    final end = math.min(1.0, (i * _stagger + _drop) / total);
    final drop = AppMotionCurves.expressiveDefaultSpatial.transform(
      ((_enter.value - start) / (end - start)).clamp(0.0, 1.0),
    );
    final phase = (_bob.value + i * .13) % 1;
    final lift = _bob.isAnimating ? _bump(phase) : 0.0;
    final dy = -36 * (1 - drop) - 10 * lift;
    final shadowScale = 1 - .45 * lift;
    return Positioned(
      left: at.dx,
      top: at.dy,
      child: Opacity(
        opacity: drop > 0 ? 1 : 0,
        child: Stack(
          clipBehavior: Clip.none,
          children: [
            // Ground shadow under the tip; shrinks while the pin is up.
            Transform.translate(
              offset: const Offset(0, -2),
              child: FractionalTranslation(
                translation: const Offset(-.5, -.5),
                child: Transform.scale(
                  scale: shadowScale,
                  child: Container(
                    width: pin.featured ? 16 : 11,
                    height: pin.featured ? 6 : 4,
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(
                        alpha: .4 * (.5 + .5 * shadowScale),
                      ),
                      borderRadius: BorderRadius.circular(8),
                    ),
                  ),
                ),
              ),
            ),
            Transform.translate(
              offset: Offset(0, dy),
              child: FractionalTranslation(
                translation: const Offset(-.5, -1),
                child: _PinBody(
                  pin: pin,
                  label: widget.isArabic ? pin.ar : pin.en,
                  ink: widget.ink,
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _PinBody extends StatelessWidget {
  const _PinBody({required this.pin, required this.label, required this.ink});

  final HrLoginMapPin pin;
  final String label;
  final Color ink;

  static const Color _red = Color(0xFFEA4335);
  static const Color _redDark = Color(0xFFA50E0E);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final size = pin.featured ? 40.0 : 30.0;
    final labelStyle = text.labelMedium?.copyWith(
      fontSize: pin.featured ? 14 : 12,
      fontWeight: pin.featured ? FontWeight.w800 : FontWeight.w700,
      color: cs.brightness == Brightness.dark ? cs.onPrimary : cs.primary,
      height: 1.3,
    );
    return Semantics(
      label: label,
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          DecoratedBox(
            decoration: BoxDecoration(
              color: ink.withValues(alpha: pin.featured ? 1 : .88),
              borderRadius: BorderRadius.circular(999),
              boxShadow: [
                BoxShadow(
                  color: Colors.black.withValues(alpha: pin.featured ? .3 : .2),
                  blurRadius: pin.featured ? 8 : 4,
                  offset: const Offset(0, 2),
                ),
              ],
            ),
            child: Padding(
              padding: EdgeInsets.symmetric(
                horizontal: pin.featured ? 12 : 9,
                vertical: pin.featured ? 4 : 1,
              ),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  if (pin.featured) ...[
                    Icon(
                      Symbols.star_rounded,
                      fill: 1,
                      size: 16,
                      color: labelStyle?.color,
                    ),
                    const SizedBox(width: 4),
                  ],
                  Text(label, style: labelStyle),
                ],
              ),
            ),
          ),
          SizedBox(
            width: size,
            height: size,
            child: Stack(
              alignment: Alignment.center,
              children: [
                Icon(
                  Symbols.location_on_rounded,
                  fill: 1,
                  size: size,
                  color: _red,
                  shadows: const [
                    Shadow(
                      color: Color(0x59000000),
                      blurRadius: 3,
                      offset: Offset(0, 2),
                    ),
                  ],
                ),
                Positioned(
                  top: size * .25,
                  child: Container(
                    width: size * .26,
                    height: size * .26,
                    decoration: const BoxDecoration(
                      color: _redDark,
                      shape: BoxShape.circle,
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}
