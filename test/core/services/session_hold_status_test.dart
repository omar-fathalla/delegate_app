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

    test('non-empty holds map is held even if status is still active', () {
      expect(
        SessionManagementService.isHeldSnapshot({
          'status': 'active',
          'holds': {'subscription_expired': <String, dynamic>{}},
        }),
        isTrue,
      );
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
