import 'dart:async';

import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
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

  StreamSubscription<bool>? _anonymousAuthSub;

  /// True after the user confirms logout, until the next successful sign-in.
  /// Blocks cache restore and the anonymous-session handler from navigating
  /// again or signing the user back in.
  bool _explicitLogout = false;

  AuthBloc({
    required this.loginUseCase,
    required this.checkAutoLoginUseCase,
    required this.logoutUseCase,
    required this.cacheDelegateUseCase,
    required this.cacheAllDelegatesUseCase,
    this.isAnonymousSession,
    this.signOutAuth,
    this.anonymousSessionRestored,
  }) : super(AuthInitial()) {
    on<LoginRequested>(_onLoginRequested);
    on<CheckAutoLoginRequested>(_onCheckAutoLogin);
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
    emit(AuthLoading());
    if (isAnonymousSession?.call() == true) {
      await _signOutAnonymousSession(emit);
      return;
    }
    final result = await checkAutoLoginUseCase(NoParams());

    await result.fold(
      (failure) async {
        emit(const AuthUnauthenticated());
      },
      (delegate) async {
        if (delegate != null) {
          // 1. فحص إبطال الجلسة أو الخروج الإجباري من الإدارة
          final sessionCheck =
              await SessionManagementService.checkSessionStatus(
                delegate: delegate,
              );
          if (!sessionCheck.isValid) {
            await logoutUseCase(const LogoutParams());
            emit(AuthUnauthenticated(message: sessionCheck.reason));
            return;
          }

          // 2. فحص بصمة الجهاز للتسجيل التلقائي
          final deviceCheck = await DeviceBindingService.verifyOrBindDevice(
            delegate: delegate,
          );
          if (deviceCheck.isMismatched) {
            await logoutUseCase(const LogoutParams());
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

          emit(AuthAuthenticated(delegate: delegate));
        } else {
          emit(const AuthUnauthenticated());
        }
      },
    );
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    _explicitLogout = true;
    emit(AuthLoading());
    try {
      await logoutUseCase(LogoutParams(userId: event.userId));
    } catch (_) {}
    emit(const AuthUnauthenticated(fromLogout: true));
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
