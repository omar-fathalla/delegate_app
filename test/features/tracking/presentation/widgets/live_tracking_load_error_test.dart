import 'package:delegate_app/features/tracking/presentation/widgets/live_tracking_load_error.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  testWidgets('shows Arabic error copy and invokes retry', (tester) async {
    var retried = 0;
    await tester.pumpWidget(
      MaterialApp(
        home: Scaffold(
          body: LiveTrackingLoadError(
            error: Exception('permission-denied'),
            onRetry: () => retried++,
          ),
        ),
      ),
    );

    expect(find.byKey(const Key('live_tracking_load_error')), findsOneWidget);
    expect(find.text('تعذّر تحميل التتبع المباشر'), findsOneWidget);
    expect(find.textContaining('حدث خطأ أثناء جلب بيانات المناديب'), findsOneWidget);
    expect(find.byKey(const Key('live_tracking_retry')), findsOneWidget);

    await tester.tap(find.byKey(const Key('live_tracking_retry')));
    await tester.pump();
    expect(retried, 1);
  });
}
