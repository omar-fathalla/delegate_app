import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/data/chain_duplicate_lookup.dart';

void main() {
  test(
    'flags a chain that already has the national id, and a pending request',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('organizations/o1/companies/c1/delegates/d1').set({
        'uid': 'd1',
        'nationalId': '20000000000001',
        'companyUID': 'c1',
      });
      await db.doc('delegate_requests/r2').set({
        'status': 'pending',
        'companyUID': 'c1',
        'phoneNumber': '01000000911',
        'organizationUID': 'o2',
        'organizationUIDs': ['o2', 'o3'],
      });

      final found = await findDuplicateChainUids(
        firestore: db,
        companyUID: 'c1',
        nationalId: '20000000000001',
        phoneNumber: '01000000911',
        organizationUIDs: ['o1', 'o2', 'o3', 'o4'],
      );
      expect(found, {'o1', 'o2', 'o3'});

      final lookup = await lookupDuplicateChains(
        firestore: db,
        companyUID: 'c1',
        nationalId: '20000000000001',
        phoneNumber: '01000000911',
        organizationUIDs: ['o1', 'o2', 'o3', 'o4'],
      );
      expect(lookup.duplicateOrgUids, {'o1', 'o2', 'o3'});
      expect(lookup.existingDelegateUid, 'd1');
      expect(lookup.existingDelegateOrganizationUID, 'o1');
    },
  );

  test(
    'phone match with a different national ID is refused and not attached',
    () async {
      final db = FakeFirebaseFirestore();
      await db.doc('organizations/o1/companies/c1/delegates/perf177').set({
        'uid': 'perf177',
        'nationalId': '20000000000177',
        'phoneNumber': '01500000177',
        'companyUID': 'c1',
      });

      expect(
        () => lookupDuplicateChains(
          firestore: db,
          companyUID: 'c1',
          nationalId: '29901010101772',
          phoneNumber: '01500000177',
          organizationUIDs: ['o1', 'o2'],
        ),
        throwsA(
          isA<DuplicateChainLookupException>().having(
            (e) => e.message,
            'message',
            contains('رقم الهاتف مسجّل لمندوب برقم قومي مختلف'),
          ),
        ),
      );

      final same = await lookupDuplicateChains(
        firestore: db,
        companyUID: 'c1',
        nationalId: '20000000000177',
        phoneNumber: '01500000177',
        organizationUIDs: ['o1'],
      );
      expect(same.existingDelegateUid, 'perf177');
      expect(same.duplicateOrgUids, {'o1'});
    },
  );
}
