import 'package:delegate_app/features/hr/domain/services/leave_notification_target.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('leaveNotificationDelegateUid', () {
    test('uses supervisorUid when present', () {
      expect(
        leaveNotificationDelegateUid(
          supervisorUid: 'sup-1',
          companyUID: 'co_dev_test',
        ),
        'sup-1',
      );
    });

    test('falls back to supervisor_{company} when supervisorUid is empty', () {
      expect(
        leaveNotificationDelegateUid(
          supervisorUid: null,
          companyUID: 'co_dev_test',
        ),
        'supervisor_co_dev_test',
      );
      expect(
        leaveNotificationDelegateUid(
          supervisorUid: '  ',
          companyUID: 'co_dev_test',
        ),
        'supervisor_co_dev_test',
      );
    });

    test('returns null when both supervisor and company are empty', () {
      expect(
        leaveNotificationDelegateUid(supervisorUid: null, companyUID: ''),
        isNull,
      );
    });
  });
}
