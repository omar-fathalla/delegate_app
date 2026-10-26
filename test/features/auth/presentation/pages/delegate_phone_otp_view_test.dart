import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/delegate_phone_otp_view.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

class _FakeOtpClient implements DelegatePhoneOtpClient {
  _FakeOtpClient({this.autoVerify = false, this.confirmError});

  final bool autoVerify;
  PhoneOtpLinkException? confirmError;
  int? lastResendToken;
  int sendCount = 0;
  String? confirmedCode;

  @override
  Future<void> sendCode({
    required String e164Phone,
    int? forceResendingToken,
    required void Function(OtpCodeDispatch sent) onCodeSent,
    required void Function() onAutoVerified,
    required void Function(PhoneOtpLinkException error) onFailed,
  }) async {
    sendCount += 1;
    lastResendToken = forceResendingToken;
    if (autoVerify) {
      onAutoVerified();
      return;
    }
    onCodeSent(
      const OtpCodeDispatch(verificationId: 'verification-1', resendToken: 4),
    );
  }

  @override
  Future<void> confirmCode({
    required String verificationId,
    required String smsCode,
  }) async {
    confirmedCode = smsCode;
    final error = confirmError;
    if (error != null) throw error;
  }
}

void main() {
  late MockAuthBloc bloc;

  setUpAll(() {
    registerFallbackValue(const PhoneOtpVerified());
  });

  setUp(() {
    bloc = MockAuthBloc();
    when(() => bloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => bloc.state).thenReturn(AuthInitial());
  });

  Widget host(
    _FakeOtpClient client, {
    Locale locale = const Locale('ar'),
  }) {
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: DelegatePhoneOtpView(phoneE164: '+201211857725', client: client),
      ),
    );
  }

  Future<void> expectPhoneOnItsOwnLtrLine(WidgetTester tester) async {
    const sentence = 'أدخل رمز التحقق المرسل إلى';
    const phone = '+201211857725';

    expect(find.text(sentence), findsOneWidget);
    expect(find.text(phone), findsOneWidget);
    expect(find.text('$sentence $phone'), findsNothing);

    final phoneDirection = tester.widget<Directionality>(
      find.ancestor(
        of: find.text(phone),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(phoneDirection.textDirection, TextDirection.ltr);

    final sentenceDirection = tester.widget<Directionality>(
      find.ancestor(
        of: find.text(sentence),
        matching: find.byType(Directionality),
      ).first,
    );
    expect(sentenceDirection.textDirection, TextDirection.rtl);

    final sentenceBox = tester.getRect(find.text(sentence));
    final phoneBox = tester.getRect(find.text(phone));
    expect(phoneBox.top, greaterThan(sentenceBox.bottom - 1));
    expect(phoneBox.center.dx, closeTo(sentenceBox.center.dx, 1));
  }

  testWidgets('shows an Arabic prompt and confirms the typed code', (
    tester,
  ) async {
    final client = _FakeOtpClient();
    await tester.pumpWidget(host(client));
    await tester.pump();
    await tester.pump();

    expect(find.text('تأكيد رقم الجوال'), findsOneWidget);
    expect(find.text('أدخل رمز التحقق المرسل إلى'), findsOneWidget);
    expect(find.text('+201211857725'), findsOneWidget);
    expect(find.textContaining('إعادة الإرسال بعد'), findsOneWidget);

    await tester.enterText(find.byType(TextField), '654321');
    await tester.tap(find.text('تأكيد'));
    await tester.pump();

    expect(client.confirmedCode, '654321');
    verify(() => bloc.add(const PhoneOtpVerified())).called(1);
  });

  testWidgets(
    'shows the E.164 number left-to-right on its own line in Arabic and English',
    (tester) async {
      for (final locale in const [Locale('ar'), Locale('en')]) {
        final client = _FakeOtpClient();
        await tester.pumpWidget(host(client, locale: locale));
        await tester.pump();
        await tester.pump();

        await expectPhoneOnItsOwnLtrLine(tester);
      }
    },
  );

  testWidgets(
    'shows the Arabic error for a rejected code and does not continue',
    (tester) async {
      final client = _FakeOtpClient(
        confirmError: const PhoneOtpLinkException(
          PhoneOtpLinkFailure.invalidCode,
          phoneOtpInvalidCodeMessage,
        ),
      );
      await tester.pumpWidget(host(client));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(TextField), '000000');
      await tester.tap(find.text('تأكيد'));
      await tester.pump();

      expect(find.text(phoneOtpInvalidCodeMessage), findsOneWidget);
      verifyNever(() => bloc.add(const PhoneOtpVerified()));
    },
  );

  testWidgets('explains when the phone is already linked to another account', (
    tester,
  ) async {
    final client = _FakeOtpClient(
      confirmError: const PhoneOtpLinkException(
        PhoneOtpLinkFailure.credentialAlreadyInUse,
        phoneOtpAlreadyInUseMessage,
      ),
    );
    await tester.pumpWidget(host(client));
    await tester.pump();
    await tester.pump();
    await tester.enterText(find.byType(TextField), '111111');
    await tester.tap(find.text('تأكيد'));
    await tester.pump();

    expect(find.text(phoneOtpAlreadyInUseMessage), findsOneWidget);
    verifyNever(() => bloc.add(const PhoneOtpVerified()));
  });

  testWidgets('lets the user resend after the cooldown and keeps the token', (
    tester,
  ) async {
    final client = _FakeOtpClient();
    await tester.pumpWidget(host(client));
    await tester.pump();
    await tester.pump();

    expect(
      tester
          .widget<TextButton>(
            find.widgetWithText(TextButton, 'إعادة الإرسال بعد 60 ث'),
          )
          .onPressed,
      isNull,
    );

    await tester.pump(const Duration(seconds: 60));

    await tester.tap(find.text('إعادة إرسال الرمز'));
    await tester.pump();

    expect(client.sendCount, 2);
    expect(client.lastResendToken, 4);
  });

  testWidgets('finishes when Android retrieves the code automatically', (
    tester,
  ) async {
    final client = _FakeOtpClient(autoVerify: true);
    await tester.pumpWidget(host(client));
    await tester.pump();
    await tester.pump();

    verify(() => bloc.add(const PhoneOtpVerified())).called(1);
    expect(find.byType(TextField), findsNothing);
  });

  testWidgets('cancel signs the incomplete session out', (tester) async {
    final client = _FakeOtpClient();
    await tester.pumpWidget(host(client));
    await tester.pump();
    await tester.pump();

    await tester.tap(find.text('إلغاء'));
    await tester.pump();

    verify(() => bloc.add(const PhoneOtpCancelled())).called(1);
  });
}
