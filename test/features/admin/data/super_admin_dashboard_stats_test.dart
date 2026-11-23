import 'package:delegate_app/features/admin/data/super_admin_dashboard_stats.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

// TAS-89: the dashboard counts moved from realtime listeners to count() /
// one-shot reads. These tests pin the numbers to what the listeners showed.
void main() {
  group('countPendingDelegateRequests', () {
    test('counts only status == pending (same filter as the old listener)',
        () async {
      final fs = FakeFirebaseFirestore();
      final col = fs.collection('delegate_requests');
      await col.add({'status': 'pending'});
      await col.add({'status': 'pending'});
      await col.add({'status': 'approved'});
      await col.add({'status': 'rejected'});
      await col.add({'other': 1});

      final legacy = await col.where('status', isEqualTo: 'pending').get();
      expect(await countPendingDelegateRequests(fs), legacy.docs.length);
      expect(await countPendingDelegateRequests(fs), 2);
    });

    test('returns 0 on an empty collection', () async {
      expect(await countPendingDelegateRequests(FakeFirebaseFirestore()), 0);
    });
  });

  group('loadSuperAdminDelegateStats', () {
    late FakeFirebaseFirestore fs;

    Future<void> addDelegate(String org, String company, String id,
        Map<String, dynamic> data) {
      return fs
          .collection('organizations')
          .doc(org)
          .collection('companies')
          .doc(company)
          .collection('delegates')
          .doc(id)
          .set({'organizationUID': org, ...data});
    }

    setUp(() async {
      fs = FakeFirebaseFirestore();
      await addDelegate('o1', 'c1', 'd1', {
        'isDeductedFromCompany': true,
        'documents': [
          {
            'documentKey': 'electronicPaymentReceipt',
            'documentURL': 'https://x/1',
            'documentStatus': 'approved',
          },
        ],
      });
      await addDelegate('o1', 'c1', 'd2', {
        'documents': [
          {
            'documentKey': 'electronic_receipt',
            'documentURL': 'https://x/2',
            'documentStatus': 'pending',
          },
        ],
      });
      await addDelegate('o1', 'c2', 'd3', {
        'documents': [
          {'documentKey': 'electronicPaymentReceipt', 'documentURL': '  '},
        ],
      });
      await addDelegate('o1', 'c2', 'd4', {
        'documents': [
          {'documentKey': 'nationalIdFront', 'documentURL': 'https://x/4'},
        ],
      });
      await addDelegate('o2', 'c9', 'd5', {
        'isDeductedFromCompany': true,
        'documents': [
          {
            'documentKey': 'electronicPaymentReceipt',
            'documentURL': 'https://x/5',
            'documentStatus': 'approved',
          },
        ],
      });
    });

    test('organization-scoped super admin only counts its organization',
        () async {
      final stats = await loadSuperAdminDelegateStats(fs, 'o1');
      expect(stats.total, 4);
      expect(stats.withImage, 2);
      expect(stats.approved, 1);
      expect(stats.emptyOrMissing, 2);
      expect(stats.deducted, 1);
    });

    test('global super admin counts every delegate', () async {
      final stats = await loadSuperAdminDelegateStats(fs, '');
      expect(stats.total, 5);
      expect(stats.withImage, 3);
      expect(stats.approved, 2);
      expect(stats.emptyOrMissing, 2);
      expect(stats.deducted, 2);
    });

    test('path post-filter drops a doc whose field and path disagree',
        () async {
      // organizationUID field says o1 but the doc lives under o2.
      await fs
          .collection('organizations')
          .doc('o2')
          .collection('companies')
          .doc('c9')
          .collection('delegates')
          .doc('d6')
          .set({'organizationUID': 'o1', 'documents': []});
      final stats = await loadSuperAdminDelegateStats(fs, 'o1');
      expect(stats.total, 4);
    });
  });
}
