import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('rejection never creates a stub (7 Nov prod stubs)', () {
    test('missing pending doc stays missing', () async {
      final fs = FakeFirebaseFirestore();
      final updated = await markRejectedDelegateDocIfExists(
        firestore: fs, organizationUID: 'o1', companyUID: 'c1', docId: 'r1', reason: 'تعديل الصورة',
      );
      expect(updated, isFalse);
      final d = await fs.doc('organizations/o1/companies/c1/delegates/r1').get();
      expect(d.exists, isFalse);
    });

    test('existing pending doc is marked rejected, other fields kept', () async {
      final fs = FakeFirebaseFirestore();
      await fs.doc('organizations/o1/companies/c1/delegates/r1').set({'status': 'pending', 'firstName': 'أ'});
      final updated = await markRejectedDelegateDocIfExists(
        firestore: fs, organizationUID: 'o1', companyUID: 'c1', docId: 'r1', reason: 'تعديل الصورة',
      );
      expect(updated, isTrue);
      final d = (await fs.doc('organizations/o1/companies/c1/delegates/r1').get()).data()!;
      expect(d['status'], 'rejected');
      expect(d['firstName'], 'أ');
    });

    test('empty company: nothing written', () async {
      final fs = FakeFirebaseFirestore();
      expect(
        await markRejectedDelegateDocIfExists(
          firestore: fs, organizationUID: 'o1', companyUID: '', docId: 'r1', reason: 'x'),
        isFalse,
      );
    });
  });

  group('delete_delegate targets', () {
    Future<FakeFirebaseFirestore> seed() async {
      final fs = FakeFirebaseFirestore();
      for (final o in ['o1', 'o2', 'o3']) {
        await fs.doc('organizations/$o').set({'name': o});
        await fs.doc('organizations/$o/companies/smotchi').set({'name': 'smotchi'});
        await fs.doc('organizations/$o/companies/other').set({'name': 'other'});
      }
      return fs;
    }

    test('empty companyUID: found through the chain companies (stub case)', () async {
      final fs = await seed();
      await fs.doc('organizations/o1/companies/smotchi/delegates/u1').set({'status': 'rejected'});
      final t = await resolveDelegateDeleteTargets(
        firestore: fs, delegateUid: 'u1', companyUID: '', organizationUID: 'o1');
      expect(t.map((r) => r.path), ['organizations/o1/companies/smotchi/delegates/u1']);
    });

    test('empty companyUID: users/{uid}.companyUID, all chain copies', () async {
      final fs = await seed();
      await fs.doc('users/u2').set({'companyUID': 'smotchi', 'role': 'delegate'});
      await fs.doc('organizations/o1/companies/smotchi/delegates/u2').set({'uid': 'u2'});
      await fs.doc('organizations/o3/companies/smotchi/delegates/u2').set({'uid': 'u2'});
      final t = await resolveDelegateDeleteTargets(
        firestore: fs, delegateUid: 'u2', companyUID: '', organizationUID: '');
      expect(t.map((r) => r.path).toSet(), {
        'organizations/o1/companies/smotchi/delegates/u2',
        'organizations/o3/companies/smotchi/delegates/u2',
      });
    });

    test('nothing found: empty list (caller fails visibly, request not approved)', () async {
      final fs = await seed();
      final t = await resolveDelegateDeleteTargets(
        firestore: fs, delegateUid: 'ghost', companyUID: '', organizationUID: 'o1');
      expect(t, isEmpty);
      expect(kDeleteDelegateNotFoundMessage, contains('لم تتم الموافقة'));
    });
  });
}
