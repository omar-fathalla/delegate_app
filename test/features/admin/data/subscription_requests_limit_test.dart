import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockStorage extends Mock implements FirebaseStorage {}

/// TAS-260: the pending badge reads a capped page of pending requests for the
/// caller's company only; full lists (no limit) are unchanged.
void main() {
  late FakeFirebaseFirestore db;
  late DelegateSubscriptionRepositoryImpl repo;

  setUp(() async {
    db = FakeFirebaseFirestore();
    repo = DelegateSubscriptionRepositoryImpl(firestore: db, storage: _MockStorage());
    Future<void> add(String id, String status, String company) =>
        db.doc('delegate_requests/$id').set({
          'requestType': 'new_delegate',
          'status': status,
          'organizationUID': 'org-1',
          'companyUID': company,
          'createdAt': DateTime(2026, 11, 23).toIso8601String(),
        });
    for (var i = 0; i < 5; i++) {
      await add('a-pending-$i', 'pending', 'co-a');
    }
    await add('a-approved', 'approved', 'co-a');
    await add('b-pending', 'pending', 'co-b');
  });

  test('limit caps the pending stream and keeps the company filter', () async {
    final list = await repo
        .getSubscriptionRequestsStream(
          statusFilter: SubscriptionRequestStatus.pending,
          companyUID: 'co-a',
          limit: 3,
        )
        .first;
    expect(list, hasLength(3));
    expect(list.every((r) => r.companyUID == 'co-a'), isTrue);
    expect(list.every((r) => r.status == SubscriptionRequestStatus.pending), isTrue);
  });

  test('no limit returns every matching request (list screens unchanged)', () async {
    final pending = await repo
        .getSubscriptionRequestsStream(
          statusFilter: SubscriptionRequestStatus.pending,
          companyUID: 'co-a',
        )
        .first;
    expect(pending, hasLength(5));
    final all = await repo.getSubscriptionRequestsStream(companyUID: 'co-a').first;
    expect(all, hasLength(6));
  });

  test('badge label shows the exact count below the cap and "cap+" at it', () {
    expect(pendingRequestsBadgeLabel(7), '7');
    expect(pendingRequestsBadgeLabel(pendingRequestsBadgeCap - 1), '${pendingRequestsBadgeCap - 1}');
    expect(pendingRequestsBadgeLabel(pendingRequestsBadgeCap), '$pendingRequestsBadgeCap+');
  });
}
