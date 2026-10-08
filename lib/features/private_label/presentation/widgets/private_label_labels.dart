import 'package:delegate_app/features/private_label/domain/entities/private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:flutter/material.dart';

/// Arabic labels, Google icons and seed-derived colors for the Private Label UI.
abstract final class PrivateLabelLabels {
  static const List<String> months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر',
  ];

  /// Saturday-first week (Egypt).
  static const List<String> weekdaysShort = ['س', 'ح', 'ن', 'ث', 'ر', 'خ', 'ج'];

  static const List<String> weekdays = [
    'الاثنين', 'الثلاثاء', 'الأربعاء', 'الخميس', 'الجمعة', 'السبت', 'الأحد',
  ];

  static String monthTitle(int year, int month) => '${months[month - 1]} $year';

  /// e.g. "الأربعاء 7 أكتوبر"
  static String dayTitle(String dayKey) {
    final d = PrivateLabelDates.parseDayKey(dayKey);
    return '${weekdays[d.weekday - 1]} ${d.day} ${months[d.month - 1]}';
  }

  static String price(double value) {
    final fixed = value.toStringAsFixed(2);
    final trimmed = fixed.endsWith('.00') ? fixed.substring(0, fixed.length - 3) : fixed;
    return '$trimmed ج.م';
  }

  static String time(DateTime t) {
    final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
    final m = t.minute.toString().padLeft(2, '0');
    return '$h:$m ${t.hour < 12 ? 'ص' : 'م'}';
  }

  // ─── Stock status ───
  static String stock(PrivateLabelStockStatus s) {
    switch (s) {
      case PrivateLabelStockStatus.available:
        return 'متوفر';
      case PrivateLabelStockStatus.low:
        return 'كمية قليلة';
      case PrivateLabelStockStatus.outOfStock:
        return 'نافد';
      case PrivateLabelStockStatus.notDisplayed:
        return 'مش معروض';
    }
  }

  static IconData stockIcon(PrivateLabelStockStatus s) {
    switch (s) {
      case PrivateLabelStockStatus.available:
        return Icons.inventory_2_rounded;
      case PrivateLabelStockStatus.low:
        return Icons.production_quantity_limits_rounded;
      case PrivateLabelStockStatus.outOfStock:
        return Icons.remove_shopping_cart_rounded;
      case PrivateLabelStockStatus.notDisplayed:
        return Icons.visibility_off_rounded;
    }
  }

  // ─── Review status ───
  static String review(PrivateLabelReviewStatus s) {
    switch (s) {
      case PrivateLabelReviewStatus.pending:
        return 'في انتظار المراجعة';
      case PrivateLabelReviewStatus.approved:
        return 'معتمد';
      case PrivateLabelReviewStatus.priceIssue:
        return 'مخالفة سعر';
      case PrivateLabelReviewStatus.rejected:
        return 'مرفوض';
    }
  }

  static IconData reviewIcon(PrivateLabelReviewStatus s) {
    switch (s) {
      case PrivateLabelReviewStatus.pending:
        return Icons.hourglass_top_rounded;
      case PrivateLabelReviewStatus.approved:
        return Icons.verified_rounded;
      case PrivateLabelReviewStatus.priceIssue:
        return Icons.price_change_rounded;
      case PrivateLabelReviewStatus.rejected:
        return Icons.block_rounded;
    }
  }

  /// Colors derived from the seed scheme only.
  static Color reviewColor(PrivateLabelReviewStatus s, ColorScheme cs) {
    switch (s) {
      case PrivateLabelReviewStatus.pending:
        return cs.outline;
      case PrivateLabelReviewStatus.approved:
        return cs.primary;
      case PrivateLabelReviewStatus.priceIssue:
        return cs.tertiary;
      case PrivateLabelReviewStatus.rejected:
        return cs.error;
    }
  }
}
