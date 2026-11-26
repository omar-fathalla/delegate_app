import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';
import 'package:delegate_app/features/auth/presentation/widgets/web_hr_login_map.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// HR web login. Mounted only when [WebRuntimePolicy.isWeb] is true.
///
/// Wide windows (≥840) use the brand hero (TAS-188): the whole page is the
/// theme purple with a light map of the Nile Delta and red branch pins, the
/// headline sits on the start side, and the form is a floating side sheet on
/// the end side (520 wide from 1200, 440 below). The fields stay at most 400
/// wide. Below 840, a compact brand band, the form, and all eight features
/// stack in one column.
class WebHrLoginView extends StatelessWidget {
  const WebHrLoginView({
    super.key,
    required this.formKey,
    required this.shakeKey,
    required this.phoneController,
    required this.passwordController,
    required this.obscurePassword,
    required this.rememberMe,
    required this.loading,
    required this.autovalidateMode,
    required this.formError,
    required this.credentialError,
    required this.delegateNotice,
    required this.isArabic,
    required this.onToggleObscure,
    required this.onToggleRemember,
    required this.onSubmit,
    required this.onForgot,
    required this.onSupport,
    required this.onSupportWhatsApp,
    required this.onLanguage,
  });

  static const double wideBreakpoint = 840;
  static const double comfortableBreakpoint = 1200;
  static const double formMaxWidth = 400;

  final GlobalKey<FormState> formKey;
  final GlobalKey<ShakeState> shakeKey;
  final TextEditingController phoneController;
  final TextEditingController passwordController;
  final bool obscurePassword;
  final bool rememberMe;
  final bool loading;
  final AutovalidateMode autovalidateMode;
  final String? formError;
  final bool credentialError;
  final bool delegateNotice;
  final bool isArabic;
  final VoidCallback onToggleObscure;
  final VoidCallback onToggleRemember;
  final VoidCallback onSubmit;
  final VoidCallback onForgot;

  /// Calls the support number.
  final VoidCallback onSupport;

  /// Opens a WhatsApp chat with the support number.
  final VoidCallback onSupportWhatsApp;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideBreakpoint) {
          return _HeroLayout(view: this, size: constraints.biggest);
        }
        return _NarrowColumn(view: this);
      },
    );
  }
}

/// Wide layout: brand hero with the map, and the form in a side sheet.
class _HeroLayout extends StatelessWidget {
  const _HeroLayout({required this.view, required this.size});

  final WebHrLoginView view;
  final Size size;

  static const double _sheetMargin = 16;

  @override
  Widget build(BuildContext context) {
    final brand = _BrandColors.of(context);
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final comfortable = size.width >= WebHrLoginView.comfortableBreakpoint;
    final sheetWidth = comfortable ? 520.0 : 440.0;
    final copyInset = comfortable ? 64.0 : 40.0;

    // Free hero area beside the sheet; the map sits under the headline.
    final sheetEdge = _sheetMargin + sheetWidth + 40;
    final freeLeft = rtl ? sheetEdge : 40.0;
    final freeRight = rtl ? size.width - 40 : size.width - sheetEdge;
    final freeWidth = (freeRight - freeLeft).clamp(0.0, double.infinity);
    final mapTop = (size.height * .42).clamp(340.0, double.infinity);
    // Keep Cairo (the lowest pins) above the bottom edge.
    final byHeight =
        ((size.height - 40 - mapTop) / (kHrLoginMapCairoY + .06)) *
        kHrLoginMapAspect;
    final mapWidth = freeWidth < byHeight ? freeWidth : byHeight;
    final mapBox = Rect.fromLTWH(
      freeLeft + (freeWidth - mapWidth) / 2,
      mapTop,
      mapWidth,
      mapWidth / kHrLoginMapAspect,
    );
    final copyWidth = (freeWidth + 40 - copyInset).clamp(240.0, 600.0);

    return ColoredBox(
      color: brand.panel,
      child: Stack(
        children: [
          Positioned.fill(
            child: IgnorePointer(
              // Decorative: screen readers skip the map and pins.
              child: ExcludeSemantics(
                child: HrLoginMap(
                  key: const ValueKey('login_web_map'),
                  box: mapBox,
                  ink: brand.onPanel,
                  water: brand.onPanelMuted,
                  isArabic: view.isArabic,
                ),
              ),
            ),
          ),
          PositionedDirectional(
            start: copyInset,
            top: 40,
            width: copyWidth,
            child: _HeroCopy(
              isArabic: view.isArabic,
              brand: brand,
              large: comfortable,
            ),
          ),
          PositionedDirectional(
            end: _sheetMargin,
            top: _sheetMargin,
            bottom: _sheetMargin,
            width: sheetWidth,
            child: _SideSheet(view: view, roomy: comfortable),
          ),
        ],
      ),
    );
  }
}

