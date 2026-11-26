/// Display helpers for money stored as integer piastres (1 EGP = 100).
///
/// Rule: amounts are shown with Western digits and two decimals, followed by
/// the currency label, e.g. `1,250.50 ج.م`. Never format a double.
abstract final class Money {
  static const currency = 'ج.م';

  /// `125050` -> `1,250.50`
  static String amount(int piastres) {
    final negative = piastres < 0;
    final abs = piastres.abs();
    final pounds = abs ~/ 100;
    final cents = (abs % 100).toString().padLeft(2, '0');
    final grouped = pounds.toString().replaceAllMapped(
      RegExp(r'\B(?=(\d{3})+(?!\d))'),
      (_) => ',',
    );
    return '${negative ? '-' : ''}$grouped.$cents';
  }

  /// `125050` -> `1,250.50 ج.م`
  static String format(int piastres) => '${amount(piastres)} $currency';

  /// Quantities are reals (weighed goods). Drop a trailing `.0`.
  static String qty(double q) => q == q.roundToDouble()
      ? q.toInt().toString()
      : q.toStringAsFixed(3).replaceFirst(RegExp(r'0+$'), '');
}
