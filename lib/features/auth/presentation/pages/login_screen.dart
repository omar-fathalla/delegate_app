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
    with TickerProviderStateMixin {
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
  // Submit choreography: 0 = form, 1 = sheet gone + logo centered + loader.
  late final AnimationController _submit = AnimationController(
    vsync: this,
    duration: M3Motion.medium4,
  );
  late final Animation<double> _submitCurve = CurvedAnimation(
    parent: _submit,
    curve: M3Motion.emphasizedAccel,
    reverseCurve: M3Motion.emphasizedDecel,
  );
  late final Animation<double> _logoCurve = CurvedAnimation(
    parent: _submit,
    curve: Curves.easeInOutCubicEmphasized,
  );

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
    _sheetSlide = Tween<Offset>(begin: const Offset(0, 1), end: Offset.zero)
        .animate(
          CurvedAnimation(
            parent: _animationController,
            curve: const Interval(
              100 / 900,
              600 / 900,
              curve: M3Motion.emphasizedDecel,
            ),
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
    _submit.dispose();
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
        listener: (context, state) =>
            _onAuthState(context, state, l10n, colorScheme),
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
              final header = _buildHeader(
                context,
                isArabic,
                headerHeight,
                compact,
              );
              final formRows = _buildFormRows(
                context,
                state,
                l10n,
                isArabic,
                loading,
              );
              final bottom = _buildBottom(context, l10n, isArabic, loading);

              // Grouped sections on an 8dp rhythm. Leftover height is shared
              // evenly between the groups (Spacers); the button stays at the
              // bottom on tall screens and everything scrolls when it can't fit.
              final sheetBody = CustomScrollView(
                keyboardDismissBehavior:
                    ScrollViewKeyboardDismissBehavior.onDrag,
                slivers: [
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: SafeArea(
                      top: false,
                      minimum: EdgeInsets.fromLTRB(
                        16,
                        compact ? 24 : 32,
                        16,
                        12,
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          formRows[0], // (1) title + subtitle
                          const SizedBox(height: 24),
                          const Spacer(),
                          formRows[1], // (2) account type
                          const SizedBox(height: 32),
                          const Spacer(),
                          formRows[2], // (3) fields
                          const SizedBox(height: 8),
                          formRows[3], // (4) remember me + forgot password
                          const SizedBox(height: 24),
                          const Spacer(),
                          ...bottom, // (5) login + support + version
                        ],
                      ),
                    ),
                  ),
                ],
              );

              final reduce = M3Motion.reduced(context);
              final sheet = SlideTransition(
                position: _sheetSlide,
                child: Material(
                  color: colorScheme.surface,
                  shape: const RoundedRectangleBorder(
                    borderRadius: BorderRadius.vertical(
                      top: Radius.circular(28),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: sheetBody,
                ),
              );
              return Stack(
                children: [
                  Positioned.fill(
                    child: Column(
                      children: [
                        SizedBox(
                          height:
                              headerHeight + MediaQuery.paddingOf(context).top,
                        ),
                        Expanded(
                          child: reduce
                              ? FadeTransition(
                                  opacity: ReverseAnimation(_submit),
                                  child: sheet,
                                )
                              : SlideTransition(
                                  position: Tween<Offset>(
                                    begin: Offset.zero,
                                    end: const Offset(0, 1.05),
                                  ).animate(_submitCurve),
                                  child: sheet,
                                ),
                        ),
                      ],
                    ),
                  ),
                  Positioned(
                    top: 0,
                    left: 0,
                    right: 0,
                    child: AnimatedBuilder(
                      animation: _logoCurve,
                      builder: (context, child) {
                        final t = _logoCurve.value;
                        final dy = reduce
                            ? 0.0
                            : (constraints.maxHeight / 2 -
                                      (MediaQuery.paddingOf(context).top +
                                          headerHeight / 2)) *
                                  t;
                        return Transform.translate(
                          offset: Offset(0, dy),
                          child: child,
                        );
                      },
                      child: header,
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
      curve: Interval(
        start.clamp(0.0, 1.0),
        end,
        curve: M3Motion.emphasizedDecel,
      ),
    );
    return AnimatedBuilder(
      animation: anim,
      builder: (_, c) => Opacity(
        opacity: anim.value,
        child: Transform.translate(
          offset: Offset(0, 16 * (1 - anim.value)),
          child: c,
        ),
      ),
      child: child,
    );
  }

  Widget _buildHeader(
    BuildContext context,
    bool isArabic,
    double height,
    bool compact,
  ) {
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
                  ScaleTransition(
                    scale: Tween<double>(
                      begin: 1,
                      end: M3Motion.reduced(context)
                          ? 1
                          : (compact ? 1.6 : 1.3),
                    ).animate(_logoCurve),
                    child: TashilLogoTile(size: compact ? 56 : 80),
                  ),
                  const SizedBox(height: 8),
                  Stack(
                    alignment: Alignment.topCenter,
                    children: [
                      FadeTransition(
                        opacity: ReverseAnimation(_submit),
                        child: FadeTransition(
                          opacity: _fadeAnimation,
                          child: Column(
                            children: [
                              Text(
                                AppLocalizations.of(context)!.appTitle,
                                style: text.headlineMedium?.copyWith(
                                  color: brand.onPrimary,
                                  fontWeight: FontWeight.w700,
                                  height: 1.3,
                                ),
                              ),
                              if (!compact)
                                Text(
                                  AppLocalizations.of(context)!.delegateApp,
                                  style: text.bodyMedium?.copyWith(
                                    color: brand.onPrimary.withValues(
                                      alpha: 0.85,
                                    ),
                                  ),
                                ),
                            ],
                          ),
                        ),
                      ),
                      Padding(
                        padding: const EdgeInsets.only(top: 24),
                        child: FadeTransition(
                          key: const ValueKey('login_submit_loader'),
                          opacity: CurvedAnimation(
                            parent: _submit,
                            curve: const Interval(0.5, 1),
                          ),
                          child: SizedBox.square(
                            dimension: 40,
                            child: AnimatedBuilder(
                              animation: _submit,
                              builder: (_, _) => _submit.isDismissed
                                  ? const SizedBox.shrink()
                                  : CircularProgressIndicator(
                                      color: brand.onPrimary,
                                      strokeWidth: 4,
                                      strokeCap: StrokeCap.round,
                                    ),
                            ),
                          ),
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            PositionedDirectional(
              top: 4,
              end: 16,
              child: FadeTransition(
                opacity: ReverseAnimation(_submit),
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
                      side: BorderSide(
                        color: brand.onPrimary.withValues(alpha: 0.6),
                      ),
                      shape: const StadiumBorder(),
                    ),
                  ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  List<Widget> _buildFormRows(
    BuildContext context,
    AuthState state,
    AppLocalizations l10n,
    bool isArabic,
    bool loading,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    var i = 0;
    return [
      _row(
        i++,
        Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              l10n.loginButton,
              style: text.titleLarge?.copyWith(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              key: const ValueKey('login_mode_helper'),
              _isStaff
                  ? AppLocalizations.of(context)!.loginSubtitleStaff
                  : AppLocalizations.of(context)!.loginSubtitleDelegate,
              style: text.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
      _row(
        i++,
        M3ButtonGroup<LoginMode>(
          key: const ValueKey('login_mode_switch'),
          values: const [LoginMode.delegate, LoginMode.staff],
          labels: [
            AppLocalizations.of(context)!.roleDelegate,
            AppLocalizations.of(context)!.staffLabel,
          ],
          icons: const [
            Icons.badge_outlined,
            Icons.admin_panel_settings_outlined,
          ],
          selected: _mode,
          onChanged: loading ? null : _setMode,
        ),
      ),
      _row(
        i++,
        Shake(
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
        ),
      ),
      _row(
        i++,
        Row(
          children: [
            // Compact: checkbox, 8dp, label; whole row tappable, 48dp min.
            InkWell(
              key: const ValueKey('login_remember_me'),
              borderRadius: BorderRadius.circular(8),
              onTap: () => setState(() => _rememberMe = !_rememberMe),
              child: ConstrainedBox(
                constraints: const BoxConstraints(minHeight: 48),
                child: Padding(
                  padding: const EdgeInsetsDirectional.only(end: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Semantics(
                        label: l10n.rememberMe,
                        child: Checkbox(
                          value: _rememberMe,
                          materialTapTargetSize:
                              MaterialTapTargetSize.shrinkWrap,
                          visualDensity: VisualDensity.compact,
                          onChanged: (v) =>
                              setState(() => _rememberMe = v ?? false),
                        ),
                      ),
                      const SizedBox(width: 4),
                      Text(
                        l10n.rememberMe,
                        style: text.bodyLarge?.copyWith(
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const Spacer(),
            if (_isStaff)
              TextButton(
                key: const ValueKey('login_forgot_password'),
                onPressed: loading
                    ? null
                    : () => _forgotPassword(context, isArabic),
                child: Text(AppLocalizations.of(context)!.forgotPasswordQ,
                ),
              ),
          ],
        ),
      ),
    ];
  }

  List<Widget> _buildFields(
    BuildContext context,
    AppLocalizations l10n,
    bool isArabic,
    bool loading,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final fieldStyle = TextStyle(
      fontSize: 16,
      color: colorScheme.onSurface,
      letterSpacing: 1,
    );
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
          helper: AppLocalizations.of(context)!.phoneHelper,
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
            helper: AppLocalizations.of(context)!.nationalIdHelper,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              key: const ValueKey('login_national_id_eye'),
              tooltip: _obscureNationalId
                  ? AppLocalizations.of(context)!.showAction
                  : AppLocalizations.of(context)!.hideAction,
              icon: Icon(
                _obscureNationalId
                    ? Icons.visibility_rounded
                    : Icons.visibility_off_rounded,
                color: eyeColor,
              ),
              onPressed: () =>
                  setState(() => _obscureNationalId = !_obscureNationalId),
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
            label: AppLocalizations.of(context)!.password,
            colorScheme: colorScheme,
            suffixIcon: IconButton(
              tooltip: _obscurePassword
                  ? AppLocalizations.of(context)!.showAction
                  : AppLocalizations.of(context)!.hideAction,
              icon: Icon(
                _obscurePassword
                    ? Icons.visibility_off_outlined
                    : Icons.visibility_outlined,
                color: eyeColor,
              ),
              onPressed: () =>
                  setState(() => _obscurePassword = !_obscurePassword),
            ),
          ),
          validator: (value) => validateStaffPassword(
            value,
            emptyMessage: AppLocalizations.of(context)!.enterPassword2,
          ),
        ),
    ];
  }

  List<Widget> _buildBottom(
    BuildContext context,
    AppLocalizations l10n,
    bool isArabic,
    bool loading,
  ) {
    final colorScheme = Theme.of(context).colorScheme;
    final reduce = M3Motion.reduced(context);
    return [
      Semantics(
        liveRegion: loading,
        label: loading ? AppLocalizations.of(context)!.signingIn : null,
        child: ConstrainedBox(
          // min 52dp; grows with large text scales instead of clipping.
          constraints: const BoxConstraints(minHeight: 52),
          child: FilledButton(
            key: const ValueKey('login_submit'),
            // IgnorePointer keeps the primary colour while loading (spec §3).
            onPressed: () => _submitLogin(context),
            style: FilledButton.styleFrom(
              minimumSize: const Size.fromHeight(52),
              // The app theme's FilledButton padding is vertical 16, which in
              // a 52dp box left only 20dp for Cairo's ~27dp line and clipped
              // the label. Keep vertical padding small and centre the label.
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 8),
              alignment: Alignment.center,
              foregroundColor: colorScheme.onPrimary,
              backgroundColor: colorScheme.primary,
              shape: const StadiumBorder(),
              textStyle: Theme.of(context).textTheme.labelLarge?.copyWith(
                fontSize: 16,
                fontWeight: FontWeight.w600,
                height: 1.4,
              ),
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
                        child: CircularProgressIndicator(
                          strokeWidth: 2.5,
                          color: colorScheme.onPrimary,
                        ),
                      )
                    : Text(
                        l10n.loginButton,
                        key: const ValueKey('login_label'),
                        textAlign: TextAlign.center,
                        maxLines: 1,
                        overflow: TextOverflow.visible,
                        style: TextStyle(color: colorScheme.onPrimary),
                      ),
              ),
            ),
          ),
        ),
      ),
      const SizedBox(height: 4),
      TextButton(
        key: const ValueKey('login_support_button'),
        onPressed: () => _launchPhoneDialer(l10n.contactNumber),
        child: Text(AppLocalizations.of(context)!.contactSupport),
      ),
      TashilVersionText(
        color: colorScheme.onSurfaceVariant,
        isArabic: isArabic,
      ),
    ];
  }

  void _onAuthState(
    BuildContext context,
    AuthState state,
    AppLocalizations l10n,
    ColorScheme colorScheme,
  ) {
    if (state is! AuthLoading &&
        state is! AuthAuthenticated &&
        _submit.value > 0) {
      // Failure / extra step: bring the form back, then shake on error.
      final isError = state is AuthError || state is AuthDeviceMismatchState;
      _submit.reverse().then((_) {
        if (mounted && isError) _shakeKey.currentState?.shake();
      });
    }
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
      _showOrganizationSelector(context, state.delegates, state.rememberMe);
    } else if (state is AuthAuthenticated) {
      final delegate = state.delegate;
      debugPrint(
        '🚀 LoginScreen: AuthAuthenticated received! name=${delegate.fullName}, role=${delegate.role}, uid=${delegate.uid}',
      );
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
        sl<PushNotificationService>().initialize(delegate.uid).catchError((e) {
          debugPrint('FCM Init Error: $e');
        });
      });
    }
  }

  // ---- Helper: Submit Login ----
  void _submitLogin(BuildContext context) {
    if (BlocProvider.of<AuthBloc>(context).state is AuthLoading) return;

    if (_formKey.currentState!.validate()) {
      FocusScope.of(context).unfocus();
      _submit.forward();
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
        AppLocalizations.of(context)!.checkHighlightedFields,
        isArabic ? TextDirection.rtl : TextDirection.ltr,
      );
      if (_autovalidate != AutovalidateMode.onUserInteraction) {
        setState(() => _autovalidate = AutovalidateMode.onUserInteraction);
      }
    }
  }

  // ---- Helper: Forgot password (staff only) ----
  Future<void> _forgotPassword(BuildContext context, bool isArabic) async {
    final l10n = AppLocalizations.of(context)!;
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
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          content: Text(l10n.resetLinkSentIfRegistered,
          ),
        ),
      );
    } catch (_) {
      messenger.showSnackBar(
        SnackBar(
          behavior: SnackBarBehavior.floating,
          backgroundColor: colorScheme.error,
          content: Text(l10n.resetLinkFailed,
          ),
        ),
      );
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
        title: Text(AppLocalizations.of(context)!.forgotPassword),
        content: Form(
          key: key,
          child: TextFormField(
            controller: controller,
            keyboardType: TextInputType.emailAddress,
            textDirection: TextDirection.ltr,
            autofocus: prefill == null,
            decoration: InputDecoration(
              labelText: AppLocalizations.of(context)!.emailLabel,
              prefixIcon: const Icon(Icons.alternate_email_rounded),
            ),
            validator: (v) {
              final t = (v ?? '').trim();
              if (!RegExp(r'^[^@\s]+@[^@\s]+\.[^@\s]+$').hasMatch(t)) {
                return AppLocalizations.of(context)!.invalidEmail2;
              }
              return null;
            },
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(AppLocalizations.of(context)!.cancel),
          ),
          TextButton(
            onPressed: () {
              if (key.currentState!.validate()) {
                Navigator.pop(dialogContext, controller.text.trim());
              }
            },
            child: Text(AppLocalizations.of(context)!.sendLink),
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
      enabledBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.outline),
      ),
      focusedBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.primary, width: 2),
      ),
      errorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error),
      ),
      focusedErrorBorder: OutlineInputBorder(
        borderSide: BorderSide(color: colorScheme.error, width: 2),
      ),
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
              Text(AppLocalizations.of(context)!.selectOrganization,
                style: TextStyle(
                  fontSize: 20,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 8),
              Text(AppLocalizations.of(context)!.multipleOrgsChoose,
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
