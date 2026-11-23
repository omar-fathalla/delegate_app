import 'package:delegate_app/features/notifications/data/send_staff_notification_request.dart';
import 'package:flutter_test/flutter_test.dart';

Map<String, dynamic> _build({
  String audience = 'all',
  String role = 'delegate',
  String? org = 'org_dev_test',
  String phone = '',
}) =>
    buildSendStaffNotificationPayload(
      title: '  عنوان  ',
      body: ' نص ',
      type: 'announcement',
      audience: audience,
      role: role,
      organizationUid: org,
      phone: phone,
    );

void main() {
  group('buildSendStaffNotificationPayload (TAS-216)', () {
    test('all audience maps to kind all and trims text', () {
      expect(_build(), {
        'title': 'عنوان',
        'body': 'نص',
        'type': 'announcement',
        'target': {'kind': 'all'},
      });
    });

    test('org audience sends the selected organization', () {
      expect(_build(audience: 'org')['target'],
          {'kind': 'org', 'organizationUID': 'org_dev_test'});
      expect(_build(audience: 'org', org: null)['target'],
          {'kind': 'org', 'organizationUID': ''});
    });

    test('role audience sends only the role, no scope fields', () {
      final target = _build(audience: 'role', role: 'supervisor')['target'];
      expect(target, {'kind': 'role', 'role': 'supervisor'});
    });

    test('user audience sends the trimmed phone', () {
      expect(_build(audience: 'user', phone: ' 01001234567 ')['target'],
          {'kind': 'user', 'phone': '01001234567'});
    });

    test('payload never carries sender scope or identity', () {
      for (final a in ['all', 'org', 'role', 'user']) {
        final p = _build(audience: a, phone: '01001234567');
        for (final k in ['senderUid', 'senderRole', 'companyUID', 'organizationId', 'companyId']) {
          expect(p.containsKey(k), isFalse, reason: '$a/$k');
        }
      }
    });
  });

  group('sendStaffNotificationErrorMessage', () {
    test('maps scope reasons to Arabic', () {
      expect(sendStaffNotificationErrorMessage('permission-denied', 'broadcast_global_only'),
          contains('البث العام'));
      expect(sendStaffNotificationErrorMessage('permission-denied', 'out_of_scope'),
          contains('نطاق'));
      expect(sendStaffNotificationErrorMessage('permission-denied', 'type_not_allowed'),
          contains('تحديث التطبيق'));
      expect(sendStaffNotificationErrorMessage('internal', null), isNotEmpty);
    });
  });
}
