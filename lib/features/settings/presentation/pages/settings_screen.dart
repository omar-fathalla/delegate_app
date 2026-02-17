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
      backgroundColor: Colors.grey[100],
      body: SingleChildScrollView(
        padding: const EdgeInsetsDirectional.only(
          start: 20,
          end: 20,
          top: 20,
          bottom: 80,
        ),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Section: General
            _buildSectionHeader(l10n.settings),
            const SizedBox(height: 12),

            // Language Toggle
            _buildSettingsTile(
              context: context,
              icon: Icons.translate_rounded,
              title: l10n.changeLanguage,
              subtitle: isArabic ? l10n.arabic : l10n.english,
              trailing: Container(
                padding: const EdgeInsets.symmetric(
                  horizontal: 12,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: const Color(0xFF0D47A1).withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(20),
                  border: Border.all(
                    color: const Color(0xFF0D47A1).withValues(alpha: 0.3),
                  ),
                ),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isArabic ? 'EN' : 'ع',
                      style: const TextStyle(
                        fontSize: 14,
                        fontWeight: FontWeight.bold,
                        color: Color(0xFF0D47A1),
                      ),
                    ),
                    const SizedBox(width: 4),
                    const Icon(
                      Icons.swap_horiz_rounded,
                      size: 18,
                      color: Color(0xFF0D47A1),
                    ),
                  ],
                ),
              ),
              onTap: () => _toggleLanguage(context),
            ),
            const SizedBox(height: 40),

            // Section: Account
            _buildSectionHeader(isArabic ? 'الحساب' : 'Account'),
            const SizedBox(height: 12),

            // Logout
            _buildSettingsTile(
              context: context,
              icon: Icons.logout_rounded,
              title: l10n.logout,
              iconColor: Colors.red,
              titleColor: Colors.red,
              onTap: () => _showLogoutConfirmation(context),
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
          fontSize: 18,
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
    Color iconColor = const Color(0xFF0D47A1),
    Color titleColor = Colors.black87,
    required VoidCallback onTap,
  }) {
    return Material(
      color: Colors.white,
      borderRadius: BorderRadius.circular(16),
      elevation: 1,
      shadowColor: Colors.grey.withValues(alpha: 0.15),
      child: InkWell(
        onTap: onTap,
        borderRadius: BorderRadius.circular(16),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 16),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(10),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.1),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: iconColor, size: 24),
              ),
              const SizedBox(width: 14),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      title,
                      style: TextStyle(
                        fontSize: 16,
                        fontWeight: FontWeight.w600,
                        color: titleColor,
                      ),
                    ),
                    if (subtitle != null) ...[
                      const SizedBox(height: 2),
                      Text(
                        subtitle,
                        style: TextStyle(fontSize: 13, color: Colors.grey[500]),
                      ),
                    ],
                  ],
                ),
              ),
              if (trailing != null) trailing,
              if (trailing == null)
                Icon(Icons.chevron_right_rounded, color: Colors.grey[400]),
            ],
          ),
        ),
      ),
    );
  }

  void _toggleLanguage(BuildContext context) {
    final messenger = ScaffoldMessenger.of(context);
    localeProvider.toggleLocale();

    Future.delayed(const Duration(milliseconds: 300), () {
      final newLangName = localeProvider.isArabic ? 'العربية' : 'English';
      messenger.showSnackBar(
        SnackBar(
          content: Row(
            children: [
              const Icon(Icons.check_circle, color: Colors.white, size: 20),
              const SizedBox(width: 8),
              Text(
                localeProvider.isArabic
                    ? 'تم تغيير اللغة إلى $newLangName'
                    : 'Language changed to $newLangName',
              ),
            ],
          ),
          backgroundColor: const Color(0xFF0D47A1),
          behavior: SnackBarBehavior.floating,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(12),
          ),
          duration: const Duration(seconds: 2),
        ),
      );
    });
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
          ElevatedButton(
            style: ElevatedButton.styleFrom(
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
