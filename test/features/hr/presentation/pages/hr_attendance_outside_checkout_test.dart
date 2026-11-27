import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:material_ui/material_ui.dart';

/// TAS-361 phase 1: HR sees the server's «check-out outside the branch» flag.
void main() {
  group('serverCheckOutVerdict', () {
    test('flag on the check-in record (checkOutLocation stamped there)', () {
      final v = serverCheckOutVerdict(
        {'checkOutOutsideBranch': true, 'checkOutVerifiedDistanceMeters': 222.4},
        null,
      );
      expect(v.outside, isTrue);
      expect(v.distanceMeters, 222.4);
    });

    test('flag on the type == check_out record', () {
      final v = serverCheckOutVerdict(
        {'checkOutOutsideBranch': false},
        {'checkOutOutsideBranch': true, 'verifiedDistanceMeters': 900},
      );
      expect(v.outside, isTrue);
      expect(v.distanceMeters, 900);
    });

    test('records the trigger never saw, or inside check-outs, are not flagged', () {
      expect(serverCheckOutVerdict({}, null).outside, isFalse);
      expect(serverCheckOutVerdict({'checkOutOutsideBranch': false}, {}).outside, isFalse);
      // The client cannot pass a string for the flag.
      expect(serverCheckOutVerdict({'checkOutOutsideBranch': 'true'}, null).outside, isFalse);
    });
  });

  group('serverCheckInVerdict', () {
    test('used only when the trigger computed it (reason ok)', () {
      final v = serverCheckInVerdict({
        'verifiedReason': 'ok',
        'verifiedDistanceMeters': 55.6,
        'verifiedInsideBranch': true,
      });
      expect(v!.distanceMeters, 55.6);
      expect(v.inside, isTrue);
      expect(
        serverCheckInVerdict({'verifiedReason': 'no_branch', 'verifiedInsideBranch': null}),
        isNull,
      );
      expect(serverCheckInVerdict({}), isNull);
    });
  });

  testWidgets('label shows the rounded distance', (tester) async {
    await tester.pumpWidget(MaterialApp(
      theme: AppTheme.lightTheme(),
      home: const Directionality(
        textDirection: TextDirection.rtl,
        child: Scaffold(body: AttendanceOutsideCheckOutLabel(distanceMeters: 222.4)),
      ),
    ));
    expect(find.text('انصراف من برّه الفرع (222 م)'), findsOneWidget);
  });
}
