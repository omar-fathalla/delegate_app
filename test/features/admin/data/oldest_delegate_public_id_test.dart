// TAS-246: one code per delegate. When a delegate already has codes in other
// chains, approval reuses the oldest one. Pure function, no Firebase.
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';

void main() {
  group('oldestDelegatePublicId (TAS-246)', () {
    String? pick(List<String?> c) =>
        DelegateSubscriptionRepositoryImpl.oldestDelegatePublicId(c);

    test('picks the lowest number, not the first found', () {
      expect(pick(['DEL-6599', 'DEL-6389', 'DEL-6574']), 'DEL-6389');
      expect(pick(['DEL-6458', 'DEL-3396']), 'DEL-3396');
    });

    test('ignores empty, null and non-codes', () {
      expect(pick([null, '', '  ', 'abc', ' DEL-12 ']), 'DEL-12');
    });

    test('none found: null (caller allocates only if the lookup worked)', () {
      expect(pick(const []), isNull);
      expect(pick([null, '']), isNull);
    });
  });
}