class _HeroCopy extends StatelessWidget {
  const _HeroCopy({
    required this.isArabic,
    required this.brand,
    required this.large,
  });

  final bool isArabic;
  final _BrandColors brand;
  final bool large;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    final headline = large ? text.displayMedium : text.displaySmall;
    return _EnterFade(
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            key: const ValueKey('login_web_brand_header'),
            mainAxisSize: MainAxisSize.min,
            children: [
              TashilLogoTile(size: large ? 56 : 48),
              const SizedBox(width: 14),
              Text(
                l10n.appTitle,
                style: text.headlineSmall?.copyWith(
                  color: brand.onPanel,
                  fontWeight: FontWeight.w800,
                  height: 1.2,
                ),
              ),
              const SizedBox(width: 14),
              Container(
                width: 1,
                height: 24,
                color: brand.onPanel.withValues(alpha: .35),
              ),
              const SizedBox(width: 14),
              Flexible(
                child: Text(
                  isArabic ? 'نظام الموارد البشرية' : 'HR system',
                  overflow: TextOverflow.ellipsis,
                  style: text.titleMedium?.copyWith(
                    color: brand.onPanelMuted,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
          ),
          SizedBox(height: large ? 72 : 48),
          Text(
            key: const ValueKey('login_web_headline'),
            isArabic
                ? 'فريقك في الفروع في نظام واحد'
                : 'Your branch teams, in one system',
            style: headline?.copyWith(
              color: brand.onPanel,
              fontWeight: FontWeight.w800,
              height: 1.25,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            isArabic
                ? 'لشركات التجزئة العاملة مع الهايبرماركت'
                : 'For retail companies working with hypermarkets',
            style: text.titleMedium?.copyWith(
              color: brand.onPanelMuted,
              fontSize: large ? 18 : 16,
              height: 1.4,
            ),
          ),
        ],
      ),
    );
  }
}

/// Fades and slides its child in once when the page opens.
class _EnterFade extends StatelessWidget {
  const _EnterFade({required this.child, this.fromEnd = false});

  final Widget child;
  final bool fromEnd;

  @override
  Widget build(BuildContext context) {
    if (MediaQuery.disableAnimationsOf(context)) return child;
    final rtl = Directionality.of(context) == TextDirection.rtl;
    final dx = fromEnd ? (rtl ? -24.0 : 24.0) : 0.0;
    return TweenAnimationBuilder<double>(
      tween: Tween(begin: 0, end: 1),
      duration: AppMotionDurations.long2,
      curve: AppMotionCurves.emphasizedDecelerate,
      child: child,
      builder: (context, t, child) => Opacity(
        opacity: t,
        child: Transform.translate(
          offset: Offset(dx * (1 - t), fromEnd ? 0 : 12 * (1 - t)),
          child: child,
        ),
      ),
    );
  }
}

/// The floating sheet that holds the form (M3 side sheet, radius 28).
class _SideSheet extends StatelessWidget {
  const _SideSheet({required this.view, required this.roomy});

