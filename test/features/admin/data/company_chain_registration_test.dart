import 'package:delegate_app/features/admin/data/company_chain_registration.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('ensureCompanyInChains is idempotent and never overwrites', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('organizations/o1').set({'name': 'A', 'code': 'A1'});
    await db.doc('organizations/o2').set({'name': 'B', 'code': 'B1'});
    await db.doc('organizations/o1/companies/c1').set({'name': 'C', 'companyCodeInOrg': '7', 'status': 'Pending'});
    Future<List<String>> run() => ensureCompanyInChains(
          firestore: db,
          companyUID: 'c1',
          companyName: 'C',
          chains: const {'o1': 'A', 'o2': 'B'},
          supervisorUid: 'sup',
          supervisorName: 'S',
          supervisorPhone: '01000000000',
        );
    expect(await run(), ['o2']);
    final first = (await db.doc('organizations/o2/companies/c1').get()).data()!;
    expect(first['status'], 'active'); // template was Pending -> active
    expect(first['companyCodeInOrg'], '7');
    await db.doc('organizations/o2/companies/c1').update({'delegatesCount': 3});
    expect(await run(), isEmpty);
    expect((await db.doc('organizations/o2/companies/c1').get()).data()!['delegatesCount'], 3);
    expect((await db.doc('organizations/o1/companies/c1').get()).data()!['status'], 'Pending');
    expect((await db.doc('organizations/o1/companies/c1/admins/sup').get()).exists, isTrue);
  });

  test('no template: minimal record with code pending', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('organizations/o2').set({'name': 'B', 'code': 'B1'});
    await ensureCompanyInChains(
      firestore: db,
      companyUID: 'c9',
      companyName: 'New Co',
      chains: const {'o2': 'B'},
      supervisorUid: '',
      supervisorName: '',
      supervisorPhone: '',
    );
    final d = (await db.doc('organizations/o2/companies/c9').get()).data()!;
    expect(d['name'], 'New Co');
    expect(d['companyCodeInOrgPending'], isTrue);
    expect(d['organizationCode'], 'B1');
  });

  test('firstInvalidRequestChain: missing chain and unregistered hidden chain', () async {
    final db = FakeFirebaseFirestore();
    await db.doc('organizations/o1').set({'name': 'كارفور'});
    await db.doc('organizations/of').set({'name': 'fathalla market'});
    expect(await firstInvalidRequestChain(firestore: db, companyUID: 'c1', orgIds: ['o1']), isNull);
    expect(await firstInvalidRequestChain(firestore: db, companyUID: 'c1', orgIds: ['o1', 'gone']), 'gone');
    expect(await firstInvalidRequestChain(firestore: db, companyUID: 'c1', orgIds: ['of']), 'of');
    await db.doc('organizations/of/companies/c1').set({'name': 'C'});
    expect(await firstInvalidRequestChain(firestore: db, companyUID: 'c1', orgIds: ['of']), isNull);
  });

  test('approvalStampBlocks only on a real failure', () {
    expect(approvalStampBlocks(null), isFalse);
    expect(approvalStampBlocks({'orgCompanyCheck': 'ok'}), isFalse);
    expect(approvalStampBlocks({'orgCompanyCheck': 'failed', 'orgCompanyCheckReason': 'org_not_in_company'}), isFalse);
    expect(approvalStampBlocks({'orgCompanyCheck': 'failed', 'orgCompanyCheckReason': 'chain_not_available'}), isTrue);
    expect(approvalStampBlocks({'orgCompanyCheck': 'failed'}), isTrue);
  });
}
