
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_all_delegates.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
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

class MockCacheDelegate extends Mock implements CacheDelegate {}

class MockCacheAllDelegates extends Mock implements CacheAllDelegates {}

class FakeNoParams extends Fake implements NoParams {}

const _ok = DeviceVerificationResult(status: DeviceVerificationStatus.bypassed);

void main() {
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
  final tStaff = Delegate(
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
    role: UserRole.hr,
  );

  late MockCheckAutoLogin checkAutoLogin;
  late MockLogout logout;

  setUpAll(() {
    registerFallbackValue(FakeNoParams());
    registerFallbackValue(const LogoutParams());
  });

  setUp(() {
    checkAutoLogin = MockCheckAutoLogin();
    logout = MockLogout();
    when(() => logout(any())).thenAnswer((_) async => const Right(null));
  });

  AuthBloc build({Future<bool> Function()? hasAuthUser}) => AuthBloc(
        loginUseCase: MockLogin(),
        checkAutoLoginUseCase: checkAutoLogin,
        logoutUseCase: logout,
        cacheDelegateUseCase: MockCacheDelegate(),
        cacheAllDelegatesUseCase: MockCacheAllDelegates(),
        hasAuthUser: hasAuthUser,
        sessionCheck: (_) async => const SessionVerificationResult.valid(),
        deviceCheck: (_) async => _ok,
      );

  Future<List<AuthState>> run(AuthBloc bloc) async {
    final states = <AuthState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(CheckAutoLoginRequested());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await sub.cancel();
    await bloc.close();
    return states;
  }

  group('auto-login without a Firebase user (TAS-287)', () {
    test('cached delegate with no Firebase user goes back to login', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final states = await run(build(hasAuthUser: () async => false));
      expect(
        states.last,
        const AuthUnauthenticated(message: AuthBloc.sessionLostMessage),
      );
      verify(() => logout(any())).called(1);
    });

    test('cached delegate with a Firebase user stays signed in', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final states = await run(build(hasAuthUser: () async => true));
      expect(states.last, AuthAuthenticated(delegate: tDelegate));
      verifyNever(() => logout(any()));
    });

    test('staff roles are not affected by the check', () async {
      final staff = tStaff;
      when(() => checkAutoLogin(any())).thenAnswer((_) async => Right(staff));
      final states = await run(build(hasAuthUser: () async => false));
      expect(states.last, AuthAuthenticated(delegate: staff));
      verifyNever(() => logout(any()));
    });

    test('no check wired keeps the old behaviour', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final states = await run(build());
      expect(states.last, AuthAuthenticated(delegate: tDelegate));
    });
  });
}
