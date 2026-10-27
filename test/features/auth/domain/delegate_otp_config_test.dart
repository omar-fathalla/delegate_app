import 'dart:async';

import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

void main() {
  setUp(DelegateOtpConfig.debugReset);
  tearDown(DelegateOtpConfig.debugReset);

  group('resolveDelegateOtpEnabled', () {
    test('a compiled true beats a pin of false and a remote false', () {
      expect(
        resolveDelegateOtpEnabled(
          dartDefineForcesOn: true,
          pinned: false,
          remoteValue: false,
        ),
        isTrue,
      );
    });

    test('a pin beats the remote value when the define is off', () {
      expect(
        resolveDelegateOtpEnabled(
          dartDefineForcesOn: false,
          pinned: false,
          remoteValue: true,
        ),
        isFalse,
      );
      expect(
        resolveDelegateOtpEnabled(
          dartDefineForcesOn: false,
          pinned: true,
          remoteValue: false,
        ),
        isTrue,
      );
    });

    test('uses the remote value when nothing is pinned', () {
      expect(
        resolveDelegateOtpEnabled(
          dartDefineForcesOn: false,
          pinned: null,
          remoteValue: true,
        ),
        isTrue,
      );
      expect(
        resolveDelegateOtpEnabled(
          dartDefineForcesOn: false,
          pinned: null,
          remoteValue: false,
        ),
        isFalse,
      );
    });
  });

  group('DelegateOtpConfig', () {
    test('stays off until a source is installed', () {
      expect(DelegateOtpConfig.enabled, isFalse);
    });

    test('reads the installed source at call time', () async {
      final source = _FakeFlagSource(false);
      await DelegateOtpConfig.refreshFromRemoteConfig(source: source);
      expect(DelegateOtpConfig.enabled, isFalse);

      source.value = true;
      expect(DelegateOtpConfig.enabled, isTrue);
      expect(delegateLoginNeedsPhoneOtp([_profile()]), isTrue);

      source.value = false;
      expect(delegateLoginNeedsPhoneOtp([_profile()]), isFalse);
    });

    test('a test pin hides the remote value', () async {
      await DelegateOtpConfig.refreshFromRemoteConfig(
        source: _FakeFlagSource(true),
      );
      DelegateOtpConfig.enabled = false;
      expect(DelegateOtpConfig.enabled, isFalse);
      expect(delegateLoginNeedsPhoneOtp([_profile()]), isFalse);
    });

    test('a failed fetch does not throw and leaves the flag off', () async {
      await DelegateOtpConfig.refreshFromRemoteConfig(
        source: _FakeFlagSource(true, failPrepare: true),
      );
      expect(DelegateOtpConfig.enabled, isFalse);
    });

    test('a hung fetch times out and leaves the flag off', () async {
      await DelegateOtpConfig.refreshFromRemoteConfig(
        source: _HangingFlagSource(),
        timeout: const Duration(milliseconds: 30),
      );
      expect(DelegateOtpConfig.enabled, isFalse);
    });

    test('a read error falls back to false', () async {
      await DelegateOtpConfig.refreshFromRemoteConfig(
        source: _FakeFlagSource(true, failRead: true),
      );
      expect(DelegateOtpConfig.enabled, isFalse);
      expect(delegateLoginNeedsPhoneOtp([_profile()]), isFalse);
    });
  });
}

class _FakeFlagSource implements DelegateOtpFlagSource {
  _FakeFlagSource(
    this.value, {
    this.failPrepare = false,
    this.failRead = false,
  });

  bool value;
  final bool failPrepare;
  final bool failRead;

  @override
  String get sourceName => 'valueRemote';

  @override
  Future<void> prepare() async {
    if (failPrepare) throw StateError('offline');
  }

  @override
  bool read() {
    if (failRead) throw StateError('unfetched');
    return value;
  }
}

class _HangingFlagSource implements DelegateOtpFlagSource {
  @override
  String get sourceName => 'valueStatic';

  @override
  Future<void> prepare() => Completer<void>().future;

  @override
  bool read() => true;
}

Delegate _profile() {
  return Delegate(
    uid: 'd1',
    firstName: 'Test',
    middleName: 'User',
    lastName: 'Name',
    fullName: 'Test User Name',
    nationalityID: '29712200201981',
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
