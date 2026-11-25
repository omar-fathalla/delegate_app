// TAS-48: staff tracking screens prefer the server verdict
// (verifiedStatus / verifiedDistanceMeters) and flag statusMismatch.
import 'package:delegate_app/features/tracking/data/models/delegate_tracking_session_model.dart';
import 'package:delegate_app/features/tracking/domain/entities/delegate_tracking_session.dart';
import 'package:delegate_app/features/tracking/domain/utils/tracking_geofence_status.dart';
import 'package:delegate_app/features/tracking/presentation/widgets/tracking_mismatch_chip.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _doc([Map<String, dynamic> extra = const {}]) => {
      'delegateId': 'seed-fake-del',
      'delegateName': 'مندوب تجريبي',
      'companyUID': 'c1',
      'organizationUID': 'o1',
      'branchId': 'b1',
      'branchLat': 30.0544,
      'branchLng': 31.2357,
      'geofenceRadius': 100,
      'currentStatus': 'inside',
      'currentDistanceMeters': 0,
      'lastLatitude': 30.0544,
      'lastLongitude': 31.2357,
      ...extra,
    };

DelegateTrackingSession _parse([Map<String, dynamic> extra = const {}]) =>
    DelegateTrackingSessionModel.fromJson(_doc(extra), 'seed-fake-del');

void main() {
  group('preferServerVerdict', () {
    test('no verdict yet (old docs): the app values are kept', () {
      final s = _parse().preferServerVerdict();
      expect(s.currentStatus, TrackingStatus.insideZone);
      expect(s.currentDistanceMeters, 0);
      expect(s.statusMismatch, isFalse);
    });

    test('faked inside: the server outside verdict and distance win', () {
      final s = _parse({
        'verifiedStatus': 'outside',
        'verifiedDistanceMeters': 1112.4,
        'verifiedBranchRadius': 120,
        'statusMismatch': true,
      }).preferServerVerdict();
      expect(s.currentStatus, TrackingStatus.outsideZone);
      expect(s.isInside, isFalse);
      expect(s.currentDistanceMeters, 1112.4);
      expect(s.geofenceRadius, 120);
      expect(s.statusMismatch, isTrue);
    });

    test('server inside overrides an app outside', () {
      final s = _parse({
        'currentStatus': 'outside',
        'currentDistanceMeters': 900,
        'verifiedStatus': 'inside',
        'verifiedDistanceMeters': 12,
      }).preferServerVerdict();
      expect(s.currentStatus, TrackingStatus.insideZone);
      expect(s.currentDistanceMeters, 12);
      expect(s.geofenceRadius, 100, reason: 'no verified radius: app value');
    });

    test('unknown verdict falls back to the app fields', () {
      final s = _parse({
        'verifiedStatus': 'unknown',
        'verifiedDistanceMeters': null,
      }).preferServerVerdict();
      expect(s.currentStatus, TrackingStatus.insideZone);
      expect(s.currentDistanceMeters, 0);
    });

    test('non-geofence statuses keep the app status', () {
      for (final raw in ['checked_out', 'offline', 'suspended']) {
        final s = _parse({
          'currentStatus': raw,
          'verifiedStatus': 'inside',
          'verifiedDistanceMeters': 5,
        }).preferServerVerdict();
        expect(s.isInside, isFalse, reason: raw);
      }
    });

    test('the server fields are never sent back by toJson', () {
      final model = DelegateTrackingSessionModel.fromJson(
        _doc({'verifiedStatus': 'outside', 'statusMismatch': true}),
        'seed-fake-del',
      );
      final json = model.toJson();
      expect(json.containsKey('verifiedStatus'), isFalse);
      expect(json.containsKey('statusMismatch'), isFalse);
    });
  });

  testWidgets('status pill uses the verified distance; chip shows on mismatch',
      (tester) async {
    final flagged = _parse({
      'verifiedStatus': 'outside',
      'verifiedDistanceMeters': 400,
      'statusMismatch': true,
    }).preferServerVerdict();
    final clean = _parse({
      'verifiedStatus': 'inside',
      'verifiedDistanceMeters': 30,
    }).preferServerVerdict();

    late ColorScheme cs;
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(
          textDirection: TextDirection.rtl,
          child: Scaffold(
            body: Builder(builder: (context) {
              cs = Theme.of(context).colorScheme;
              return Column(
                children: [
                  TrackingMismatchChip(session: flagged),
                  TrackingMismatchChip(session: clean),
                  TrackingMismatchChip(session: flagged, compact: true),
                ],
              );
            }),
          ),
        ),
      ),
    );

    expect(find.byKey(const ValueKey('tracking-mismatch-chip')), findsNWidgets(2));
    expect(find.text(TrackingMismatchChip.label), findsOneWidget);
    expect(find.byIcon(Icons.gpp_maybe_rounded), findsNWidgets(2));

    // 400 m from a 100 m branch: "خارج (+300م)", not the app's "داخل (0م)".
    expect(TrackingGeofenceStatus.resolve(flagged, cs).title, 'خارج (+300م)');
    expect(TrackingGeofenceStatus.resolve(clean, cs).title, 'داخل (30م)');
  });
}
