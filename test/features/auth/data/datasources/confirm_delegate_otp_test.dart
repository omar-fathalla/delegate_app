import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/data/datasources/firebase_phone_otp.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _MockAuth extends Mock implements FirebaseAuth {}

class _MockUser extends Mock implements User {}

class _MockConfirmApi extends Mock implements ConfirmDelegateOtpApi {}

class _MockIdTokenResult extends Mock implements IdTokenResult {}

class _MockUserCredential extends Mock implements UserCredential {}

class _FakeCredential extends Fake implements PhoneAuthCredential {}

void main() {
  late _MockAuth auth;
  late _MockUser user;
  late _MockConfirmApi confirmApi;
  late _MockUserCredential userCredential;
  late FirebaseDelegatePhoneOtpClient client;

  setUpAll(() {
    registerFallbackValue(_FakeCredential());
  });

  setUp(() {
    auth = _MockAuth();
    user = _MockUser();
    confirmApi = _MockConfirmApi();
    userCredential = _MockUserCredential();
    client = FirebaseDelegatePhoneOtpClient(auth, confirmOtpApi: confirmApi);
    when(() => auth.currentUser).thenReturn(user);
    when(() => user.linkWithCredential(any())).thenAnswer(
      (_) async => userCredential,
    );
  });

  void stubToken({required bool otpRequired}) {
    final token = _MockIdTokenResult();
    when(() => token.claims).thenReturn({'otp_required': otpRequired});
    when(() => user.getIdTokenResult()).thenAnswer((_) async => token);
    when(() => user.getIdToken(any())).thenAnswer((_) async => 'refreshed');
  }

  test('after link, confirms possession and refreshes the ID token', () async {
    stubToken(otpRequired: true);
    when(() => confirmApi.confirm()).thenAnswer((_) async {});

    await client.confirmCode(verificationId: 'vid', smsCode: '123456');

    verify(() => confirmApi.confirm()).called(1);
    verify(() => user.getIdToken(true)).called(1);
  });

  test('when otp is not required, an unavailable confirm is ignored', () async {
    stubToken(otpRequired: false);
    when(() => confirmApi.confirm()).thenThrow(
      const ConfirmDelegateOtpException('unavailable'),
    );

    await client.confirmCode(verificationId: 'vid', smsCode: '123456');

    verify(() => confirmApi.confirm()).called(1);
    verifyNever(() => user.getIdToken(true));
  });

  test('when otp is required, an unavailable confirm fails the link', () async {
    stubToken(otpRequired: true);
    when(() => confirmApi.confirm()).thenThrow(
      const ConfirmDelegateOtpException('unavailable'),
    );

    await expectLater(
      client.confirmCode(verificationId: 'vid', smsCode: '123456'),
      throwsA(
        isA<PhoneOtpLinkException>().having(
          (e) => e.failure,
          'failure',
          PhoneOtpLinkFailure.other,
        ),
      ),
    );
  });

  test('phone mismatch from confirm surfaces as a link failure', () async {
    stubToken(otpRequired: true);
    when(() => confirmApi.confirm()).thenThrow(
      const ConfirmDelegateOtpException('phone_mismatch'),
    );

    await expectLater(
      client.confirmCode(verificationId: 'vid', smsCode: '123456'),
      throwsA(
        isA<PhoneOtpLinkException>().having(
          (e) => e.message,
          'message',
          phoneOtpAlreadyInUseMessage,
        ),
      ),
    );
  });
}
