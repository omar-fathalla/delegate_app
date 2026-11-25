// TAS-207: a staff account with TOTP two-step verification must reach the
// code step instead of looking like a wrong password.
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
import 'package:delegate_app/features/auth/data/datasources/totp_mfa.dart';
import 'package:delegate_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/mfa_required_failure.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_all_delegates.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:firebase_auth_mocks/firebase_auth_mocks.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class _FakeAssertion extends Fake implements MultiFactorAssertion {}

class _FakeCredential extends Fake implements UserCredential {}

class _FakeResolver extends Fake implements MultiFactorResolver {
  _FakeResolver(this.hints);

  @override
  final List<MultiFactorInfo> hints;
  final String acceptedCode = '123456';
  String? lastCode;
  int resolveCalls = 0;

  @override
  Future<UserCredential> resolveSignIn(MultiFactorAssertion assertion) async {
    resolveCalls++;
    if (lastCode != acceptedCode) {
      throw FirebaseAuthException(code: 'invalid-verification-code');
    }
    return _FakeCredential();
  }
}

class _FakeMfaException extends Fake
    implements FirebaseAuthMultiFactorException {
  _FakeMfaException(this.resolver);

  @override
  final MultiFactorResolver resolver;

  @override
  String get code => 'multi-factor-auth-required';
}

class _MfaAuth extends MockFirebaseAuth {
  _MfaAuth(this.resolver);

  final MultiFactorResolver resolver;

  @override
  Future<UserCredential> signInWithEmailAndPassword({
    required String email,
    required String password,
  }) async {
    throw _FakeMfaException(resolver);
  }
}

class _FakeStaffLookup implements StaffPhoneLookupApi {
  @override
  Future<StaffPhoneProfile?> lookup(String phone) async => StaffPhoneProfile(
    uid: 'super-uid',
    role: 'super_admin',
    email: 'super@example.com',
    displayName: 'Super Admin',
    phoneNumber: '01500000001',
  );
}

class _MockRemote extends Mock implements AuthRemoteDataSource {}

class _MockLocal extends Mock implements AuthLocalDataSource {}

class _MockRepository extends Mock implements AuthRepository {}

class _MockLogin extends Mock implements Login {}

class _MockCheckAutoLogin extends Mock implements CheckAutoLogin {}

class _MockLogout extends Mock implements Logout {}

class _MockCacheDelegate extends Mock implements CacheDelegate {}

class _MockCacheAllDelegates extends Mock implements CacheAllDelegates {}

class _FakeLoginParams extends Fake implements LoginParams {}

class _FakeNoParams extends Fake implements NoParams {}

const _totp = MultiFactorInfo(
  factorId: 'totp',
  enrollmentTimestamp: 0,
  displayName: 'TOTP',
  uid: 'totp-enrollment-1',
);

const _sms = MultiFactorInfo(
  factorId: 'phone',
  enrollmentTimestamp: 0,
  displayName: 'SMS',
  uid: 'sms-enrollment-1',
);

Delegate _staff({String uid = 'super-uid'}) => Delegate(
  uid: uid,
  firstName: 'Super',
  middleName: '',
  lastName: 'Admin',
  fullName: 'Super Admin',
  nationalityID: '__firebase_auth__:super@example.com',
  email: 'super@example.com',
  motherName: '',
  city: '',
  phoneNumber: '01500000001',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990, 1, 1),
  organizationUID: '',
  organizationName: '',
  companyUID: '',
  companyName: '',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2024, 1, 1),
  createdBy: 'system_admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.superAdmin,
);

