// TAS-259: collection transactions are loaded per month in parallel; the
// result (all months, newest first, periodKey fallback) is unchanged.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/data/collection_transactions_loader.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('returns every transaction of every month, newest first', () async {
    final fs = FakeFirebaseFirestore();
    for (final m in ['2026-09', '2026-10', '2026-11']) {
      await fs.collection('monthly_collections').doc(m).set({'x': 1});
    }
    Future<void> tx(String month, String id, DateTime at, num amount,
        {bool withPeriodKey = true}) {
      return fs
          .collection('monthly_collections')
          .doc(month)
          .collection('transactions')
          .doc(id)
          .set({
        if (withPeriodKey) 'periodKey': month,
        'collectedAmount': amount,
        'createdAt': Timestamp.fromDate(at),
      });
    }

    await tx('2026-09', 't1', DateTime(2026, 9, 3), 100);
    await tx('2026-10', 't2', DateTime(2026, 10, 9), 50, withPeriodKey: false);
    await tx('2026-10', 't3', DateTime(2026, 10, 1), 25);
    await tx('2026-11', 't4', DateTime(2026, 11, 20), 10);
    // A wallet transaction must never be counted.
    await fs
        .collection('wallets')
        .doc('w1')
        .collection('transactions')
        .doc('w')
        .set({'collectedAmount': 999});

    final all = await loadAllCollectionTransactions(fs);

    expect(all.map((t) => t['id']), ['t4', 't2', 't3', 't1']);
    expect(all.firstWhere((t) => t['id'] == 't2')['periodKey'], '2026-10');
    final total = all.fold<num>(0, (s, t) => s + (t['collectedAmount'] as num));
    expect(total, 185);
  });

  test('no months means no transactions', () async {
    expect(await loadAllCollectionTransactions(FakeFirebaseFirestore()), isEmpty);
  });
}
