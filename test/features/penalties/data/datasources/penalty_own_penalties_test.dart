import 'package:delegate_app/features/penalties/data/datasources/penalty_remote_data_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

void main() {
  late FakeFirebaseFirestore firestore;
  late PenaltyRemoteDataSourceImpl dataSource;

  Future<void> seed(String id, String companyId, String target) =>
      firestore.collection('penalties').doc(id).set({
        'companyId': companyId,
        'companyName': 'Fake $companyId',
        'createdById': 'seed-fake-supervisor',
        'createdByName': 'مشرف وهمي',
        'title': 'تأخير',
        'category': 'attendance',
        'incidentDescription': 'وهمي',
        'fineAmount': 50,
        'status': 'issued',
        'targetDelegateId': target,
        'createdAt': DateTime(2026, 11, 1).toIso8601String(),
        'updatedAt': DateTime(2026, 11, 1).toIso8601String(),
      });

  setUp(() async {
    firestore = FakeFirebaseFirestore();
    dataSource = PenaltyRemoteDataSourceImpl(
      firestore: firestore,
      storage: _MockStorage(),
    );
    await seed('own-uid', 'seed-fake-co-alpha', 'seed-fake-hr-006');
    await seed('own-phone', 'seed-fake-co-alpha', '01000000006');
    await seed('other-hr', 'seed-fake-co-alpha', 'seed-fake-hr-004');
    await seed('delegate', 'seed-fake-co-alpha', 'seed-fake-delegate-1');
    await seed('other-company', 'seed-fake-co-beta', 'seed-fake-hr-006');
  });

  test('returns only penalties issued to the user, by uid or phone', () async {
    final list = await dataSource.getOwnPenalties(
      uid: 'seed-fake-hr-006',
      companyId: 'seed-fake-co-alpha',
      phoneNumber: '01000000006',
    );
    expect(list.map((p) => p.penaltyId).toSet(), {'own-uid', 'own-phone'});
  });

  test('never returns another company even for the same uid', () async {
    final list = await dataSource.getOwnPenalties(
      uid: 'seed-fake-hr-006',
      companyId: 'seed-fake-co-alpha',
    );
    expect(list.map((p) => p.penaltyId), ['own-uid']);
    expect(list.every((p) => p.companyId == 'seed-fake-co-alpha'), isTrue);
  });

  test('an account without a company gets nothing and no query', () async {
    final list = await dataSource.getOwnPenalties(
      uid: 'seed-fake-hr-006',
      companyId: '',
      phoneNumber: '01000000006',
    );
    expect(list, isEmpty);
  });
}
