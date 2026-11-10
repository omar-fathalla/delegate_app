import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:bloc_concurrency/bloc_concurrency.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/config/debug_stall.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/core/services/device_binding_service.dart';
import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/auth/domain/delegate_otp_config.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_all_delegates.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  /// Shown when a leftover anonymous Firebase session is signed out.
  static const freshSignInMessage =
      'انتهت جلسة الدخول السابقة. يرجى تسجيل الدخول من جديد.\n'
      'Your previous session has ended. Please sign in again.';

  final Login loginUseCase;
  final CheckAutoLogin checkAutoLoginUseCase;
  final Logout logoutUseCase;
  final CacheDelegate cacheDelegateUseCase;
  final CacheAllDelegates cacheAllDelegatesUseCase;
  final bool Function()? isAnonymousSession;
  final Future<void> Function()? signOutAuth;
  final Stream<bool>? anonymousSessionRestored;

  /// Test seams; default to the real services.
  final Future<SessionVerificationResult> Function(Delegate delegate)
      sessionCheck;
  final Future<DeviceVerificationResult> Function(Delegate delegate)
      deviceCheck;

  StreamSubscription<bool>? _anonymousAuthSub;

  /// True after the user confirms logout, until the next successful sign-in.
  /// Blocks cache restore and the anonymous-session handler from navigating
  /// again or signing the user back in.
  bool _explicitLogout = false;

  /// Bumped per auto-login run and on cancel; a run whose generation is stale
  /// must not log out or emit.
  int _autoLoginGen = 0;

  AuthBloc({
    required this.loginUseCase,
    required this.checkAutoLoginUseCase,
    required this.logoutUseCase,
    required this.cacheDelegateUseCase,
    required this.cacheAllDelegatesUseCase,
    this.isAnonymousSession,
    this.signOutAuth,
    this.anonymousSessionRestored,
    Future<SessionVerificationResult> Function(Delegate delegate)?
        sessionCheck,
    Future<DeviceVerificationResult> Function(Delegate delegate)? deviceCheck,
  })  : sessionCheck = sessionCheck ??
            ((d) => SessionManagementService.checkSessionStatus(delegate: d)),
        deviceCheck = deviceCheck ??
            ((d) => DeviceBindingService.verifyOrBindDevice(delegate: d)),
        super(AuthInitial()) {
    on<LoginRequested>(_onLoginRequested);
    // restartable: a Retry while a check is in flight cancels the old
    // handler (its emits become no-ops) and runs a fresh one.
    on<CheckAutoLoginRequested>(_onCheckAutoLogin, transformer: restartable());
    on<AutoLoginCancelled>(_onAutoLoginCancelled);
    on<LogoutRequested>(_onLogoutRequested);
    on<OrganizationSelected>(_onOrganizationSelected);
    on<AnonymousSessionDetected>(_onAnonymousSessionDetected);
    on<PhoneOtpVerified>(_onPhoneOtpVerified);
    on<PhoneOtpCancelled>(_onPhoneOtpCancelled);

    final restored = anonymousSessionRestored;
    if (restored != null) {
      _anonymousAuthSub = restored.listen((isAnonymous) {
        if (isAnonymous) add(const AnonymousSessionDetected());
      }, onError: (_) {});
    }
  }

  @override
  Future<void> close() {
    _anonymousAuthSub?.cancel();
    return super.close();
  }

  Future<void> _onLoginRequested(
    LoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await loginUseCase(
      LoginParams(
        phoneNumber: event.phoneNumber,
        password: event.password,
        rememberMe: event.rememberMe,
        mode: event.mode,
      ),
    );

    await result.fold(
      (failure) async {
        emit(
          AuthError(
            message: failure.message,
            code: failure is AuthFailure ? failure.code : null,
          ),
        );
      },
      (delegates) async {
        _explicitLogout = false;
        await cacheAllDelegatesUseCase(delegates);

        if (delegateLoginNeedsPhoneOtp(delegates)) {
          final e164 = egyptianPhoneToE164(event.phoneNumber);
          if (e164 == null) {
            await _signOutIncompleteSession();
            emit(
              const AuthError(
                message: 'تعذر إرسال رمز التحقق لهذا الرقم.',
                code: 'invalid_phone',
              ),
            );
            return;
          }
          emit(
            AuthPhoneOtpRequired(
              delegates: delegates,
              rememberMe: event.rememberMe,
              e164Phone: e164,
            ),
          );
          return;
        }

        await _continueAfterCredentials(
          delegates: delegates,
          rememberMe: event.rememberMe,
          emit: emit,
        );
      },
    );
  }

  Future<void> _onPhoneOtpVerified(
    PhoneOtpVerified event,
    Emitter<AuthState> emit,
  ) async {
    final pending = state;
    if (pending is! AuthPhoneOtpRequired) return;
    await _continueAfterCredentials(
      delegates: pending.delegates,
      rememberMe: pending.rememberMe,
      emit: emit,
    );
  }

  Future<void> _onPhoneOtpCancelled(
    PhoneOtpCancelled event,
    Emitter<AuthState> emit,
  ) async {
    await _signOutIncompleteSession();
    emit(const AuthUnauthenticated(fromLogout: true));
  }

  Future<void> _signOutIncompleteSession() async {
    _explicitLogout = true;
    try {
      await logoutUseCase(const LogoutParams());
    } catch (_) {}
  }

  Future<void> _continueAfterCredentials({
    required List<Delegate> delegates,
    required bool rememberMe,
    required Emitter<AuthState> emit,
  }) async {
    final uniqueOrgs = <String, List<Delegate>>{};
    for (final d in delegates) {
      final orgKey = d.organizationUID.isNotEmpty
          ? d.organizationUID
          : d.organizationName;
      uniqueOrgs.putIfAbsent(orgKey, () => []).add(d);
    }

    if (uniqueOrgs.length <= 1) {
      final orgDelegates = uniqueOrgs.isNotEmpty
          ? uniqueOrgs.values.first
          : delegates;
      final delegate = orgDelegates.firstWhere(
        (d) =>
            d.status == DelegateStatus.approved ||
            d.status == DelegateStatus.active,
        orElse: () => orgDelegates.first,
      );

      if (rememberMe) {
        await cacheDelegateUseCase(delegate);
      }

      final deviceCheck = await DeviceBindingService.verifyOrBindDevice(
        delegate: delegate,
      );
      if (deviceCheck.isMismatched) {
        emit(
          AuthDeviceMismatchState(
            delegate: delegate,
            boundDeviceModel: deviceCheck.boundDeviceModel,
            currentDeviceModel: deviceCheck.currentDeviceModel,
            message: deviceCheck.message ?? 'هذا الحساب مقترن بجهاز آخر',
          ),
        );
        return;
      }

      SessionManagementService.clearReLoginFlag(
        delegateUid: delegate.uid,
        organizationUID: delegate.organizationUID,
        companyUID: delegate.companyUID,
      ).ignore();

      emit(AuthAuthenticated(delegate: delegate));
      return;
    }

    final distinctDelegates = uniqueOrgs.values.map((orgDelegates) {
      return orgDelegates.firstWhere(
        (d) =>
            d.status == DelegateStatus.approved ||
            d.status == DelegateStatus.active,
        orElse: () => orgDelegates.first,
      );
    }).toList();

    emit(
      AuthOrganizationSelectionRequired(
        delegates: distinctDelegates,
        rememberMe: rememberMe,
      ),
    );
  }

  Future<void> _onAnonymousSessionDetected(
    AnonymousSessionDetected event,
    Emitter<AuthState> emit,
  ) async {
    if (_explicitLogout) return;
    await _signOutAnonymousSession(emit);
  }

  Future<void> _signOutAnonymousSession(Emitter<AuthState> emit) async {
    final stillAnonymous = isAnonymousSession?.call() == true;
    if (!stillAnonymous && state is AuthAuthenticated) return;

    if (stillAnonymous) {
      try {
        await signOutAuth?.call();
      } catch (_) {}
    }
    try {
      await logoutUseCase(const LogoutParams());
    } catch (_) {}

    final current = state;
    if (current is AuthUnauthenticated &&
        current.message == freshSignInMessage) {
      return;
    }
    emit(const AuthUnauthenticated(message: freshSignInMessage));
  }

  Future<void> _onCheckAutoLogin(
    CheckAutoLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    if (_explicitLogout) {
      emit(const AuthUnauthenticated(fromLogout: true));
      return;
    }
    final gen = ++_autoLoginGen;
    emit(AuthLoading());
    if (isAnonymousSession?.call() == true) {
      await _signOutAnonymousSession(emit);
      return;
    }
    if (debugStallActive) {
      // DEV-only (?debugStall=1): hang auto-login so the splash stall UI can
      // be exercised. Compiled out of prod (AppEnv.isDev is const false).
      await Completer<void>().future;
    }
    Delegate? cached;
    final _AutoLoginDecision decision;
    try {
      decision = await _resolveAutoLogin(
        (d) => cached = d,
        gen,
      ).timeout(autoLoginTimeout);
    } on TimeoutException {
      if (gen != _autoLoginGen) return;
      // Network hang: never log out or unbind on a timeout. Keep the cached
      // session if we have one; otherwise send the user to login.
      final d = cached;
      emit(
        d != null
            ? AuthAuthenticated(delegate: d)
            : const AuthUnauthenticated(),
      );
      return;
    }
    if (gen != _autoLoginGen) return;
    if (decision.logout) {
      await logoutUseCase(const LogoutParams());
    }
    emit(decision.state);
  }

  Future<void> _onAutoLoginCancelled(
    AutoLoginCancelled event,
    Emitter<AuthState> emit,
  ) async {
    _autoLoginGen++; // any in-flight auto-login result is now ignored
    try {
      await logoutUseCase(const LogoutParams());
    } catch (_) {}
    emit(const AuthUnauthenticated());
  }

  /// Overall cap on auto-login (cache read + session check + device check).
  static Duration autoLoginTimeout = const Duration(seconds: 10);

  /// Computes the auto-login outcome without emitting or logging out, so a
  /// late result after [autoLoginTimeout] has no side effects.
  Future<_AutoLoginDecision> _resolveAutoLogin(
    void Function(Delegate) onCached,
    int gen,
  ) async {
    final result = await checkAutoLoginUseCase(NoParams());
    final delegate = result.fold((_) => null, (d) => d);
    if (delegate == null) {
      return const _AutoLoginDecision(AuthUnauthenticated());
    }
    onCached(delegate);

    // 1. فحص إبطال الجلسة أو الخروج الإجباري من الإدارة
    final session = await sessionCheck(delegate);
    if (!session.isValid) {
      return _AutoLoginDecision(
        AuthUnauthenticated(message: session.reason),
        logout: true,
      );
    }

    // 2. فحص بصمة الجهاز للتسجيل التلقائي
    // A stale (timed-out, cancelled or restarted) run must not touch the
    // device binding.
    if (gen != _autoLoginGen) {
      return _AutoLoginDecision(AuthAuthenticated(delegate: delegate));
    }
    final device = await deviceCheck(delegate);
    if (device.isMismatched) {
      return _AutoLoginDecision(
        AuthDeviceMismatchState(
          delegate: delegate,
          boundDeviceModel: device.boundDeviceModel,
          currentDeviceModel: device.currentDeviceModel,
          message: device.message ?? 'هذا الحساب مقترن بجهاز آخر',
        ),
        logout: true,
      );
    }

    return _AutoLoginDecision(AuthAuthenticated(delegate: delegate));
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    _explicitLogout = true;
    // Emit first so Home / profile listeners are cancelled, then drop
    // the FCM token while still signed in, then signOut (M31 f7dbcf37).
    emit(const AuthUnauthenticated(fromLogout: true));
    await Future<void>.delayed(const Duration(milliseconds: 400));
    try {
      await logoutUseCase(LogoutParams(userId: event.userId));
    } catch (_) {}
  }

  Future<void> _onOrganizationSelected(
    OrganizationSelected event,
    Emitter<AuthState> emit,
  ) async {
    final delegate = event.delegate;
    // التحقق من بصمة الجهاز عند اختيار المنظمة
    final deviceCheck = await DeviceBindingService.verifyOrBindDevice(
      delegate: delegate,
    );
    if (deviceCheck.isMismatched) {
      emit(
        AuthDeviceMismatchState(
          delegate: delegate,
          boundDeviceModel: deviceCheck.boundDeviceModel,
          currentDeviceModel: deviceCheck.currentDeviceModel,
          message: deviceCheck.message ?? 'هذا الحساب مقترن بجهاز آخر',
        ),
      );
      return;
    }

    if (event.rememberMe) {
      await cacheDelegateUseCase(delegate);
    }

    // تصفير علامة الخروج الإجباري فور اختيار المنظمة
    SessionManagementService.clearReLoginFlag(
      delegateUid: delegate.uid,
      organizationUID: delegate.organizationUID,
      companyUID: delegate.companyUID,
    ).ignore();

    emit(AuthAuthenticated(delegate: delegate));
  }
}

class _AutoLoginDecision {
  final AuthState state;
  final bool logout;
  const _AutoLoginDecision(this.state, {this.logout = false});
}
