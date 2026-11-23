import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

/// TAS-254: requests on the base (free) chain are reviewed by super admins
/// only. The base chain's org admin (org filter, no company filter) gets an
/// empty list instead of a denied query; other chains are unchanged.
void main() {
  late FakeFirebaseFirestore db;
  late DelegateSubscriptionRepositoryImpl repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    await db.doc('config/subscriptions').set({'freeChainOrgUids': ['base']});
    for (final (id, org) in [('r1', 'base'), ('r2', 'paid')]) {
      await db.doc('delegate_requests/$id').set({
        'requestType': 'new_delegate', 'status': 'pending', 'organizationUID': org,
        'companyUID': 'co-a', 'createdAt': DateTime(2026, 11, 23).toIso8601String(),
      });
    }
  });

  test('base chain org admin sees no requests', () async {
    final list = await repo.getSubscriptionRequestsStream(organizationUID: 'base').first;
    expect(list, isEmpty);
  });

  test('another chain org admin sees its own requests', () async {
    final list = await repo.getSubscriptionRequestsStream(organizationUID: 'paid').first;
    expect(list.map((r) => r.id), ['r2']);
  });

  test('company filter (supervisor of the requesting company) still lists the base-chain request', () async {
    final list = await repo
        .getSubscriptionRequestsStream(organizationUID: 'base', companyUID: 'co-a')
        .first;
    expect(list.map((r) => r.id), ['r1']);
  });

  test('super admin (no filter) sees both', () async {
    final list = await repo.getSubscriptionRequestsStream().first;
    expect(list.map((r) => r.id).toSet(), {'r1', 'r2'});
  });
}
