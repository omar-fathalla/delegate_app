import 'package:delegate_app/features/tracking/data/models/tracking_breadcrumb_model.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:flutter_test/flutter_test.dart';

/// TAS-82: the trail must show the most recent points (where the delegate
/// is now), drawn oldest→newest, not the first points of the day.
void main() {
  late FakeFirebaseFirestore db;
  late DelegateTrackingService service;
  final start = DateTime(2026, 11, 22, 8);

  setUp(() async {
    db = FakeFirebaseFirestore();
    service = DelegateTrackingService(firestore: db);
    final col = db.collection('delegate_tracking').doc('del_1').collection('breadcrumbs');
    for (var i = 0; i < 10; i++) {
      await col.doc('p$i').set(TrackingBreadcrumbModel(
        id: 'p$i',
        latitude: 30.0 + i / 1000,
        longitude: 31.0,
        timestamp: start.add(Duration(minutes: i)),
      ).toJson());
    }
  });

  test('getTodayBreadcrumbs returns the newest points, oldest first', () async {
    final points = await service.getTodayBreadcrumbs(delegateId: 'del_1', limit: 3);
    expect(points.map((p) => p.id), ['p7', 'p8', 'p9']);
  });

  test('streamBreadcrumbs returns the newest points, oldest first', () async {
    final points = await service.streamBreadcrumbs(delegateId: 'del_1', limit: 4).first;
    expect(points.map((p) => p.id), ['p6', 'p7', 'p8', 'p9']);
  });

  test('latestBreadcrumbsInOrder flips a newest-first page', () {
    final page = [
      TrackingBreadcrumbModel(id: 'b', latitude: 0, longitude: 0, timestamp: start.add(const Duration(minutes: 1))),
      TrackingBreadcrumbModel(id: 'a', latitude: 0, longitude: 0, timestamp: start),
    ];
    expect(latestBreadcrumbsInOrder(page).map((p) => p.id), ['a', 'b']);
  });
}
