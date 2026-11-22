import 'package:delegate_app/features/home/presentation/chain_auto_switch_session.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('pending tab is consumed once (TAS-245)', () {
    ChainAutoSwitchSession.openTabAfterSwitch(1);
    expect(ChainAutoSwitchSession.takePendingTab(), 1);
    expect(ChainAutoSwitchSession.takePendingTab(), isNull);
  });

  test('pause is tied to the delegate uid', () {
    ChainAutoSwitchSession.pause('uid-a');
    expect(ChainAutoSwitchSession.isPaused('uid-a'), isTrue);
    expect(ChainAutoSwitchSession.isPaused('uid-b'), isFalse);
  });
}
