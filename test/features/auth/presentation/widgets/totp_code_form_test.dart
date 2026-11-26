// TAS-207: the TOTP code step shown after a staff password on an account
// with two-step verification.
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/presentation/widgets/totp_code_form.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

Widget _host(Widget child) => MaterialApp(home: child);

void main() {
  test('isValidTotpCode accepts exactly six digits', () {
    expect(isValidTotpCode('123456'), isTrue);
    expect(isValidTotpCode(' 123456 '), isTrue);
    expect(isValidTotpCode('12345'), isFalse);
    expect(isValidTotpCode('1234567'), isFalse);
    expect(isValidTotpCode('12a456'), isFalse);
  });

  testWidgets('renders the code step with Arabic copy', (tester) async {
    await tester.pumpWidget(
      _host(
        TotpLoginView(
          onSubmit: (_) async {},
          onVerified: () {},
          onCancel: () {},
        ),
      ),
    );

    expect(find.text('التحقق بخطوتين'), findsOneWidget);
    expect(find.text(totpCodeHint), findsOneWidget);
    expect(find.byKey(const ValueKey('totp_code_input')), findsOneWidget);
    expect(find.byKey(const ValueKey('totp_confirm')), findsOneWidget);
    expect(find.byKey(const ValueKey('totp_cancel')), findsOneWidget);
  });

  testWidgets('a short code is refused without calling the resolver', (
    tester,
  ) async {
    var calls = 0;
    await tester.pumpWidget(
      _host(
        TotpLoginView(
          onSubmit: (_) async => calls++,
          onVerified: () {},
          onCancel: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '123');
    await tester.tap(find.byKey(const ValueKey('totp_confirm')));
    await tester.pump();

    expect(calls, 0);
    expect(find.text(totpCodeLengthError), findsOneWidget);
  });

  testWidgets('six digits call the resolver, then onVerified', (tester) async {
    final codes = <String>[];
    var verified = 0;
    await tester.pumpWidget(
      _host(
        TotpLoginView(
          onSubmit: (code) async => codes.add(code),
          onVerified: () => verified++,
          onCancel: () {},
        ),
      ),
    );

    // Six digits auto-submit, like the delegate phone step.
    await tester.enterText(find.byType(EditableText), '654321');
    await tester.pumpAndSettle();

    expect(codes, ['654321']);
    expect(verified, 1);
  });

  testWidgets('a wrong code shows the error and allows a retry', (
    tester,
  ) async {
    final codes = <String>[];
    var verified = 0;
    await tester.pumpWidget(
      _host(
        TotpLoginView(
          onSubmit: (code) async {
            codes.add(code);
            if (code != '111111') {
              throw const AuthFailure(
                'رمز التحقق غير صحيح',
                'invalid_mfa_code',
              );
            }
          },
          onVerified: () => verified++,
          onCancel: () {},
        ),
      ),
    );

    await tester.enterText(find.byType(EditableText), '000000');
    await tester.pumpAndSettle();
    expect(find.text('رمز التحقق غير صحيح'), findsOneWidget);
    expect(verified, 0);

    await tester.enterText(find.byType(EditableText), '111111');
    await tester.pumpAndSettle();
    expect(codes, ['000000', '111111']);
    expect(verified, 1);
    expect(find.byKey(const ValueKey('totp_code_error')), findsNothing);
  });

  testWidgets('cancel calls onCancel', (tester) async {
    var cancelled = 0;
    await tester.pumpWidget(
      _host(
        TotpLoginView(
          onSubmit: (_) async {},
          onVerified: () {},
          onCancel: () => cancelled++,
        ),
      ),
    );

    await tester.tap(find.byKey(const ValueKey('totp_cancel')));
    await tester.pump();

    expect(cancelled, 1);
  });

  testWidgets('showTotpCodeSheet returns true once the code is accepted', (
    tester,
  ) async {
    bool? result;
    await tester.pumpWidget(
      _host(
        Builder(
          builder: (context) => Scaffold(
            body: TextButton(
              onPressed: () async {
                result = await showTotpCodeSheet(
                  context,
                  onSubmit: (_) async {},
                );
              },
              child: const Text('open'),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open'));
    await tester.pumpAndSettle();
    expect(find.byType(TotpCodeForm), findsOneWidget);

    await tester.enterText(find.byType(EditableText), '123456');
    await tester.pumpAndSettle();

    expect(result, isTrue);
    expect(find.byType(TotpCodeForm), findsNothing);
  });
}
