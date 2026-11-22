import 'package:delegate_app/features/hr/data/hr_leave_settings_writer.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-74: the delegate doc is the record; the users copy is best effort.
void main() {
  const delegatePath = 'organizations/org_a/companies/co_1/delegates/d1';
  const payload = {'isAnnualLeaveEnabled': true, 'annualLeaveQuota': 21};

  test('updates the delegate doc and mirrors an existing users doc', () async {
    final db = FakeFirebaseFirestore();
    await db.doc(delegatePath).set({'fullName': 'Fake'});
    await db.doc('users/d1').set({'role': 'delegate'});
    final mirrored = await saveDelegateLeaveSettings(
      firestore: db,
      organizationUID: 'org_a',
      companyUID: 'co_1',
      delegateUid: 'd1',
      payload: payload,
    );
    expect(mirrored, isTrue);
    expect((await db.doc(delegatePath).get()).data()!['annualLeaveQuota'], 21);
    expect((await db.doc('users/d1').get()).data()!['isAnnualLeaveEnabled'], true);
  });

  test('never creates a users doc that does not exist', () async {
    final db = FakeFirebaseFirestore();
    await db.doc(delegatePath).set({'fullName': 'Fake'});
    final mirrored = await saveDelegateLeaveSettings(
      firestore: db,
      organizationUID: 'org_a',
      companyUID: 'co_1',
      delegateUid: 'd1',
      payload: payload,
    );
    expect(mirrored, isFalse);
    expect((await db.doc('users/d1').get()).exists, isFalse);
  });

  test('a missing delegate doc is an error (update never creates a stub)', () async {
    final db = FakeFirebaseFirestore();
    await expectLater(
      saveDelegateLeaveSettings(
        firestore: db,
        organizationUID: 'org_a',
        companyUID: 'co_1',
        delegateUid: 'missing',
        payload: payload,
      ),
      throwsA(anything),
    );
  });
}
