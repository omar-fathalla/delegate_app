import 'package:flutter/material.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:go_router/go_router.dart';

class SettingsScreen extends StatelessWidget {
  final Delegate delegate;

  const SettingsScreen({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final isArabic = localeProvider.isArabic;

    return Scaffold(
      backgroundColor: const Color(0xFFF4F6F9), // Light grayish-blue background
      body: SafeArea(
        child: Column(
          children: [
            // Custom App Bar Header
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 16),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    icon: const Icon(
                      Icons.notifications_rounded,
                      color: Color(0xFF334155),
                    ),
                    onPressed: () {},
                  ),
                  Text(
                    l10n.settings,
                    style: const TextStyle(
                      fontSize: 20,
                      fontWeight: FontWeight.w500,
                      color: Colors.black87,
                    ),
                  ),
                  CircleAvatar(
                    radius: 20,
                    backgroundColor: Colors.orange.shade200,
                    child: Icon(Icons.person, color: Colors.orange.shade800),
                  ),
                ],
              ),
            ),

            Expanded(
              child: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 20,
                  vertical: 12,
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Section: Settings
                    _buildSectionHeader(l10n.settings),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.translate_rounded,
                            title: l10n.language,
                            subtitle: isArabic ? l10n.arabic : l10n.english,
                            trailing: GestureDetector(
                              onTap: () => _toggleLanguage(context),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 6,
                                ),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFD3E3FD),
                                  borderRadius: BorderRadius.circular(20),
                                ),
                                child: Text(
                                  isArabic ? 'English' : 'العربية',
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.w500,
                                    color: Color(0xFF041E49),
                                  ),
                                ),
                              ),
                            ),
                          ),
                          Divider(
                            height: 1,
                            color: Colors.grey.shade200,
                            indent: 64,
                          ),
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.dark_mode_rounded,
                            title: l10n.darkMode,
                            subtitle:
                                'Off', // Optional: translate "Off" if desired, or skip
                            trailing: Switch(
                              value: false,
                              onChanged: (val) {},
                              activeTrackColor: const Color(
                                0xFF0D47A1,
                              ).withValues(alpha: 0.5),
                              activeThumbColor: const Color(0xFF0D47A1),
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 32),

                    // Section: Account
                    _buildSectionHeader(l10n.account),
                    const SizedBox(height: 12),

                    Container(
                      decoration: BoxDecoration(
                        color: Colors.white,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        children: [
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.privacy_tip_outlined,
                            title: l10n.privacyPolicy,
                            onTap: () {},
                          ),
                          Divider(
                            height: 1,
                            color: Colors.grey.shade200,
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
                            color: Colors.grey.shade200,
                            indent: 64,
                          ),
                          _buildSettingsTile(
                            context: context,
                            icon: Icons.logout_rounded,
                            title: l10n.logout,
                            iconColor: Colors.red,
                            titleColor: Colors.red,
                            onTap: () => _showLogoutConfirmation(context),
                            hideTrailingIcon: true,
                          ),
                        ],
                      ),
                    ),

                    const SizedBox(height: 48),
                    // Version Text
                    Center(
                      child: Text(
                        l10n.version('2.4.0'),
                        style: TextStyle(
                          color: Colors.grey.shade500,
                          fontSize: 13,
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
      ),
    );
  }

  Widget _buildSectionHeader(String title) {
    return Padding(
      padding: const EdgeInsetsDirectional.only(start: 4),
      child: Text(
        title,
        style: const TextStyle(
          fontSize: 14,
          fontWeight: FontWeight.bold,
          color: Color(0xFF0D47A1),
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
    Color iconColor = const Color(0xFF475569),
    Color titleColor = const Color(0xFF1E293B),
    VoidCallback? onTap,
    bool hideTrailingIcon = false,
  }) {
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(16),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
        child: Row(
          children: [
            Icon(icon, color: iconColor, size: 28),
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
                      color: titleColor,
                    ),
                  ),
                  if (subtitle != null) ...[
                    const SizedBox(height: 4),
                    Text(
                      subtitle,
                      style: TextStyle(fontSize: 13, color: Colors.grey[600]),
                    ),
                  ],
                ],
              ),
            ),
            if (trailing != null) trailing,
            if (trailing == null && !hideTrailingIcon)
              Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
          ],
        ),
      ),
    );
  }

  void _toggleLanguage(BuildContext context) {
    localeProvider.toggleLocale();
  }

  void _showLogoutConfirmation(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    showDialog(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
        title: Row(
          children: [
            const Icon(Icons.logout_rounded, color: Colors.red, size: 24),
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
              style: const TextStyle(color: Colors.grey),
            ),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
            ),
            onPressed: () {
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
