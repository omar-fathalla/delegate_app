import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:url_launcher/url_launcher.dart';

class LoginScreen extends StatefulWidget {
  const LoginScreen({super.key});

  @override
  State<LoginScreen> createState() => _LoginScreenState();
}

class _LoginScreenState extends State<LoginScreen>
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
      duration: const Duration(milliseconds: 1000),
    );

    _fadeAnimation = Tween<double>(begin: 0.0, end: 1.0).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(0.0, 0.6, curve: Curves.easeOut),
      ),
    );

    _slideAnimation =
        Tween<Offset>(begin: const Offset(0, 0.15), end: Offset.zero).animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(0.2, 1.0, curve: Curves.easeOutCubic),
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

  // Removed hardcoded color constants in favor of M3 ColorScheme

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      backgroundColor: colorScheme.surface,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) {
          if (state is AuthError) {
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
            // Initialize FCM with delegate UID for token storage
            sl<PushNotificationService>()
                .initialize(state.delegate.uid)
                .catchError((e) {
                  debugPrint('FCM Init Error: $e');
                });
            // تأخير بسيط للتأكد من إغلاق أي dialog/bottom sheet أولاً
            WidgetsBinding.instance.addPostFrameCallback((_) {
              if (!mounted) return;
              final delegate = state.delegate;
              if (delegate.role == UserRole.superAdmin ||
                  delegate.role == UserRole.admin) {
                context.go('/admin/home', extra: delegate);
              } else if (delegate.role == UserRole.marketing ||
                  delegate.role == UserRole.marketingPromotion) {
                context.go('/marketing/home', extra: delegate);
              } else {
                context.go('/home', extra: delegate);
              }
            });
          }
        },
        builder: (context, state) {
          return SafeArea(
            child: CustomScrollView(
              slivers: [
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Padding(
                    padding: const EdgeInsetsDirectional.symmetric(
                      horizontal: 28.0,
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.center,
                      children: [
                        const SizedBox(height: 16),

                        // ---- Language Toggle ----
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Align(
                            alignment: AlignmentDirectional.centerEnd,
                            child: Material(
                              color: colorScheme.surface.withValues(alpha: 0),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(20),
                                onTap: () {
                                  localeProvider.toggleLocale();
                                },
                                child: Container(
                                  padding:
                                      const EdgeInsetsDirectional.symmetric(
                                        horizontal: 16,
                                        vertical: 8,
                                      ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(20),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.language_rounded,
                                        size: 18,
                                        color: colorScheme.onSurface,
                                      ),
                                      const SizedBox(width: 6),
                                      Text(
                                        isArabic ? 'English' : 'العربية',
                                        style: TextStyle(
                                          fontSize: 14,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),
                                ),
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),

                        // ---- App Title (Logo) ----
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Text(
                            l10n.appTitle,
                            style: TextStyle(
                              fontSize: 48,
                              fontWeight: FontWeight.w900,
                              color: colorScheme.primary,
                              letterSpacing: 1.0,
                            ),
                          ),
                        ),

                        const SizedBox(height: 8),

                        // ---- Subtitle ----
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: Text(
                            l10n.delegateApp,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w400,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),

                        const Spacer(flex: 1),

                        // ---- Login Text ----
                        SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: SizedBox(
                              width: double.infinity,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Text(
                                    l10n.login,
                                    style: TextStyle(
                                      fontSize: 24,
                                      fontWeight: FontWeight.w400,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 12),
                                  Text(
                                    l10n.loginToContinue,
                                    style: TextStyle(
                                      fontSize: 14,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const SizedBox(height: 32),

                        // ---- Login Form ----
                        SlideTransition(
                          position: _slideAnimation,
                          child: FadeTransition(
                            opacity: _fadeAnimation,
                            child: Form(
                              key: _formKey,
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  // Phone field
                                  TextFormField(
                                    controller: _phoneController,
                                    keyboardType: TextInputType.phone,
                                    textInputAction: TextInputAction.next,
                                    autofillHints: const [
                                      AutofillHints.telephoneNumber,
                                    ],
                                    textDirection: TextDirection.ltr,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colorScheme.onSurface,
                                    ),
                                    decoration: _inputDecoration(
                                      hintText: l10n.mobileNumber,
                                      prefixIcon: Icons.phone_android_rounded,
                                      colorScheme: colorScheme,
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return l10n.enterMobileNumber;
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 16),

                                  // Password field
                                  TextFormField(
                                    controller: _passwordController,
                                    textInputAction: TextInputAction.done,
                                    autofillHints: const [
                                      AutofillHints.password,
                                    ],
                                    onFieldSubmitted: (_) =>
                                        _submitLogin(context),
                                    textDirection: TextDirection.ltr,
                                    obscureText: _obscurePassword,
                                    style: TextStyle(
                                      fontSize: 16,
                                      color: colorScheme.onSurface,
                                    ),
                                    decoration: _inputDecoration(
                                      hintText: l10n.password,
                                      prefixIcon: Icons.lock_rounded,
                                      colorScheme: colorScheme,
                                      suffixIcon: IconButton(
                                        icon: Icon(
                                          _obscurePassword
                                              ? Icons.visibility_off_outlined
                                              : Icons.visibility_outlined,
                                          color: colorScheme.onSurfaceVariant,
                                          size: 22,
                                        ),
                                        onPressed: () {
                                          setState(() {
                                            _obscurePassword =
                                                !_obscurePassword;
                                          });
                                        },
                                      ),
                                    ),
                                    validator: (value) {
                                      if (value == null || value.isEmpty) {
                                        return l10n.enterPassword;
                                      }
                                      return null;
                                    },
                                  ),

                                  const SizedBox(height: 16),

                                  // Remember Me
                                  Row(
                                    children: [
                                      SizedBox(
                                        height: 24,
                                        width: 24,
                                        child: Checkbox(
                                          value: _rememberMe,
                                          onChanged: (value) {
                                            setState(() {
                                              _rememberMe = value ?? false;
                                            });
                                          },
                                          activeColor: colorScheme.primary,
                                          shape: RoundedRectangleBorder(
                                            borderRadius:
                                                BorderRadius.circular(4),
                                          ),
                                        ),
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.rememberMe,
                                        style: TextStyle(
                                          fontSize: 14,
                                          color: colorScheme.onSurface,
                                        ),
                                      ),
                                    ],
                                  ),

                                  const SizedBox(height: 32),

                                  // Login Button
                                  SizedBox(
                                    width: double.infinity,
                                    child: FilledButton(
                                      onPressed: state is AuthLoading
                                          ? null
                                          : () => _submitLogin(context),
                                      style: FilledButton.styleFrom(
                                        minimumSize: const Size.fromHeight(
                                          64,
                                        ),
                                        padding: const EdgeInsets.symmetric(
                                          vertical: 12,
                                        ),
                                        backgroundColor: colorScheme.primary,
                                        foregroundColor:
                                            colorScheme.onPrimary,
                                        disabledBackgroundColor: colorScheme
                                            .primary
                                            .withValues(alpha: 0.6),
                                        shape: const StadiumBorder(),
                                        textStyle: const TextStyle(
                                          fontFamily: 'Cairo', // Fallback
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                      child: state is AuthLoading
                                          ? SizedBox(
                                              height: 22,
                                              width: 22,
                                              child:
                                                  CircularProgressIndicator(
                                                    color:
                                                        colorScheme.onPrimary,
                                                    strokeWidth: 2.5,
                                                  ),
                                            )
                                          : Text(
                                              l10n.loginButton,
                                              style: TextStyle(
                                                fontSize: 18,
                                                color: colorScheme.onPrimary,
                                                fontWeight: FontWeight.w700,
                                              ),
                                            ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                        ),

                        const Spacer(flex: 2),

                        // ---- Contact Section ----
                        FadeTransition(
                          opacity: _fadeAnimation,
                          child: GestureDetector(
                            onTap: () {
                              _launchPhoneDialer(l10n.contactNumber);
                            },
                            child: Column(
                              children: [
                                Text(
                                  l10n.noAccountTitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                                const SizedBox(height: 6),
                                Text(
                                  l10n.noAccountSubtitle,
                                  textAlign: TextAlign.center,
                                  style: TextStyle(
                                    fontSize: 13,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                                const SizedBox(height: 12),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 16,
                                    vertical: 10,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer
                                        .withValues(alpha: 0.3),
                                    borderRadius: BorderRadius.circular(20),
                                    border: Border.all(
                                      color: colorScheme.primary.withValues(
                                        alpha: 0.3,
                                      ),
                                    ),
                                  ),
                                  child: Row(
                                    mainAxisSize: MainAxisSize.min,
                                    children: [
                                      Icon(
                                        Icons.support_agent_rounded,
                                        color: colorScheme.primary,
                                        size: 20,
                                      ),
                                      const SizedBox(width: 8),
                                      Text(
                                        l10n.contactNumber,
                                        style: TextStyle(
                                          fontSize: 15,
                                          fontWeight: FontWeight.w700,
                                          letterSpacing: 1.2,
                                          color: colorScheme.primary,
                                        ),
                                        textDirection: TextDirection.ltr,
                                      ),
                                    ],
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),

                        const SizedBox(height: 24),
                      ],
                    ),
                  ),
                ),
              ],
            ),
          );
        },
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

  // ---- Helper: Launch Phone Dialer ----
  Future<void> _launchPhoneDialer(String phoneNumber) async {
    final cleanPhone = phoneNumber.replaceAll(RegExp(r'[^\d+]'), '');
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {}
    } catch (_) {}
  }

  // ---- Helper: Input decoration ----
  InputDecoration _inputDecoration({
    required String hintText,
    required IconData prefixIcon,
    required ColorScheme colorScheme,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      hintText: hintText,
      hintStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      prefixIcon: Icon(
        prefixIcon,
        color: colorScheme.onSurfaceVariant,
        size: 22,
      ),
      suffixIcon: suffixIcon,
    );
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
          // أغلق الـ bottom sheet باستخدام context الخاص به
          Navigator.pop(sheetContext);
          // انتظر frame واحد حتى يُغلق الـ bottom sheet تماماً
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
