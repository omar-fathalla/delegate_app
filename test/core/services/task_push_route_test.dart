import 'package:delegate_app/core/services/task_push_route.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('opens /tasks/<id> when the FCM data has a taskId', () {
    expect(
      taskPushRoute({'taskId': 'qa55_t1', 'type': 'task', 'organizationId': 'org'}),
      '/tasks/qa55_t1',
    );
  });

  test('ignores a missing or blank taskId so the tap does not go home via a bad route', () {
    expect(taskPushRoute({'type': 'task'}), isNull);
    expect(taskPushRoute({'taskId': ''}), isNull);
    expect(taskPushRoute({'taskId': '  '}), isNull);
    expect(taskPushRoute({}), isNull);
  });
}
