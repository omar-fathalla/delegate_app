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
import 'package:delegate_app/features/hr/presentation/widgets/hr_adaptive_sheet.dart';
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
    Widget divider() => const Divider(height: 1, indent: 56);

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
      body: SafeArea(
        child: ListView(
          padding: const EdgeInsetsDirectional.symmetric(
            vertical: TashilSpacing.md,
          ),
          children: [
            // TAS-358 (C-11): language is a connected ButtonGroup with both
            // choices visible, not a chip that flips on tap.
            ListTile(
              leading: const Icon(Icons.translate_rounded),
              title: Text(l10n.language),
            ),
            Padding(
              padding: const EdgeInsetsDirectional.fromSTEB(
                TashilSpacing.page,
                0,
                TashilSpacing.page,
                TashilSpacing.sm,
              ),
              child: ButtonGroup<String>(
                key: const Key('settings_language'),
                variant: ButtonGroupVariant.connected,
                expand: true,
                selected: {isArabic ? 'ar' : 'en'},
                onSelectionChanged: (v) {
                  if ((v.first == 'ar') != isArabic) _toggleLanguage(context);
                },
                items: [
                  ButtonGroupItem(value: 'ar', label: l10n.arabic),
                  ButtonGroupItem(value: 'en', label: l10n.english),
                ],
              ),
            ),
            divider(),
            _buildSettingsTile(
              context: context,
              icon: Symbols.dark_mode_rounded,
              title: l10n.themeModeTitle,
              subtitle: _themeModeLabel(
                l10n,
                context.watch<ThemeCubit>().state.themeMode,
              ),
              onTap: () => _showThemeModeSheet(context),
            ),
            const SizedBox(height: TashilSpacing.xl),
            _buildSectionHeader(context, l10n.settingsGeneral),
            _buildSettingsTile(
              context: context,
              icon: Icons.privacy_tip_rounded,
              title: l10n.privacyPolicy,
              onTap: () => context.push('/privacy-policy'),
            ),
            // TAS-383: the m3-kit component playground, dev builds only
            // (never in a store build).
            if (AppEnv.isDev) ...[
              divider(),
              _buildSettingsTile(
                context: context,
                icon: Icons.widgets_outlined,
                title: 'مكونات التصميم (نسخة المطورين)',
                onTap: () => PlaygroundLauncher.open(context),
              ),
            ],
            divider(),
            _buildSettingsTile(
              context: context,
              icon: Icons.feedback_rounded,
              title: l10n.sendFeedback,
              // Inner page inside the web HR shell (TAS-157).
              onTap: () => HrAccountPages.openSendFeedback(context, delegate),
            ),
            // Store rating has no meaning in a browser (TAS-158).
            if (!WebRuntimePolicy.isWeb) ...[
              divider(),
              _buildSettingsTile(
                context: context,
                icon: Icons.star_rate_rounded,
                title: l10n.rateTheApp,
                onTap: () => sl<ReviewService>().requestManualReview(),
              ),
            ],
            divider(),
            _buildSettingsTile(
              context: context,
              icon: Icons.history_rounded,
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
            if (delegate.role == UserRole.delegate) ...[
              divider(),
              _buildSettingsTile(
                context: context,
                icon: Icons.camera_alt_rounded,
                title: l10n.photoPermissions2,
                onTap: () => context.push(
                  '/photo-permissions/delegate',
                  extra: delegate,
                ),
              ),
            ],
            if (showLogout) ...[
              divider(),
              ListTile(
                key: const Key('settings_logout'),
                leading: Icon(Icons.logout_rounded, color: cs.error),
                title: Text(l10n.logout, style: TextStyle(color: cs.error)),
                onTap: () => _showLogoutConfirmation(context),
              ),
            ],
            const SizedBox(height: TashilSpacing.xl),
            _buildSectionHeader(context, l10n.appColor),
            Padding(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: TashilSpacing.page,
                vertical: TashilSpacing.sm,
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceAround,
                children: AppColorSchemes.seedColors
                    .map((c) => _buildColorOption(context, c))
                    .toList(),
              ),
            ),
            const SizedBox(height: TashilSpacing.xxl),
            FutureBuilder<PackageInfo>(
              future: PackageInfo.fromPlatform(),
              builder: (context, snapshot) {
                final version =
                    snapshot.hasData ? snapshot.data!.version : '...';
                return Center(
                  child: Text(
                    // The web isn't the «مندوب تسهيل» app (TAS-158).
                    WebRuntimePolicy.isWeb
                        ? l10n.webVersion(version)
                        : l10n.version(version),
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                );
              },
            ),
            const SizedBox(height: TashilSpacing.xl),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.page,
        TashilSpacing.sm,
        TashilSpacing.page,
        TashilSpacing.sm,
      ),
      child: Text(
        title,
        style: Theme.of(context).textTheme.titleSmall?.copyWith(
          color: Theme.of(context).colorScheme.primary,
        ),
      ),
    );
  }

  String _themeModeLabel(AppLocalizations l10n, ThemeMode mode) =>
      switch (mode) {
        ThemeMode.system => l10n.themeModeSystem,
        ThemeMode.light => l10n.themeModeLight,
        ThemeMode.dark => l10n.themeModeDark,
      };

  Future<void> _showThemeModeSheet(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cubit = context.read<ThemeCubit>();
    // Wide web windows get a dialog (TAS-158). Mobile and narrow windows keep
    // the original bottom sheet unchanged.
    if (HrSheet.useDesktop(context)) {
      return showHrAdaptiveSheet<void>(
        context: context,
        title: l10n.themeModeTitle,
        dialogWidth: 440,
        builder: (sheetContext) =>
            _themeModeOptions(sheetContext, cubit, l10n, showTitle: false),
      );
    }
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: _themeModeOptions(sheetContext, cubit, l10n, showTitle: true),
      ),
    );
  }

  /// Radio list of theme modes. Picking one applies it and closes the sheet
  /// or dialog that hosts it.
  Widget _themeModeOptions(
    BuildContext sheetContext,
    ThemeCubit cubit,
    AppLocalizations l10n, {
    required bool showTitle,
  }) {
    return BlocBuilder<ThemeCubit, ThemeState>(
      bloc: cubit,
      builder: (_, state) => RadioGroup<ThemeMode>(
        groupValue: state.themeMode,
        onChanged: (m) {
          if (m == null) return;
          cubit.setThemeMode(m);
          Navigator.of(sheetContext).pop();
        },
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (showTitle)
              Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  TashilSpacing.xl,
                  0,
                  TashilSpacing.xl,
                  TashilSpacing.sm,
                ),
                child: Text(
                  l10n.themeModeTitle,
                  style: Theme.of(sheetContext).textTheme.titleLarge,
                ),
              ),
            for (final (m, icon) in [
              (ThemeMode.system, Symbols.brightness_auto_rounded),
              (ThemeMode.light, Symbols.light_mode_rounded),
              (ThemeMode.dark, Symbols.dark_mode_rounded),
            ])
              RadioListTile<ThemeMode>(
                key: ValueKey('theme_mode_${m.name}'),
                value: m,
                secondary: Icon(icon, fill: state.themeMode == m ? 1 : 0),
                title: Text(_themeModeLabel(l10n, m)),
                subtitle: m == ThemeMode.system
                    ? Text(l10n.themeModeSystemHint)
                    : null,
              ),
            if (showTitle) const SizedBox(height: TashilSpacing.sm),
          ],
        ),
      ),
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
    return ListTile(
      leading: Icon(icon),
      title: Text(title),
      subtitle: subtitle == null ? null : Text(subtitle),
      trailing: const Icon(Icons.chevron_right_rounded),
      onTap: onTap,
    );
  }

  Widget _buildColorOption(BuildContext context, Color color) {
    final themeCubit = context.watch<ThemeCubit>();
    // ignore: deprecated_member_use
    final isSelected = themeCubit.state.seedColor.value == color.value;

    return GestureDetector(
      onTap: () => context.read<ThemeCubit>().setSeedColor(color),
      child: Container(
        width: 48,
        height: 48,
        decoration: BoxDecoration(
          color: color,
          shape: BoxShape.circle,
          border: isSelected
              ? Border.all(
                  color: Theme.of(context).colorScheme.onSurface,
                  width: 3,
                )
              : null,
        ),
        child: isSelected
            ? Icon(
                Icons.check_rounded,
                color: Theme.of(context).colorScheme.onPrimary,
                size: 24,
              )
            : null,
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
