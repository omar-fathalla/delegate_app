import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';

/// Dedicated Web HR Portal Login Screen.
/// Designed specifically for desktop web browsers and HR administration.
class HrLoginScreen extends StatefulWidget {
  const HrLoginScreen({super.key});

  @override
  State<HrLoginScreen> createState() => _HrLoginScreenState();
}

class _HrLoginScreenState extends State<HrLoginScreen>
    with SingleTickerProviderStateMixin {
  final _formKey = GlobalKey<FormState>();
  final _phoneController = TextEditingController();
  final _passwordController = TextEditingController();
  bool _obscurePassword = true;
  bool _rememberMe = false;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _slideAnimation;

  @override
  void initState() {
    super.initState();
    _animationController = AnimationController(
      vsync: this,
      duration: AppMotionDurations.extraLong4, // 1000ms M3 Token
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: AppMotionCurves.standardDecelerate),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 1.0, curve: AppMotionCurves.emphasizedDecelerate),
          ),
        );

    _animationController.forward();
  }

  @override
  void dispose() {
    _animationController.dispose();
    _phoneController.dispose();
    _passwordController.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthDeviceMismatchState) {
            DeviceLockDialog.show(
              context,
              boundDeviceModel: state.boundDeviceModel,
              currentDeviceModel: state.currentDeviceModel,
              delegateName: state.delegate.fullName,
              delegate: state.delegate,
            );
          } else if (state is AuthError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
                behavior: SnackBarBehavior.floating,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(12),
                ),
              ),
            );
          } else if (state is AuthOrganizationSelectionRequired) {
            _showOrganizationSelector(
              context,
              state.delegates,
              state.rememberMe,
            );
          } else if (state is AuthAuthenticated) {
            final delegate = state.delegate;
            debugPrint(
              '🚀 HrLoginScreen: AuthAuthenticated received! name=${delegate.fullName}, role=${delegate.role}, uid=${delegate.uid}',
            );
            try {
              if (delegate.role == UserRole.hr) {
                debugPrint('🚀 HrLoginScreen: Navigating to /hr/home');
                context.go('/hr/home', extra: delegate);
              } else if (delegate.role == UserRole.superAdmin ||
                  delegate.role == UserRole.admin ||
                  delegate.role == UserRole.organizationAdmin ||
                  delegate.role == UserRole.technicalSupport ||
                  delegate.role == UserRole.branchesMarketingManager) {
                debugPrint('🚀 HrLoginScreen: Navigating to /admin/home');
                context.go('/admin/home', extra: delegate);
              } else if (delegate.role == UserRole.accountant) {
                debugPrint('🚀 HrLoginScreen: Navigating to /accountant/home');
                context.go('/accountant/home', extra: delegate);
              } else if (delegate.role == UserRole.marketing ||
                  delegate.role == UserRole.marketingPromotion) {
                debugPrint('🚀 HrLoginScreen: Navigating to /marketing/home');
                context.go('/marketing/home', extra: delegate);
              } else {
                debugPrint('🚀 HrLoginScreen: Navigating to /home');
                context.go('/home', extra: delegate);
              }
            } catch (e, stack) {
              debugPrint('❌ Navigation Error in HrLoginScreen: $e\n$stack');
            }

            Future.delayed(const Duration(milliseconds: 1500), () {
              sl<PushNotificationService>()
                  .initialize(delegate.uid)
                  .catchError((e) {
                    debugPrint('FCM Init Error: $e');
                  });
            });
          }
        },
        builder: (context, state) {
          return Scaffold(
            backgroundColor: const Color(0xFF090D16),
            body: SafeArea(
              child: Stack(
                children: [
                  // Subtle ambient background gradient
                  Positioned.fill(
                    child: Container(
                      decoration: const BoxDecoration(
                        gradient: RadialGradient(
                          center: Alignment(0.0, -0.2),
                          radius: 1.2,
                          colors: [
                            Color(0xFF131D31),
                            Color(0xFF0A0F1D),
                            Color(0xFF060913),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Top Language Switcher
                  PositionedDirectional(
                    top: 24,
                    end: 28,
                    child: _buildLanguagePill(colorScheme, isArabic),
                  ),

                  // Centered HR Login Card
                  Center(
                    child: SingleChildScrollView(
                      physics: const BouncingScrollPhysics(),
                      padding: const EdgeInsets.symmetric(
                        horizontal: 24,
                        vertical: 36,
                      ),
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(maxWidth: 450),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: SlideTransition(
                            position: _slideAnimation,
                            child: _buildHRLoginCard(
                              context,
                              colorScheme,
                              l10n,
                              isArabic,
                              state,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // CENTERED HR LOGIN CARD (RESPONSIVE & CLEAN)
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildHRLoginCard(
    BuildContext context,
    ColorScheme colorScheme,
    AppLocalizations l10n,
    bool isArabic,
    AuthState state,
  ) {
    return Container(
      decoration: BoxDecoration(
        color: const Color(0xFF0F172A),
        borderRadius: BorderRadius.circular(28),
        border: Border.all(
          color: const Color(0xFF1E293B),
          width: 1.5,
        ),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.5),
            blurRadius: 40,
            offset: const Offset(0, 16),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(horizontal: 36, vertical: 40),
      child: Form(
        key: _formKey,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              // HR Portal Badge
              Center(
                child: Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 7,
                  ),
                  decoration: BoxDecoration(
                    color: const Color(0xFF6366F1).withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: const Color(0xFF6366F1).withValues(alpha: 0.35),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const Icon(
                        Icons.badge_outlined,
                        size: 16,
                        color: Color(0xFFA5B4FC),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isArabic
                            ? 'بوابة الموارد البشرية (HR Portal)'
                            : 'HR Portal',
                        style: const TextStyle(
                          fontSize: 12.5,
                          fontWeight: FontWeight.w700,
                          color: Color(0xFFA5B4FC),
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              const SizedBox(height: 24),

              // Title & App Name
              Center(
                child: Column(
                  children: [
                    Text(
                      l10n.appTitle,
                      style: const TextStyle(
                        fontSize: 42,
                        fontWeight: FontWeight.w900,
                        letterSpacing: 1.2,
                        color: Colors.white,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      isArabic
                          ? 'تطبيق المندوب وإدارة العمليات'
                          : 'Delegate & Operations App',
                      style: const TextStyle(
                        fontSize: 13.5,
                        color: Color(0xFF94A3B8),
                        fontWeight: FontWeight.w500,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 32),

              // Section Header
              Text(
                l10n.login,
                style: const TextStyle(
                  fontSize: 22,
                  fontWeight: FontWeight.w800,
                  color: Colors.white,
                ),
              ),
              const SizedBox(height: 6),
              Text(
                l10n.loginToContinue,
                style: const TextStyle(
                  fontSize: 13.5,
                  color: Color(0xFF94A3B8),
                ),
              ),
              const SizedBox(height: 24),

              // Phone Field
              TextFormField(
                controller: _phoneController,
                keyboardType: TextInputType.phone,
                textInputAction: TextInputAction.next,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.telephoneNumber],
                textDirection: TextDirection.ltr,
                style: const TextStyle(fontSize: 15, color: Colors.white),
                decoration: _darkInputDecoration(
                  hintText: l10n.mobileNumber,
                  prefixIcon: Icons.phone_android_rounded,
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.enterMobileNumber;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Password Field
              TextFormField(
                controller: _passwordController,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                autofillHints: const [AutofillHints.password],
                onFieldSubmitted: (_) => _submitLogin(context),
                textDirection: TextDirection.ltr,
                obscureText: _obscurePassword,
                style: const TextStyle(fontSize: 15, color: Colors.white),
                decoration: _darkInputDecoration(
                  hintText: l10n.password,
                  prefixIcon: Icons.lock_outline_rounded,
                  suffixIcon: IconButton(
                    icon: Icon(
                      _obscurePassword
                          ? Icons.visibility_off_outlined
                          : Icons.visibility_outlined,
                      color: const Color(0xFF94A3B8),
                      size: 20,
                    ),
                    onPressed: () {
                      setState(() {
                        _obscurePassword = !_obscurePassword;
                      });
                    },
                  ),
                ),
                validator: (value) {
                  if (value == null || value.trim().isEmpty) {
                    return l10n.enterPassword;
                  }
                  return null;
                },
              ),
              const SizedBox(height: 16),

              // Remember Me Checkbox
              Row(
                children: [
                  SizedBox(
                    height: 22,
                    width: 22,
                    child: Checkbox(
                      value: _rememberMe,
                      onChanged: (value) {
                        setState(() {
                          _rememberMe = value ?? false;
                        });
                      },
                      activeColor: const Color(0xFF6366F1),
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(4),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    l10n.rememberMe,
                    style: const TextStyle(
                      fontSize: 13.5,
                      color: Color(0xFFCBD5E1),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 28),

              // Login Button
              SizedBox(
                width: double.infinity,
                height: 52,
                child: FilledButton(
                  onPressed: state is AuthLoading
                      ? null
                      : () => _submitLogin(context),
                  style: FilledButton.styleFrom(
                    backgroundColor: const Color(0xFF6366F1),
                    foregroundColor: Colors.white,
                    disabledBackgroundColor: const Color(
                      0xFF6366F1,
                    ).withValues(alpha: 0.5),
                    elevation: 3,
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(28),
                    ),
                    textStyle: const TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 16,
                      fontWeight: FontWeight.w700,
                    ),
                  ),
                  child: state is AuthLoading
                      ? const SizedBox(
                          height: 22,
                          width: 22,
                          child: CircularProgressIndicator(
                            color: Colors.white,
                            strokeWidth: 2.5,
                          ),
                        )
                      : Text(l10n.loginButton),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // LANGUAGE TOGGLE PILL
  // ──────────────────────────────────────────────────────────────────────────
  Widget _buildLanguagePill(ColorScheme colorScheme, bool isArabic) {
    return Material(
      color: Colors.transparent,
      child: InkWell(
        borderRadius: BorderRadius.circular(20),
        onTap: () => localeProvider.toggleLocale(),
        child: Container(
          padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 7),
          decoration: BoxDecoration(
            color: const Color(0xFF1E293B),
            borderRadius: BorderRadius.circular(20),
            border: Border.all(color: const Color(0xFF334155)),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              const Icon(Icons.language_rounded, size: 16, color: Colors.white),
              const SizedBox(width: 6),
              Text(
                isArabic ? 'English' : 'العربية',
                style: const TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: Colors.white,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ──────────────────────────────────────────────────────────────────────────
  // DARK INPUT DECORATION
  // ──────────────────────────────────────────────────────────────────────────
  InputDecoration _darkInputDecoration({
    required String hintText,
    required IconData prefixIcon,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: const TextStyle(color: Color(0xFF64748B), fontSize: 14),
      filled: true,
      fillColor: const Color(0xFF131B26),
      contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
      prefixIcon: Icon(prefixIcon, color: const Color(0xFF94A3B8), size: 20),
      suffixIcon: suffixIcon,
      border: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF263345), width: 1.2),
      ),
      enabledBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF263345), width: 1.2),
      ),
      focusedBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFF6366F1), width: 1.8),
      ),
      errorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.2),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderRadius: BorderRadius.circular(14),
        borderSide: const BorderSide(color: Color(0xFFEF4444), width: 1.8),
      ),
    );
  }

  // ---- Helper: Submit Login ----
  void _submitLogin(BuildContext context) {
    if (BlocProvider.of<AuthBloc>(context).state is AuthLoading) return;

    if (_formKey.currentState!.validate()) {
      BlocProvider.of<AuthBloc>(context).add(
        LoginRequested(
          phoneNumber: _phoneController.text,
          password: _passwordController.text,
          rememberMe: _rememberMe,
        ),
      );
    }
  }

  // ---- Helper: Organization Selection Bottom Sheet ----
  void _showOrganizationSelector(
    BuildContext blocContext,
    List<Delegate> delegates,
    bool rememberMe,
  ) {
    final colorScheme = Theme.of(blocContext).colorScheme;
    final isArabic = localeProvider.isArabic;

    showModalBottomSheet(
      context: blocContext,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      isDismissible: false,
      enableDrag: false,
      builder: (sheetContext) {
        return Container(
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(28)),
          ),
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 36),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 20),
              Text(
                isArabic ? 'اختر المنظمة' : 'Select Organization',
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                isArabic
                    ? 'أنت مسجل في أكثر من منظمة. اختر للمتابعة.'
                    : 'You are registered in multiple organizations.',
                style: TextStyle(
                  fontSize: 14,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              const SizedBox(height: 16),
              ...delegates.map(
                (delegate) => _buildOrgCard(
                  blocContext,
                  sheetContext: sheetContext,
                  delegate: delegate,
                  rememberMe: rememberMe,
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  Widget _buildOrgCard(
    BuildContext blocContext, {
    required BuildContext sheetContext,
    required Delegate delegate,
    required bool rememberMe,
  }) {
    final colorScheme = Theme.of(blocContext).colorScheme;
    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: InkWell(
        borderRadius: BorderRadius.circular(16),
        onTap: () {
          Navigator.pop(sheetContext);
          WidgetsBinding.instance.addPostFrameCallback((_) {
            if (!mounted) return;
            BlocProvider.of<AuthBloc>(blocContext).add(
              OrganizationSelected(delegate: delegate, rememberMe: rememberMe),
            );
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer,
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(
                  Icons.business_rounded,
                  color: colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      delegate.organizationName,
                      style: TextStyle(
                        fontSize: 15,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      delegate.companyName,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Icon(
                Icons.chevron_right_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}
