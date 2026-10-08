import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionCycleHelper', () {
    test('getCycleCode returns correct H1 and H2 codes', () {
      final h1Date = DateTime(2026, 3, 15);
      final h2Date = DateTime(2026, 8, 20);

      expect(SubscriptionCycleHelper.getCycleCode(h1Date), equals('2026_H1'));
      expect(SubscriptionCycleHelper.getCycleCode(h2Date), equals('2026_H2'));
    });

    test('getCycleTitleArabic contains expected cycle information', () {
      final h1Date = DateTime(2026, 2, 1);
      final h2Date = DateTime(2026, 10, 1);

      final h1Title = SubscriptionCycleHelper.getCycleTitleArabic(h1Date);
      final h2Title = SubscriptionCycleHelper.getCycleTitleArabic(h2Date);

      expect(h1Title, contains('دورة النصف الأول (2026)'));
      expect(h1Title, contains('1 يناير حتى 30 يونيو'));

      expect(h2Title, contains('دورة النصف الثاني (2026)'));
      expect(h2Title, contains('1 يوليو حتى 31 ديسمبر'));
    });

    test('getCycleStartDate returns Jan 1 for H1 and Jul 1 for H2', () {
      final h1Date = DateTime(2026, 4, 10);
      final h2Date = DateTime(2026, 11, 5);

      final h1Start = SubscriptionCycleHelper.getCycleStartDate(h1Date);
      final h2Start = SubscriptionCycleHelper.getCycleStartDate(h2Date);

      expect(h1Start, equals(DateTime(2026, 1, 1)));
      expect(h2Start, equals(DateTime(2026, 7, 1)));
    });

    test('getCycleEndDate returns Jun 30 for H1 and Dec 31 for H2', () {
      final h1Date = DateTime(2026, 4, 10);
      final h2Date = DateTime(2026, 11, 5);

      final h1End = SubscriptionCycleHelper.getCycleEndDate(h1Date);
      final h2End = SubscriptionCycleHelper.getCycleEndDate(h2Date);

      expect(h1End.year, equals(2026));
      expect(h1End.month, equals(6));
      expect(h1End.day, equals(30));

      expect(h2End.year, equals(2026));
      expect(h2End.month, equals(12));
      expect(h2End.day, equals(31));
    });

    test('isSubscriptionExpired calculates expiration correctly', () {
      final pastDate = DateTime.now().subtract(const Duration(days: 5));
      final futureDate = DateTime.now().add(const Duration(days: 5));

      expect(SubscriptionCycleHelper.isSubscriptionExpired(pastDate), isTrue);
      expect(SubscriptionCycleHelper.isSubscriptionExpired(futureDate), isFalse);
      expect(SubscriptionCycleHelper.isSubscriptionExpired(null), isFalse);
    });

    test('daysRemaining calculates days properly', () {
      final futureDate = DateTime.now().add(const Duration(days: 10, hours: 2));
      final pastDate = DateTime.now().subtract(const Duration(days: 2));

      expect(SubscriptionCycleHelper.daysRemaining(futureDate), inInclusiveRange(9, 11));
      expect(SubscriptionCycleHelper.daysRemaining(pastDate), equals(0));
      expect(SubscriptionCycleHelper.daysRemaining(null), equals(0));
    });

    test('getRemainingMonthsInCycle calculates remaining months properly in H1 and H2', () {
      // H1 (Jan to Jun)
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 1, 15)), equals(6));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 2, 10)), equals(5));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 3, 20)), equals(4));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 4, 5)), equals(3));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 5, 25)), equals(2));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 6, 30)), equals(1));

      // H2 (Jul to Dec)
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 7, 1)), equals(6));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 8, 14)), equals(5));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 9, 15)), equals(4));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 10, 22)), equals(3));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 11, 8)), equals(2));
      expect(SubscriptionCycleHelper.getRemainingMonthsInCycle(DateTime(2026, 12, 31)), equals(1));
    });

    test('isFreePromotionActive correctly identifies promotion window until 31/12/2026', () {
      expect(SubscriptionCycleHelper.isFreePromotionActive(DateTime(2026, 10, 8)), isTrue);
      expect(SubscriptionCycleHelper.isFreePromotionActive(DateTime(2026, 12, 31, 23, 59, 59)), isTrue);
      expect(SubscriptionCycleHelper.isFreePromotionActive(DateTime(2027, 1, 1, 0, 0, 1)), isFalse);
    });

    test('getFeeForMonths returns correct rounded fee per user tiers', () {
      expect(SubscriptionCycleHelper.getFeeForMonths(6), equals(500.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(5), equals(450.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(4), equals(350.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(3), equals(250.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(2), equals(200.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(1), equals(100.0));
    });

    test('getProratedSubscriptionFee returns 0.0 during active free promotion in 2026', () {
      // Free during active promotion in 2026
      expect(SubscriptionCycleHelper.getProratedSubscriptionFee(DateTime(2026, 10, 8)), equals(0.0));
      expect(SubscriptionCycleHelper.getProratedSubscriptionFee(DateTime(2026, 12, 1)), equals(0.0));
      expect(SubscriptionCycleHelper.getProratedSubscriptionFee(DateTime(2026, 12, 31)), equals(0.0));

      // Post promotion in 2027 (standard tiers)
      expect(SubscriptionCycleHelper.getProratedSubscriptionFee(DateTime(2027, 1, 1)), equals(500.0));
      expect(SubscriptionCycleHelper.getProratedSubscriptionFee(DateTime(2027, 3, 1)), equals(350.0));
      expect(SubscriptionCycleHelper.getProratedSubscriptionFee(DateTime(2027, 4, 1)), equals(250.0));
    });
  });
}
