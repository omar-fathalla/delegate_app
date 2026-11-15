import 'package:delegate_app/core/constants/cloud_functions.dart';
import 'package:delegate_app/core/notifications/list_global_notify_staff_parse.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('listGlobalNotifyStaff callable name is wired (TA-35)', () {
    expect(CloudCallableNames.listGlobalNotifyStaff, 'listGlobalNotifyStaff');
  });

  test('parseListGlobalNotifyStaffUsers drops invalid rows', () {
    expect(parseListGlobalNotifyStaffUsers(null), isEmpty);
    expect(parseListGlobalNotifyStaffUsers('x'), isEmpty);
    final rows = parseListGlobalNotifyStaffUsers([
      {'uid': 'sa1', 'phoneNumber': '010', 'role': 'super-admin', 'password': 'x'},
      {'phoneNumber': '011'},
      'not-a-map',
      {'uid': '  ', 'role': 'technical_support'},
      {'uid': 'ts1', 'phone': '012', 'role': 'technical_support'},
    ]);
    expect(rows, hasLength(2));
    expect(rows[0]['uid'], 'sa1');
    expect(rows[0].containsKey('password'), isFalse);
    expect(rows[1]['uid'], 'ts1');
  });
}