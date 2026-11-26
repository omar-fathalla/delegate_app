import 'package:material_ui/material_ui.dart';
import 'package:go_router/go_router.dart';

import '../../domain/entities/company.dart';
import 'company_list_item.dart';

/// List widget for displaying company search results with infinite scroll
class CompanySearchList extends StatelessWidget {
  final List<Company> companies;
  final ScrollController scrollController;
  final bool hasReachedMax;
  final bool isLoadingMore;

  const CompanySearchList({
    super.key,
    required this.companies,
    required this.scrollController,
    required this.hasReachedMax,
    this.isLoadingMore = false,
  });

  @override
  Widget build(BuildContext context) {
    return ListView.separated(
      controller: scrollController,
      padding: const EdgeInsets.all(16),
      itemCount: companies.length + (isLoadingMore || !hasReachedMax ? 1 : 0),
      separatorBuilder: (context, index) => const SizedBox(height: 12),
      itemBuilder: (context, index) {
        // Show company item
        if (index < companies.length) {
          return CompanyListItem(
            company: companies[index],
            onTap: () => _onCompanyTap(context, companies[index]),
          );
        }

        // Show loading indicator at the bottom
        if (isLoadingMore) {
          return _buildLoadingIndicator(context);
        }

        // Show "Load more" indicator if not reached max
        if (!hasReachedMax) {
          return _buildLoadMoreIndicator(context);
        }

        // Show end of list indicator
        return _buildEndOfListIndicator(context);
      },
    );
  }

  /// Handle company item tap
  void _onCompanyTap(BuildContext context, Company company) {
    // Navigate to company details screen
    context.push('/admin/company-details', extra: company);
  }

  /// Build loading indicator for pagination
  Widget _buildLoadingIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: SizedBox(
          width: 24,
          height: 24,
          child: CircularProgressIndicator(
            strokeWidth: 2,
            color: colorScheme.primary,
          ),
        ),
      ),
    );
  }

  /// Build load more indicator
  Widget _buildLoadMoreIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            SizedBox(
              width: 16,
              height: 16,
              child: CircularProgressIndicator(
                strokeWidth: 2,
                color: colorScheme.outline,
              ),
            ),
            const SizedBox(width: 12),
            Text(
              'جاري تحميل المزيد...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// Build end of list indicator
  Widget _buildEndOfListIndicator(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(16),
      child: Center(
        child: Row(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Icon(
              Icons.check_circle_outline_rounded,
              size: 16,
              color: colorScheme.outline,
            ),
            const SizedBox(width: 8),
            Text(
              'تم عرض جميع النتائج',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }
}
