import 'package:material_ui/material_ui.dart';

import '../../../../l10n/app_localizations.dart';

/// Search bar widget for company search
class CompanySearchBar extends StatelessWidget {
  final TextEditingController controller;
  final ValueChanged<String> onSubmitted;
  final VoidCallback onClear;

  const CompanySearchBar({
    super.key,
    required this.controller,
    required this.onSubmitted,
    required this.onClear,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return SearchBar(
      controller: controller,
      hintText: l10n.enterCompanyCode,
      leading: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
      trailing: [
        if (controller.text.isNotEmpty)
          IconButton(
            onPressed: onClear,
            icon: Icon(
              Icons.clear_rounded,
              color: colorScheme.onSurfaceVariant,
            ),
            tooltip: l10n.clear,
          ),
      ],
      onSubmitted: onSubmitted,
      onChanged: (value) {
        // Trigger rebuild to show/hide clear button
        if (value.isEmpty || value.isNotEmpty) {
          // This will trigger a rebuild
        }
      },
      backgroundColor: WidgetStateProperty.all(
        colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
      ),
      surfaceTintColor: WidgetStateProperty.all(Colors.transparent),
      side: WidgetStateProperty.all(
        BorderSide(color: colorScheme.outline.withValues(alpha: 0.2), width: 1),
      ),
      shape: WidgetStateProperty.all(
        RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
      ),
      textStyle: WidgetStateProperty.all(
        theme.textTheme.bodyLarge?.copyWith(color: colorScheme.onSurface),
      ),
      hintStyle: WidgetStateProperty.all(
        theme.textTheme.bodyLarge?.copyWith(
          color: colorScheme.onSurfaceVariant,
        ),
      ),
    );
  }
}
