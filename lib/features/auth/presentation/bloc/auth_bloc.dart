import 'package:bloc/bloc.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_all_delegates.dart';

part 'auth_event.dart';
part 'auth_state.dart';

class AuthBloc extends Bloc<AuthEvent, AuthState> {
  final Login loginUseCase;
  final CheckAutoLogin checkAutoLoginUseCase;
  final Logout logoutUseCase;
  final CacheDelegate cacheDelegateUseCase;
  final CacheAllDelegates cacheAllDelegatesUseCase;

  AuthBloc({
    required this.loginUseCase,
    required this.checkAutoLoginUseCase,
    required this.logoutUseCase,
    required this.cacheDelegateUseCase,
    required this.cacheAllDelegatesUseCase,
  }) : super(AuthInitial()) {
    on<LoginRequested>(_onLoginRequested);
    on<CheckAutoLoginRequested>(_onCheckAutoLogin);
    on<LogoutRequested>(_onLogoutRequested);
    on<OrganizationSelected>(_onOrganizationSelected);
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
        emit(AuthError(message: failure.message));
      },
      (delegates) async {
        // Always cache all delegates for organization switching later
        await cacheAllDelegatesUseCase(delegates);

        if (delegates.length == 1) {
          // Single organization - proceed directly
          emit(AuthAuthenticated(delegate: delegates.first));
        } else {
          // Multiple organizations - show selection
          emit(
            AuthOrganizationSelectionRequired(
              delegates: delegates,
              rememberMe: event.rememberMe,
            ),
          );
        }
      },
    );
  }

  Future<void> _onCheckAutoLogin(
    CheckAutoLoginRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    final result = await checkAutoLoginUseCase(NoParams());

    await result.fold(
      (failure) async {
        emit(AuthUnauthenticated());
      },
      (delegate) async {
        if (delegate != null) {
          emit(AuthAuthenticated(delegate: delegate));
        } else {
          emit(AuthUnauthenticated());
        }
      },
    );
  }

  Future<void> _onLogoutRequested(
    LogoutRequested event,
    Emitter<AuthState> emit,
  ) async {
    emit(AuthLoading());
    await logoutUseCase(NoParams());
    emit(AuthUnauthenticated());
  }

  Future<void> _onOrganizationSelected(
    OrganizationSelected event,
    Emitter<AuthState> emit,
  ) async {
    if (event.rememberMe) {
      await cacheDelegateUseCase(event.delegate);
    }
    emit(AuthAuthenticated(delegate: event.delegate));
  }
}
