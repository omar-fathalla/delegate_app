import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/data/chain_duplicate_lookup.dart';

void main() {
  test('flags a chain that already has the national id, and a pending request', () async {
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
  });
}
