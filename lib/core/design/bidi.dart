import 'package:material_ui/material_ui.dart';

/// Bidirectional text and layout helpers
/// (m3.material.io/foundations/layout/bidirectionality-rtl).
///
/// Invoice numbers, barcodes, phone numbers, emails, URLs and dates are
/// left-to-right runs inside Arabic text. Without isolation the bidi
/// algorithm reorders their parts (`0001-20261125-0042` would show as
/// `0042-20261125-0001`, and `ali@tashil.app` could put the domain first).
abstract final class Bidi {
  /// Wraps [s] in Unicode LEFT-TO-RIGHT ISOLATE ... POP DIRECTIONAL ISOLATE.
  static String ltr(String s) => '\u2066$s\u2069';

  /// FIRST STRONG ISOLATE: for text the person typed (a customer or
  /// product name may be English inside an Arabic sentence). The run takes
  /// the direction of its first strong letter and cannot reorder its
  /// neighbours.
  static String auto(String s) => '\u2068$s\u2069';

  static bool isRtl(BuildContext context) =>
      Directionality.of(context) == TextDirection.rtl;
}

/// A directional icon that must mirror in RTL even though Flutter's
/// [IconData] is not marked `matchTextDirection` (logout, login,
/// keyboard_arrow_left/right, trending_flat, ...). Icons already marked,
/// such as arrow_back and send, mirror on their own with a plain [Icon].
///
/// Do not use it for icons that keep their direction: clocks, refresh and
/// other clockwise arrows, media controls, check marks, logos.
class MirroredIcon extends StatelessWidget {
  const MirroredIcon(
    this.icon, {
    super.key,
    this.size,
    this.color,
    this.semanticLabel,
  });

  final IconData icon;
  final double? size;
  final Color? color;
  final String? semanticLabel;

  @override
  Widget build(BuildContext context) {
    final child = Icon(
      icon,
      size: size,
      color: color,
      semanticLabel: semanticLabel,
    );
    if (icon.matchTextDirection || !Bidi.isRtl(context)) return child;
    return Transform.flip(flipX: true, child: child);
  }
}

/// Keeps [child] left-to-right inside an Arabic screen. For media
/// controls and their progress (always LTR in M3), and for fields whose
/// content is LTR: phone, email, URL, barcode, IBAN. Text inside still
/// reads correctly; only the order of the parts stays LTR.
class LtrIsland extends StatelessWidget {
  const LtrIsland({super.key, required this.child});

  final Widget child;

  @override
  Widget build(BuildContext context) =>
      Directionality(textDirection: TextDirection.ltr, child: child);
}
