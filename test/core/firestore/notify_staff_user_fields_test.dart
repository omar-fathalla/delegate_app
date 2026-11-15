import 'package:delegate_app/core/constants/cloud_functions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('new-delegate notify uses listGlobalNotifyStaff callable (TA-35)', () {
    expect(CloudCallableNames.listGlobalNotifyStaff, 'listGlobalNotifyStaff');
    expect(CloudCallableNames.listGlobalNotifyStaff, isNot(CloudCallableNames.checkDelegateDuplicate));
  });
}