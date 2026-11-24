// Staff read the 'all' broadcast (delegates do not query it).
// TAS-51: a shared (broadcast) notification is read and hidden per user
// through readBy / deletedBy with the caller's own ids only. The doc-wide
// isRead flag would mark it for everyone.
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  late FakeFirebaseFirestore db;
  late NotificationRemoteDataSourceImpl ds;

  Map<String, dynamic> broadcast({List<String>? readBy, List<String>? deletedBy}) => {
        'delegateUid': 'all',
        'title': 'Fake broadcast',
        'body': 'b',
        'type': 'announcement',
        'isRead': false,
        'createdAt': Timestamp.fromDate(DateTime.now()),
        'readBy': ?readBy,
        'deletedBy': ?deletedBy,
      };

  setUp(() {
    db = FakeFirebaseFirestore();
    ds = NotificationRemoteDataSourceImpl(firestore: db, currentAuthUid: () => 'auth-1');
  });

  test('markAsRead adds the caller to readBy', () async {
    await db.collection('notifications').doc('n1').set(broadcast());
    await ds.markAsRead('n1');
    final data = (await db.collection('notifications').doc('n1').get()).data()!;
    expect(data['readBy'], ['auth-1']);
  });

  test('a shared notification read by someone else stays unread for me', () async {
    await db.collection('notifications').doc('n1').set(broadcast(readBy: ['someone-else']));
    await db.collection('notifications').doc('n2').set(broadcast(readBy: ['auth-1']));
    final list = await ds.getNotifications('del-1', 'org-1', userRole: 'hr');
    final byId = {for (final n in list) n.id: n};
    expect(byId['n1']!.isRead, isFalse);
    expect(byId['n2']!.isRead, isTrue);
  });

  test('soft delete writes only my own ids (no phone number)', () async {
    await db.collection('notifications').doc('n1').set(broadcast());
    await ds.deleteAllNotificationsForUser(['n1'], 'del-1', phoneNumber: '01000000000');
    final data = (await db.collection('notifications').doc('n1').get()).data()!;
    expect((data['deletedBy'] as List).toSet(), {'del-1', 'auth-1'});
  });

  test('my soft delete hides the notification; a legacy phone entry still hides it', () async {
    await db.collection('notifications').doc('mine').set(broadcast(deletedBy: ['auth-1']));
    await db.collection('notifications').doc('legacy').set(broadcast(deletedBy: ['01000000000']));
    await db.collection('notifications').doc('other').set(broadcast(deletedBy: ['someone-else']));
    final list = await ds.getNotifications('del-1', 'org-1',
        userRole: 'hr', phoneNumber: '01000000000');
    expect(list.map((n) => n.id), ['other']);
  });
}
