import 'package:delegate_app/core/utils/google_maps_loader.dart';
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:delegate_app/features/tracking/presentation/widgets/tracking_live_map_view.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

void main() {
  setUp(() {
    googleMapsAvailabilityOverride = () => false; // Maps blocked
    googleMapsReloadOverride = () {};
  });
  tearDown(() {
    googleMapsAvailabilityOverride = null;
    googleMapsReloadOverride = null;
  });

  testWidgets('Live Tracking reaches «الخريطة غير متاحة» when Maps is blocked',
      (tester) async {
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: Scaffold(
          body: TrackingLiveMapView(
            sessions: const [],
            onToggleTracking: (_) {},
            trackingService: DelegateTrackingService(
              firestore: FakeFirebaseFirestore(),
            ),
          ),
        ),
      ),
    );
    await tester.pump();
    expect(find.textContaining('قيد التحميل'), findsNothing);
    await tester.pump(const Duration(seconds: 16));
    await tester.pump();
    expect(find.text('الخريطة غير متاحة'), findsOneWidget);
    expect(find.byKey(const Key('maps_gate_retry')), findsOneWidget);
    await tester.pump(const Duration(seconds: 30)); // drain timers
  });
}