  final WebHrLoginView view;
  final bool roomy;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return _EnterFade(
      fromEnd: true,
      child: Material(
        key: const ValueKey('login_web_sheet'),
        color: cs.surface,
        elevation: 6,
        shadowColor: Colors.black.withValues(alpha: .35),
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
        clipBehavior: Clip.antiAlias,
        child: Padding(
          padding: EdgeInsets.fromLTRB(
            roomy ? 48 : 24,
            24,
            roomy ? 48 : 24,
            20,
          ),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: _LanguageChip(
                  isArabic: view.isArabic,
                  onPressed: view.onLanguage,
                ),
              ),
              Expanded(
                child: LayoutBuilder(
                  builder: (context, constraints) => SingleChildScrollView(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: ConstrainedBox(
                      constraints: BoxConstraints(
                        minHeight: (constraints.maxHeight - 32).clamp(
                          0.0,
                          double.infinity,
                        ),
                      ),
                      child: Center(
                        child: ConstrainedBox(
                          key: const ValueKey('login_web_form_column'),
                          constraints: const BoxConstraints(
                            maxWidth: WebHrLoginView.formMaxWidth,
                          ),
                          child: _FormBody(view: view),
                        ),
                      ),
                    ),
                  ),
                ),
              ),
              Divider(height: 1, color: cs.outlineVariant),
              const SizedBox(height: 12),
              _LoginFooter(view: view),
            ],
          ),
        ),
      ),
    );
  }
}

/// Support (WhatsApp, call) and the app version.
class _LoginFooter extends StatelessWidget {
  const _LoginFooter({required this.view});

  final WebHrLoginView view;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ar = view.isArabic;
    ButtonStyle tonal() => FilledButton.styleFrom(
      backgroundColor: cs.secondaryContainer,
      foregroundColor: cs.onSecondaryContainer,
      visualDensity: VisualDensity.standard,
      minimumSize: const Size(48, 40),
      padding: const EdgeInsets.symmetric(horizontal: 14),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      textStyle: text.labelLarge?.copyWith(fontWeight: FontWeight.w600),
    );
    return Column(
      mainAxisSize: MainAxisSize.min,
      children: [
        Wrap(
          alignment: WrapAlignment.spaceBetween,
          crossAxisAlignment: WrapCrossAlignment.center,
          runSpacing: 8,
          spacing: 8,
          children: [
            Wrap(
              crossAxisAlignment: WrapCrossAlignment.center,
              spacing: 8,
              runSpacing: 8,
              children: [
                Text(
                  ar ? 'الدعم الفني' : 'Support',
                  style: text.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                FilledButton.icon(
                  key: const ValueKey('login_support_whatsapp'),
                  onPressed: view.onSupportWhatsApp,
                  style: tonal(),
                  icon: const Icon(Symbols.chat_rounded, size: 18),
                  label: Text(ar ? 'واتساب' : 'WhatsApp'),
                ),
                FilledButton.icon(
                  key: const ValueKey('login_support_button'),
                  onPressed: view.onSupport,
                  style: tonal(),
                  icon: const Icon(Symbols.call_rounded, size: 18),
                  label: Text(ar ? 'اتصال' : 'Call'),
                ),
              ],
            ),
            TashilVersionText(color: cs.onSurfaceVariant, isArabic: ar),
          ],
        ),
        if (AppEnv.isDev)
          Padding(
            padding: const EdgeInsets.only(top: 4),
            child: Text(
              'GIT_SHA=${AppEnv.gitSha.isEmpty ? 'unset' : AppEnv.gitSha}',
              key: const ValueKey('login_git_sha'),
              textAlign: TextAlign.center,
              style: text.labelSmall?.copyWith(
                color: cs.onSurfaceVariant,
                fontSize: 10,
                height: 1.2,
              ),
            ),
          ),
      ],
    );
  }
}

class _FormBody extends StatefulWidget {
  const _FormBody({required this.view});

  final WebHrLoginView view;

  @override
  State<_FormBody> createState() => _FormBodyState();
}

class _FormBodyState extends State<_FormBody> {
  bool _passwordFocused = false;
  bool _capsLock = false;

  @override
  void initState() {
    super.initState();
    HardwareKeyboard.instance.addHandler(_onKey);
  }

  @override
  void dispose() {
    HardwareKeyboard.instance.removeHandler(_onKey);
    super.dispose();
  }

  bool _onKey(KeyEvent event) {
    final caps = HardwareKeyboard.instance.lockModesEnabled.contains(
      KeyboardLockMode.capsLock,
    );
    if (caps != _capsLock && mounted) setState(() => _capsLock = caps);
    return false;
  }

