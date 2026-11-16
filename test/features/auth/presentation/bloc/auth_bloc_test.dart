import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_all_delegates.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLogin extends Mock implements Login {}

class MockCheckAutoLogin extends Mock implements CheckAutoLogin {}

class MockLogout extends Mock implements Logout {}

class MockCacheDelegate extends Mock implements CacheDelegate {}

class MockCacheAllDelegates extends Mock implements CacheAllDelegates {}

class FakeLoginParams extends Fake implements LoginParams {}

class FakeNoParams extends Fake implements NoParams {}

void main() {
  late AuthBloc authBloc;
  late MockLogin mockLogin;
  late MockCheckAutoLogin mockCheckAutoLogin;
  late MockLogout mockLogout;
  late MockCacheDelegate mockCacheDelegate;
  late MockCacheAllDelegates mockCacheAllDelegates;

  final tDelegate = Delegate(
    uid: '1',
    firstName: 'Test',
    middleName: 'User',
    lastName: 'Name',
    fullName: 'Test User Name',
    nationalityID: 'testPass',
    motherName: 'Mother',
    city: 'Cairo',
    phoneNumber: '01234567890',
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

  setUpAll(() {
    registerFallbackValue(FakeLoginParams());
    registerFallbackValue(FakeNoParams());
    registerFallbackValue(const LogoutParams());
    registerFallbackValue(
      Delegate(
        uid: 'fake',
        firstName: 'fake',
        middleName: 'fake',
        lastName: 'fake',
        fullName: 'fake',
        nationalityID: 'fake',
        motherName: 'fake',
        city: 'fake',
        phoneNumber: 'fake',
        gender: DelegateGender.male,
        position: DelegatePosition.promoter,
        birthDate: DateTime(2000, 1, 1),
        organizationUID: 'fake',
        organizationName: 'fake',
        companyUID: 'fake',
        companyName: 'fake',
        status: DelegateStatus.active,
        delegatePublicId: 'fake',
        allReceiptCodes: const [],
        createdAt: DateTime.now(),
        createdBy: 'fake',
        hasPendingUpdate: false,
        isDeductedFromCompany: false,
        isPrinted: false,
        isProfileComplete: true,
        numberOfDocuments: 0,
        paymentAmount: 0,
        version: 1,
        documents: const [],
      ),
    );
  });

  setUp(() {
    DelegateOtpConfig.enabled = false;
    mockLogin = MockLogin();
    mockCheckAutoLogin = MockCheckAutoLogin();
    mockLogout = MockLogout();
    mockCacheDelegate = MockCacheDelegate();
    mockCacheAllDelegates = MockCacheAllDelegates();

    // Setup default return values for mocks
    when(
      () => mockCacheDelegate(any()),
    ).thenAnswer((_) async => const Right(null));
    when(
      () => mockCacheAllDelegates(any()),
    ).thenAnswer((_) async => const Right(null));

    authBloc = AuthBloc(
      loginUseCase: mockLogin,
      checkAutoLoginUseCase: mockCheckAutoLogin,
      logoutUseCase: mockLogout,
      cacheDelegateUseCase: mockCacheDelegate,
      cacheAllDelegatesUseCase: mockCacheAllDelegates,
    );
  });

  tearDown(() {
    DelegateOtpConfig.enabled = false;
    WebRuntimePolicy.debugReset();
    authBloc.close();
  });

  test('initial state should be AuthInitial', () {
    expect(authBloc.state, AuthInitial());
  });

  group('LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when login succeeds with single delegate',
      build: () {
        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Right([tDelegate]));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(phoneNumber: '01234567890', password: 'testPass'),
      ),
      expect: () => [AuthLoading(), AuthAuthenticated(delegate: tDelegate)],
      verify: (_) {
        verify(() => mockLogin(any())).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] directly when multiple accounts belong to the SAME organization',
      build: () {
        final tDelegateSameOrg = Delegate(
          uid: '2',
          firstName: 'Test2',
          middleName: 'User',
          lastName: 'Name',
          fullName: 'Test User Name 2',
          nationalityID: 'testPass',
          motherName: 'Mother',
          city: 'Cairo',
          phoneNumber: '01234567890',
          gender: DelegateGender.male,
          position: DelegatePosition.promoter,
          birthDate: DateTime(1990, 1, 1),
          organizationUID: 'org1',
          organizationName: 'Org',
          companyUID: 'comp2',
          companyName: 'Comp 2',
          status: DelegateStatus.active,
          delegatePublicId: 'DEL-2',
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

        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Right([tDelegate, tDelegateSameOrg]));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(phoneNumber: '01234567890', password: 'testPass'),
      ),
      expect: () => [AuthLoading(), AuthAuthenticated(delegate: tDelegate)],
      verify: (_) {
        verify(() => mockLogin(any())).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthOrganizationSelectionRequired] when accounts belong to DIFFERENT organizations',
      build: () {
        final tDelegateDiffOrg = Delegate(
          uid: '3',
          firstName: 'Test3',
          middleName: 'User',
          lastName: 'Name',
          fullName: 'Test User Name 3',
          nationalityID: 'testPass',
          motherName: 'Mother',
          city: 'Cairo',
          phoneNumber: '01234567890',
          gender: DelegateGender.male,
          position: DelegatePosition.promoter,
          birthDate: DateTime(1990, 1, 1),
          organizationUID: 'org2',
          organizationName: 'Org 2',
          companyUID: 'comp3',
          companyName: 'Comp 3',
          status: DelegateStatus.active,
          delegatePublicId: 'DEL-3',
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

        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Right([tDelegate, tDelegateDiffOrg]));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(
          phoneNumber: '01234567890',
          password: 'testPass',
          rememberMe: true,
        ),
      ),
      expect: () => [
        AuthLoading(),
        isA<AuthOrganizationSelectionRequired>()
            .having((s) => s.delegates.length, 'distinct delegates length', 2)
            .having((s) => s.rememberMe, 'rememberMe', true),
      ],
      verify: (_) {
        verify(() => mockLogin(any())).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when login fails',
      build: () {
        when(() => mockLogin(any())).thenAnswer(
          (_) async => const Left(ServerFailure('فشل تسجيل الدخول')),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(phoneNumber: '01234567890', password: 'wrong'),
      ),
      expect: () => [
        AuthLoading(),
        const AuthError(message: 'فشل تسجيل الدخول'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthError] when password is incorrect',
      build: () {
        when(() => mockLogin(any())).thenAnswer(
          (_) async => const Left(AuthFailure('كلمة المرور غير صحيحة')),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(phoneNumber: '01234567890', password: 'wrongPass'),
      ),
      expect: () => [
        AuthLoading(),
        const AuthError(message: 'كلمة المرور غير صحيحة'),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'asks for a phone code after delegate login when otp is enabled',
      build: () {
        DelegateOtpConfig.enabled = true;
        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Right([tDelegate]));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(
          phoneNumber: '01211857725',
          password: '29712200201981',
          rememberMe: true,
        ),
      ),
      expect: () => [
        AuthLoading(),
        AuthPhoneOtpRequired(
          delegates: [tDelegate],
          rememberMe: true,
          e164Phone: '+201211857725',
        ),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'continues the delegate session only after the phone code is confirmed',
      build: () {
        DelegateOtpConfig.enabled = true;
        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Right([tDelegate]));
        return authBloc;
      },
      act: (bloc) async {
        bloc.add(
          const LoginRequested(
            phoneNumber: '01234567890',
            password: 'testPass',
          ),
        );
        await bloc.stream.firstWhere((state) => state is AuthPhoneOtpRequired);
        bloc.add(const PhoneOtpVerified());
      },
      expect: () => [
        AuthLoading(),
        isA<AuthPhoneOtpRequired>().having(
          (state) => state.e164Phone,
          'e164',
          '+201234567890',
        ),
        AuthAuthenticated(delegate: tDelegate),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'signs out the custom token when the phone step is cancelled',
      build: () {
        DelegateOtpConfig.enabled = true;
        when(
          () => mockLogin(any()),
        ).thenAnswer((_) async => Right([tDelegate]));
        when(
          () => mockLogout(any()),
        ).thenAnswer((_) async => const Right(null));
        return authBloc;
      },
      act: (bloc) async {
        bloc.add(
          const LoginRequested(
            phoneNumber: '01234567890',
            password: 'testPass',
          ),
        );
        await bloc.stream.firstWhere((state) => state is AuthPhoneOtpRequired);
        bloc.add(const PhoneOtpCancelled());
      },
      expect: () => [
        AuthLoading(),
        isA<AuthPhoneOtpRequired>(),
        const AuthUnauthenticated(fromLogout: true),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'does not ask staff or super-admin password logins for a phone code',
      build: () {
        DelegateOtpConfig.enabled = true;
        final staff = Delegate(
          uid: 'staff',
          firstName: 'Omar',
          middleName: '',
          lastName: 'Fathalla',
          fullName: 'Omar Fathalla',
          nationalityID: '__firebase_auth__:omar@example.com',
          motherName: '',
          city: '',
          phoneNumber: '01508899965',
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
        when(() => mockLogin(any())).thenAnswer((_) async => Right([staff]));
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(phoneNumber: '01508899965', password: 'secret'),
      ),
      expect: () => [
        AuthLoading(),
        isA<AuthAuthenticated>().having(
          (state) => state.delegate.role,
          'role',
          UserRole.superAdmin,
        ),
      ],
    );
  });

  group('CheckAutoLoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when cached delegate found',
      build: () {
        when(
          () => mockCheckAutoLogin(any()),
        ).thenAnswer((_) async => Right(tDelegate));
        return authBloc;
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [AuthLoading(), AuthAuthenticated(delegate: tDelegate)],
    );

    blocTest<AuthBloc, AuthState>(
      'on web, signs out a cached delegate and shows the app-only message',
      setUp: () {
        WebRuntimePolicy.debugIsWebOverride = true;
        when(
          () => mockLogout(any()),
        ).thenAnswer((_) async => const Right(null));
        when(
          () => mockCheckAutoLogin(any()),
        ).thenAnswer((_) async => Right(tDelegate));
      },
      build: () => authBloc,
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        AuthLoading(),
        const AuthUnauthenticated(
          message: WebRuntimePolicy.delegateLoginWebMessage,
        ),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
      },
    );

    blocTest<AuthBloc, AuthState>(
      'on web, a cached staff session still signs in',
      setUp: () {
        WebRuntimePolicy.debugIsWebOverride = true;
        when(() => mockCheckAutoLogin(any())).thenAnswer(
          (_) async => Right(
            Delegate(
              uid: tDelegate.uid,
              firstName: tDelegate.firstName,
              middleName: tDelegate.middleName,
              lastName: tDelegate.lastName,
              fullName: tDelegate.fullName,
              nationalityID: tDelegate.nationalityID,
              motherName: tDelegate.motherName,
              city: tDelegate.city,
              phoneNumber: tDelegate.phoneNumber,
              gender: tDelegate.gender,
              position: tDelegate.position,
              birthDate: tDelegate.birthDate,
              organizationUID: tDelegate.organizationUID,
              organizationName: tDelegate.organizationName,
              companyUID: tDelegate.companyUID,
              companyName: tDelegate.companyName,
              status: tDelegate.status,
              delegatePublicId: tDelegate.delegatePublicId,
              allReceiptCodes: tDelegate.allReceiptCodes,
              createdAt: tDelegate.createdAt,
              createdBy: tDelegate.createdBy,
              hasPendingUpdate: tDelegate.hasPendingUpdate,
              isDeductedFromCompany: tDelegate.isDeductedFromCompany,
              isPrinted: tDelegate.isPrinted,
              isProfileComplete: tDelegate.isProfileComplete,
              numberOfDocuments: tDelegate.numberOfDocuments,
              paymentAmount: tDelegate.paymentAmount,
              version: tDelegate.version,
              documents: tDelegate.documents,
              role: UserRole.admin,
            ),
          ),
        );
      },
      build: () => authBloc,
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        AuthLoading(),
        isA<AuthAuthenticated>().having(
          (state) => state.delegate.role,
          'role',
          UserRole.admin,
        ),
      ],
      verify: (_) {
        verifyNever(() => mockLogout(any()));
      },
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when no cached delegate',
      build: () {
        when(
          () => mockCheckAutoLogin(any()),
        ).thenAnswer((_) async => const Right(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [AuthLoading(), AuthUnauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when auto login fails',
      build: () {
        when(() => mockCheckAutoLogin(any())).thenAnswer(
          (_) async => const Left(CacheFailure('لا توجد بيانات مخزنة')),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [AuthLoading(), AuthUnauthenticated()],
    );

    blocTest<AuthBloc, AuthState>(
      'signs out an anonymous session, clears remember-me, and asks for a fresh sign-in',
      build: () {
        when(
          () => mockLogout(any()),
        ).thenAnswer((_) async => const Right(null));
        var anonymous = true;
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
          cacheDelegateUseCase: mockCacheDelegate,
          cacheAllDelegatesUseCase: mockCacheAllDelegates,
          isAnonymousSession: () => anonymous,
          signOutAuth: () async {
            anonymous = false;
          },
        );
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        AuthLoading(),
        const AuthUnauthenticated(message: AuthBloc.freshSignInMessage),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
        verifyNever(() => mockCheckAutoLogin(any()));
      },
    );

    late StreamController<bool> restoredAnonymous;
    blocTest<AuthBloc, AuthState>(
      'signs out when auth state restores an anonymous user',
      build: () {
        when(
          () => mockLogout(any()),
        ).thenAnswer((_) async => const Right(null));
        var anonymous = true;
        restoredAnonymous = StreamController<bool>();
        return AuthBloc(
          loginUseCase: mockLogin,
          checkAutoLoginUseCase: mockCheckAutoLogin,
          logoutUseCase: mockLogout,
          cacheDelegateUseCase: mockCacheDelegate,
          cacheAllDelegatesUseCase: mockCacheAllDelegates,
          isAnonymousSession: () => anonymous,
          signOutAuth: () async {
            anonymous = false;
          },
          anonymousSessionRestored: restoredAnonymous.stream,
        );
      },
      act: (bloc) => restoredAnonymous.add(true),
      tearDown: () => restoredAnonymous.close(),
      expect: () => [
        const AuthUnauthenticated(message: AuthBloc.freshSignInMessage),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
        verifyNever(() => mockCheckAutoLogin(any()));
      },
    );
  });

  group('LogoutRequested', () {
    // Logout emits AuthUnauthenticated(fromLogout: true) first (no AuthLoading)
    // so the UI can leave signed-in streams before signOut. The use case runs
    // after a 400ms delay, so these tests wait long enough to observe it.
    const logoutWait = Duration(milliseconds: 600);

    blocTest<AuthBloc, AuthState>(
      'emits logged-out and passes the user id to the logout use case',
      build: () {
        when(
          () => mockLogout(any()),
        ).thenAnswer((_) async => const Right(null));
        return authBloc;
      },
      act: (bloc) => bloc.add(const LogoutRequested(userId: 'uid-1')),
      wait: logoutWait,
      expect: () => [
        const AuthUnauthenticated(fromLogout: true),
      ],
      verify: (_) {
        final params =
            verify(() => mockLogout(captureAny())).captured.single
                as LogoutParams;
        expect(params.userId, 'uid-1');
      },
    );

    blocTest<AuthBloc, AuthState>(
      'still leaves the user logged out when sign-out throws',
      build: () {
        when(() => mockLogout(any())).thenThrow(Exception('offline'));
        return authBloc;
      },
      act: (bloc) => bloc.add(const LogoutRequested(userId: 'uid-1')),
      wait: logoutWait,
      expect: () => [
        const AuthUnauthenticated(fromLogout: true),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'does not restore the cached delegate or treat logout as an anonymous session',
      build: () {
        when(
          () => mockLogout(any()),
        ).thenAnswer((_) async => const Right(null));
        when(
          () => mockCheckAutoLogin(any()),
        ).thenAnswer((_) async => Right(tDelegate));
        return authBloc;
      },
      act: (bloc) async {
        bloc.add(const LogoutRequested(userId: '1'));
        await bloc.stream.firstWhere(
          (state) => state is AuthUnauthenticated && state.fromLogout,
        );
        bloc.add(CheckAutoLoginRequested());
        bloc.add(const AnonymousSessionDetected());
      },
      wait: logoutWait,
      expect: () => [
        const AuthUnauthenticated(fromLogout: true),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
        verifyNever(() => mockCheckAutoLogin(any()));
      },
    );
  });
}
