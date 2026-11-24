import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/phone_otp.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  group('normalizeEgyptianPhone', () {
    test('accepts the formats already stored for delegates', () {
      expect(normalizeEgyptianPhone('+20 123 456 7890'), '01234567890');
      expect(normalizeEgyptianPhone('00201234567890'), '01234567890');
      expect(normalizeEgyptianPhone('1234567890'), '01234567890');
      expect(normalizeEgyptianPhone('٠١٢٣٤٥٦٧٨٩٠'), '01234567890');
      expect(normalizeEgyptianPhone('01234567890'), '01234567890');
    });
  });

  group('validateLoginPhone', () {
    test('requires a value and an Egyptian mobile', () {
      expect(
        validateLoginPhone('', emptyMessage: 'empty', invalidMessage: 'bad'),
        'empty',
      );
      expect(
        validateLoginPhone('123', emptyMessage: 'empty', invalidMessage: 'bad'),
        'bad',
      );
      expect(
        validateLoginPhone(
          '+201234567890',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        isNull,
      );
    });
  });

  group('validateLoginSecret', () {
    test('requires a national ID and accepts a staff password', () {
      expect(
        validateLoginSecret(null, emptyMessage: 'empty', invalidMessage: 'bad'),
        'empty',
      );
      expect(
        validateLoginSecret(
          '123',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        'bad',
      );
      expect(
        validateLoginSecret(
          '29712200201981',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        isNull,
      );
      expect(
        validateLoginSecret(
          'StaffPass1',
          emptyMessage: 'empty',
          invalidMessage: 'bad',
        ),
        isNull,
      );
    });
  });

  test('phone variants include the international forms', () {
    final variants = egyptianPhoneVariants('01234567890');
    expect(variants, contains('01234567890'));
    expect(variants, contains('+201234567890'));
    expect(variants, contains('201234567890'));
  });

  group('egyptianPhoneToE164', () {
    test('prefixes +20 and drops the trunk zero', () {
      expect(egyptianPhoneToE164('01211857725'), '+201211857725');
      expect(egyptianPhoneToE164('+201211857725'), '+201211857725');
      expect(egyptianPhoneToE164('00201211857725'), '+201211857725');
      expect(egyptianPhoneToE164('1211857725'), '+201211857725');
    });

    test('rejects a number that is not an Egyptian mobile', () {
      expect(egyptianPhoneToE164('123'), isNull);
      expect(egyptianPhoneToE164(''), isNull);
    });
  });

  group('delegate phone otp gate', () {
    tearDown(() => DelegateOtpConfig.enabled = false);

    test('stays off unless the flag is enabled for a delegate session', () {
      final delegate = _profile('29712200201981');
      final staff = _profile('__firebase_auth__:staff@example.com');
      DelegateOtpConfig.enabled = false;
      expect(delegateLoginNeedsPhoneOtp([delegate]), isFalse);
      DelegateOtpConfig.enabled = true;
      expect(delegateLoginNeedsPhoneOtp([delegate]), isTrue);
      expect(delegateLoginNeedsPhoneOtp([staff]), isFalse);
      expect(delegateLoginNeedsPhoneOtp([delegate, staff]), isFalse);
    });

    test('maps link errors without switching accounts', () {
      expect(
        actionForLinkError('provider-already-linked'),
        PhoneOtpLinkAction.reauthenticate,
      );
      expect(
        actionForLinkError('credential-already-in-use'),
        PhoneOtpLinkAction.fail,
      );
      expect(
        failureForAuthCode('credential-already-in-use'),
        PhoneOtpLinkFailure.credentialAlreadyInUse,
      );
      expect(
        failureForAuthCode('invalid-verification-code'),
        PhoneOtpLinkFailure.invalidCode,
      );
      expect(
        failureForAuthCode('session-expired'),
        PhoneOtpLinkFailure.expired,
      );
      expect(
        messageForPhoneOtpFailure(PhoneOtpLinkFailure.credentialAlreadyInUse),
        phoneOtpAlreadyInUseMessage,
      );
    });
  });

  // TAS-112 (user decision 2026-11-24): UAE mobiles for login and OTP.
  group('UAE mobiles', () {
    test('every UAE form normalizes to 05xxxxxxxx', () {
      for (final raw in [
        '+971 50 123 4567',
        '00971501234567',
        '971501234567',
        '0501234567',
        '501234567',
        '+٩٧١٥٠١٢٣٤٥٦٧',
      ]) {
        expect(normalizeEgyptianPhone(raw), '0501234567', reason: raw);
      }
    });

    test('login accepts UAE and Egyptian mobiles only', () {
      String? v(String s) =>
          validateLoginPhone(s, emptyMessage: 'empty', invalidMessage: 'bad');
      expect(v('+971501234567'), isNull);
      expect(v('0501234567'), isNull);
      expect(v('01000000002'), isNull);
      expect(v('+966501234567'), 'bad');
      expect(v('0601234567'), 'bad');
    });

    test('OTP number and lookup variants', () {
      expect(egyptianPhoneToE164('0501234567'), '+971501234567');
      expect(egyptianPhoneToE164('01000000002'), '+201000000002');
      expect(egyptianPhoneToE164('0601234567'), isNull);
      expect(
        egyptianPhoneVariants('0501234567'),
        containsAll(['0501234567', '501234567', '971501234567', '+971501234567', '00971501234567']),
      );
    });
  });
}

Delegate _profile(String nationalityId) {
  return Delegate(
    uid: '1',
    firstName: 'Test',
    middleName: 'User',
    lastName: 'Name',
    fullName: 'Test User Name',
    nationalityID: nationalityId,
    motherName: 'Mother',
    city: 'Cairo',
    phoneNumber: '01211857725',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org1',
    organizationName: 'Org',
    companyUID: 'comp1',
    companyName: 'Comp',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-1',
    allReceiptCodes: const [],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: const [],
  );
}
