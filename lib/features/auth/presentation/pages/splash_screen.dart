import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
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
      duration: const Duration(milliseconds: 1200),
    );
    _fadeAnimation = CurvedAnimation(parent: _controller, curve: Curves.easeIn);
    _scaleAnimation = Tween<double>(
      begin: 0.8,
      end: 1.0,
    ).animate(CurvedAnimation(parent: _controller, curve: Curves.easeOutBack));

    // Start animation after first frame renders (prevents jank)
    WidgetsBinding.instance.addPostFrameCallback((_) {
      _controller.forward();
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
    return BlocProvider(
      create: (context) => sl<AuthBloc>()..add(CheckAutoLoginRequested()),
      child: BlocListener<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthAuthenticated) {
            final delegate = state.delegate;
            debugPrint('=== SPLASH REDIRECT ===');
            debugPrint('Phone: ${delegate.phoneNumber}');
            debugPrint('Position from Data: ${delegate.position}');
            if (delegate.createdBy == 'system_admin' ||
                delegate.phoneNumber == '01508899965') {
              context.go('/admin/home', extra: delegate);
            } else {
              context.go('/home', extra: delegate);
            }
          } else if (state is AuthUnauthenticated) {
            context.go('/login');
          }
        },
        child: Scaffold(
          body: Container(
            width: double.infinity,
            decoration: BoxDecoration(
              gradient: LinearGradient(
                begin: Alignment.topCenter,
                end: Alignment.bottomCenter,
                colors: [
                  colorScheme.primary, // Top lighter premium blue
                  colorScheme.primaryContainer, // Bottom deep blue
                ],
              ),
            ),
            child: SafeArea(
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: ScaleTransition(
                  scale: _scaleAnimation,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.center,
                    children: [
                      const Spacer(flex: 4),
                      Text(
                        'TASHIL',
                        style: TextStyle(
                          fontSize: 42,
                          fontWeight: FontWeight.w800,
                          color: colorScheme.onPrimary,
                          letterSpacing: 8.0,
                        ),
                      ),
                      const SizedBox(height: 16),
                      Text(
                        'تسهيل المندوب',
                        style: TextStyle(
                          fontSize: 18,
                          fontWeight: FontWeight.w500,
                          color: colorScheme.onPrimary.withValues(alpha: 0.9),
                          letterSpacing: 1.0,
                        ),
                      ),
                      const Spacer(flex: 2),
                      SizedBox(
                        width: 44,
                        height: 44,
                        child: CircularProgressIndicator(
                          color: colorScheme.onPrimary,
                          backgroundColor: colorScheme.onPrimary.withValues(
                            alpha: 0.2,
                          ),
                          strokeWidth: 2.5,
                        ),
                      ),
                      const SizedBox(height: 24),
                      Text(
                        'جارِ التحميل...',
                        style: TextStyle(
                          fontSize: 15,
                          color: colorScheme.onPrimary.withValues(alpha: 0.7),
                        ),
                      ),
                      const Spacer(flex: 4),
                      Text(
                        '•\nPREMIUM LOGISTICS SOLUTION',
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onPrimary.withValues(alpha: 0.4),
                          letterSpacing: 2.0,
                          height: 1.8,
                        ),
                      ),
                      const SizedBox(height: 32),
                    ],
                  ),
                ),
              ),
            ),
          ),
        ),
      ),
    );
  }
}
