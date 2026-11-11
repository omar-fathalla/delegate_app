import 'package:delegate_app/core/config/app_env.dart';

/// Delegate subscription rules. Mirrors functions/src/subscription_logic.ts;
/// the server is authoritative (it quotes the Paymob amount and suspends).
///
/// - Periods (Africa/Cairo): H1 = 1 Jan..30 Jun, H2 = 1 Jul..31 Dec.
/// - Fee: 500 EGP per delegate per period, prorated by remaining months,
///   join month counted in full: 500 * remainingMonths / 6, 2 decimals.
/// - Free until 31/12/2026 (Cairo). First paid period: 2027_H1.
/// - One subscription per delegate covers all chains.
///
/// Dates: a UTC [DateTime] is converted to Cairo wall time; a local
/// (non-UTC) [DateTime] is read as Cairo wall time as-is.
class SubscriptionCycleHelper {
  static const double periodFee = 500.0;
  static const int monthsPerPeriod = 6;

  /// Mohamed policy (PR #212): max delegates per single renewal / Paymob payment.
  static const int maxDelegatesPerRenewal = 100;

  /// Last free day (inclusive), Cairo calendar date.
  static final DateTime freePromotionLastDay = DateTime(2026, 12, 31);

  /// Fake tashil-dev company whose free period is treated as ended.
  /// Honored only when [AppEnv.isDev] is true (ENV=dev). A prod build
  /// never bypasses the promotion, even if this company id is used.
  static const String devPaidRenewalCompanyUID = 'co_dev_renewal_paid';

  /// Kept for older callers: last free instant (Cairo wall time).
  static final DateTime freePromotionEndDate = DateTime(2026, 12, 31, 23, 59, 59);

  // ---------------------------------------------------------------- Cairo time

  /// Converts [date] (default: now) to Cairo wall time.
  static DateTime cairoTime([DateTime? date]) {
    final d = date ?? DateTime.now().toUtc();
    if (!d.isUtc) return d;
    final offset = cairoUtcOffset(d);
    final w = d.add(offset);
    return DateTime(w.year, w.month, w.day, w.hour, w.minute, w.second, w.millisecond);
  }

  /// Egypt: UTC+2, UTC+3 from the last Friday of April 00:00 to the end of the
  /// last Thursday of October (rule in force since 2023).
  static Duration cairoUtcOffset(DateTime utc) {
    final y = utc.year;
    if (y < 2023) return const Duration(hours: 2);
    final start = _lastWeekday(y, 4, DateTime.friday); // 00:00 local = 22:00 UTC the day before
    final end = _lastWeekday(y, 10, DateTime.thursday); // 24:00 local (UTC+3) = 21:00 UTC
    final startUtc = DateTime.utc(start.year, start.month, start.day).subtract(const Duration(hours: 2));
    final endUtc = DateTime.utc(end.year, end.month, end.day, 21);
    final inDst = !utc.isBefore(startUtc) && utc.isBefore(endUtc);
    return Duration(hours: inDst ? 3 : 2);
  }

  static DateTime _lastWeekday(int year, int month, int weekday) {
    var d = DateTime.utc(year, month + 1, 0);
    while (d.weekday != weekday) {
      d = d.subtract(const Duration(days: 1));
    }
    return d;
  }

  // ------------------------------------------------------------------- periods

  /// Cycle code, e.g. "2027_H1".
  static String getCycleCode([DateTime? date]) {
    final d = cairoTime(date);
    return '${d.year}_${d.month <= 6 ? "H1" : "H2"}';
  }

  static String getCycleTitleArabic([DateTime? date]) {
    final d = cairoTime(date);
    if (d.month <= 6) {
      return 'دورة النصف الأول (${d.year}) • 1 يناير حتى 30 يونيو';
    } else {
      return 'دورة النصف الثاني (${d.year}) • 1 يوليو حتى 31 ديسمبر';
    }
  }

  /// First day of the period (Cairo wall time).
  static DateTime getCycleStartDate([DateTime? date]) {
    final d = cairoTime(date);
    return DateTime(d.year, d.month <= 6 ? 1 : 7, 1);
  }

  /// Last second of the period (Cairo wall time).
  static DateTime getCycleEndDate([DateTime? date]) {
    final d = cairoTime(date);
    return d.month <= 6
        ? DateTime(d.year, 6, 30, 23, 59, 59)
        : DateTime(d.year, 12, 31, 23, 59, 59);
  }

