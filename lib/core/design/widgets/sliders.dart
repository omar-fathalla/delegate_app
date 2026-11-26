import 'package:material_ui/material_ui.dart';

/// Sliders that follow m3.material.io/components/sliders/guidelines.
///
/// The app theme opts into Flutter's 2024 slider (`year2023: false`), which
/// already draws the M3 Expressive parts: the bar handle that narrows while
/// pressed, the gap between handle and track, stop indicators for
/// divisions, the end stop, and the value label above the handle while it
/// is dragged. [Slider] and [RangeSlider] are used as they are; this file
/// adds what Flutter does not have yet:
///
/// * the five **sizes** (XS 16, S 24, M 40, L 56, XL 96dp track);
/// * the **inset icon** for M, L and XL (moves to the inactive track when
///   there is no room, and can swap at zero: volume to mute);
/// * the **centered** variant (active track from the middle to the handle);
/// * **vertical** orientation (minimum at the bottom, in RTL too).
enum SliderSize {
  xs(16, 44),
  s(24, 44),
  m(40, 52),
  l(56, 68),
  xl(96, 108);

  const SliderSize(this.trackHeight, this.handleHeight);

  final double trackHeight;
  final double handleHeight;

  /// M3: inset icons only on M and up (track 40dp or more).
  bool get allowsInsetIcon => trackHeight >= 40;
}

/// Theme for a slider of [size]. Wrap any [Slider] or [RangeSlider].
SliderThemeData sliderThemeFor(BuildContext context, SliderSize size) =>
    SliderTheme.of(context).copyWith(
      trackHeight: size.trackHeight,
      thumbSize: WidgetStateProperty.resolveWith(
        (s) => Size(
          s.contains(WidgetState.pressed) || s.contains(WidgetState.dragged)
              ? 2
              : 4,
          size.handleHeight,
        ),
      ),
    );

/// Height of the slider's box: the handle plus room for the focus ring,
/// at least the 48dp touch target.
double _height(SliderSize size) =>
    size.handleHeight + 8 < 48 ? 48 : size.handleHeight + 8;

