import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/auth/presentation/auth_error_message.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/auth/presentation/pages/delegate_phone_otp_view.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_login_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/core/widgets/device_lock_dialog.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:flutter/services.dart';
import 'package:flutter/semantics.dart';
import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';

/// SharedPreferences key for the last account type picked on login.
const kLoginModePrefKey = 'login_selected_mode';

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
  bool _obscureNationalId = true;
  final _shakeKey = GlobalKey<ShakeState>();
  bool _rememberMe = false;
  LoginMode _mode = LoginMode.delegate;
  AutovalidateMode _autovalidate = AutovalidateMode.disabled;
  late AnimationController _animationController;
  late Animation<double> _fadeAnimation;
  late Animation<Offset> _sheetSlide;

  @override
  void initState() {
    super.initState();
    // Entrance: sheet slides up 500ms emphasizedDecel (starts +100ms),
    // rows stagger 50ms each (fade + 16px rise, 200ms).
    _animationController = AnimationController(
      vsync: this,
      duration: const Duration(milliseconds: 900),
    );
    _fadeAnimation = CurvedAnimation(
      parent: _animationController,
      curve: const Interval(0.1, 0.5, curve: M3Motion.standard),
    );
    _sheetSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero).animate(
      CurvedAnimation(
        parent: _animationController,
        curve: const Interval(100 / 900, 600 / 900, curve: M3Motion.emphasizedDecel),
      ),
    );
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      if (M3Motion.reduced(context)) {
        _animationController.value = 1;
      } else {
        _animationController.forward();
      }
    });
    _restoreMode();
  }

  bool get _isStaff => _mode == LoginMode.staff;

  void _restoreMode() {
    try {
      final saved = sl<SharedPreferences>().getString(kLoginModePrefKey);
      if (saved == LoginMode.staff.name) _mode = LoginMode.staff;
    } catch (_) {}
  }

  void _setMode(LoginMode mode) {
    if (mode == _mode) return;
    setState(() {
      _mode = mode;
      _passwordController.clear();
      _obscurePassword = true;
      _autovalidate = AutovalidateMode.disabled;
    });
    try {
      sl<SharedPreferences>().setString(kLoginModePrefKey, mode.name);
    } catch (_) {}
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
    if (kIsWeb) {
      return const HrLoginScreen();
    }
    return Theme(
      data: tashilAuthTheme(context),
      child: Builder(builder: _buildThemed),
    );
  }

  Widget _buildThemed(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;
    final colorScheme = Theme.of(context).colorScheme;
    final brand = kTashilBrandScheme;

    return Scaffold(
      backgroundColor: brand.primary,
      resizeToAvoidBottomInset: true,
      body: BlocConsumer<AuthBloc, AuthState>(
        listener: (context, state) => _onAuthState(context, state, l10n, colorScheme),
        builder: (context, state) {
          if (state is AuthPhoneOtpRequired) {
            return ColoredBox(
              color: colorScheme.surface,
              child: DelegatePhoneOtpView(phoneE164: state.e164Phone),
            );
          }
          final loading = state is AuthLoading;
          return LayoutBuilder(
            builder: (context, constraints) {
              final compact = constraints.maxHeight < 680;
              final headerHeight = compact
                  ? 176.0
                  : (constraints.maxHeight * 0.27).clamp(200.0, 250.0);
              final header = _buildHeader(context, isArabic, headerHeight, compact);
              final formRows = _buildFormRows(context, state, l10n, isArabic, loading);
              final bottom = _buildBottom(context, l10n, isArabic, loading);

              final sheetBody = compact
                  ? SingleChildScrollView(
                      keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                      padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [...formRows, const SizedBox(height: 24), ...bottom],
                      ),
                    )
                  : Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        Expanded(
                          child: SingleChildScrollView(
                            keyboardDismissBehavior: ScrollViewKeyboardDismissBehavior.onDrag,
                            padding: const EdgeInsets.fromLTRB(16, 28, 16, 16),
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.stretch,
                              children: formRows,
                            ),
                          ),
                        ),
                        SafeArea(
                          top: false,
                          minimum: const EdgeInsets.fromLTRB(16, 8, 16, 12),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: bottom,
                          ),
                        ),
                      ],
                    );

              return Column(
                children: [
                  header,
                  Expanded(
                    child: SlideTransition(
                      position: _sheetSlide,
                      child: Material(
                        color: colorScheme.surface,
                        shape: const RoundedRectangleBorder(
                          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: sheetBody,
                      ),
                    ),
                  ),
                ],
              );
            },
          );
        },
      ),
    );
  }

  /// Fade + 16px rise for the i-th sheet row (50ms stagger).
  Widget _row(int i, Widget child) {
    final start = (300 + 50 * i) / 900;
    final end = (start + 200 / 900).clamp(0.0, 1.0);
    final anim = CurvedAnimation(
      parent: _animationController,
      curve: Interval(start.clamp(0.0, 1.0), end, curve: M3Motion.emphasizedDecel),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(offset: Offset(0, 16 * (1 - anim.value)), child: c),
      ),
      child: child,
    );
  }

  Widget _buildHeader(BuildContext context, bool isArabic, double height, bool compact) {
    final brand = kTashilBrandScheme;
    final text = Theme.of(context).textTheme;
    return SizedBox(
      height: height + MediaQuery.paddingOf(context).top,
      child: SafeArea(
        bottom: false,
        child: Stack(
          children: [
            Center(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  TashilLogoTile(size: compact ? 56 : 80),
                  const SizedBox(height: 8),
                  FadeTransition(
                    opacity: _fadeAnimation,
                    child: Column(
                      children: [
                        Text(AppLocalizations.of(context)!.appTitle,
                            style: text.headlineMedium?.copyWith(
                                color: brand.onPrimary, fontWeight: FontWeight.w700, height: 1.3)),
                        if (!compact)
                          Text(AppLocalizations.of(context)!.delegateApp,
                              style: text.bodyMedium?.copyWith(
                                  color: brand.onPrimary.withValues(alpha: 0.85))),
                      ],
                    ),
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              top: 4,
              end: 16,
              child: FadeTransition(
                opacity: _fadeAnimation,
                child: OutlinedButton.icon(
                  key: const ValueKey('login_language_toggle'),
                  onPressed: () => localeProvider.toggleLocale(),
                  icon: const Icon(Icons.language_rounded, size: 18),
                  label: Text(isArabic ? 'English' : 'العربية'),
                  style: OutlinedButton.styleFrom(
                    foregroundColor: brand.onPrimary,
                    minimumSize: const Size(0, 40),
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    side: BorderSide(color: brand.onPrimary.withValues(alpha: 0.6)),
                    shape: const StadiumBorder(),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFormRows(BuildContext context, AuthState state,
      AppLocalizations l10n, bool isArabic, bool loading) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    var i = 0;
    return [
      _row(i++, Text(l10n.loginButton,
          style: text.titleLarge?.copyWith(fontWeight: FontWeight.w600, color: colorScheme.onSurface))),
      _row(i++, Text(
        key: const ValueKey('login_mode_helper'),
        _isStaff
            ? (isArabic ? 'اختر نوع حسابك ثم ادخل بكلمة المرور' : 'Pick your account type, then sign in with your password')
            : (isArabic ? 'اختر نوع حسابك ثم أدخل بياناتك' : 'Pick your account type, then enter your details'),
        style: text.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
      )),
      const SizedBox(height: 20),
      _row(i++, M3ButtonGroup<LoginMode>(
        key: const ValueKey('login_mode_switch'),
        values: const [LoginMode.delegate, LoginMode.staff],
        labels: [isArabic ? 'مندوب' : 'Delegate', isArabic ? 'موظف إداري' : 'Admin staff'],
        icons: const [Icons.badge_outlined, Icons.admin_panel_settings_outlined],
        selected: _mode,
        onChanged: loading ? null : _setMode,
      )),
      const SizedBox(height: 24),
      _row(i++, Shake(
        key: _shakeKey,
        child: Form(
          key: _formKey,
          autovalidateMode: _autovalidate,
          child: AutofillGroup(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: _buildFields(context, l10n, isArabic, loading),
            ),
          ),
        ),
      )),
      _row(i++, CheckboxListTile(
        key: const ValueKey('login_remember_me'),
        value: _rememberMe,
        onChanged: (v) => setState(() => _rememberMe = v ?? false),
        controlAffinity: ListTileControlAffinity.leading,
        contentPadding: EdgeInsets.zero,
        dense: false,
        visualDensity: VisualDensity.standard,
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
        title: Text(l10n.rememberMe, style: text.bodyLarge?.copyWith(color: colorScheme.onSurface)),
      )),
    ];
  }

  List<Widget> _buildFields(BuildContext context, AppLocalizations l10n, bool isArabic, bool loading) {
    final colorScheme = Theme.of(context).colorScheme;
    final fieldStyle = TextStyle(fontSize: 16, color: colorScheme.onSurface, letterSpacing: 1);
    final eyeColor = colorScheme.onSurfaceVariant;
    return [
      TextFormField(
        key: const ValueKey('login_phone'),
        controller: _phoneController,
        keyboardType: TextInputType.phone,
        inputFormatters: [
          FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
          LengthLimitingTextInputFormatter(11),
        ],
        textInputAction: TextInputAction.next,
        autocorrect: false,
        enableSuggestions: false,
        autofillHints: const [AutofillHints.telephoneNumber],
        textDirection: TextDirection.ltr,
        textAlign: TextAlign.right,
        style: fieldStyle,
        decoration: _inputDecoration(
          label: l10n.mobileNumber,
          helper: isArabic ? 'رقم الجوال المسجل لدى الشركة' : 'Your mobile number registered with the company',
          colorScheme: colorScheme,
        ),
        validator: (value) => validateLoginPhone(
          value,
          emptyMessage: l10n.enterMobileNumber,
          invalidMessage: l10n.invalidMobileNumber,
        ),
      ),
      const SizedBox(height: 16),
      if (!_isStaff)
        TextFormField(
          key: const ValueKey('login_national_id'),
          controller: _passwordController,
          keyboardType: TextInputType.number,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9٠-٩۰-۹]')),
            LengthLimitingTextInputFormatter(14),
          ],
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          obscureText: _obscureNationalId,
          onFieldSubmitted: (_) => _submitLogin(context),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          style: fieldStyle,
          decoration: _inputDecoration(
            label: l10n.nationalIdNumber,
            helper: isArabic ? '14 رقم' : '14 digits',
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              key: const ValueKey('login_national_id_eye'),
              tooltip: _obscureNationalId ? (isArabic ? 'إظهار' : 'Show') : (isArabic ? 'إخفاء' : 'Hide'),
              icon: Icon(_obscureNationalId ? Icons.visibility_rounded : Icons.visibility_off_rounded,
                  color: eyeColor),
              onPressed: () => setState(() => _obscureNationalId = !_obscureNationalId),
            ),
          ),
          validator: (value) => validateDelegateNationalId(
            value,
            emptyMessage: l10n.enterNationalId,
            invalidMessage: l10n.invalidNationalId,
          ),
        )
      else
        TextFormField(
          key: const ValueKey('login_staff_password'),
          controller: _passwordController,
          keyboardType: TextInputType.visiblePassword,
          textInputAction: TextInputAction.done,
          autocorrect: false,
          enableSuggestions: false,
          autofillHints: const [AutofillHints.password],
          onFieldSubmitted: (_) => _submitLogin(context),
          textDirection: TextDirection.ltr,
          textAlign: TextAlign.right,
          obscureText: _obscurePassword,
          style: fieldStyle,
          decoration: _inputDecoration(
            label: isArabic ? 'كلمة المرور' : 'Password',
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              tooltip: _obscurePassword ? (isArabic ? 'إظهار' : 'Show') : (isArabic ? 'إخفاء' : 'Hide'),
              icon: Icon(
                _obscurePassword ? Icons.visibility_off_outlined : Icons.visibility_outlined,
                color: eyeColor,
              ),
              onPressed: () => setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) => validateStaffPassword(
            value,
            emptyMessage: isArabic ? 'يرجى إدخال كلمة المرور' : 'Please enter your password',
          ),
        ),
      if (_isStaff)
        Align(
          alignment: AlignmentDirectional.centerEnd,
          child: TextButton(
            key: const ValueKey('login_forgot_password'),
            onPressed: loading ? null : () => _forgotPassword(context, isArabic),
            child: Text(isArabic ? 'نسيت كلمة المرور؟' : 'Forgot password?'),
          ),
        )
      else
        const SizedBox(height: 8),
    ];
  }

  List<Widget> _buildBottom(BuildContext context, AppLocalizations l10n, bool isArabic, bool loading) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduce = M3Motion.reduced(context);
    return [
      Semantics(
        liveRegion: loading,
        label: loading ? (isArabic ? 'جارٍ تسجيل الدخول' : 'Signing in') : null,
        child: SizedBox(
          height: 52,
          child: FilledButton(
            key: const ValueKey('login_submit'),
            // IgnorePointer keeps the primary colour while loading (spec §3).
            onPressed: () => _submitLogin(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              shape: const StadiumBorder(),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(fontSize: 16, fontWeight: FontWeight.w600),
            ),
            child: IgnorePointer(
              ignoring: loading,
              child: AnimatedSwitcher(
                duration: reduce ? Duration.zero : M3Motion.short4,
                switchInCurve: M3Motion.emphasizedDecel,
                switchOutCurve: M3Motion.emphasizedAccel,
                child: loading
                    ? SizedBox.square(
                        key: const ValueKey('login_loading'),
                        dimension: 20,
                        child: CircularProgressIndicator(strokeWidth: 2.5, color: colorScheme.onPrimary),
                      )
                    : Text(l10n.loginButton, key: const ValueKey('login_label')),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      TextButton(
        key: const ValueKey('login_support_button'),
        onPressed: () => _launchPhoneDialer(l10n.contactNumber),
        child: Text(isArabic ? 'تواصل مع الدعم الفني' : 'Contact support'),
      ),
      TashilVersionText(color: colorScheme.onSurfaceVariant, isArabic: isArabic),
    ];
  }

  void _onAuthState(BuildContext context, AuthState state, AppLocalizations l10n, ColorScheme colorScheme) {
          if (state is AuthDeviceMismatchState) {
            DeviceLockDialog.show(
              context,
              boundDeviceModel: state.boundDeviceModel,
              currentDeviceModel: state.currentDeviceModel,
              delegateName: state.delegate.fullName,
              delegate: state.delegate,
            );
          } else if (state is AuthError) {
            if (state.code == 'device_mismatch') {
              DeviceLockDialog.show(context, requestAlreadyFiled: true);
            } else {
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: Text(
                    localizedAuthError(
                      l10n,
                      message: state.message,
                      code: state.code,
                    ),
                  ),
                  backgroundColor: colorScheme.error,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                  ),
                ),
              );
            }
          } else if (state is AuthOrganizationSelectionRequired) {
            _showOrganizationSelector(
              context,
              state.delegates,
              state.rememberMe,
            );
          } else if (state is AuthAuthenticated) {
            final delegate = state.delegate;
            debugPrint('🚀 LoginScreen: AuthAuthenticated received! name=${delegate.fullName}, role=${delegate.role}, uid=${delegate.uid}');
            try {
              if (delegate.role == UserRole.superAdmin ||
                  delegate.role == UserRole.admin ||
                  delegate.role == UserRole.organizationAdmin ||
                  delegate.role == UserRole.technicalSupport ||
                  delegate.role == UserRole.branchesMarketingManager) {
                debugPrint('🚀 LoginScreen: Navigating to /admin/home');
                context.go('/admin/home', extra: delegate);
              } else if (delegate.role == UserRole.accountant) {
                debugPrint('🚀 LoginScreen: Navigating to /accountant/home');
                context.go('/accountant/home', extra: delegate);
              } else if (delegate.role == UserRole.hr) {
                debugPrint('🚀 LoginScreen: Navigating to /hr/home');
                context.go('/hr/home', extra: delegate);
              } else if (delegate.role == UserRole.marketing ||
                  delegate.role == UserRole.marketingPromotion) {
                debugPrint('🚀 LoginScreen: Navigating to /marketing/home');
                context.go('/marketing/home', extra: delegate);
              } else {
                debugPrint('🚀 LoginScreen: Navigating to /home');
                context.go('/home', extra: delegate);
              }
            } catch (e, stack) {
              debugPrint('❌ Navigation Error in LoginScreen: $e\n$stack');
            }

            // تهيئة الإشعارات في الخلفية بعد اكتمال الانتقال لتجنب تجميد الواجهة أو قفل حوار الأذونات
            Future.delayed(const Duration(milliseconds: 1500), () {
              sl<PushNotificationService>()
                  .initialize(delegate.uid)
                  .catchError((e) {
                    debugPrint('FCM Init Error: $e');
                  });
            });
          }
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
          mode: _mode,
        ),
      );
    } else {
      // Submit failure only: shake + haptic + announce + focus first invalid.
      _shakeKey.currentState?.shake();
      HapticFeedback.heavyImpact();
      final isArabic = localeProvider.isArabic;
      SemanticsService.sendAnnouncement(
        View.of(context),
        isArabic ? 'يرجى مراجعة البيانات المدخلة' : 'Please check the highlighted fields',
        isArabic ? TextDirection.rtl : TextDirection.ltr,
      );
      if (_autovalidate != AutovalidateMode.onUserInteraction) {
        setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      }
    }
  }

  // ---- Helper: Forgot password (staff only) ----
  Future<void> _forgotPassword(BuildContext context, bool isArabic) async {
    final messenger = ScaffoldMessenger.of(context);
    final colorScheme = Theme.of(context).colorScheme;
    String? email;
    final phone = _phoneController.text.trim();
    if (phone.isNotEmpty) {
      try {
        final ds = sl<AuthRemoteDataSource>();
        if (ds is AuthRemoteDataSourceImpl) {
          email = await ds.lookupStaffEmail(phone);
        }
      } catch (_) {}
    }
    if (!context.mounted) return;
    final entered = await _askResetEmail(context, isArabic, prefill: email);
    if (entered == null || !context.mounted) return;
    try {
      await FirebaseAuth.instance.sendPasswordResetEmail(email: entered);
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(isArabic
            ? 'لو الإيميل مسجّل، هيوصلك رابط لتغيير كلمة المرور.'
            : 'If this email is registered, a reset link is on its way.'),
      ));
    } catch (_) {
      messenger.showSnackBar(SnackBar(
        behavior: SnackBarBehavior.floating,
        backgroundColor: colorScheme.error,
        content: Text(isArabic
            ? 'تعذر إرسال رابط تغيير كلمة المرور. حاول مرة أخرى.'
            : 'Could not send the reset link. Try again.'),
      ));
    }
  }

  Future<String?> _askResetEmail(
    BuildContext context,
    bool isArabic, {
    String? prefill,
  }) {
    final controller = TextEditingController(text: prefill ?? '');
    final key = GlobalKey<FormState>();
    return showDialog<String>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        icon: const Icon(Icons.lock_reset_rounded),
        title: Text(isArabic ? 'نسيت كلمة المرور' : 'Forgot password'),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            autofocus: prefill == null,
            decoration: InputDecoration(
              labelText: isArabic ? 'البريد الإلكتروني' : 'Email',
              prefixIcon: const Icon(Icons.alternate_email_rounded),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                return isArabic ? 'يرجى إدخال بريد إلكتروني صحيح' : 'Enter a valid email';
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(isArabic ? 'إلغاء' : 'Cancel'),
          ),
          TextButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: Text(isArabic ? 'إرسال الرابط' : 'Send link'),
          ),
        ],
      ),
    );
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

  // ---- Helper: Input decoration (outlined, floating label + helper) ----
  InputDecoration _inputDecoration({
    required String label,
    String? helper,
    required ColorScheme colorScheme,
    Widget? suffixIcon,
  }) {
    return InputDecoration(
      labelText: label,
      helperText: helper,
      helperStyle: TextStyle(color: colorScheme.onSurfaceVariant),
      filled: false,
      border: const OutlineInputBorder(),
      enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.outline)),
      focusedBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.primary, width: 2)),
      errorBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.error)),
      focusedErrorBorder: OutlineInputBorder(borderSide: BorderSide(color: colorScheme.error, width: 2)),
      counterText: '',
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
