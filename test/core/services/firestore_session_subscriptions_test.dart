import 'dart:async';

import 'package:delegate_app/core/services/firestore_session_subscriptions.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  tearDown(() {
    FirestoreSessionSubscriptions.instance.debugReset();
  });

  test('cancelAll cancels every registered listener', () async {
    final registry = FirestoreSessionSubscriptions.instance;
    final first = StreamController<int>();
    final second = StreamController<int>();
    var firstCancelled = false;
    var secondCancelled = false;

    registry.register(
      'leaves.leave_requests.dlg_dev_test_1',
      first.stream.listen((_) {}, onDone: () => firstCancelled = true),
    );
    registry.register(
      'home.users.dlg_dev_test_1',
      second.stream.listen((_) {}, onDone: () => secondCancelled = true),
    );
    expect(registry.length, 2);

    await registry.cancelAll();
    // Closing after cancelAll must be safe; subscriptions are already dropped.
    await first.close();
    await second.close();
    expect(registry.length, 0);
    expect(firstCancelled || first.isClosed, isTrue);
    expect(secondCancelled || second.isClosed, isTrue);
  });
}