/// A standard slider with an M3 size, optional inset icon and optional
/// vertical orientation. Changes apply immediately (M3: people see the
/// effect while moving it).
class TashilSlider extends StatelessWidget {
  const TashilSlider({
    super.key,
    required this.value,
    required this.onChanged,
    this.min = 0,
    this.max = 1,
    this.divisions,
    this.label,
    this.size = SliderSize.xs,
    this.insetIcon,
    this.vertical = false,
    this.semanticFormatter,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;

  /// Stops: the handle snaps to the closest one. Keep them few.
  final int? divisions;

  /// Value shown above the handle while it is dragged.
  final String Function(double)? label;
  final SliderSize size;

  /// Icon inside the track (M, L, XL only). Gets the value so it can
  /// change at zero (volume_up to volume_off).
  final IconData Function(double)? insetIcon;
  final bool vertical;
  final String Function(double)? semanticFormatter;

  @override
  Widget build(BuildContext context) {
    assert(
      insetIcon == null || size.allowsInsetIcon,
      'M3: no inset icon under a 40dp track',
    );
    final theme = sliderThemeFor(
      context,
      size,
    ).copyWith(padding: insetIcon == null ? null : EdgeInsets.zero);
    Widget slider = SliderTheme(
      data: theme,
      child: Slider(
        value: value,
        min: min,
        max: max,
        divisions: divisions,
        label: label?.call(value),
        onChanged: onChanged,
        semanticFormatterCallback: semanticFormatter,
      ),
    );

    slider = SizedBox(height: _height(size), child: slider);
    if (insetIcon != null && !vertical) {
      slider = _withInsetIcon(context, slider);
    }

    if (!vertical) return slider;
    // Vertical: the minimum is at the bottom whatever the text direction.
    return RotatedBox(
      quarterTurns: 3,
      child: Directionality(textDirection: TextDirection.ltr, child: slider),
    );
  }

  Widget _withInsetIcon(BuildContext context, Widget slider) {
    final scheme = Theme.of(context).colorScheme;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final fraction = max == min ? 0.0 : (value - min) / (max - min);
    const pad = 12.0;
    final iconSize = size.trackHeight >= 56 ? 24.0 : 20.0;
    return LayoutBuilder(
      builder: (context, c) {
        final w = c.maxWidth;
        final handle = fraction * w;
        // Enough room on the active part? Otherwise after the handle.
        final onActive = handle - 6 >= iconSize + 2 * pad;
        final fromStart = onActive ? pad : handle + 6 + pad;
        final icon = Icon(
          insetIcon!(value),
          size: iconSize,
          color: onActive ? scheme.onPrimary : scheme.onSecondaryContainer,
        );
        return Stack(
          alignment: Alignment.center,
          children: [
            slider,
            Positioned(
              left: rtl ? null : fromStart,
              right: rtl ? fromStart : null,
              child: IgnorePointer(child: ExcludeSemantics(child: icon)),
            ),
          ],
        );
      },
    );
  }
}

/// Centered slider: for a value around a middle default (price change
/// from -20% to +20%). The active track runs from the centre to the
/// handle. No inset icon (M3).
class CenteredSlider extends StatelessWidget {
  const CenteredSlider({
    super.key,
    required this.value,
    required this.onChanged,
    required this.min,
    required this.max,
    this.divisions,
    this.label,
    this.size = SliderSize.xs,
    this.vertical = false,
  });

  final double value;
  final ValueChanged<double>? onChanged;
  final double min;
  final double max;
  final int? divisions;
  final String Function(double)? label;
  final SliderSize size;
  final bool vertical;

  @override
  Widget build(BuildContext context) {
    final slider = SizedBox(
      height: _height(size),
      child: SliderTheme(
        data: sliderThemeFor(
          context,
          size,
        ).copyWith(trackShape: const CenteredSliderTrackShape()),
        child: Slider(
          value: value,
          min: min,
          max: max,
          divisions: divisions,
          label: label?.call(value),
          onChanged: onChanged,
        ),
      ),
    );
    if (!vertical) return slider;
    return RotatedBox(
      quarterTurns: 3,
      child: Directionality(textDirection: TextDirection.ltr, child: slider),
    );
  }
}

/// Track for [CenteredSlider]: inactive on both sides of the handle, active
/// from the centre of the track to the handle, with the M3 gap around the
/// handle.
class CenteredSliderTrackShape extends SliderTrackShape
    with BaseSliderTrackShape {
  const CenteredSliderTrackShape();

  @override
  void paint(
    PaintingContext context,
    Offset offset, {
    required RenderBox parentBox,
    required SliderThemeData sliderTheme,
    required Animation<double> enableAnimation,
    required TextDirection textDirection,
    required Offset thumbCenter,
    Offset? secondaryOffset,
    bool isDiscrete = false,
    bool isEnabled = false,
    double additionalActiveTrackHeight = 2,
  }) {
    final rect = getPreferredRect(
      parentBox: parentBox,
      offset: offset,
      sliderTheme: sliderTheme,
      isEnabled: isEnabled,
      isDiscrete: isDiscrete,
    );
    final active = Paint()
      ..color = ColorTween(
        begin: sliderTheme.disabledActiveTrackColor,
        end: sliderTheme.activeTrackColor,
      ).evaluate(enableAnimation)!;
    final inactive = Paint()
      ..color = ColorTween(
        begin: sliderTheme.disabledInactiveTrackColor,
        end: sliderTheme.inactiveTrackColor,
      ).evaluate(enableAnimation)!;
    final gap = sliderTheme.trackGap ?? 6;
    final outer = Radius.circular(rect.height / 2);
    const inner = Radius.circular(2);
    final x = thumbCenter.dx;
    final c = context.canvas;

    if (x - gap > rect.left) {
      c.drawRRect(
        RRect.fromLTRBAndCorners(
          rect.left,
          rect.top,
          x - gap,
          rect.bottom,
          topLeft: outer,
          bottomLeft: outer,
          topRight: inner,
          bottomRight: inner,
        ),
        inactive,
      );
    }
    if (x + gap < rect.right) {
      c.drawRRect(
        RRect.fromLTRBAndCorners(
          x + gap,
          rect.top,
          rect.right,
          rect.bottom,
          topRight: outer,
          bottomRight: outer,
          topLeft: inner,
          bottomLeft: inner,
        ),
        inactive,
      );
    }
    final mid = rect.center.dx;
    if ((x - mid).abs() > gap) {
      final from = x > mid ? mid : x + gap;
      final to = x > mid ? x - gap : mid;
      c.drawRRect(
        RRect.fromLTRBR(from, rect.top, to, rect.bottom, inner),
        active,
      );
    }
  }
}
