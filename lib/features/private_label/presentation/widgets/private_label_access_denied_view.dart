import 'package:flutter/material.dart';

class PrivateLabelAccessDeniedView extends StatelessWidget {
  final String title;
  final String screenName;

  const PrivateLabelAccessDeniedView({
    super.key,
    required this.title,
    required this.screenName,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Directionality(
      textDirection: isArabic ? TextDirection.rtl : TextDirection.ltr,
      child: Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(title),
          leading: IconButton(
            icon: const Icon(Icons.arrow_back_rounded),
            onPressed: () => Navigator.of(context).pop(),
          ),
        ),
        body: Center(
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 32),
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Container(
                  padding: const EdgeInsets.all(20),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.5),
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    Icons.lock_person_rounded,
                    size: 48,
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 20),
                Text(
                  isArabic ? 'صلاحية الوصول غير مفعلة' : 'Access Restricted',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 8),
                Text(
                  isArabic
                      ? 'عفواً، لا تمتلك حالياً صلاحية الوصول لشاشة ($screenName).\nيرجى التواصل مع السوبر أدمن لتفعيل الصلاحية لحسابك.'
                      : 'You do not currently have permission to access ($screenName).\nPlease contact Super Admin to grant access.',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                    height: 1.5,
                  ),
                  textAlign: TextAlign.center,
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: () => Navigator.of(context).pop(),
                  icon: const Icon(Icons.arrow_back_rounded, size: 18),
                  label: Text(isArabic ? 'العودة للخلف' : 'Go Back'),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
