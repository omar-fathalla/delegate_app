class SubscriptionCycleHelper {
  /// Returns the cycle code for the given date (defaults to now), e.g. "2026_H1" or "2026_H2".
  static String getCycleCode([DateTime? date]) {
    final d = date ?? DateTime.now();
    return '${d.year}_${d.month <= 6 ? "H1" : "H2"}';
  }

  /// Returns user-friendly Arabic description of the cycle.
  static String getCycleTitleArabic([DateTime? date]) {
    final d = date ?? DateTime.now();
    if (d.month <= 6) {
      return 'دورة النصف الأول (${d.year}) • 1 يناير حتى 30 يونيو';
    } else {
      return 'دورة النصف الثاني (${d.year}) • 1 يوليو حتى 31 ديسمبر';
    }
  }

  /// Calculates start date of current 6-month cycle.
  static DateTime getCycleStartDate([DateTime? date]) {
    final d = date ?? DateTime.now();
    return DateTime(d.year, d.month <= 6 ? 1 : 7, 1);
  }

  /// Calculates end date of current 6-month cycle.
  static DateTime getCycleEndDate([DateTime? date]) {
    final d = date ?? DateTime.now();
    return d.month <= 6
        ? DateTime(d.year, 6, 30, 23, 59, 59)
        : DateTime(d.year, 12, 31, 23, 59, 59);
  }

  /// Checks if subscription has expired.
  static bool isSubscriptionExpired(DateTime? endDate) {
    if (endDate == null) return false;
    return DateTime.now().isAfter(endDate);
  }

  /// Days remaining until subscription end.
  static int daysRemaining(DateTime? endDate) {
    if (endDate == null) return 0;
    final diff = endDate.difference(DateTime.now()).inDays;
    return diff > 0 ? diff : 0;
  }

  /// Calculates the number of months remaining in the current half-year cycle (1 to 6),
  /// including the current active month.
  static int getRemainingMonthsInCycle([DateTime? date]) {
    final d = date ?? DateTime.now();
    if (d.month <= 6) {
      // H1 ends at June (month 6)
      final remaining = 6 - d.month + 1;
      return remaining.clamp(1, 6);
    } else {
      // H2 ends at December (month 12)
      final remaining = 12 - d.month + 1;
      return remaining.clamp(1, 6);
    }
  }

  /// Returns the subscription fee in EGP for a given count of remaining months (1 to 6),
  /// with custom rounding requested:
  /// - 6 months: 500 EGP
  /// - 5 months: 450 EGP
  /// - 4 months: 350 EGP
  /// - 3 months: 250 EGP
  /// - 2 months: 200 EGP
  /// - 1 month: 100 EGP
  static double getFeeForMonths(int months) {
    switch (months) {
      case 6:
        return 500.0;
      case 5:
        return 450.0;
      case 4:
        return 350.0;
      case 3:
        return 250.0;
      case 2:
        return 200.0;
      case 1:
      default:
        return 100.0;
    }
  }

  /// End date of the free registration promotion (end of year: 31/12/2026).
  static final DateTime freePromotionEndDate = DateTime(2026, 12, 31, 23, 59, 59);

  /// Checks if the free promotion period is currently active (up to 31/12/2026).
  static bool isFreePromotionActive([DateTime? date]) {
    final d = date ?? DateTime.now();
    return !d.isAfter(freePromotionEndDate);
  }

  /// Calculates the prorated subscription fee for the given date (defaults to now).
  /// If the free promotion is active, the fee is 0.0 EGP.
  static double getProratedSubscriptionFee([DateTime? date]) {
    if (isFreePromotionActive(date)) {
      return 0.0;
    }
    final months = getRemainingMonthsInCycle(date);
    return getFeeForMonths(months);
  }
}
