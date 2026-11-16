import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/features/auth/domain/delegate_login_validator.dart';
import 'package:delegate_app/features/auth/presentation/widgets/tashil_m3.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:material_symbols_icons/symbols.dart';

/// HR web login. Mounted only when [WebRuntimePolicy.isWeb] is true.
///
/// Wide windows (≥840) are a split screen: the form sits on the start side
/// and the brand panel on the end side. Narrow windows stack a compact brand
/// band, the form, and a short feature list.
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
    required this.onLanguage,
  });

  static const double wideBreakpoint = 840;
  static const double comfortableBreakpoint = 1200;

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
  final VoidCallback onSupport;
  final VoidCallback onLanguage;

  @override
  Widget build(BuildContext context) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth >= wideBreakpoint) {
          final formWidth = constraints.maxWidth >= comfortableBreakpoint
              ? 400.0
              : 360.0;
          return Row(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              SizedBox(
                key: const ValueKey('login_web_form_column'),
                width: formWidth,
                child: _FormColumn(view: this),
              ),
              Expanded(
                child: _BrandPanel(
                  isArabic: isArabic,
                  onLanguage: onLanguage,
                  tight: constraints.maxWidth < comfortableBreakpoint,
                ),
              ),
            ],
          );
        }
        return _NarrowColumn(view: this);
      },
    );
  }
}

class _FormColumn extends StatelessWidget {
  const _FormColumn({required this.view});

  final WebHrLoginView view;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return ColoredBox(
      color: cs.surface,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final minHeight = constraints.maxHeight.isFinite
              ? (constraints.maxHeight - 64).clamp(0.0, double.infinity)
              : 0.0;
          return SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
            child: ConstrainedBox(
              constraints: BoxConstraints(minHeight: minHeight),
              child: Center(child: _FormBody(view: view)),
            ),
          );
        },
      ),
    );
  }
}

class _FormBody extends StatelessWidget {
  const _FormBody({required this.view});

  final WebHrLoginView view;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
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
                style: text.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                  height: 1.3,
                ),
              ),
              const SizedBox(height: 4),
              Text(
                key: const ValueKey('login_web_subtitle'),
                view.isArabic
                    ? 'لحسابات الموظفين والإدارة'
                    : 'For staff and admin accounts',
                style: text.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
              ),
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
                autofillHints: const [AutofillHints.telephoneNumber],
                textDirection: TextDirection.ltr,
                textAlign: TextAlign.left,
                onFieldSubmitted: (_) => view.onSubmit(),
                style: TextStyle(fontSize: 16, color: cs.onSurface),
                decoration: _fieldDecoration(
                  context,
                  label: l10n.mobileNumber,
                  helper: view.isArabic
                      ? 'رقم الجوال المسجل في الشركة'
                      : l10n.phoneHelper,
                  credentialError: view.credentialError,
                ),
                validator: (value) => validateLoginPhone(
                  value,
                  emptyMessage: l10n.enterMobileNumber,
                  invalidMessage: l10n.invalidMobileNumber,
                ),
              ),
              const SizedBox(height: 16),
              TextFormField(
                key: const ValueKey('login_staff_password'),
                controller: view.passwordController,
                keyboardType: TextInputType.visiblePassword,
                textInputAction: TextInputAction.done,
                autocorrect: false,
                enableSuggestions: false,
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
                              label: l10n.rememberMe,
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
                                l10n.rememberMe,
                                style: text.bodyLarge?.copyWith(
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
                      minimumSize: const Size(48, 48),
                      padding: const EdgeInsets.symmetric(horizontal: 12),
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                    ),
                    child: Text(l10n.forgotPasswordQ),
                  ),
                ],
              ),
              if (view.formError != null) ...[
                const SizedBox(height: 8),
                _FormErrorBanner(
                  key: ValueKey(
                    view.delegateNotice && !view.credentialError
                        ? 'login_web_delegate_notice'
                        : 'login_form_error',
                  ),
                  message: view.formError!,
                ),
              ],
              const SizedBox(height: 16),
              Semantics(
                liveRegion: view.loading,
                label: view.loading ? l10n.signingIn : null,
                child: FilledButton(
                  key: const ValueKey('login_submit'),
                  onPressed: view.onSubmit,
                  style: FilledButton.styleFrom(
                    minimumSize: const Size.fromHeight(48),
                    padding: const EdgeInsets.symmetric(
                      horizontal: 24,
                      vertical: 8,
                    ),
                    backgroundColor: cs.primary,
                    foregroundColor: cs.onPrimary,
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
                          ),
                        )
                      : Text(
                          l10n.loginButton,
                          key: const ValueKey('login_label'),
                          textAlign: TextAlign.center,
                        ),
                ),
              ),
              const SizedBox(height: 4),
              Center(
                child: TextButton(
                  key: const ValueKey('login_support_button'),
                  onPressed: view.onSupport,
                  style: TextButton.styleFrom(
                    minimumSize: const Size(48, 48),
                  ),
                  child: Text(l10n.contactSupport),
                ),
              ),
              TashilVersionText(
                color: cs.onSurfaceVariant,
                isArabic: view.isArabic,
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
          ),
        ),
      ),
    );
  }
}

