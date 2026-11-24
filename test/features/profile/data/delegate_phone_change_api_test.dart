// TAS-112: the phone change callables and how their reasons map for the UI.
import 'package:cloud_functions/cloud_functions.dart';
import 'package:delegate_app/features/profile/data/phone_change/delegate_phone_change_api.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  test('request sends the trimmed number and national ID, returns E.164', () async {
    String? name;
    Map<String, dynamic>? sent;
    final api = DelegatePhoneChangeApi(call: (n, d) async {
      name = n;
      sent = d;
      return {'ok': true, 'e164': '+201000000002'};
    });
    final e164 = await api.request(newPhone: ' 01000000002 ', nationalId: ' 29001010000001 ');
    expect(name, 'requestDelegatePhoneChange');
    expect(sent, {'newPhone': '01000000002', 'nationalId': '29001010000001'});
    expect(e164, '+201000000002');
  });

  test('confirm returns the stored number', () async {
    final api = DelegatePhoneChangeApi(call: (n, d) async {
      expect(n, 'confirmDelegatePhoneChange');
      return {'ok': true, 'phoneNumber': '01000000002'};
    });
    expect(await api.confirm(), '01000000002');
  });

  test('server reasons become failures', () async {
    final cases = {
      'phone_taken': PhoneChangeFailure.phoneTaken,
      'national_id_mismatch': PhoneChangeFailure.nationalIdMismatch,
      'too_many': PhoneChangeFailure.tooMany,
      'expired': PhoneChangeFailure.expired,
      'phone_not_verified': PhoneChangeFailure.notVerified,
      'something_else': PhoneChangeFailure.other,
    };
    for (final entry in cases.entries) {
      final api = DelegatePhoneChangeApi(call: (n, d) async {
        throw FirebaseFunctionsException(
          message: 'x', code: 'failed-precondition', details: {'reason': entry.key});
      });
      await expectLater(
        api.request(newPhone: '01000000002', nationalId: '1'),
        throwsA(isA<PhoneChangeException>().having((e) => e.failure, 'failure', entry.value)),
        reason: entry.key,
      );
    }
  });

  test('odd answers and network errors are "other"', () async {
    final odd = DelegatePhoneChangeApi(call: (n, d) async => 'nope');
    await expectLater(odd.confirm(),
        throwsA(isA<PhoneChangeException>().having((e) => e.failure, 'f', PhoneChangeFailure.other)));
    final broken = DelegatePhoneChangeApi(call: (n, d) async => throw Exception('net'));
    await expectLater(broken.request(newPhone: '01000000002', nationalId: '1'),
        throwsA(isA<PhoneChangeException>()));
  });
}
