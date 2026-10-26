import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:pinput/pinput.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/delegate_phone_otp_view.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class MockAuthBloc extends Mock implements AuthBloc {}

class _ScriptedSmsRetriever implements SmsRetriever {
  _ScriptedSmsRetriever(this.codes);

  final List<String?> codes;
  int listens = 0;
  int disposeCount = 0;

  @override
  bool get listenForMultipleSms => false;

  @override
  Future<String?> getSmsCode() async {
    final index = listens++;
    if (index >= codes.length) return null;
    return codes[index];
  }

  @override
  Future<void> dispose() async {
    disposeCount++;
  }
}

class _FakeOtpClient implements DelegatePhoneOtpClient {
  _FakeOtpClient({
    this.autoVerify = false,
    this.confirmError,
    this.signalTimeout = false,
  });

  final bool autoVerify;
  final bool signalTimeout;
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
    void Function()? onAutoRetrievalTimeout,
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
    if (signalTimeout) onAutoRetrievalTimeout?.call();
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
    SmsRetriever? smsRetriever,
  }) {
    return MaterialApp(
      locale: locale,
      supportedLocales: AppLocalizations.supportedLocales,
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      home: BlocProvider<AuthBloc>.value(
        value: bloc,
        child: DelegatePhoneOtpView(
          phoneE164: '+201211857725',
          client: client,
          smsRetriever: smsRetriever ?? _ScriptedSmsRetriever(const []),
        ),
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
      find
          .ancestor(of: find.text(phone), matching: find.byType(Directionality))
          .first,
    );
    expect(phoneDirection.textDirection, TextDirection.ltr);

    final sentenceDirection = tester.widget<Directionality>(
      find
          .ancestor(
            of: find.text(sentence),
            matching: find.byType(Directionality),
          )
          .first,
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

    await tester.enterText(find.byType(EditableText), '654321');
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

      await tester.enterText(find.byType(EditableText), '000000');
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
    await tester.enterText(find.byType(EditableText), '111111');
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
    expect(client.confirmedCode, isNull);
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

  testWidgets('offers the iOS one-time-code hint and a 6-digit Pinput', (
    tester,
  ) async {
    final client = _FakeOtpClient();
    await tester.pumpWidget(host(client));
    await tester.pump();

    final pin = tester.widget<Pinput>(find.byType(Pinput));
    expect(pin.length, 6);
    expect(pin.autofillHints, contains(AutofillHints.oneTimeCode));
    expect(pin.smsRetriever, isNotNull);
  });

  testWidgets(
    'submits when the code fills the field, without tapping confirm',
    (tester) async {
      final client = _FakeOtpClient();
      await tester.pumpWidget(host(client));
      await tester.pump();
      await tester.pump();

      await tester.enterText(find.byType(EditableText), '246810');
      await tester.pump();

      expect(client.confirmedCode, '246810');
      verify(() => bloc.add(const PhoneOtpVerified())).called(1);
    },
  );

  testWidgets('Android SMS Retriever fills every box and verifies the code', (
    tester,
  ) async {
    final client = _FakeOtpClient();
    final retriever = _ScriptedSmsRetriever(['135790']);
    await tester.pumpWidget(host(client, smsRetriever: retriever));
    await tester.pump();
    await tester.pump();

    expect(retriever.listens, greaterThan(0));
    expect(client.confirmedCode, '135790');
    verify(() => bloc.add(const PhoneOtpVerified())).called(1);
  });

  testWidgets('cancels the SMS listener when the screen is disposed', (
    tester,
  ) async {
    final retriever = _ScriptedSmsRetriever(const [null]);
    await tester.pumpWidget(host(_FakeOtpClient(), smsRetriever: retriever));
    await tester.pump();

    await tester.pumpWidget(const SizedBox.shrink());

    expect(retriever.disposeCount, greaterThan(0));
  });

  testWidgets('auto-retrieval timeout leaves manual entry working', (
    tester,
  ) async {
    final client = _FakeOtpClient(signalTimeout: true);
    await tester.pumpWidget(host(client));
    await tester.pump();
    await tester.pump();

    expect(find.byType(EditableText), findsOneWidget);
    expect(find.text(phoneOtpSendFailedMessage), findsNothing);

    await tester.enterText(find.byType(EditableText), '112233');
    await tester.pump();

    expect(client.confirmedCode, '112233');
    verify(() => bloc.add(const PhoneOtpVerified())).called(1);
  });
}
