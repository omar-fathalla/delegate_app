import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../../../l10n/app_localizations.dart';

/// Example screen showing how to navigate to company search
class CompanySearchExample extends StatelessWidget {
  final String organizationUID;

  const CompanySearchExample({super.key, required this.organizationUID});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Scaffold(
      appBar: AppBar(
        title: Text('Company Search Example'),
        backgroundColor: colorScheme.surface,
      ),
      body: Center(
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(Icons.search_rounded, size: 64, color: colorScheme.primary),
            const SizedBox(height: 24),
            Text(
              'Company Search with Infinite Scroll',
              style: theme.textTheme.headlineSmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'Search for companies using company code with pagination',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
            const SizedBox(height: 32),
            FilledButton.icon(
              onPressed: () {
                context.push('/admin/company-search', extra: organizationUID);
              },
              icon: const Icon(Icons.search_rounded),
              label: Text(l10n.searchCompanies),
            ),
          ],
        ),
      ),
    );
  }
}
