// TAS-207: «التحقق بخطوتين» in the profile is for super admins only, and
// the sheet enrolls TOTP through an injected client (no Firebase here).
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/totp_mfa.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/widgets/totp_enrollment_sheet.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:qr_flutter/qr_flutter.dart';

class _FakeEnrollment implements TotpEnrollmentClient {
  _FakeEnrollment({this.enrolled = false, this.startError});

  bool enrolled;
  final Failure? startError;
  final finished = <String>[];

  @override
  Future<bool> isEnrolled() async => enrolled;

  @override
  Future<TotpEnrollmentStart> start() async {
    final error = startError;
    if (error != null) throw error;
    return const TotpEnrollmentStart(
      secretKey: 'JBSWY3DPEHPK3PXP',
      qrCodeUrl:
          'otpauth://totp/Tashil:super@example.com?secret=JBSWY3DPEHPK3PXP&issuer=Tashil',
    );
  }

  @override
  Future<void> finish(String code) async {
    finished.add(code);
    if (code != '123456') {
      throw const AuthFailure(totpInvalidCodeMessage, 'invalid_mfa_code');
    }
    enrolled = true;
  }
}

Widget _host(Widget child) => MaterialApp(
  home: Scaffold(body: SingleChildScrollView(child: child)),
);

void main() {
  group('canEnrollTwoStep', () {
    test('super admin only', () {
      expect(canEnrollTwoStep(UserRole.superAdmin, null), isTrue);
      expect(canEnrollTwoStep(null, 'super-admin'), isTrue);
      expect(canEnrollTwoStep(null, 'super_admin'), isTrue);
      expect(
        canEnrollTwoStep(UserRole.technicalSupport, 'technical_support'),
        isFalse,
      );
      expect(
        canEnrollTwoStep(UserRole.organizationAdmin, 'organization_admin'),
        isFalse,
      );
      expect(canEnrollTwoStep(UserRole.admin, 'company_admin'), isFalse);
      expect(canEnrollTwoStep(UserRole.hr, 'hr'), isFalse);
      expect(canEnrollTwoStep(UserRole.delegate, null), isFalse);
      expect(canEnrollTwoStep(null, null), isFalse);
    });
  });

  testWidgets('the entry is shown for a super admin', (tester) async {
    await tester.pumpWidget(
      _host(
        TwoStepVerificationButton(
          role: UserRole.superAdmin,
          clientFactory: _FakeEnrollment.new,
        ),
      ),
    );
    expect(
      find.byKey(const ValueKey('two_step_verification_button')),
      findsOneWidget,
    );
    expect(find.text(twoStepTitle), findsOneWidget);
  });

  for (final role in [
    UserRole.technicalSupport,
    UserRole.organizationAdmin,
    UserRole.admin,
    UserRole.hr,
    UserRole.delegate,
  ]) {
    testWidgets('the entry is hidden for ${role.name}', (tester) async {
      await tester.pumpWidget(
        _host(TwoStepVerificationButton(role: role, rawRole: role.name)),
      );
      expect(
        find.byKey(const ValueKey('two_step_verification_button')),
        findsNothing,
      );
    });
  }

  testWidgets('enrolls: QR + secret, wrong code then right code', (
    tester,
  ) async {
    final client = _FakeEnrollment();
    await tester.pumpWidget(
      _host(
        TwoStepVerificationButton(
          role: UserRole.superAdmin,
          clientFactory: () => client,
        ),
      ),
    );

    await tester.tap(
      find.byKey(const ValueKey('two_step_verification_button')),
    );
    await tester.pumpAndSettle();

    expect(find.byType(QrImageView), findsOneWidget);
    expect(find.text('JBSWY3DPEHPK3PXP'), findsOneWidget);
    expect(find.byKey(const ValueKey('totp_copy_secret')), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, '000000');
    await tester.pumpAndSettle();
    expect(find.text(totpInvalidCodeMessage), findsOneWidget);

    await tester.enterText(find.byType(EditableText).last, '123456');
    await tester.pumpAndSettle();
    expect(client.finished, ['000000', '123456']);
    expect(client.enrolled, isTrue);
    expect(find.byKey(const ValueKey('totp_enrolled_message')), findsOneWidget);
  });

  testWidgets('an enrolled account sees the enabled state, no QR', (
    tester,
  ) async {
    await tester.pumpWidget(
      _host(
        TotpEnrollmentPanel(
          client: _FakeEnrollment(enrolled: true),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text('التحقق بخطوتين مفعّل على حسابك.'), findsOneWidget);
    expect(find.byType(QrImageView), findsNothing);
  });

  testWidgets('requires-recent-login shows a clear message', (tester) async {
    await tester.pumpWidget(
      _host(
        TotpEnrollmentPanel(
          client: _FakeEnrollment(
            startError: AuthFailure(
              totpErrorMessage('requires-recent-login'),
              'requires_recent_login',
            ),
          ),
          onClose: () {},
        ),
      ),
    );
    await tester.pumpAndSettle();

    expect(find.text(totpRecentLoginMessage), findsOneWidget);
    expect(find.byKey(const ValueKey('totp_enroll_retry')), findsOneWidget);
  });
}