class _FormErrorBanner extends StatelessWidget {
  const _FormErrorBanner({super.key, required this.message});

  final String message;

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
              child: Text(
                message,
                style: text.bodyMedium?.copyWith(
                  color: cs.onErrorContainer,
                  fontWeight: FontWeight.w600,
                  height: 1.4,
                ),
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
    enabledBorder: OutlineInputBorder(
      borderSide: BorderSide(color: idle),
    ),
    focusedBorder: OutlineInputBorder(
      borderSide: BorderSide(color: focus, width: 2),
    ),
    errorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: cs.error),
    ),
    focusedErrorBorder: OutlineInputBorder(
      borderSide: BorderSide(color: cs.error, width: 2),
    ),
  );
}

class _LanguageChip extends StatelessWidget {
  const _LanguageChip({required this.isArabic, required this.onPressed});

  final bool isArabic;
  final VoidCallback onPressed;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    // Light chip, dark label: AA on the purple panel and on a dark surface.
    final background = dark ? cs.inverseSurface : cs.surfaceContainerLowest;
    final foreground = dark ? cs.onInverseSurface : cs.onSurface;
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

class _BrandPanel extends StatelessWidget {
  const _BrandPanel({
    required this.isArabic,
    required this.onLanguage,
    required this.tight,
  });

