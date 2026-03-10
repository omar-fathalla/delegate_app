import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockLogin extends Mock implements Login {}

class MockCheckAutoLogin extends Mock implements CheckAutoLogin {}

class MockLogout extends Mock implements Logout {}

class FakeLoginParams extends Fake implements LoginParams {}

class FakeNoParams extends Fake implements NoParams {}

void main() {
  late AuthBloc authBloc;
  late MockLogin mockLogin;
  late MockCheckAutoLogin mockCheckAutoLogin;
  late MockLogout mockLogout;

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
  });

  setUp(() {
    mockLogin = MockLogin();
    mockCheckAutoLogin = MockCheckAutoLogin();
    mockLogout = MockLogout();
    authBloc = AuthBloc(
      loginUseCase: mockLogin,
      checkAutoLoginUseCase: mockCheckAutoLogin,
      logoutUseCase: mockLogout,
    );
  });

  tearDown(() {
    authBloc.close();
  });

  test('initial state should be AuthInitial', () {
    expect(authBloc.state, AuthInitial());
  });

  group('LoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when login succeeds',
      build: () {
        when(() => mockLogin(any())).thenAnswer(
          (_) async => Right(tDelegate),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(
        const LoginRequested(
          phoneNumber: '01234567890',
          password: 'testPass',
        ),
      ),
      expect: () => [
        AuthLoading(),
        AuthAuthenticated(delegate: tDelegate),
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
        const LoginRequested(
          phoneNumber: '01234567890',
          password: 'wrong',
        ),
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
        const LoginRequested(
          phoneNumber: '01234567890',
          password: 'wrongPass',
        ),
      ),
      expect: () => [
        AuthLoading(),
        const AuthError(message: 'كلمة المرور غير صحيحة'),
      ],
    );
  });

  group('CheckAutoLoginRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthAuthenticated] when cached delegate found',
      build: () {
        when(() => mockCheckAutoLogin(any())).thenAnswer(
          (_) async => Right(tDelegate),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        AuthLoading(),
        AuthAuthenticated(delegate: tDelegate),
      ],
    );

    blocTest<AuthBloc, AuthState>(
      'emits [AuthLoading, AuthUnauthenticated] when no cached delegate',
      build: () {
        when(() => mockCheckAutoLogin(any())).thenAnswer(
          (_) async => const Right(null),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(CheckAutoLoginRequested()),
      expect: () => [
        AuthLoading(),
        AuthUnauthenticated(),
      ],
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
      expect: () => [
        AuthLoading(),
        AuthUnauthenticated(),
      ],
    );
  });

  group('LogoutRequested', () {
    blocTest<AuthBloc, AuthState>(
      'emits [AuthUnauthenticated] when logout is requested',
      build: () {
        when(() => mockLogout(any())).thenAnswer(
          (_) async => const Right(null),
        );
        return authBloc;
      },
      act: (bloc) => bloc.add(LogoutRequested()),
      expect: () => [
        AuthUnauthenticated(),
      ],
      verify: (_) {
        verify(() => mockLogout(any())).called(1);
      },
    );
  });
}