void main() {
  setUpAll(() {
    registerFallbackValue(_FakeLoginParams());
    registerFallbackValue(_FakeNoParams());
    registerFallbackValue(const LogoutParams());
    registerFallbackValue(_staff());
    registerFallbackValue(<Delegate>[]);
  });

  group('AuthRemoteDataSource.verifyAdminPassword (TAS-207)', () {
    late _FakeResolver resolver;
    late List<String> assertedFor;
    late AuthRemoteDataSourceImpl source;

    setUp(() {
      resolver = _FakeResolver(const [_totp]);
      assertedFor = [];
      source = AuthRemoteDataSourceImpl(
        firestore: FakeFirebaseFirestore(),
        firebaseAuth: _MfaAuth(resolver),
        staffPhoneLookupApi: _FakeStaffLookup(),
        totpSignInAssertion: (enrollmentId, code) async {
          assertedFor.add(enrollmentId);
          resolver.lastCode = code;
          return _FakeAssertion();
        },
      );
    });

    test('throws MfaRequiredFailure instead of returning false', () async {
      await expectLater(
        source.verifyAdminPassword('super@example.com', 'right-password'),
        throwsA(
          isA<MfaRequiredFailure>().having(
            (f) => f.code,
            'code',
            'mfa_required',
          ),
        ),
      );
    });

    test('verifyPhonePassword passes the MFA failure up too', () async {
      await expectLater(
        source.verifyPhonePassword('01500000001', 'right-password'),
        throwsA(isA<MfaRequiredFailure>()),
      );
    });

    test('resolve signs in with the TOTP hint and the typed code', () async {
      MfaRequiredFailure? failure;
      try {
        await source.verifyAdminPassword('super@example.com', 'pw');
      } on MfaRequiredFailure catch (f) {
        failure = f;
      }
      await failure!.resolve(' 123456 ');
      expect(assertedFor, ['totp-enrollment-1']);
      expect(resolver.lastCode, '123456');
      expect(resolver.resolveCalls, 1);
    });

    test(
      'a wrong code throws an Arabic AuthFailure and can be retried',
      () async {
        MfaRequiredFailure? failure;
        try {
          await source.verifyAdminPassword('super@example.com', 'pw');
        } on MfaRequiredFailure catch (f) {
          failure = f;
        }
        await expectLater(
          failure!.resolve('000000'),
          throwsA(
            isA<AuthFailure>()
                .having((f) => f.code, 'code', 'invalid_mfa_code')
                .having((f) => f.message, 'message', totpInvalidCodeMessage),
          ),
        );
        await failure.resolve('123456');
        expect(resolver.resolveCalls, 2);
      },
    );

    test('an account with only an SMS factor gets mfa_unsupported', () async {
      final smsOnly = AuthRemoteDataSourceImpl(
        firestore: FakeFirebaseFirestore(),
        firebaseAuth: _MfaAuth(_FakeResolver(const [_sms])),
      );
      await expectLater(
        smsOnly.verifyAdminPassword('super@example.com', 'pw'),
        throwsA(
          isA<AuthFailure>().having((f) => f.code, 'code', 'mfa_unsupported'),
        ),
      );
    });
  });

  group('totpErrorMessage', () {
    test('maps Firebase codes to Arabic messages', () {
      expect(
        totpErrorMessage('invalid-verification-code'),
        totpInvalidCodeMessage,
      );
      expect(totpErrorMessage('session-expired'), totpSessionExpiredMessage);
      expect(totpErrorMessage('requires-recent-login'), totpRecentLoginMessage);
      expect(totpErrorMessage('network-request-failed'), totpGenericMessage);
    });
  });

  group('AuthRepositoryImpl.verifyAdminPassword (TAS-207)', () {
    test('maps the MFA failure to Left', () async {
      final remote = _MockRemote();
      final failure = MfaRequiredFailure(resolve: (_) async {});
      when(() => remote.verifyAdminPassword(any(), any())).thenThrow(failure);
      final repo = AuthRepositoryImpl(
        remoteDataSource: remote,
        localDataSource: _MockLocal(),
      );

      final result = await repo.verifyAdminPassword('a@b.c', 'pw');

      expect(result, Left<Failure, bool>(failure));
    });
  });

  group('Login use case, staff mode (TAS-207)', () {
    late _MockRepository repo;
    late Login login;
    final staff = _staff();

    setUp(() {
      repo = _MockRepository();
      login = Login(repo);
      when(
        () => repo.getDelegatesByPhone(any()),
      ).thenAnswer((_) async => Right([staff]));
    });

    test(
      'returns MfaRequiredFailure carrying the matched staff profile',
      () async {
        Future<void> resolve(String _) async {}
        when(
          () => repo.verifyAdminPassword(any(), any()),
        ).thenAnswer((_) async => Left(MfaRequiredFailure(resolve: resolve)));

        final result = await login(
          const LoginParams(
            phoneNumber: '01500000001',
            password: 'pw',
            mode: LoginMode.staff,
          ),
        );

        final failure = result.fold((f) => f, (_) => null);
        expect(failure, isA<MfaRequiredFailure>());
        final mfa = failure! as MfaRequiredFailure;
        expect(mfa.pendingDelegates, [staff]);
        expect(mfa.resolve, same(resolve));
        verifyNever(() => repo.cacheDelegate(any()));
      },
    );

    test('mfa_unsupported is shown as is, not as a wrong password', () async {
      when(() => repo.verifyAdminPassword(any(), any())).thenAnswer(
        (_) async =>
            const Left(AuthFailure(mfaUnsupportedMessage, mfaUnsupportedCode)),
      );

      final result = await login(
        const LoginParams(
          phoneNumber: '01500000001',
          password: 'pw',
          mode: LoginMode.staff,
        ),
      );

      expect(
        result,
        const Left<Failure, List<Delegate>>(
          AuthFailure(mfaUnsupportedMessage, mfaUnsupportedCode),
        ),
      );
    });

    test('other verify failures still read as a wrong password', () async {
      when(
        () => repo.verifyAdminPassword(any(), any()),
      ).thenAnswer((_) async => const Left(ServerFailure('boom')));

      final result = await login(
        const LoginParams(
          phoneNumber: '01500000001',
          password: 'pw',
          mode: LoginMode.staff,
        ),
      );

      expect(
        result.fold((f) => (f as AuthFailure).code, (_) => null),
        'invalid_credentials',
      );
    });
  });

  group('AuthBloc TOTP step (TAS-207)', () {
    late _MockLogin mockLogin;
    late _MockLogout mockLogout;
    late _MockCacheAllDelegates cacheAll;
    final staff = _staff();
    final challenge = MfaRequiredFailure(
      resolve: (_) async {},
      pendingDelegates: [staff],
    );

    AuthBloc build() {
      final cacheOne = _MockCacheDelegate();
      when(() => cacheOne(any())).thenAnswer((_) async => const Right(null));
      return AuthBloc(
        loginUseCase: mockLogin,
        checkAutoLoginUseCase: _MockCheckAutoLogin(),
        logoutUseCase: mockLogout,
        cacheDelegateUseCase: cacheOne,
        cacheAllDelegatesUseCase: cacheAll,
      );
    }

    setUp(() {
      DelegateOtpConfig.enabled = false;
      mockLogin = _MockLogin();
      mockLogout = _MockLogout();
      cacheAll = _MockCacheAllDelegates();
      when(() => cacheAll(any())).thenAnswer((_) async => const Right(null));
      when(() => mockLogout(any())).thenAnswer((_) async => const Right(null));
      when(() => mockLogin(any())).thenAnswer((_) async => Left(challenge));
      when(() => mockLogin.resolveSignedInStaff(any(), any())).thenAnswer(
        (inv) async => Right(inv.positionalArguments[1] as List<Delegate>),
      );
    });

    const request = LoginRequested(
      phoneNumber: '01500000001',
      password: 'pw',
      rememberMe: true,
      mode: LoginMode.staff,
    );

    blocTest<AuthBloc, AuthState>(
      'asks for the TOTP code instead of showing an error',
      build: build,
      act: (bloc) => bloc.add(request),
      expect: () => [
        AuthLoading(),
        AuthMfaRequired(challenge: challenge, rememberMe: true),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'continues the staff login after the code is accepted',
      build: build,
      act: (bloc) async {
        bloc.add(request);
        await bloc.stream.firstWhere((s) => s is AuthMfaRequired);
        bloc.add(const MfaVerified());
      },
      expect: () => [
        AuthLoading(),
        isA<AuthMfaRequired>(),
        AuthAuthenticated(delegate: staff),
      ],
      verify: (_) {
        verify(() => cacheAll([staff])).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'cancel signs out and returns to the password form',
      build: build,
      act: (bloc) async {
        bloc.add(request);
        await bloc.stream.firstWhere((s) => s is AuthMfaRequired);
        bloc.add(const MfaCancelled());
      },
      expect: () => [
        AuthLoading(),
        isA<AuthMfaRequired>(),
        const AuthUnauthenticated(fromLogout: true),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
      },
    );

    // TAS-314: the pending profile is the email-only placeholder.
    final placeholder = _staff(uid: '');
    final placeholderChallenge = MfaRequiredFailure(
      resolve: (_) async {},
      pendingDelegates: [placeholder],
    );

    blocTest<AuthBloc, AuthState>(
      'TAS-314: loads the full profile after the code, then continues',
      build: () {
        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Left(placeholderChallenge));
        when(
          () => mockLogin.resolveSignedInStaff('01500000001', [placeholder]),
        ).thenAnswer((_) async => Right([staff]));
        return build();
      },
      act: (bloc) async {
        bloc.add(request);
        await bloc.stream.firstWhere((s) => s is AuthMfaRequired);
        bloc.add(const MfaVerified());
      },
      expect: () => [
        AuthLoading(),
        isA<AuthMfaRequired>(),
        AuthAuthenticated(delegate: staff),
      ],
      verify: (_) {
        verify(() => cacheAll([staff])).called(1);
        verifyNever(() => cacheAll([placeholder]));
      },
    );

    blocTest<AuthBloc, AuthState>(
      'TAS-314: signs out when the full profile cannot be loaded',
      build: () {
        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Left(placeholderChallenge));
        when(() => mockLogin.resolveSignedInStaff(any(), any())).thenAnswer(
          (_) async => const Left(AuthFailure('x', 'profile_unavailable')),
        );
        return build();
      },
      act: (bloc) async {
        bloc.add(request);
        await bloc.stream.firstWhere((s) => s is AuthMfaRequired);
        bloc.add(const MfaVerified());
      },
      expect: () => [
        AuthLoading(),
        isA<AuthMfaRequired>(),
        const AuthError(message: 'x', code: 'profile_unavailable'),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
        verifyNever(() => cacheAll(any()));
      },
    );
  });

  group('Login use case, email-only lookup (TAS-314)', () {
    late _MockRepository repo;
    late Login login;
    final full = _staff();
    final placeholder = _staff(uid: '');
    const params = LoginParams(
      phoneNumber: '01500000001',
      password: 'pw',
      mode: LoginMode.staff,
    );

    setUp(() {
      repo = _MockRepository();
      login = Login(repo);
      when(
        () => repo.verifyAdminPassword(any(), any()),
      ).thenAnswer((_) async => const Right(true));
    });

    test('placeholder is recognised; full profiles are not', () {
      expect(Login.isPendingStaffProfile(placeholder), isTrue);
      expect(Login.isPendingStaffProfile(full), isFalse);
    });

    test('asks again after sign-in and returns the full profile', () async {
      var calls = 0;
      when(() => repo.getDelegatesByPhone(any())).thenAnswer((_) async {
        calls++;
        return Right(calls == 1 ? [placeholder] : [full]);
      });

      final result = await login(params);

      expect(result.fold((_) => null, (d) => d), [full]);
      expect(calls, 2);
      verify(
        () => repo.verifyAdminPassword('super@example.com', 'pw'),
      ).called(1);
    });

    test('an older server (full profile first) needs no second call', () async {
      when(
        () => repo.getDelegatesByPhone(any()),
      ).thenAnswer((_) async => Right([full]));

      final result = await login(params);

      expect(result.fold((_) => null, (d) => d), [full]);
      verify(() => repo.getDelegatesByPhone(any())).called(1);
    });

    test(
      'fails with profile_unavailable when the second answer is still email-only',
      () async {
        when(
          () => repo.getDelegatesByPhone(any()),
        ).thenAnswer((_) async => Right([placeholder]));

        final result = await login(params);

        expect(
          result.fold((f) => (f as AuthFailure).code, (_) => null),
          'profile_unavailable',
        );
        verifyNever(() => repo.cacheDelegate(any()));
      },
    );

    test('wrong password never triggers the second lookup', () async {
      when(
        () => repo.getDelegatesByPhone(any()),
      ).thenAnswer((_) async => Right([placeholder]));
      when(
        () => repo.verifyAdminPassword(any(), any()),
      ).thenAnswer((_) async => const Right(false));

      final result = await login(params);

      expect(
        result.fold((f) => (f as AuthFailure).code, (_) => null),
        'invalid_credentials',
      );
      verify(() => repo.getDelegatesByPhone(any())).called(1);
    });
  });
}