  final bool isArabic;
  final VoidCallback onLanguage;
  final bool tight;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final panel = dark ? cs.surfaceContainer : cs.primary;
    final onPanel = dark ? cs.onSurface : cs.onPrimary;
    final onPanelMuted = dark
        ? cs.onSurfaceVariant
        : cs.onPrimary.withValues(alpha: 0.88);
    return ColoredBox(
      color: panel,
      child: Stack(
        children: [
          PositionedDirectional(
            bottom: -140,
            end: -140,
            child: IgnorePointer(
              child: Container(
                width: 280,
                height: 280,
                decoration: BoxDecoration(
                  shape: BoxShape.circle,
                  color: (dark ? cs.primary : cs.onPrimary).withValues(
                    alpha: dark ? 0.16 : 0.08,
                  ),
                ),
              ),
            ),
          ),
          Padding(
            padding: EdgeInsets.fromLTRB(tight ? 28 : 48, 16, tight ? 28 : 48, 24),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                Align(
                  alignment: AlignmentDirectional.centerEnd,
                  child: _LanguageChip(
                    isArabic: isArabic,
                    onPressed: onLanguage,
                  ),
                ),
                Expanded(
                  child: LayoutBuilder(
                    builder: (context, constraints) {
                      return SingleChildScrollView(
                        child: ConstrainedBox(
                          constraints: BoxConstraints(
                            minHeight: constraints.maxHeight,
                          ),
                          child: Center(
                            child: _BrandCopy(
                              isArabic: isArabic,
                              onPanel: onPanel,
                              onPanelMuted: onPanelMuted,
                              tight: tight,
                              chipColor: cs.primaryContainer,
                              iconColor: cs.onPrimaryContainer,
                            ),
                          ),
                        ),
                      );
                    },
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

class _BrandCopy extends StatelessWidget {
  const _BrandCopy({
    required this.isArabic,
    required this.onPanel,
    required this.onPanelMuted,
    required this.tight,
    required this.chipColor,
    required this.iconColor,
  });

  final bool isArabic;
  final Color onPanel;
  final Color onPanelMuted;
  final bool tight;
  final Color chipColor;
  final Color iconColor;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final text = Theme.of(context).textTheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      mainAxisSize: MainAxisSize.min,
      children: [
        TashilLogoTile(size: tight ? 56 : 72),
        const SizedBox(height: 16),
        Text(
          l10n.appTitle,
          style: text.headlineMedium?.copyWith(
            color: onPanel,
            fontWeight: FontWeight.w700,
            height: 1.2,
          ),
        ),
        SizedBox(height: tight ? 12 : 20),
        Text(
          isArabic
              ? 'نظام موارد بشرية متكامل'
              : 'A complete human resources system',
          style: text.titleLarge?.copyWith(
            color: onPanel,
            fontWeight: FontWeight.w700,
            height: 1.35,
          ),
        ),
        const SizedBox(height: 6),
        Text(
          isArabic
              ? 'لشركات التجزئة العاملة مع الهايبرماركت'
              : 'For retail companies working with hypermarkets',
          style: text.bodyLarge?.copyWith(color: onPanelMuted, height: 1.4),
        ),
        SizedBox(height: tight ? 20 : 32),
        _FeatureGrid(
          isArabic: isArabic,
          tight: tight,
          labelColor: onPanel,
          chipColor: chipColor,
          iconColor: iconColor,
          features: _features,
        ),
      ],
    );
  }
}

class _NarrowColumn extends StatelessWidget {
  const _NarrowColumn({required this.view});

  final WebHrLoginView view;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final dark = Theme.of(context).brightness == Brightness.dark;
    final band = dark ? cs.surfaceContainer : cs.primary;
    final onBand = dark ? cs.onSurface : cs.onPrimary;
    final text = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    return ColoredBox(
      color: cs.surface,
      child: ListView(
        padding: EdgeInsets.zero,
        children: [
          ColoredBox(
            color: band,
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
                      ),
                    ),
                    const SizedBox(height: 8),
                    TashilLogoTile(size: 48),
                    const SizedBox(height: 8),
                    Text(
                      l10n.appTitle,
                      style: text.headlineSmall?.copyWith(
                        color: onBand,
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
                        color: onBand,
                        fontWeight: FontWeight.w600,
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
            padding: const EdgeInsets.fromLTRB(20, 4, 20, 28),
            child: Column(
              children: [
                for (final feature in _features.take(4))
                  Padding(
                    padding: const EdgeInsets.only(bottom: 10),
                    child: _FeatureTile(
                      feature: feature,
                      isArabic: view.isArabic,
                      tight: true,
                      labelColor: cs.onSurface,
                      chipColor: cs.primaryContainer,
                      iconColor: cs.onPrimaryContainer,
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

class _FeatureGrid extends StatelessWidget {
  const _FeatureGrid({
    required this.isArabic,
    required this.tight,
    required this.labelColor,
    required this.chipColor,
    required this.iconColor,
    required this.features,
  });

  final bool isArabic;
  final bool tight;
  final Color labelColor;
  final Color chipColor;
  final Color iconColor;
  final List<_LoginFeature> features;

  @override
  Widget build(BuildContext context) {
    return GridView.builder(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: features.length,
      gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
        crossAxisCount: 2,
        mainAxisExtent: tight ? 44 : 52,
        mainAxisSpacing: tight ? 8 : 16,
        crossAxisSpacing: tight ? 12 : 20,
      ),
      itemBuilder: (context, index) {
        return _FeatureTile(
          feature: features[index],
          isArabic: isArabic,
          tight: tight,
          labelColor: labelColor,
          chipColor: chipColor,
          iconColor: iconColor,
        );
      },
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
