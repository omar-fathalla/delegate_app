import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:go_router/go_router.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;
  late final Animation<double> _scaleAnimation;

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
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(
      CurvedAnimation(
        parent: _controller,
        curve: AppMotionCurves.expressiveDefaultSpatial,
      ),
    );

    // Start animation after first frame renders (prevents jank)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
      // Trigger auto-login check using global AuthBloc
      context.read<AuthBloc>().add(CheckAutoLoginRequested());
    });
  }

  @override
  void dispose() {
    _controller.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return BlocListener<AuthBloc, AuthState>(
      listener: (context, state) {
        if (state is AuthAuthenticated) {
          final delegate = state.delegate;
          if (delegate.role == UserRole.superAdmin ||
              delegate.role == UserRole.admin ||
              delegate.role == UserRole.organizationAdmin ||
              delegate.role == UserRole.technicalSupport ||
              delegate.role == UserRole.branchesMarketingManager) {
            context.go('/admin/home', extra: delegate);
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
              );
            }
          });
        } else if (state is AuthUnauthenticated) {
          context.go('/login');
          if (state.message != null && state.message!.isNotEmpty) {
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
