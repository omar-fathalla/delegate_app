// TAS-232: a delegate's `position` is only ever `Promoter` or `Supervisor`.
// Chain names live in organizationName / allOrganizationNames, never in
// `position`. Pure function, no Firebase.
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';

void main() {
  group('formatSmartPosition (TAS-232)', () {
    String fmt(
      List<String> orgs, {
      String? current,
      String? origin,
      String? base,
    }) =>
        base == null
            ? DelegateSubscriptionRepositoryImpl.formatSmartPosition(
                allOrgs: orgs,
                currentOrgName: current,
                originOrgName: origin,
              )
            : DelegateSubscriptionRepositoryImpl.formatSmartPosition(
                allOrgs: orgs,
                currentOrgName: current,
                originOrgName: origin,
                basePosition: base,
              );

    test('no chains: Promoter', () {
      expect(fmt(const []), 'Promoter');
    });

    test('one other chain: no chain name in position', () {
      expect(fmt(const ['سلسلة أ'], current: 'سلسلة ب'), 'Promoter');
    });

    test('two chains: no chain name in position', () {
      expect(
        fmt(const ['سلسلة أ', 'سلسلة ب'], current: 'سلسلة أ'),
        'Promoter',
      );
    });

    test('many chains: Promoter, not "Promoter (X + N سلاسل)"', () {
      final orgs = [
        'جملة ماركت',
        for (var i = 1; i <= 9; i++) 'سلسلة $i',
      ];
      expect(fmt(orgs, current: 'سلسلة 1', origin: 'جملة ماركت'), 'Promoter');
      expect(
        fmt(orgs, current: 'جملة ماركت', origin: 'جملة ماركت'),
        'Promoter',
      );
    });

    test('Supervisor stays Supervisor', () {
      expect(
        fmt(const ['سلسلة أ', 'سلسلة ب', 'سلسلة ج'], base: 'Supervisor'),
        'Supervisor',
      );
    });

    test('strips a legacy chain suffix from the base', () {
      expect(
        fmt(const ['سلسلة أ'], base: 'Promoter (جملة ماركت + 9 سلاسل)'),
        'Promoter',
      );
      expect(
        fmt(const [], base: 'Supervisor (مشترك - 3 سلاسل)'),
        'Supervisor',
      );
      expect(fmt(const [], base: '  Promoter (سلسلة أ، سلسلة ب) '), 'Promoter');
    });

    test('empty base falls back to Promoter', () {
      expect(fmt(const [], base: ''), 'Promoter');
      expect(fmt(const [], base: ' (سلسلة أ)'), 'Promoter');
    });
  });
}
