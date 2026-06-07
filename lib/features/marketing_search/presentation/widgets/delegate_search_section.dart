import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';

/// قسم البحث عن المندوبين
/// Delegate search section widget
class DelegateSearchSection extends StatelessWidget {
  final TextEditingController controller;
  final VoidCallback onSearch;

  const DelegateSearchSection({
    super.key,
    required this.controller,
    required this.onSearch,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // العنوان مع الأيقونة
        Row(
          children: [
            Container(
              padding: const EdgeInsets.all(8),
              decoration: BoxDecoration(
                color: colorScheme.secondaryContainer,
                borderRadius: BorderRadius.circular(8),
              ),
              child: Icon(
                Icons.person_rounded,
                color: colorScheme.onSecondaryContainer,
                size: 20,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'البحث عن مندوب',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // حقل إدخال رقم الموبايل
        TextField(
          controller: controller,
          keyboardType: TextInputType.phone,
          textDirection: TextDirection.ltr,
          inputFormatters: [
            FilteringTextInputFormatter.allow(RegExp(r'[0-9+\-\s]')),
          ],
          decoration: InputDecoration(
            labelText: 'رقم الموبايل',
            hintText: 'أدخل رقم الموبايل (مثال: 01012345678)',
            hintStyle: TextStyle(color: colorScheme.outline),
            prefixIcon: Icon(
              Icons.phone_android_rounded,
              color: colorScheme.secondary,
            ),
            suffixIcon: controller.text.isNotEmpty
                ? IconButton(
                    tooltip: l10n.clear,
                    icon: Icon(Icons.clear_rounded, color: colorScheme.outline),
                    onPressed: () {
                      controller.clear();
                    },
                  )
                : null,
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outline),
            ),
            focusedBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.secondary, width: 2),
            ),
            filled: true,
            fillColor: colorScheme.surface,
          ),
          onSubmitted: (_) => onSearch(),
        ),

        const SizedBox(height: 16),

        // زر البحث
        SizedBox(
          width: double.infinity,
          height: 52,
          child: ElevatedButton(
            onPressed: onSearch,
            style: ElevatedButton.styleFrom(
              backgroundColor: colorScheme.secondary,
              foregroundColor: colorScheme.onSecondary,
              elevation: 2,
              shadowColor: colorScheme.secondary.withValues(alpha: 0.3),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(12),
              ),
              padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 12),
            ),
            child: const Row(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.search_rounded, size: 22),
                SizedBox(width: 12),
                Text(
                  'بحث عن المندوب',
                  style: TextStyle(
                    fontSize: 16,
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.5,
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