  /// 'YYYY-MM-DD' inclusive bounds stored on subscriptions.
  static String periodStartDay([DateTime? date]) => _day(getCycleStartDate(date));
  static String periodEndDay([DateTime? date]) => _day(getCycleEndDate(date));

  static String _day(DateTime d) =>
      '${d.year.toString().padLeft(4, '0')}-${d.month.toString().padLeft(2, '0')}-${d.day.toString().padLeft(2, '0')}';

  static bool isSubscriptionExpired(DateTime? endDate) {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate);
  }

  static int daysRemaining(DateTime? endDate) {
    if (endDate == null) return 0;
    final diff = endDate.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Months left in the period including the current month (1..6).
  static int getRemainingMonthsInCycle([DateTime? date]) {
    final d = cairoTime(date);
    return monthsPerPeriod - ((d.month - 1) % monthsPerPeriod);
  }

  // ---------------------------------------------------------------------- fees

  /// The single rounding rule for money: half-up to 2 decimals.
  static double roundMoney(double value) {
    final cents = (value * 100 + (value >= 0 ? 1e-9 : -1e-9)).round();
    return cents / 100.0;
  }

  /// 500 * months / 6, rounded: 6→500, 5→416.67, 4→333.33, 3→250, 2→166.67, 1→83.33.
  static double getFeeForMonths(int months) {
    final m = months.clamp(1, monthsPerPeriod);
    return roundMoney(periodFee * m / monthsPerPeriod);
  }

  /// Whether the ENV=dev build may skip the free promotion for [companyUID].
  /// Always false when [isDev] is false (prod builds).
  static bool devFreePeriodBypass({
    required bool isDev,
    required String? companyUID,
  }) {
    if (!isDev) return false;
    final company = (companyUID ?? '').trim();
    return company.isNotEmpty && company == devPaidRenewalCompanyUID;
  }

  static bool isFreePromotionActive([DateTime? date, String? companyUID]) {
    if (devFreePeriodBypass(isDev: AppEnv.isDev, companyUID: companyUID)) {
      return false;
    }
    final d = cairoTime(date);
    final day = DateTime(d.year, d.month, d.day);
    return !day.isAfter(freePromotionLastDay);
  }

  /// Fee one delegate pays when registering or renewing at [date].
  static double getProratedSubscriptionFee([DateTime? date, String? companyUID]) {
    if (isFreePromotionActive(date, companyUID)) return 0.0;
    return getFeeForMonths(getRemainingMonthsInCycle(date));
  }

  /// Total for several delegates renewed together (one Paymob payment).
  static double totalFor(int delegateCount, [DateTime? date, String? companyUID]) {
    if (delegateCount <= 0) return 0.0;
    return roundMoney(getProratedSubscriptionFee(date, companyUID) * delegateCount);
  }

  static String formatEgp(double amount) {
    final r = roundMoney(amount);
    return r == r.truncateToDouble() ? r.toStringAsFixed(0) : r.toStringAsFixed(2);
  }

  /// True when [subscription] is paid for a period that still covers [at],
  /// or waived during the free promotion. Status `active` is not a substitute.
  static bool hasPaidCoverage(
    Map<String, dynamic>? subscription, {
    DateTime? at,
    String? companyUID,
  }) {
    if (subscription == null) return false;
    final status = (subscription['paymentStatus'] ?? '').toString().trim();
    final period = (subscription['periodCode'] ?? '').toString().trim();
    if (period.isEmpty) return false;
    final when = cairoTime(at);
    if (status == 'paid') {
      if (period == getCycleCode(at)) return true;
      final end = _coverageEnd(subscription, period);
      return end != null && !when.isAfter(end);
    }
    if (status == 'waived' && isFreePromotionActive(at, companyUID)) return true;
    return false;
  }

  static DateTime? _coverageEnd(Map<String, dynamic> subscription, String period) {
    final raw = subscription['periodEnd'] ?? subscription['period_end'];
    if (raw is String && raw.length >= 10) {
      final parsed = DateTime.tryParse(raw.substring(0, 10));
      if (parsed != null) {
        return DateTime(parsed.year, parsed.month, parsed.day, 23, 59, 59);
      }
    }
    final m = RegExp(r'^(\d{4})_H([12])$').firstMatch(period);
    if (m == null) return null;
    final year = int.parse(m.group(1)!);
    return m.group(2) == '1'
        ? DateTime(year, 6, 30, 23, 59, 59)
        : DateTime(year, 12, 31, 23, 59, 59);
  }

  // -------------------------------------------------------- advance renewal

  /// Default length of the advance-renewal window (Cairo calendar days).
  static const int defaultAdvanceRenewalDays = 30;

  /// tashil-dev window so the ENV=dev app can be exercised before late December.
  static const int devAdvanceRenewalDays = 60;

  /// The period after [code] (or after the period of [date] when [code] is null).
  static String nextCycleCode([DateTime? date, String? code]) {
    final current = code ?? getCycleCode(date);
    final m = RegExp(r'^(\d{4})_H([12])$').firstMatch(current);
    if (m == null) {
      final d = cairoTime(date);
      return d.month <= 6 ? '${d.year}_H2' : '${d.year + 1}_H1';
    }
    final year = int.parse(m.group(1)!);
    return m.group(2) == '1' ? '${year}_H2' : '${year + 1}_H1';
  }

  /// First day of [periodCode] as Cairo wall time. Throws on a bad code.
  static DateTime getCycleStartDateForCode(String periodCode) {
    final m = RegExp(r'^(\d{4})_H([12])$').firstMatch(periodCode.trim());
    if (m == null) {
      throw ArgumentError.value(periodCode, 'periodCode');
    }
    final year = int.parse(m.group(1)!);
    return m.group(2) == '1' ? DateTime(year, 1, 1) : DateTime(year, 7, 1);
  }

  static DateTime getCycleEndDateForCode(String periodCode) {
    final m = RegExp(r'^(\d{4})_H([12])$').firstMatch(periodCode.trim());
    if (m == null) {
      throw ArgumentError.value(periodCode, 'periodCode');
    }
    final year = int.parse(m.group(1)!);
    return m.group(2) == '1'
        ? DateTime(year, 6, 30, 23, 59, 59)
        : DateTime(year, 12, 31, 23, 59, 59);
  }

  static String periodStartDayForCode(String periodCode) => _day(getCycleStartDateForCode(periodCode));
  static String periodEndDayForCode(String periodCode) => _day(getCycleEndDateForCode(periodCode));

  /// 00:00 Cairo on the first day of the last [days] calendar days of the
  /// current period (the period end day is included).
  static DateTime advanceWindowOpensAt(DateTime date, {int days = defaultAdvanceRenewalDays}) {
    final safe = days < 1 ? defaultAdvanceRenewalDays : (days > 180 ? 180 : days);
    final end = getCycleEndDate(date);
    final openDay = DateTime(end.year, end.month, end.day).subtract(Duration(days: safe - 1));
    return DateTime(openDay.year, openDay.month, openDay.day);
  }

  static bool isAdvanceRenewalOpen(
    DateTime date, {
    required bool enabled,
    int days = defaultAdvanceRenewalDays,
  }) {
    if (!enabled) return false;
    final cairo = cairoTime(date);
    final opens = advanceWindowOpensAt(date, days: days);
    final periodEndExclusive = getCycleEndDate(date).add(const Duration(seconds: 1));
    return !cairo.isBefore(opens) && cairo.isBefore(periodEndExclusive);
  }

  /// Cycle a quote/request should target at [date]. Next period when the
  /// advance window is open; otherwise the current period.
  static String payableCycleCode(
    DateTime date, {
    required bool enabled,
    int days = defaultAdvanceRenewalDays,
  }) {
    if (isAdvanceRenewalOpen(date, enabled: enabled, days: days)) {
      return nextCycleCode(date);
    }
    return getCycleCode(date);
  }

  /// Fee for [periodCode] at [date]. A future period is quoted at its start
  /// (full 500, not today's remaining months or today's free-promotion zero).
  static double getFeeForPeriod(String periodCode, [DateTime? date, String? companyUID]) {
    final current = getCycleCode(date);
    if (periodCode == current) {
      return getProratedSubscriptionFee(date, companyUID);
    }
    return getProratedSubscriptionFee(getCycleStartDateForCode(periodCode), companyUID);
  }
}
