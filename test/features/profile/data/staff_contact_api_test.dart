// TAS-49: helpers for the staff phone / email change.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/profile/data/staff_contact_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('staffEmailNeedsSync', () {
    test('a confirmed new Auth email needs a sync', () {
      expect(staffEmailNeedsSync('new@example.test', 'old@example.test'), isTrue);
      expect(staffEmailNeedsSync('New@Example.test', null), isTrue);
    });
    test('same email (any case / spaces) or no Auth email does not', () {
      expect(staffEmailNeedsSync('a@example.test', ' A@Example.TEST '), isFalse);
      expect(staffEmailNeedsSync(null, 'a@example.test'), isFalse);
      expect(staffEmailNeedsSync('', 'a@example.test'), isFalse);
    });
  });

  group('staffContactErrorMessage', () {
    FirebaseFunctionsException err(String code, [String? reason]) => FirebaseFunctionsException(
          code: code,
          message: 'x',
          details: reason == null ? null : {'reason': reason},
        );
    test('maps server reasons to Arabic', () {
      expect(staffContactErrorMessage(err('already-exists', 'phone_taken')), contains('حساب تاني'));
      expect(staffContactErrorMessage(err('invalid-argument', 'bad_phone')), contains('رقم موبايل'));
      expect(staffContactErrorMessage(err('permission-denied', 'not_staff')), contains('للموظفين'));
      expect(staffContactErrorMessage(err('unavailable')), contains('اتصال'));
      expect(staffContactErrorMessage(Exception('x')), contains('جرّب تاني'));
    });
  });
}
