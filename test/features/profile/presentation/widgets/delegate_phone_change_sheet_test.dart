// TAS-112: the delegate phone change sheet: form -> code -> confirm.
import 'package:delegate_app/features/profile/data/phone_change/delegate_phone_change_api.dart';
import 'package:delegate_app/features/profile/presentation/widgets/delegate_phone_change_sheet.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';

class _FakeOtp implements PhoneChangeOtp {
  String? sentTo;
  String? confirmed;
  String? failWith;
  @override
  Future<void> sendCode({
    required String e164Phone,
    bool resend = false,
    required void Function() onAutoVerified,
    required void Function(String code) onFailed,
  }) async {
    sentTo = e164Phone;
  }

  @override
  Future<void> confirmCode(String smsCode) async {
    if (failWith != null) throw FirebaseAuthException(code: failWith!);
    confirmed = smsCode;
  }
}

Widget _host(Widget sheet, void Function(Object?) onResult) => MaterialApp(
      locale: const Locale('ar'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: Builder(
        builder: (context) => Scaffold(
          body: Center(
            child: TextButton(
              onPressed: () async {
                final r = await showModalBottomSheet<String>(
                  context: context,
                  isScrollControlled: true,
                  builder: (_) => sheet,
                );
                onResult(r);
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

void main() {
  testWidgets('sends the code to the new number and confirms', (tester) async {
    final calls = <String>[];
    final api = DelegatePhoneChangeApi(call: (name, data) async {
      calls.add(name);
      if (name == 'requestDelegatePhoneChange') return {'e164': '+201000000002'};
      return {'phoneNumber': '01000000002'};
    });
    final otp = _FakeOtp();
    Object? result;
    await tester.pumpWidget(_host(
      DelegatePhoneChangeSheet(api: api, otp: otp, refreshToken: () async {}),
      (r) => result = r,
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();

    await tester.enterText(find.byKey(const Key('phone_change_new_phone')), '01000000002');
    await tester.enterText(find.byKey(const Key('phone_change_national_id')), '29001010000001');
    await tester.tap(find.byKey(const Key('phone_change_primary')));
    await tester.pumpAndSettle();
    expect(otp.sentTo, '+201000000002');
    expect(find.byKey(const Key('phone_change_code')), findsOneWidget);

    await tester.enterText(find.byKey(const Key('phone_change_code')), '123456');
    await tester.tap(find.byKey(const Key('phone_change_primary')));
    await tester.pumpAndSettle();
    expect(otp.confirmed, '123456');
    expect(calls, ['requestDelegatePhoneChange', 'confirmDelegatePhoneChange']);
    expect(result, '01000000002');
  });

  testWidgets('shows the server reason and stays on the form', (tester) async {
    final api = DelegatePhoneChangeApi(
        call: (name, data) async => throw const PhoneChangeException(PhoneChangeFailure.phoneTaken));
    await tester.pumpWidget(_host(
      DelegatePhoneChangeSheet(api: api, otp: _FakeOtp(), refreshToken: () async {}),
      (_) {},
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone_change_new_phone')), '01000000002');
    await tester.enterText(find.byKey(const Key('phone_change_national_id')), '29001010000001');
    await tester.tap(find.byKey(const Key('phone_change_primary')));
    await tester.pumpAndSettle();
    expect(find.byKey(const Key('phone_change_error')), findsOneWidget);
    expect(find.text('الرقم ده مستخدم في حساب تاني.'), findsOneWidget);
    expect(find.byKey(const Key('phone_change_code')), findsNothing);
  });

  testWidgets('a wrong code shows the wrong-code message', (tester) async {
    final api = DelegatePhoneChangeApi(call: (name, data) async => {'e164': '+201000000002'});
    final otp = _FakeOtp()..failWith = 'invalid-verification-code';
    await tester.pumpWidget(_host(
      DelegatePhoneChangeSheet(api: api, otp: otp, refreshToken: () async {}),
      (_) {},
    ));
    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone_change_new_phone')), '01000000002');
    await tester.enterText(find.byKey(const Key('phone_change_national_id')), '29001010000001');
    await tester.tap(find.byKey(const Key('phone_change_primary')));
    await tester.pumpAndSettle();
    await tester.enterText(find.byKey(const Key('phone_change_code')), '000000');
    await tester.tap(find.byKey(const Key('phone_change_primary')));
    await tester.pumpAndSettle();
    expect(find.text('الكود غلط. اتأكد منه وجرّب تاني.'), findsOneWidget);
  });
}
