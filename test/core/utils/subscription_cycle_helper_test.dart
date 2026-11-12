import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SubscriptionCycleHelper', () {
    setUp(SubscriptionCycleHelper.resetConfigForTest);
    tearDown(SubscriptionCycleHelper.resetConfigForTest);

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
      expect(
        SubscriptionCycleHelper.isSubscriptionExpired(futureDate),
        isFalse,
      );
      expect(SubscriptionCycleHelper.isSubscriptionExpired(null), isFalse);
    });

    test('daysRemaining calculates days properly', () {
      final futureDate = DateTime.now().add(const Duration(days: 10, hours: 2));
      final pastDate = DateTime.now().subtract(const Duration(days: 2));

      expect(
        SubscriptionCycleHelper.daysRemaining(futureDate),
        inInclusiveRange(9, 11),
      );
      expect(SubscriptionCycleHelper.daysRemaining(pastDate), equals(0));
      expect(SubscriptionCycleHelper.daysRemaining(null), equals(0));
    });

    test(
      'getRemainingMonthsInCycle calculates remaining months properly in H1 and H2',
      () {
        // H1 (Jan to Jun)
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 1, 15),
          ),
          equals(6),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 2, 10),
          ),
          equals(5),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 3, 20),
          ),
          equals(4),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 4, 5),
          ),
          equals(3),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 5, 25),
          ),
          equals(2),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 6, 30),
          ),
          equals(1),
        );

        // H2 (Jul to Dec)
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 7, 1),
          ),
          equals(6),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 8, 14),
          ),
          equals(5),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 9, 15),
          ),
          equals(4),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 10, 22),
          ),
          equals(3),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 11, 8),
          ),
          equals(2),
        );
        expect(
          SubscriptionCycleHelper.getRemainingMonthsInCycle(
            DateTime(2026, 12, 31),
          ),
          equals(1),
        );
      },
    );

    test(
      'isFreePromotionActive correctly identifies promotion window until 31/12/2026',
      () {
        expect(
          SubscriptionCycleHelper.isFreePromotionActive(DateTime(2026, 10, 8)),
          isTrue,
        );
        expect(
          SubscriptionCycleHelper.isFreePromotionActive(
            DateTime(2026, 12, 31, 23, 59, 59),
          ),
          isTrue,
        );
        expect(
          SubscriptionCycleHelper.isFreePromotionActive(
            DateTime(2027, 1, 1, 0, 0, 1),
          ),
          isFalse,
        );
        // 31 Dec 2026 21:59:59 UTC is still 23:59:59 Cairo (UTC+2).
        expect(
          SubscriptionCycleHelper.isFreePromotionActive(
            DateTime.utc(2026, 12, 31, 21, 59, 59),
          ),
          isTrue,
        );
        // 31 Dec 2026 22:00:00 UTC is 1 Jan 2027 00:00 Cairo — promo ended.
        expect(
          SubscriptionCycleHelper.isFreePromotionActive(
            DateTime.utc(2026, 12, 31, 22),
          ),
          isFalse,
        );
      },
    );

    test('nowOverride is used when the date argument is omitted', () {
      SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2026, 12, 31, 21, 59, 59);
      expect(SubscriptionCycleHelper.isFreePromotionActive(), isTrue);
      SubscriptionCycleHelper.nowOverride = () => DateTime.utc(2026, 12, 31, 22);
      expect(SubscriptionCycleHelper.isFreePromotionActive(), isFalse);
    });

    test('applyConfig moves the last free Cairo day', () {
      SubscriptionCycleHelper.applyConfig(freePromotionLastDay: '2026-11-30');
      expect(
        SubscriptionCycleHelper.isFreePromotionActive(DateTime(2026, 11, 30, 23, 59, 59)),
        isTrue,
      );
      expect(
        SubscriptionCycleHelper.isFreePromotionActive(DateTime(2026, 12, 1)),
        isFalse,
      );
      SubscriptionCycleHelper.applyConfig(freePromotionLastDay: 'not-a-date');
      expect(SubscriptionCycleHelper.freePromotionLastDayIso, '2026-12-31');
    });

    test('getCycleShortTitleArabic is sentence-safe', () {
      expect(
        SubscriptionCycleHelper.getCycleShortTitleArabic(DateTime(2027, 1, 1)),
        'النصف الأول 2027',
      );
      expect(
        SubscriptionCycleHelper.getCycleShortTitleArabic(DateTime(2027, 7, 1)),
        'النصف الثاني 2027',
      );
      expect(
        SubscriptionCycleHelper.getCycleShortTitleArabicForCode('2027_H1'),
        'النصف الأول 2027',
      );
      expect(
        SubscriptionCycleHelper.getCycleTitleArabic(DateTime(2027, 1, 1)),
        contains('•'),
      );
    });

    test('dev free-period bypass is impossible when isDev is false', () {
      const company = SubscriptionCycleHelper.devPaidRenewalCompanyUID;
      expect(
        SubscriptionCycleHelper.devFreePeriodBypass(
          isDev: false,
          companyUID: company,
        ),
        isFalse,
      );
      expect(
        SubscriptionCycleHelper.devFreePeriodBypass(
          isDev: true,
          companyUID: company,
        ),
        isTrue,
      );
      expect(
        SubscriptionCycleHelper.devFreePeriodBypass(
          isDev: true,
          companyUID: 'co_other',
        ),
        isFalse,
      );
      expect(
        SubscriptionCycleHelper.devFreePeriodBypass(
          isDev: true,
          companyUID: '',
        ),
        isFalse,
      );
      // Widget/unit tests run without ENV=dev, so the live helper stays free in 2026
      // even when the test company id is passed.
      expect(
        SubscriptionCycleHelper.isFreePromotionActive(
          DateTime(2026, 6, 15),
          company,
        ),
        isTrue,
      );
    });

    test('getFeeForMonths is 500 x months / 6 rounded to 2 decimals', () {
      expect(SubscriptionCycleHelper.getFeeForMonths(6), equals(500.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(5), equals(416.67));
      expect(SubscriptionCycleHelper.getFeeForMonths(4), equals(333.33));
      expect(SubscriptionCycleHelper.getFeeForMonths(3), equals(250.0));
      expect(SubscriptionCycleHelper.getFeeForMonths(2), equals(166.67));
      expect(SubscriptionCycleHelper.getFeeForMonths(1), equals(83.33));
    });

    test('fee for every month of both halves of 2027', () {
      const expected = [500.0, 416.67, 333.33, 250.0, 166.67, 83.33];
      for (var m = 1; m <= 12; m++) {
        final first = DateTime(2027, m, 1);
        final last = DateTime(2027, m + 1, 0, 23, 59);
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(first),
          expected[(m - 1) % 6],
          reason: 'month $m day 1',
        );
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(last),
          expected[(m - 1) % 6],
          reason: 'month $m last day',
        );
      }
    });

    test('roundMoney and totals for a multi-delegate renewal', () {
      expect(SubscriptionCycleHelper.roundMoney(416.666666), 416.67);
      expect(SubscriptionCycleHelper.roundMoney(1.005), 1.01);
      expect(
        SubscriptionCycleHelper.totalFor(3, DateTime(2027, 2, 10)),
        1250.01,
      );
      expect(
        SubscriptionCycleHelper.totalFor(2, DateTime(2027, 2, 10)),
        833.34,
      );
      expect(SubscriptionCycleHelper.totalFor(0, DateTime(2027, 2, 10)), 0.0);
      expect(SubscriptionCycleHelper.totalFor(5, DateTime(2026, 11, 10)), 0.0);
      expect(SubscriptionCycleHelper.formatEgp(500), '500');
      expect(SubscriptionCycleHelper.formatEgp(416.67), '416.67');
      // Same half-up rule as functions/src/subscription_logic.ts: 2 months
      // is 166.67, and two delegates must be 333.34 (not 333.33).
      expect(SubscriptionCycleHelper.getFeeForMonths(2), 166.67);
      expect(
        SubscriptionCycleHelper.totalFor(2, DateTime(2027, 5, 10)),
        333.34,
      );
    });

    test('free promotion boundary on 2026-12-31 in Cairo time', () {
      // 21:59:59Z on 31 Dec = 23:59:59 Cairo (UTC+2) -> still free.
      expect(
        SubscriptionCycleHelper.getProratedSubscriptionFee(
          DateTime.utc(2026, 12, 31, 21, 59, 59),
        ),
        0.0,
      );
      // 22:00Z on 31 Dec = 00:00 on 1 Jan 2027 Cairo -> paid, full period.
      expect(
        SubscriptionCycleHelper.getProratedSubscriptionFee(
          DateTime.utc(2026, 12, 31, 22),
        ),
        500.0,
      );
      expect(
        SubscriptionCycleHelper.getCycleCode(DateTime.utc(2026, 12, 31, 22)),
        '2027_H1',
      );
      for (var m = 1; m <= 12; m++) {
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(
            DateTime(2026, m, 15),
          ),
          0.0,
        );
      }
    });

    test('period boundaries in Cairo time (summer time on 1 July)', () {
      // Cairo is UTC+3 on 1 July: 21:00Z on 30 June is already H2.
      expect(
        SubscriptionCycleHelper.cairoUtcOffset(DateTime.utc(2027, 6, 30, 12)),
        const Duration(hours: 3),
      );
      expect(
        SubscriptionCycleHelper.getCycleCode(
          DateTime.utc(2027, 6, 30, 20, 59, 59),
        ),
        '2027_H1',
      );
      expect(
        SubscriptionCycleHelper.getCycleCode(DateTime.utc(2027, 6, 30, 21)),
        '2027_H2',
      );
      // Winter: UTC+2.
      expect(
        SubscriptionCycleHelper.cairoUtcOffset(DateTime.utc(2027, 1, 1)),
        const Duration(hours: 2),
      );
      expect(
        SubscriptionCycleHelper.periodStartDay(DateTime(2027, 3, 3)),
        '2027-01-01',
      );
      expect(
        SubscriptionCycleHelper.periodEndDay(DateTime(2027, 3, 3)),
        '2027-06-30',
      );
      expect(
        SubscriptionCycleHelper.periodEndDay(DateTime(2027, 9, 3)),
        '2027-12-31',
      );
    });

    test(
      'getProratedSubscriptionFee returns 0.0 during the 2026 promotion, prorated after',
      () {
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(
            DateTime(2026, 10, 8),
          ),
          equals(0.0),
        );
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(
            DateTime(2026, 12, 31),
          ),
          equals(0.0),
        );
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(
            DateTime(2027, 1, 1),
          ),
          equals(500.0),
        );
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(
            DateTime(2027, 3, 1),
          ),
          equals(333.33),
        );
        expect(
          SubscriptionCycleHelper.getProratedSubscriptionFee(
            DateTime(2027, 4, 1),
          ),
          equals(250.0),
        );
      },
    );

    test(
      'hasPaidCoverage requires a paid or waived current-period subscription',
      () {
        final at = DateTime(2027, 2, 10);
        expect(
          SubscriptionCycleHelper.hasPaidCoverage({
            'paymentStatus': 'paid',
            'periodCode': '2027_H1',
          }, at: at),
          isTrue,
        );
        expect(
          SubscriptionCycleHelper.hasPaidCoverage({
            'paymentStatus': 'paid',
            'periodCode': '2026_H2',
          }, at: at),
          isFalse,
        );
        expect(
          SubscriptionCycleHelper.hasPaidCoverage({
            'paymentStatus': 'pending',
            'periodCode': '2027_H1',
          }, at: at),
          isFalse,
        );
        expect(SubscriptionCycleHelper.hasPaidCoverage(null, at: at), isFalse);
        expect(
          SubscriptionCycleHelper.hasPaidCoverage(
            {'paymentStatus': 'waived', 'periodCode': '2026_H2'},
            at: DateTime(2026, 8, 1),
            companyUID: 'other',
          ),
          isTrue,
        );
        // A prepaid next period must not count as current coverage.
        expect(
          SubscriptionCycleHelper.hasPaidCoverage(
            {'paymentStatus': 'paid', 'periodCode': '2026_H2'},
            at: DateTime(2026, 11, 11),
            nextSubscription: {
              'paymentStatus': 'paid',
              'periodCode': '2027_H1',
            },
          ),
          isTrue,
        );
        expect(
          SubscriptionCycleHelper.hasPaidCoverage({
            'paymentStatus': 'paid',
            'periodCode': '2026_H2',
          }, at: DateTime(2026, 11, 11)),
          isTrue,
        );
        expect(
          SubscriptionCycleHelper.hasPaidCoverage({
            'paymentStatus': 'paid',
            'periodCode': '2027_H1',
          }, at: DateTime(2026, 11, 11)),
          isFalse,
        );
        expect(
          SubscriptionCycleHelper.hasPaidCoverage(
            {'paymentStatus': 'paid', 'periodCode': '2026_H2'},
            at: DateTime(2027, 1, 2),
            nextSubscription: {
              'paymentStatus': 'paid',
              'periodCode': '2027_H1',
            },
          ),
          isTrue,
        );
      },
    );

    test('nextCycleCode walks H1 to H2 and H2 to the next year', () {
      expect(
        SubscriptionCycleHelper.nextCycleCode(DateTime(2026, 11, 11)),
        '2027_H1',
      );
      expect(
        SubscriptionCycleHelper.nextCycleCode(DateTime(2027, 3, 1)),
        '2027_H2',
      );
      expect(SubscriptionCycleHelper.nextCycleCode(null, '2026_H2'), '2027_H1');
    });

    test('advance window is closed when the flag is off', () {
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2026, 12, 15),
          enabled: false,
          days: 30,
        ),
        isFalse,
      );
      expect(
        SubscriptionCycleHelper.payableCycleCode(
          DateTime(2026, 12, 15),
          enabled: false,
          days: 30,
        ),
        '2026_H2',
      );
    });

    test('30-day window opens on 2 Dec and closes at the period end', () {
      expect(
        SubscriptionCycleHelper.advanceWindowOpensAt(
          DateTime(2026, 11, 11),
          days: 30,
        ),
        DateTime(2026, 12, 2),
      );
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2026, 12, 1),
          enabled: true,
          days: 30,
        ),
        isFalse,
      );
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2026, 12, 2),
          enabled: true,
          days: 30,
        ),
        isTrue,
      );
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2026, 12, 31, 23, 59, 59),
          enabled: true,
          days: 30,
        ),
        isTrue,
      );
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2027, 1, 1),
          enabled: true,
          days: 30,
        ),
        isFalse,
      );
    });

    test('60-day tashil-dev window is already open in mid-November 2026', () {
      expect(
        SubscriptionCycleHelper.advanceWindowOpensAt(
          DateTime(2026, 11, 11),
          days: 60,
        ),
        DateTime(2026, 11, 2),
      );
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2026, 11, 11),
          enabled: true,
          days: 60,
        ),
        isTrue,
      );
      expect(
        SubscriptionCycleHelper.payableCycleCode(
          DateTime(2026, 11, 11),
          enabled: true,
          days: 60,
        ),
        '2027_H1',
      );
      // February is not in the last 60 days of H1 (window opens ~3 May).
      expect(
        SubscriptionCycleHelper.isAdvanceRenewalOpen(
          DateTime(2027, 2, 10),
          enabled: true,
          days: 60,
        ),
        isFalse,
      );
    });

    test(
      'a future period is quoted at its start, not zeroed by today\'s free promotion',
      () {
        expect(
          SubscriptionCycleHelper.getFeeForPeriod(
            '2027_H1',
            DateTime(2026, 12, 15),
          ),
          500.0,
        );
        expect(
          SubscriptionCycleHelper.getFeeForPeriod(
            '2026_H2',
            DateTime(2026, 12, 15),
          ),
          0.0,
        );
        expect(
          SubscriptionCycleHelper.getFeeForPeriod(
            '2027_H1',
            DateTime(2027, 3, 1),
          ),
          333.33,
        );
      },
    );
  });
}
