import 'package:flutter/material.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

import 'package:delegate_app/main.dart';
import 'package:go_router/go_router.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/config/theme/color_schemes.dart';
import 'package:package_info_plus/package_info_plus.dart';

class SettingsScreen extends StatelessWidget {
  final Delegate delegate;

  const SettingsScreen({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;

    return Scaffold(
      backgroundColor: Theme.of(context).colorScheme.surface,
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
                            icon: Icons.dark_mode_rounded,
                            title: l10n.darkMode,
                            subtitle:
                                context.watch<ThemeCubit>().state.isDarkMode
                                ? 'On'
                                : 'Off',
                            trailing: Switch(
                              value: context
                                  .watch<ThemeCubit>()
                                  .state
                                  .isDarkMode,
                              onChanged: (val) =>
                                  context.read<ThemeCubit>().toggleTheme(),
                              activeTrackColor: Theme.of(
                                context,
                              ).colorScheme.primary.withValues(alpha: 0.5),
                              activeThumbColor: Theme.of(
                                context,
                              ).colorScheme.primary,
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Section: Account
                    Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16),
                      child: _buildSectionHeader(context, l10n.account),
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
                            icon: Icons.privacy_tip_outlined,
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
                            icon: Icons.auto_awesome_rounded,
                            title: isArabic ? 'ما الجديد؟' : "What's New?",
                            onTap: () => context.push('/changelog'),
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.feedback_outlined,
                            title: isArabic ? 'إرسال مقترح' : 'Submit Feedback',
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
                            icon: Icons.history_rounded,
                            title: delegate.role == UserRole.superAdmin
                                ? (isArabic
                                      ? 'إدارة المقترحات'
                                      : 'Manage Feedbacks')
                                : (isArabic ? 'مقترحاتي' : 'My Feedbacks'),
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
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.help_outline_rounded,
                            title: l10n.helpCenter,
                            onTap: () {},
                          ),
                          Divider(
                            height: 1,
                            color: Theme.of(context).colorScheme.outlineVariant,
                            indent: 64,
                          ),
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
                            Text(
                              isArabic ? 'ألوان التطبيق' : 'App Colors',
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
                        final version = snapshot.hasData
                            ? snapshot.data!.version
                            : '...';
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
            ?trailing,
            if (trailing == null && !hideTrailingIcon)
              Icon(
                Icons.chevron_right_rounded,
                color: theme.colorScheme.onSurfaceVariant,
              ),
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
            ? const Icon(Icons.check, color: Colors.white, size: 24)
            : null,
      ),
    );
  }

  void _toggleLanguage(BuildContext context) {
    localeProvider.toggleLocale();
  }

  void _showLogoutConfirmation(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            Icon(Icons.logout_rounded, color: colorScheme.error, size: 24),
            const SizedBox(width: 8),
            Text(l10n.logout),
          ],
        ),
        content: Text(
          localeProvider.isArabic
              ? 'هل أنت متأكد من تسجيل الخروج؟'
              : 'Are you sure you want to logout?',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext),
            child: Text(
              localeProvider.isArabic ? 'إلغاء' : 'Cancel',
              style: TextStyle(color: colorScheme.onSurfaceVariant),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.error,
              foregroundColor: colorScheme.onError,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
              // Clear FCM token before logout
              sl<PushNotificationService>().clearToken(delegate.uid).catchError(
                (e) {
                  debugPrint('FCM clear token error: $e');
                },
              );
              Navigator.pop(dialogContext);
              context.go('/login');
            },
            child: Text(l10n.logout),
          ),
        ],
      ),
    );
  }
}
