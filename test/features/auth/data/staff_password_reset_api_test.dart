import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/auth/data/staff_password_reset_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('StaffPasswordResetApi (TAS-20)', () {
    test('sends the trimmed phone to the callable', () async {
      String? sent;
      final api = StaffPasswordResetApi(call: (p) async => sent = p);
      expect(await api.request(' 01012345678 '), StaffResetOutcome.sent);
      expect(sent, '01012345678');
    });

    test('empty phone never calls the server', () async {
      var called = false;
      final api = StaffPasswordResetApi(call: (_) async => called = true);
      expect(await api.request('   '), StaffResetOutcome.invalidPhone);
      expect(called, isFalse);
    });

    test('invalid-argument means fall back to the email dialog', () async {
      final api = StaffPasswordResetApi(
        call: (_) async => throw FirebaseFunctionsException(
          code: 'invalid-argument',
          message: 'Phone is required.',
        ),
      );
      expect(await api.request('12'), StaffResetOutcome.invalidPhone);
    });

    test('other errors are reported as failed', () async {
      final api = StaffPasswordResetApi(
        call: (_) async => throw FirebaseFunctionsException(
          code: 'unavailable',
          message: 'down',
        ),
      );
      expect(await api.request('01012345678'), StaffResetOutcome.failed);
      final api2 = StaffPasswordResetApi(call: (_) async => throw StateError('x'));
      expect(await api2.request('01012345678'), StaffResetOutcome.failed);
    });
  });
}
