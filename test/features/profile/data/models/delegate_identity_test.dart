import 'package:delegate_app/features/profile/data/models/delegate_identity.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  // The exact field set found on prod ghost docs (new start, 18 Nov 2026).
  final ghost = <String, dynamic>{
    'boundDeviceBrand': 'OPPO',
    'boundDeviceId': 'RP1A.200720.011',
    'boundDeviceModel': 'OPPO CPH1989',
    'boundDeviceOs': 'Android 11 (SDK 30)',
    'deviceBoundAt': DateTime(2026, 11, 4),
    'deviceLastSeenAt': DateTime(2026, 11, 4),
    'isDeviceLocked': true,
    'position': 'Promoter',
    'delegatePublicId': 'DEL-6179',
    'updatedAt': DateTime(2026, 10, 24),
  };

  test('ghost doc with device/backfill fields only has no identity', () {
    expect(delegateDocHasIdentity(ghost), isFalse);
    expect(delegateDocHasIdentity({...ghost, 'forceLogoutAt': 1, 'requireReLogin': true}), isFalse);
    expect(delegateDocHasIdentity({'fullName': '   '}), isFalse);
    expect(delegateDocHasIdentity(null), isFalse);
    expect(delegateDocHasIdentity(const {}), isFalse);
  });

  test('a name, national ID or phone is enough', () {
    expect(delegateDocHasIdentity({'fullName': 'مينا عماد فوزي'}), isTrue);
    expect(delegateDocHasIdentity({'firstName': 'مينا'}), isTrue);
    expect(delegateDocHasIdentity({'name': 'x'}), isTrue);
    expect(delegateDocHasIdentity({'nationalityID': '30302141801253'}), isTrue);
    expect(delegateDocHasIdentity({'phoneNumber': '01279747624'}), isTrue);
    expect(delegateDocHasIdentity({...ghost, 'phone': '01000000000'}), isTrue);
  });
}
