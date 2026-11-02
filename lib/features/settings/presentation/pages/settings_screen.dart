import 'package:flutter/material.dart';
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

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
      appBar: showAppBar
          ? AppBar(
              title: Text(
                l10n.settings,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              backgroundColor: Theme.of(context).colorScheme.surface,
              surfaceTintColor: Theme.of(context).colorScheme.surfaceTint,
              elevation: 0,
              centerTitle: false,
              leading: IconButton(
                icon: const Icon(Icons.arrow_back_rounded),
                tooltip: AppLocalizations.of(context)!.backAction,
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
        child: Column(
          children: [
            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(vertical: 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.2),
                      ),
                      child: Column(
                        children: [
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.translate_rounded,
                            title: l10n.language,
                            subtitle: isArabic ? l10n.arabic : l10n.english,
                            onTap: () => _toggleLanguage(context),
                            trailing: Container(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              decoration: BoxDecoration(
                                color: Theme.of(
                                  context,
                                ).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(20),
                              ),
                              child: Text(
                                isArabic ? 'English' : 'العربية',
                                style: TextStyle(
                                  fontSize: 13,
                                  fontWeight: FontWeight.w500,
                                  color: Theme.of(
                                    context,
                                  ).colorScheme.onPrimaryContainer,
                                ),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
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
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Section: Account
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSectionHeader(context, l10n.settingsGeneral),
                    ),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.2),
                      ),
                      child: Column(
                        children: [
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.privacy_tip_rounded,
                            title: l10n.privacyPolicy,
                            onTap: () => context.push('/privacy-policy'),
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.feedback_rounded,
                            title: AppLocalizations.of(context)!.sendFeedback,
                            onTap: () => context.push(
                              '/submit-feedback',
                              extra: delegate,
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.star_rate_rounded,
                            title: AppLocalizations.of(context)!.rateTheApp,
                            onTap: () => sl<ReviewService>().requestManualReview(),
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.history_rounded,
                            title: delegate.role == UserRole.superAdmin
                                ? AppLocalizations.of(context)!.manageFeedback
                                : AppLocalizations.of(context)!.myFeedback,
                            onTap: () {
                              if (delegate.role == UserRole.superAdmin) {
                                context.push('/admin/feedbacks');
                              } else {
                                context.push('/my-feedbacks', extra: delegate);
                              }
                            },
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
                          if (delegate.role == UserRole.delegate) ...[
                            _buildSettingsTile(
                              context: context,
                              icon: Icons.camera_alt_rounded,
                              title: AppLocalizations.of(context)!.photoPermissions2,
                              onTap: () => context.push('/photo-permissions/delegate', extra: delegate),
                            ),
                            Divider(
                              height: 1,
                              color: Theme.of(context).colorScheme.outlineVariant,
                              indent: 64,
                            ),
                          ],

                          // Help center hidden: no destination exists yet
                          // (was a dead `onTap: () {}`).
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.logout_rounded,
                            title: l10n.logout,
                            iconColor: Theme.of(context).colorScheme.error,
                            titleColor: Theme.of(context).colorScheme.error,
                            onTap: () => _showLogoutConfirmation(context),
                            hideTrailingIcon: true,
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    Container(
                      decoration: BoxDecoration(
                        color: Theme.of(context)
                            .colorScheme
                            .surfaceContainerHighest
                            .withValues(alpha: 0.2),
                      ),
                      child: Padding(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 16,
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(AppLocalizations.of(context)!.appColor,
                              style: TextStyle(
                                fontSize: 14,
                                fontWeight: FontWeight.w600,
                                color: Theme.of(
                                  context,
                                ).colorScheme.onSurfaceVariant,
                              ),
                            ),
                            const SizedBox(height: 16),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceAround,
                              children: AppColorSchemes.seedColors
                                  .map((c) => _buildColorOption(context, c))
                                  .toList(),
                            ),
                          ],
                        ),
                      ),
                    ),

                    const SizedBox(height: 48),
                    // Version Text
                    FutureBuilder<PackageInfo>(
                      future: PackageInfo.fromPlatform(),
                      builder: (context, snapshot) {
                        final version =
                            snapshot.hasData ? snapshot.data!.version : '...';
                        return Center(
                          child: Text(
                            l10n.version(version),
                            style: TextStyle(
                              color: Theme.of(
                                context,
                              ).colorScheme.onSurfaceVariant,
                              fontSize: 13,
                            ),
                          ),
                        );
                      },
                    ),
                    const SizedBox(height: 24),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildSectionHeader(BuildContext context, String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        title,
        style: TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
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
    return showModalBottomSheet<void>(
      context: context,
      builder: (sheetContext) => SafeArea(
        child: BlocBuilder<ThemeCubit, ThemeState>(
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
                Padding(
                  padding: const EdgeInsets.fromLTRB(24, 0, 24, 8),
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
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildSettingsTile({
    required BuildContext context,
    required IconData icon,
    required String title,
    String? subtitle,
    Widget? trailing,
    Color? iconColor,
    Color? titleColor,
    VoidCallback? onTap,
    bool hideTrailingIcon = false,
  }) {
    final theme = Theme.of(context);
    final finalIconColor = iconColor ?? theme.colorScheme.onSurfaceVariant;
    final finalTitleColor = titleColor ?? theme.colorScheme.onSurface;

    return InkWell(
      onTap: onTap,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: finalIconColor, size: 28),
            const SizedBox(width: 16),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    title,
                    style: TextStyle(
                      fontSize: 16,
                      fontWeight: FontWeight.w400,
                      color: finalTitleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(
                        fontSize: 13,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ],
              ),
            ),
            trailing ??
                (!hideTrailingIcon
                    ? Icon(
                        Icons.chevron_right_rounded,
                        color: theme.colorScheme.onSurfaceVariant,
                      )
                    : const SizedBox.shrink()),
          ],
        ),
      ),
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
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.1),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
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
