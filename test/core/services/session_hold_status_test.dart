import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('SessionManagementService.isHeldStatus', () {
    test('treats suspended and rejected as held', () {
      expect(SessionManagementService.isHeldStatus('suspended'), isTrue);
      expect(SessionManagementService.isHeldStatus('SUSPENDED'), isTrue);
      expect(SessionManagementService.isHeldStatus('rejected'), isTrue);
      expect(SessionManagementService.isHeldStatus(' rejected '), isTrue);
    });

    test('active, approved, pending, empty and null are not held', () {
      expect(SessionManagementService.isHeldStatus('active'), isFalse);
      expect(SessionManagementService.isHeldStatus('approved'), isFalse);
      expect(SessionManagementService.isHeldStatus('pending'), isFalse);
      expect(SessionManagementService.isHeldStatus(''), isFalse);
      expect(SessionManagementService.isHeldStatus(null), isFalse);
    });
  });

  group('SessionManagementService.isHeldSnapshot', () {
    test('held status is held even with an empty holds map', () {
      expect(
        SessionManagementService.isHeldSnapshot({'status': 'suspended'}),
        isTrue,
      );
    });

    // TAS-367 (user decision 2026-11-27): the app follows the server's rule.
    // In shadow mode a hold alone does not sign the delegate out.
    test('holds alone (shadow mode, status still active) are not held', () {
      expect(
        SessionManagementService.isHeldSnapshot({
          'status': 'active',
          'holds': {'subscription_expired': <String, dynamic>{}},
        }),
        isFalse,
      );
    });

    test('the holds pick the message when the status is held', () {
      String msg(Map<String, dynamic> d) => SessionManagementService.heldMessageFor(d);
      expect(msg({'status': 'suspended', 'holds': {'subscription_expired': {}}}), contains('اشتراك شركتك خلص'));
      expect(msg({'status': 'suspended', 'holds': {'billing_cycle_reset': {}}}), contains('دورة الفوترة'));
      expect(msg({'status': 'suspended', 'holds': {'admin_suspend': {}}}), contains('الإدارة أوقفت'));
      expect(msg({'status': 'rejected'}), contains('اترفض'));
      expect(msg({'status': 'suspended'}), SessionManagementService.heldSessionMessage);
    });

    test('active with empty or missing holds is not held', () {
      expect(
        SessionManagementService.isHeldSnapshot({
          'status': 'active',
          'holds': {},
        }),
        isFalse,
      );
      expect(
        SessionManagementService.isHeldSnapshot({'status': 'active'}),
        isFalse,
      );
      expect(SessionManagementService.isHeldSnapshot(null), isFalse);
    });
  });
}
