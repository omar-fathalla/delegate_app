import 'package:material_ui/material_ui.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:delegate_app/core/services/review_service.dart';
import 'package:delegate_app/core/widgets/app_logout_modal.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

import 'package:delegate_app/main.dart';
import 'package:go_router/go_router.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/config/theme/color_schemes.dart';
import 'package:package_info_plus/package_info_plus.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/core/config/app_env.dart';
import 'package:delegate_app/features/playground/playground_launcher.dart';

class SettingsScreen extends StatelessWidget {
  final Delegate delegate;
  final bool showAppBar;

  const SettingsScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;

    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    // TAS-358: the field delegate logs out from the navigation menu (TAS-350),
    // so the row is not repeated here. Every staff role that opens this
    // screen (HR, admin, accountant, marketing, web shells) keeps it.
    final showLogout = delegate.role != UserRole.delegate;

    return Scaffold(
      appBar: showAppBar
          ? AppBar(
              title: Text(l10n.settings),
              leading: BackButton(
                onPressed: () {
                  if (Navigator.of(context).canPop()) {
                    Navigator.of(context).pop();
                  } else {
                    context.pop();
                  }
                },
              ),
            )
          : null,
      // TAS-387 (user review 27 Nov 2026): sections as cards with a title
      // above each (same as the profile), the appearance choices on the page
      // itself (no sheet), and the playground's contrast level.
      body: SafeArea(
        child: ListView(
          key: const Key('settings_list'),
          padding: const EdgeInsetsDirectional.fromSTEB(
            TashilSpacing.page,
            TashilSpacing.sm,
            TashilSpacing.page,
            TashilSpacing.xl,
          ),
          children: [
            _buildSectionHeader(context, l10n.settingsAppearance),
            _card([
              _choice(
                context,
                icon: Symbols.translate_rounded,
                title: l10n.language,
                child: ButtonGroup<String>(
                  key: const Key('settings_language'),
                  variant: ButtonGroupVariant.connected,
                  expand: true,
                  selected: {isArabic ? 'ar' : 'en'},
                  onSelectionChanged: (v) {
                    if ((v.first == 'ar') != isArabic) {
                      _toggleLanguage(context);
                    }
                  },
                  items: [
                    ButtonGroupItem(value: 'ar', label: l10n.arabic),
                    ButtonGroupItem(value: 'en', label: l10n.english),
                  ],
                ),
              ),
              _choice(
                context,
                icon: Symbols.contrast_rounded,
                title: l10n.themeModeTitle,
                child: ButtonGroup<ThemeMode>(
                  key: const Key('settings_theme_mode'),
                  variant: ButtonGroupVariant.connected,
                  expand: true,
                  selected: {context.watch<ThemeCubit>().state.themeMode},
                  onSelectionChanged: (v) =>
                      context.read<ThemeCubit>().setThemeMode(v.first),
                  items: [
                    ButtonGroupItem(
                      value: ThemeMode.system,
                      label: l10n.settingsAuto,
                      icon: Symbols.brightness_auto_rounded,
                    ),
                    ButtonGroupItem(
                      value: ThemeMode.light,
                      label: l10n.themeModeLight,
                      icon: Symbols.light_mode_rounded,
                    ),
                    ButtonGroupItem(
                      value: ThemeMode.dark,
                      label: l10n.themeModeDark,
                      icon: Symbols.dark_mode_rounded,
                    ),
                  ],
                ),
              ),
              _choice(
                context,
                icon: Symbols.tonality_rounded,
                title: l10n.settingsContrast,
                subtitle: l10n.settingsContrastHint,
                child: ButtonGroup<TashilContrast>(
                  key: const Key('settings_contrast'),
                  variant: ButtonGroupVariant.connected,
                  expand: true,
                  selected: {context.watch<ThemeCubit>().state.contrast},
                  onSelectionChanged: (v) =>
                      context.read<ThemeCubit>().setContrast(v.first),
                  items: [
                    ButtonGroupItem(
                      value: TashilContrast.standard,
                      label: l10n.settingsContrastStandard,
                    ),
                    ButtonGroupItem(
                      value: TashilContrast.medium,
                      label: l10n.settingsContrastMedium,
                    ),
                    ButtonGroupItem(
                      value: TashilContrast.high,
                      label: l10n.settingsContrastHigh,
                    ),
                  ],
                ),
              ),
              _choice(
                context,
                icon: Symbols.palette_rounded,
                title: l10n.appColor,
                subtitle: l10n.settingsColorHint,
                child: Wrap(
                  key: const Key('settings_colors'),
                  spacing: TashilSpacing.sm,
                  runSpacing: TashilSpacing.sm,
                  children: AppColorSchemes.seedColors
                      .map((c) => _buildColorOption(context, c))
                      .toList(),
                ),
              ),
            ]),
            const SizedBox(height: TashilSpacing.xl),
            _buildSectionHeader(context, l10n.settingsGeneral),
            _card([
              if (delegate.role == UserRole.delegate)
                _buildSettingsTile(
                  context: context,
                  icon: Symbols.photo_camera_rounded,
                  title: l10n.offerPhotosTitle,
                  onTap: () => context.push(
                    '/photo-permissions/delegate',
                    extra: delegate,
                  ),
                ),
              _buildSettingsTile(
                context: context,
                icon: Symbols.rate_review_rounded,
                title: l10n.sendFeedback,
                // Inner page inside the web HR shell (TAS-157).
                onTap: () => HrAccountPages.openSendFeedback(context, delegate),
              ),
              _buildSettingsTile(
                context: context,
                icon: Symbols.history_rounded,
                title: delegate.role == UserRole.superAdmin
                    ? l10n.manageFeedback
                    : l10n.myFeedback,
                onTap: () {
                  if (delegate.role == UserRole.superAdmin) {
                    context.push('/admin/feedbacks');
                  } else {
                    context.push('/my-feedbacks', extra: delegate);
                  }
                },
              ),
              // Store rating has no meaning in a browser (TAS-158).
              if (!WebRuntimePolicy.isWeb)
                _buildSettingsTile(
                  context: context,
                  icon: Symbols.star_rounded,
                  title: l10n.rateTheApp,
                  onTap: () => sl<ReviewService>().requestManualReview(),
                ),
            ]),
            const SizedBox(height: TashilSpacing.xl),
            _buildSectionHeader(context, l10n.settingsAbout),
            _card([
              _buildSettingsTile(
                context: context,
                icon: Symbols.privacy_tip_rounded,
                title: l10n.privacyPolicy,
                onTap: () => context.push('/privacy-policy'),
              ),
              // TAS-383: the m3-kit component playground, dev builds only
              // (never in a store build).
              if (AppEnv.isDev)
                _buildSettingsTile(
                  context: context,
                  icon: Symbols.widgets_rounded,
                  title: 'مكونات التصميم (نسخة المطورين)',
                  onTap: () => PlaygroundLauncher.open(context),
                ),
              FutureBuilder<PackageInfo>(
                future: PackageInfo.fromPlatform(),
                builder: (context, snapshot) {
                  final version = snapshot.hasData
                      ? snapshot.data!.version
                      : '…';
                  return ListTile(
                    key: const Key('settings_version'),
                    leading: Icon(Symbols.info_rounded, color: cs.primary),
                    // The web isn't the «مندوب تسهيل» app (TAS-158).
                    title: Text(
                      WebRuntimePolicy.isWeb
                          ? l10n.webVersion(version)
                          : l10n.version(version),
                    ),
                  );
                },
              ),
            ]),
            if (showLogout) ...[
              const SizedBox(height: TashilSpacing.xl),
              _card([
                ListTile(
                  key: const Key('settings_logout'),
                  leading: Icon(Symbols.logout_rounded, color: cs.error),
                  title: Text(
                    l10n.logout,
                    style: tt.bodyLarge?.copyWith(color: cs.error),
                  ),
                  onTap: () => _showLogoutConfirmation(context),
                ),
              ]),
            ],
          ],
        ),
      ),
    );
  }

  /// One settings group: a Card.filled of list items with inset dividers.
  Widget _card(List<Widget> children) => Card.filled(
    margin: EdgeInsets.zero,
    clipBehavior: Clip.antiAlias,
    child: Column(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const Divider(height: 1, indent: TashilSpacing.xxl * 2),
          children[i],
        ],
      ],
    ),
  );

  /// A setting chosen on the page itself: icon + title (+ hint) and the
  /// control under them across the width.
  Widget _choice(
    BuildContext context, {
    required IconData icon,
    required String title,
    String? subtitle,
    required Widget child,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.lg,
        TashilSpacing.md,
        TashilSpacing.lg,
        TashilSpacing.md,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(icon, color: cs.primary),
              const SizedBox(width: TashilSpacing.lg),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(title, style: tt.bodyLarge),
                    if (subtitle != null)
                      Text(
                        subtitle,
                        style: tt.bodySmall?.copyWith(
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: TashilSpacing.md),
          child,
        ],
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.xs,
        TashilSpacing.sm,
        TashilSpacing.xs,
        TashilSpacing.sm,
      ),
      child: Text(title, style: Theme.of(context).textTheme.titleSmall),
    );
  }

  /// TAS-358 (C-23): an official ListTile (was InkWell + Row).
  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    VoidCallback? onTap,
  }) {
    final cs = Theme.of(context).colorScheme;
    return ListTile(
      leading: Icon(icon, color: cs.primary),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      // Symbols chevrons mirror in RTL by themselves.
      trailing: Icon(Symbols.chevron_right_rounded, color: cs.onSurfaceVariant),
      onTap: onTap,
    );
  }

  /// One seed colour (48dp target, tooltip, selected state for screen
  /// readers). The roles are generated from it (design rule).
  Widget _buildColorOption(BuildContext context, Color color) {
    final cs = Theme.of(context).colorScheme;
    // ignore: deprecated_member_use
    final selected =
        context.watch<ThemeCubit>().state.seedColor.value ==
        // ignore: deprecated_member_use
        color.value;
    final scheme = ColorScheme.fromSeed(seedColor: color);
    return Semantics(
      selected: selected,
      button: true,
      child: IconButton(
        tooltip: AppLocalizations.of(context)!.appColor,
        onPressed: () => context.read<ThemeCubit>().setSeedColor(color),
        style: IconButton.styleFrom(
          backgroundColor: scheme.primary,
          minimumSize: const Size.square(48),
          side: selected
              ? BorderSide(color: cs.onSurface, width: 3)
              : BorderSide.none,
        ),
        icon: Icon(
          selected ? Symbols.check_rounded : null,
          color: scheme.onPrimary,
        ),
      ),
    );
  }

  void _toggleLanguage(BuildContext context) {
    localeProvider.toggleLocale();
  }

  void _showLogoutConfirmation(BuildContext context) {
    AppLogoutModal.show(context, delegate: delegate);
  }
}
