import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';

class SplashScreen extends StatefulWidget {
  const SplashScreen({super.key});

  @override
  State<SplashScreen> createState() => _SplashScreenState();
}

class _SplashScreenState extends State<SplashScreen>
    with SingleTickerProviderStateMixin {
  late final AnimationController _controller;
  late final Animation<double> _fadeAnimation;

  @override
  void initState() {
    super.initState();
    _controller = AnimationController(
      vsync: this,
      duration: AppMotionDurations.medium2, // short: M3 splash < 1s
    );
    _fadeAnimation = CurvedAnimation(
      parent: _controller,
      curve: AppMotionCurves.standardDecelerate,
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
      child: Theme(
        data: tashilAuthTheme(context),
        child: Builder(builder: (context) {
          final brand = kTashilBrandScheme;
          final text = Theme.of(context).textTheme;
          return Scaffold(
            backgroundColor: brand.primary,
            body: SizedBox(
              width: double.infinity,
              child: SafeArea(
                child: Stack(
                  children: [
                    Center(
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const TashilLogoTile(size: 112),
                          const SizedBox(height: 12),
                          FadeTransition(
                            opacity: _fadeAnimation,
                            child: Column(
                              children: [
                                Text('تسهيل',
                                    style: text.headlineLarge?.copyWith(
                                        color: brand.onPrimary,
                                        fontWeight: FontWeight.w700)),
                                Text('تطبيق الموظفين',
                                    style: text.bodyLarge?.copyWith(
                                        color: brand.onPrimary
                                            .withValues(alpha: 0.85))),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 32,
                      child: TashilVersionText(
                        color: brand.onPrimary.withValues(alpha: 0.7),
                      ),
                    ),
                  ],
                ),
              ),
            ),
          );
        }),
      ),
    );
  }
}