  @override
  Widget build(BuildContext context) {
    final view = widget.view;
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    final ar = view.isArabic;
    final rememberLabel = ar
        ? 'البقاء متصلاً على هذا الجهاز'
        : 'Stay signed in on this device';
    return Shake(
      key: view.shakeKey,
      child: Form(
        key: view.formKey,
        autovalidateMode: view.autovalidateMode,
        child: AutofillGroup(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                l10n.loginButton,
                style: text.headlineMedium?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                key: const ValueKey('login_web_subtitle'),
                ar
                    ? 'تسجيل الدخول للموظفين الإداريين'
                    : 'Sign in for administrative staff',
                style: text.bodyLarge?.copyWith(color: cs.onSurfaceVariant),
              ),
              if (view.formError != null) ...[
                const SizedBox(height: 20),
                _FormErrorBanner(
                  key: ValueKey(
                    view.delegateNotice && !view.credentialError
                        ? 'login_web_delegate_notice'
                        : 'login_form_error',
                  ),
                  message: view.formError!,
                  supportLabel: view.credentialError
                      ? (ar ? 'تواصل مع الدعم الفني' : 'Contact support')
                      : null,
                  onSupport: view.onSupportWhatsApp,
                ),
              ],
              const SizedBox(height: 28),
              TextFormField(
                key: const ValueKey('login_phone'),
                controller: view.phoneController,
                keyboardType: TextInputType.phone,
                inputFormatters: [
                  FilteringTextInputFormatter.allow(RegExp(r'[0-9]')),
                  LengthLimitingTextInputFormatter(11),
                ],
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
                // Web maps telephoneNumber to autocomplete="tel".
                autofillHints: const [AutofillHints.telephoneNumber],
                textDirection: TextDirection.ltr,
                // LTR digits next to the fixed +20 code.
                textAlign: TextAlign.left,
                onFieldSubmitted: (_) => view.onSubmit(),
                style: TextStyle(fontSize: 16, color: cs.onSurface),
                decoration: _fieldDecoration(
                  context,
                  label: l10n.mobileNumber,
                  helper: ar
                      ? 'رقم الجوال المسجل في الشركة، من غير الصفر الأول'
                      : 'Your company-registered mobile, without the leading 0',
                  credentialError: view.credentialError,
                  suffixIcon: const _CountryCode(),
                ),
                // 1012345678 and 01012345678 are both accepted.
                validator: (value) => validateLoginPhone(
                  value,
                  emptyMessage: l10n.enterMobileNumber,
                  invalidMessage: l10n.invalidMobileNumber,
                ),
              ),
              const SizedBox(height: 16),
              Focus(
                canRequestFocus: false,
                skipTraversal: true,
                onFocusChange: (f) => setState(() => _passwordFocused = f),
                child: TextFormField(
                  key: const ValueKey('login_staff_password'),
                  controller: view.passwordController,
                  keyboardType: TextInputType.visiblePassword,
                  textInputAction: TextInputAction.done,
                  autocorrect: false,
                  enableSuggestions: false,
                  // Web maps password to autocomplete="current-password".
                  autofillHints: const [AutofillHints.password],
                  obscureText: view.obscurePassword,
                  textDirection: TextDirection.ltr,
                  textAlign: TextAlign.left,
                  onFieldSubmitted: (_) => view.onSubmit(),
                  style: TextStyle(fontSize: 16, color: cs.onSurface),
                  decoration: _fieldDecoration(
                    context,
                    label: l10n.password,
                    credentialError: view.credentialError,
                    suffixIcon: IconButton(
                      key: const ValueKey('login_password_eye'),
                      tooltip: view.obscurePassword
                          ? l10n.showAction
                          : l10n.hideAction,
                      onPressed: view.onToggleObscure,
                      icon: Icon(
                        view.obscurePassword
                            ? Icons.visibility_off_outlined
                            : Icons.visibility_outlined,
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                  ),
                  validator: (value) => validateStaffPassword(
                    value,
                    emptyMessage: l10n.enterPassword2,
                  ),
                ),
              ),
              if (_capsLock && _passwordFocused)
                Padding(
                  key: const ValueKey('login_caps_lock_hint'),
                  padding: const EdgeInsetsDirectional.only(start: 16, top: 6),
                  child: Row(
                    children: [
                      Icon(
                        Symbols.keyboard_capslock_rounded,
                        size: 16,
                        color: cs.onSurfaceVariant,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        ar ? 'زر Caps Lock مفعّل' : 'Caps Lock is on',
                        style: text.labelMedium?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              const SizedBox(height: 8),
              Row(
                children: [
                  Expanded(
                    child: InkWell(
                      key: const ValueKey('login_remember_me'),
                      borderRadius: BorderRadius.circular(8),
                      onTap: view.onToggleRemember,
                      child: ConstrainedBox(
                        constraints: const BoxConstraints(minHeight: 48),
                        child: Row(
                          children: [
                            Semantics(
                              label: rememberLabel,
                              child: Checkbox(
                                value: view.rememberMe,
                                materialTapTargetSize:
                                    MaterialTapTargetSize.shrinkWrap,
                                visualDensity: VisualDensity.compact,
                                onChanged: (_) => view.onToggleRemember(),
                              ),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                rememberLabel,
                                style: text.bodyMedium?.copyWith(
                                  color: cs.onSurface,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  TextButton(
                    key: const ValueKey('login_forgot_password'),
                    onPressed: view.loading ? null : view.onForgot,
                    style: TextButton.styleFrom(
                      // Web's compact density would shrink a 48dp minimum to 40.
                      visualDensity: VisualDensity.standard,
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.forgotPasswordQ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              Semantics(
                liveRegion: view.loading,
                label: view.loading ? l10n.signingIn : null,
                child: FilledButton(
                  key: const ValueKey('login_submit'),
                  onPressed: view.loading ? null : view.onSubmit,
                  style: FilledButton.styleFrom(
                    visualDensity: VisualDensity.standard,
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
                    disabledBackgroundColor: cs.primary,
                    disabledForegroundColor: cs.onPrimary,
                    shape: const StadiumBorder(),
                    textStyle: text.labelLarge?.copyWith(
                      fontSize: 16,
                      fontWeight: FontWeight.w600,
                      height: 1.2,
                    ),
                  ),
                  child: view.loading
                      ? SizedBox.square(
                          key: const ValueKey('login_loading'),
                          dimension: 22,
                          child: CircularProgressIndicator(
                            strokeWidth: 2.5,
                            color: cs.onPrimary,
                            // The app theme uses the expressive indicator, which
                            // collapses to a dot inside a 22dp button slot.
                            // ignore: deprecated_member_use
                            year2023: true,
                          ),
                        )
                      : Text(
                          l10n.loginButton,
                          key: const ValueKey('login_label'),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Fixed Egyptian country code at the end of the phone field.
class _CountryCode extends StatelessWidget {
  const _CountryCode();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      key: const ValueKey('login_phone_country_code'),
      padding: const EdgeInsetsDirectional.only(start: 4, end: 12),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Container(width: 1, height: 24, color: cs.outlineVariant),
          const SizedBox(width: 12),
          Text(
            '+20',
            textDirection: TextDirection.ltr,
            style: TextStyle(fontSize: 16, color: cs.onSurface),
          ),
        ],
      ),
    );
  }
}

class _FormErrorBanner extends StatelessWidget {
  const _FormErrorBanner({
    super.key,
    required this.message,
    this.supportLabel,
    this.onSupport,
  });

  final String message;

  /// Shown under the message after a wrong phone or password.
  final String? supportLabel;
  final VoidCallback? onSupport;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return Semantics(
      liveRegion: true,
      child: Container(
        padding: const EdgeInsetsDirectional.fromSTEB(12, 12, 16, 12),
        decoration: BoxDecoration(
          color: cs.errorContainer,
          borderRadius: BorderRadius.circular(12),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Icon(Icons.error_outline_rounded, color: cs.onErrorContainer),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    message,
                    style: text.bodyMedium?.copyWith(
                      color: cs.onErrorContainer,
                      fontWeight: FontWeight.w600,
                      height: 1.4,
                    ),
                  ),
                  if (supportLabel != null && onSupport != null)
                    InkWell(
                      key: const ValueKey('login_error_support'),
                      onTap: onSupport,
                      borderRadius: BorderRadius.circular(4),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(vertical: 4),
                        child: Text(
                          supportLabel!,
                          style: text.bodyMedium?.copyWith(
                            color: cs.onErrorContainer,
                            decoration: TextDecoration.underline,
                            decorationColor: cs.onErrorContainer,
                          ),
                        ),
                      ),
                    ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }
}

InputDecoration _fieldDecoration(
  BuildContext context, {
  required String label,
  String? helper,
  required bool credentialError,
  Widget? suffixIcon,
}) {
  final cs = Theme.of(context).colorScheme;
  final idle = credentialError ? cs.error : cs.outline;
  final focus = credentialError ? cs.error : cs.primary;
  return InputDecoration(
    labelText: label,
    helperText: helper,
    helperMaxLines: 2,
    helperStyle: TextStyle(color: cs.onSurfaceVariant),
    filled: false,
    suffixIcon: suffixIcon,
    border: const OutlineInputBorder(),
    enabledBorder: OutlineInputBorder(borderSide: BorderSide(color: idle)),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: focus, width: 2),
    ),
    errorBorder: OutlineInputBorder(borderSide: BorderSide(color: cs.error)),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: cs.error, width: 2),
    ),
  );
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({
    required this.isArabic,
    required this.onPressed,
    this.onBrand = false,
  });

  final bool isArabic;
  final VoidCallback onPressed;

  /// On the purple brand band (narrow layout) the chip stays light so it
  /// reads; on the sheet it is a light mauve tonal chip.
  final bool onBrand;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final Color background;
    final Color foreground;
    if (onBrand) {
      background = dark ? cs.inverseSurface : cs.surfaceContainerLowest;
      foreground = dark ? cs.onInverseSurface : cs.onSurface;
    } else {
      background = cs.primaryContainer;
      foreground = cs.onPrimaryContainer;
    }
    return Material(
      color: background,
      shape: const StadiumBorder(),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        key: const ValueKey('login_language_toggle'),
        onTap: onPressed,
        customBorder: const StadiumBorder(),
        child: ConstrainedBox(
          constraints: const BoxConstraints(minHeight: 40),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.language_rounded, size: 18, color: foreground),
                const SizedBox(width: 8),
                Text(
                  isArabic ? 'English' : 'العربية',
                  style: Theme.of(context).textTheme.labelLarge?.copyWith(
                    color: foreground,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}

/// Brand fill for the web login hero and the narrow brand band.
///
/// Light mode uses [ColorScheme.primary] (#6750A4) with white ink. Dark mode
/// uses [ColorScheme.primaryContainer] (#4F378A for the default seed) with
/// [ColorScheme.onPrimaryContainer] ink, as approved in TAS-188.
class _BrandColors {
  const _BrandColors({
    required this.panel,
    required this.onPanel,
    required this.onPanelMuted,
    required this.chip,
    required this.onChip,
  });

  final Color panel;
  final Color onPanel;
  final Color onPanelMuted;
  final Color chip;
  final Color onChip;

  factory _BrandColors.of(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    return _BrandColors(
      panel: dark ? cs.primaryContainer : cs.primary,
      onPanel: dark ? cs.onPrimaryContainer : cs.onPrimary,
      onPanelMuted: dark ? cs.primary : cs.primaryContainer,
      chip: cs.primaryContainer,
      onChip: cs.onPrimaryContainer,
    );
  }
}

class _NarrowColumn extends StatelessWidget {
  const _NarrowColumn({required this.view});

  final WebHrLoginView view;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final brand = _BrandColors.of(context);
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      color: cs.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ColoredBox(
            color: brand.panel,
            child: SafeArea(
              bottom: false,
              child: Padding(
                padding: const EdgeInsets.fromLTRB(20, 12, 20, 20),
                child: Column(
                  children: [
                    Align(
                      alignment: AlignmentDirectional.centerEnd,
                      child: _LanguageChip(
                        isArabic: view.isArabic,
                        onPressed: view.onLanguage,
                        onBrand: true,
                      ),
                    ),
                    const SizedBox(height: 8),
                    TashilLogoTile(size: 48),
                    const SizedBox(height: 8),
                    Text(
                      l10n.appTitle,
                      style: text.headlineSmall?.copyWith(
                        color: brand.onPanel,
                        fontWeight: FontWeight.w700,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      view.isArabic
                          ? 'نظام موارد بشرية متكامل'
                          : 'A complete human resources system',
                      textAlign: TextAlign.center,
                      style: text.titleMedium?.copyWith(
                        color: brand.onPanel,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    const SizedBox(height: 4),
                    Text(
                      view.isArabic
                          ? 'لشركات التجزئة العاملة مع الهايبرماركت'
                          : 'For retail companies working with hypermarkets',
                      textAlign: TextAlign.center,
                      style: text.bodyMedium?.copyWith(
                        color: brand.onPanelMuted,
                        height: 1.4,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 8, 20, 8),
            child: _FormBody(view: view),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 12),
            child: _LoginFooter(view: view),
          ),
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              children: [
                for (final feature in _features)
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FeatureTile(
                      feature: feature,
                      isArabic: view.isArabic,
                      tight: false,
                      labelColor: cs.onSurface,
                      chipColor: brand.chip,
                      iconColor: brand.onChip,
                    ),
                  ),
              ],
            ),
          ),
        ],
      ),
    );
  }
}

class _FeatureTile extends StatelessWidget {
  const _FeatureTile({
    required this.feature,
    required this.isArabic,
    required this.tight,
    required this.labelColor,
    required this.chipColor,
    required this.iconColor,
  });

  final _LoginFeature feature;
  final bool isArabic;
  final bool tight;
  final Color labelColor;
  final Color chipColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final label = feature.label(isArabic: isArabic, tight: tight);
    return Row(
      children: [
        Container(
          width: 36,
          height: 36,
          alignment: Alignment.center,
          decoration: BoxDecoration(
            color: chipColor,
            borderRadius: BorderRadius.circular(12),
          ),
          child: Icon(
            feature.icon,
            size: 20,
            fill: 0,
            weight: 400,
            grade: 0,
            opticalSize: 24,
            color: iconColor,
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Text(
            label,
            maxLines: 1,
            softWrap: false,
            overflow: TextOverflow.visible,
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: labelColor,
              fontSize: tight ? 13 : 14,
              fontWeight: FontWeight.w600,
              height: 1.2,
            ),
          ),
        ),
      ],
    );
  }
}

class _LoginFeature {
  const _LoginFeature({
    required this.icon,
    required this.ar,
    required this.arShort,
    required this.en,
    required this.enShort,
  });

  final IconData icon;
  final String ar;
  final String arShort;
  final String en;
  final String enShort;

  String label({required bool isArabic, required bool tight}) {
    if (isArabic) return tight ? arShort : ar;
    return tight ? enShort : en;
  }
}

const List<_LoginFeature> _features = [
  _LoginFeature(
    icon: Symbols.schedule_rounded,
    ar: 'الحضور والانصراف حسب الفرع',
    arShort: 'الحضور والانصراف حسب الفرع',
    en: 'Attendance by branch',
    enShort: 'Attendance by branch',
  ),
  _LoginFeature(
    icon: Symbols.location_on_rounded,
    ar: 'متابعة المناديب في الميدان',
    arShort: 'متابعة المناديب في الميدان',
    en: 'Field team tracking',
    enShort: 'Field team tracking',
  ),
  _LoginFeature(
    icon: Symbols.photo_camera_rounded,
    ar: 'الصور والزيارات الميدانية',
    arShort: 'الصور والزيارات الميدانية',
    en: 'Field photos and visits',
    enShort: 'Photos and visits',
  ),
  _LoginFeature(
    icon: Symbols.event_rounded,
    ar: 'طلبات الإجازات والأعذار',
    arShort: 'طلبات الإجازات والأعذار',
    en: 'Leave and excuse requests',
    enShort: 'Leave requests',
  ),
  _LoginFeature(
    icon: Symbols.payments_rounded,
    ar: 'الرواتب والعمولات',
    arShort: 'الرواتب والعمولات',
    en: 'Payroll and commissions',
    enShort: 'Payroll and commissions',
  ),
  _LoginFeature(
    icon: Symbols.group_add_rounded,
    ar: 'اشتراكات واعتماد المناديب',
    arShort: 'الاشتراكات والاعتماد',
    en: 'Subscriptions and approvals',
    enShort: 'Subscriptions and approvals',
  ),
  _LoginFeature(
    icon: Symbols.task_alt_rounded,
    ar: 'المهام والغرامات',
    arShort: 'المهام والغرامات',
    en: 'Tasks and penalties',
    enShort: 'Tasks and penalties',
  ),
  _LoginFeature(
    icon: Symbols.shield_rounded,
    ar: 'تدقيق الأمان وفك الأجهزة',
    arShort: 'تدقيق الأمان',
    en: 'Security audit and device release',
    enShort: 'Security audit',
  ),
];
