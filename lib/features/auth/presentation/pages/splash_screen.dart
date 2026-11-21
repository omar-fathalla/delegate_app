import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/services/app_version_gate.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/domain/role_home.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';

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
      _continueAfterVersionGate();
    });
  }

  /// TAS-66: wait (briefly) for the forced-update decision before the
  /// auto-login touches Firestore. A blocked build goes to the update page;
  /// a slow or failed fetch lets the app continue as before (fail-open).
  Future<void> _continueAfterVersionGate() async {
    await AppVersionGate.ready
        .timeout(AppVersionGate.splashWait, onTimeout: () {});
    if (!mounted) return;
    if (AppVersionGate.isBlocked) {
      context.go(AppVersionGate.routePath);
      return;
    }
    // Trigger auto-login check using global AuthBloc
    context.read<AuthBloc>().add(CheckAutoLoginRequested());
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
          // Web reload of an HR shell URL stays on that page (TAS-139).
          context.go(
            hrShellRestoreLocation(
              landingPathForRole(delegate.role),
              GoRouter.maybeOf(context)?.routeInformationProvider.value.uri,
            ),
            extra: delegate,
          );

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
          final message = state.message;
          final delegateBlocked = WebRuntimePolicy.isWeb &&
              (message == WebRuntimePolicy.delegateLoginWebMessage ||
                  message == WebRuntimePolicy.delegateLoginWebMessageEn);
          if (delegateBlocked) {
            context.go('/login?notice=delegate');
            return;
          }
          context.go('/login');
          if (message != null &&
              message.isNotEmpty &&
              message != AuthBloc.freshSignInMessage) {
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
                    // §39: only when start-up takes longer than 1s, show the
                    // loading indicator below the logo (kept off-centre so the
                    // logo stays aligned with the native splash frame).
                    PositionedDirectional(
                      start: 0,
                      end: 0,
                      bottom: 120,
                      child: Center(
                        child: M3DelayedLoading(
                          delay: const Duration(seconds: 1),
                          child: M3LoadingIndicator(color: brand.onPrimary),
                        ),
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
