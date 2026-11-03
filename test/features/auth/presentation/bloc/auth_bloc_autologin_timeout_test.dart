import 'dart:async';

import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
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

  late MockCheckAutoLogin checkAutoLogin;
  late MockLogout logout;
  final defaultTimeout = AuthBloc.autoLoginTimeout;

  setUpAll(() {
    registerFallbackValue(FakeNoParams());
    registerFallbackValue(const LogoutParams());
  });

  setUp(() {
    checkAutoLogin = MockCheckAutoLogin();
    logout = MockLogout();
    when(() => logout(any())).thenAnswer((_) async => const Right(null));
    AuthBloc.autoLoginTimeout = const Duration(milliseconds: 200);
  });

  tearDown(() => AuthBloc.autoLoginTimeout = defaultTimeout);

  AuthBloc build({
    required Future<SessionVerificationResult> Function(Delegate) session,
    Future<DeviceVerificationResult> Function(Delegate)? device,
  }) =>
      AuthBloc(
        loginUseCase: MockLogin(),
        checkAutoLoginUseCase: checkAutoLogin,
        logoutUseCase: logout,
        cacheDelegateUseCase: MockCacheDelegate(),
        cacheAllDelegatesUseCase: MockCacheAllDelegates(),
        sessionCheck: session,
        deviceCheck: device ?? (_) async => _ok,
      );

  Future<List<AuthState>> run(AuthBloc bloc) async {
    final states = <AuthState>[];
    final sub = bloc.stream.listen(states.add);
    bloc.add(CheckAutoLoginRequested());
    await Future<void>.delayed(const Duration(milliseconds: 500));
    await sub.cancel();
    await bloc.close();
    return states;
  }

  group('auto-login timeout fallback', () {
    test('hung session check keeps cached session, no logout', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final bloc = build(
        session: (_) => Completer<SessionVerificationResult>().future,
      );
      final states = await run(bloc);
      expect(states.last, AuthAuthenticated(delegate: tDelegate));
      verifyNever(() => logout(any()));
    });

    test('hung device check keeps cached session, no logout', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final bloc = build(
        session: (_) async => const SessionVerificationResult.valid(),
        device: (_) => Completer<DeviceVerificationResult>().future,
      );
      final states = await run(bloc);
      expect(states.last, AuthAuthenticated(delegate: tDelegate));
      verifyNever(() => logout(any()));
    });

    test('hung cache read with no delegate goes to Unauthenticated', () async {
      when(() => checkAutoLogin(any())).thenAnswer(
        (_) => Completer<Either<Failure, Delegate?>>().future,
      );
      final bloc = build(
        session: (_) async => const SessionVerificationResult.valid(),
      );
      final states = await run(bloc);
      expect(states.last, const AuthUnauthenticated());
      verifyNever(() => logout(any()));
    });

    test('late invalid result after timeout does not log out', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final bloc = build(
        session: (_) async {
          await Future<void>.delayed(const Duration(milliseconds: 300));
          return const SessionVerificationResult.invalid(reason: 'x');
        },
      );
      final states = await run(bloc);
      expect(states.last, AuthAuthenticated(delegate: tDelegate));
      verifyNever(() => logout(any()));
    });

    test('fast invalid session still logs out (unchanged)', () async {
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final bloc = build(
        session: (_) async =>
            const SessionVerificationResult.invalid(reason: 'r'),
      );
      final states = await run(bloc);
      expect(states.last, const AuthUnauthenticated(message: 'r'));
      verify(() => logout(any())).called(1);
    });
  });

  group('cancel and concurrency', () {
    test('AutoLoginCancelled clears session; late result never authenticates',
        () async {
      AuthBloc.autoLoginTimeout = const Duration(seconds: 5);
      final gate = Completer<SessionVerificationResult>();
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final bloc = build(session: (_) => gate.future);
      final states = <AuthState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(CheckAutoLoginRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bloc.add(const AutoLoginCancelled());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      gate.complete(const SessionVerificationResult.valid());
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      await bloc.close();
      expect(states.last, const AuthUnauthenticated());
      expect(states.whereType<AuthAuthenticated>(), isEmpty);
      verify(() => logout(any())).called(1);
    });

    test('retry while in flight runs only the latest check (restartable)',
        () async {
      AuthBloc.autoLoginTimeout = const Duration(seconds: 5);
      final first = Completer<SessionVerificationResult>();
      var calls = 0;
      when(() => checkAutoLogin(any()))
          .thenAnswer((_) async => Right(tDelegate));
      final bloc = build(
        session: (_) {
          calls++;
          return calls == 1
              ? first.future
              : Future.value(const SessionVerificationResult.valid());
        },
      );
      final states = <AuthState>[];
      final sub = bloc.stream.listen(states.add);
      bloc.add(CheckAutoLoginRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      bloc.add(CheckAutoLoginRequested());
      await Future<void>.delayed(const Duration(milliseconds: 50));
      // Stale first run resolves "invalid" late: must not log out or emit.
      first.complete(const SessionVerificationResult.invalid(reason: 'late'));
      await Future<void>.delayed(const Duration(milliseconds: 100));
      await sub.cancel();
      await bloc.close();
      expect(states.whereType<AuthAuthenticated>().length, 1);
      expect(states.last, AuthAuthenticated(delegate: tDelegate));
      verifyNever(() => logout(any()));
    });
  });

  test('cancelled run never calls the device check', () async {
    AuthBloc.autoLoginTimeout = const Duration(seconds: 5);
    final gate = Completer<SessionVerificationResult>();
    var deviceCalls = 0;
    when(() => checkAutoLogin(any())).thenAnswer((_) async => Right(tDelegate));
    final bloc = build(
      session: (_) => gate.future,
      device: (_) async {
        deviceCalls++;
        return _ok;
      },
    );
    bloc.add(CheckAutoLoginRequested());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    bloc.add(const AutoLoginCancelled());
    await Future<void>.delayed(const Duration(milliseconds: 50));
    gate.complete(const SessionVerificationResult.valid());
    await Future<void>.delayed(const Duration(milliseconds: 100));
    await bloc.close();
    expect(deviceCalls, 0);
  });
}
