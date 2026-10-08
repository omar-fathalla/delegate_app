/// Locale-independent date keys used by the Private Label feature.
///
/// We deliberately avoid `intl`'s `DateFormat` here because, under an Arabic
/// default locale, it may emit Arabic-Indic digits, which would corrupt the
/// Firestore document IDs and equality queries (`auditDate`, `month`).
abstract final class PrivateLabelDates {
  static String _two(int v) => v.toString().padLeft(2, '0');

  /// `yyyy-MM-dd`
  static String dayKey(DateTime date) =>
      '${date.year.toString().padLeft(4, '0')}-${_two(date.month)}-${_two(date.day)}';

  /// `yyyy-MM`
  static String monthKey(int year, int month) =>
      '${year.toString().padLeft(4, '0')}-${_two(month)}';

  /// `yyyy-MM` derived from a `yyyy-MM-dd` key.
  static String monthKeyOfDay(String dayKey) =>
      dayKey.length >= 7 ? dayKey.substring(0, 7) : dayKey;

  /// Parses a `yyyy-MM-dd` key into a local [DateTime] (midnight).
  static DateTime parseDayKey(String key) {
    final parts = key.split('-');
    if (parts.length != 3) return DateTime(1970);
    return DateTime(
      int.tryParse(parts[0]) ?? 1970,
      int.tryParse(parts[1]) ?? 1,
      int.tryParse(parts[2]) ?? 1,
    );
  }

  static int daysInMonth(int year, int month) => DateTime(year, month + 1, 0).day;

  static DateTime dateOnly(DateTime d) => DateTime(d.year, d.month, d.day);

  /// Deterministic day document ID: one doc per delegate per day (no duplicates).
  static String dayDocId(String delegateUid, String dayKey) => '${delegateUid}_$dayKey';
}
