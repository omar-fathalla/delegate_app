import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  /// After this long with no navigation, show the retry / sign-in fallback.
  static Duration stallTimeout = const Duration(seconds: 12);

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;
  Timer? _stallTimer;
  bool _stalled = false;

  void _startAutoLogin() {
    _stallTimer?.cancel();
    _stallTimer = Timer(SplashScreen.stallTimeout, () {
      if (mounted) setState(() => _stalled = true);
    });
    context.read<AuthBloc>().add(CheckAutoLoginRequested());
  }

  void _retry() {
    setState(() => _stalled = false);
    _startAutoLogin();
  }

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.extraLong4, // 1000ms M3 Token
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.standardDecelerate,
    );
    _scaleAnimation = Tween<double>(begin: 0.8, end: 1.0).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppMotionCurves.expressiveDefaultSpatial,
      ),
    );

    // Start animation after first frame renders (prevents jank)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
      // Trigger auto-login check using global AuthBloc
      _startAutoLogin();
    });
  }

  @override
  void dispose() {
    _stallTimer?.cancel();
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated ||
            state is AuthDeviceMismatchState ||
            (state is AuthUnauthenticated && !state.fromLogout)) {
          _stallTimer?.cancel();
        }
        if (state is AuthAuthenticated) {
          final delegate = state.delegate;
          if (delegate.role == UserRole.superAdmin ||
              delegate.role == UserRole.admin ||
              delegate.role == UserRole.organizationAdmin ||
              delegate.role == UserRole.technicalSupport ||
              delegate.role == UserRole.branchesMarketingManager) {
            context.go('/admin/home', extra: delegate);
          } else if (delegate.role == UserRole.accountant) {
            context.go('/accountant/home', extra: delegate);
          } else if (delegate.role == UserRole.hr) {
            context.go('/hr/home', extra: delegate);
          } else if (delegate.role == UserRole.marketing ||
              delegate.role == UserRole.marketingPromotion) {
            context.go('/marketing/home', extra: delegate);
          } else {
            context.go('/home', extra: delegate);
          }

          // تهيئة الإشعارات في الخلفية بعد اكتمال الانتقال
          Future.delayed(const Duration(milliseconds: 1500), () {
            sl<PushNotificationService>().initialize(delegate.uid).catchError((
              e,
            ) {
              debugPrint('FCM Init Error: $e');
            });
          });
        } else if (state is AuthDeviceMismatchState) {
          context.go('/login');
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (context.mounted) {
              DeviceLockDialog.show(
                context,
                boundDeviceModel: state.boundDeviceModel,
                currentDeviceModel: state.currentDeviceModel,
                delegateName: state.delegate.fullName,
                delegate: state.delegate,
              );
            }
          });
        } else if (state is AuthUnauthenticated) {
          if (state.fromLogout) return;
          context.go('/login');
          if (state.message != null &&
              state.message!.isNotEmpty &&
              state.message != AuthBloc.freshSignInMessage) {
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (context.mounted) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message!),
                    duration: const Duration(seconds: 5),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            });
          }
        }
      },
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        body: SizedBox(
          width: double.infinity,
          child: SafeArea(
            child: FadeTransition(
              opacity: _fadeAnimation,
              child: ScaleTransition(
                scale: _scaleAnimation,
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    const Spacer(),
                    Text(
                      'Tashil',
                      style:
                          Theme.of(context).textTheme.displayLarge?.copyWith(
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                            letterSpacing: 1.5,
                          ) ??
                          TextStyle(
                            fontSize: 56,
                            fontWeight: FontWeight.w800,
                            color: colorScheme.primary,
                            letterSpacing: 1.5,
                          ),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      'تسهيل',
                      style:
                          Theme.of(context).textTheme.headlineSmall?.copyWith(
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary.withValues(alpha: 0.8),
                          ) ??
                          TextStyle(
                            fontSize: 24,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.primary.withValues(alpha: 0.8),
                          ),
                    ),
                    const Spacer(),
                    if (_stalled)
                      _StalledActions(
                        onRetry: _retry,
                        onSignIn: () {
                          _stallTimer?.cancel();
                          context.go('/login');
                        },
                      )
                    else
                      CircularProgressIndicator(color: colorScheme.primary),
                    const SizedBox(height: 48),
                  ],
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}

class _StalledActions extends StatelessWidget {
  final VoidCallback onRetry;
  final VoidCallback onSignIn;

  const _StalledActions({required this.onRetry, required this.onSignIn});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 24),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.wifi_off_rounded, color: colorScheme.error),
          const SizedBox(height: 8),
          Text(
            l10n?.splashConnectionFailed ?? 'تعذّر الاتصال',
            textAlign: TextAlign.center,
            style: Theme.of(context).textTheme.titleMedium,
          ),
          const SizedBox(height: 16),
          Wrap(
            spacing: 12,
            runSpacing: 8,
            alignment: WrapAlignment.center,
            children: [
              FilledButton.icon(
                key: const Key('splash_retry'),
                onPressed: onRetry,
                icon: const Icon(Icons.refresh_rounded),
                label: Text(l10n?.splashRetry ?? 'إعادة المحاولة'),
              ),
              OutlinedButton(
                key: const Key('splash_sign_in'),
                onPressed: onSignIn,
                child: Text(l10n?.splashSignIn ?? 'تسجيل الدخول'),
              ),
            ],
          ),
        ],
      ),
    );
  }
}
