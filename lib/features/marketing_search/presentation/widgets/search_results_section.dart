import 'package:material_ui/material_ui.dart';

import '../bloc/marketing_search_state.dart';
import 'company_result_card.dart';
import 'delegate_result_card.dart';

/// قسم عرض نتائج البحث
/// Search results section widget
class SearchResultsSection extends StatelessWidget {
  final MarketingSearchState state;

  const SearchResultsSection({super.key, required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عنوان القسم
        Row(
          children: [
            Icon(Icons.list_alt_rounded, color: colorScheme.primary, size: 20),
            const SizedBox(width: 8),
            Text(
              'النتائج',
              style: theme.textTheme.titleMedium?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w600,
              ),
            ),
          ],
        ),

        const SizedBox(height: 16),

        // عرض النتائج حسب الحالة
        _buildStateContent(context),
      ],
    );
  }

  Widget _buildStateContent(BuildContext context) {
    return switch (state) {
      MarketingSearchInitial() => _buildInitialState(context),
      MarketingSearchLoading() => _buildLoadingState(context),
      CompanySearchSuccess() => _buildCompanyResults(
        context,
        state as CompanySearchSuccess,
      ),
      DelegateSearchSuccess() => _buildDelegateResults(
        context,
        state as DelegateSearchSuccess,
      ),
      MarketingSearchEmpty() => _buildEmptyState(
        context,
        state as MarketingSearchEmpty,
      ),
      MarketingSearchError() => _buildErrorState(
        context,
        state as MarketingSearchError,
      ),
      _ => _buildInitialState(context),
    };
  }

  /// حالة البداية - لم يتم البحث بعد
  Widget _buildInitialState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.search_off_rounded,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              'لم يتم البحث بعد',
              style: theme.textTheme.bodyLarge?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'استخدم حقول البحث أعلاه',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// حالة التحميل
  Widget _buildLoadingState(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
      ),
      child: Center(
        child: Column(
          children: [
            CircularProgressIndicator(color: colorScheme.primary),
            const SizedBox(height: 16),
            Text(
              'جاري البحث...',
              style: theme.textTheme.bodyMedium?.copyWith(
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// نتائج البحث عن الشركات
  Widget _buildCompanyResults(
    BuildContext context,
    CompanySearchSuccess state,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عدد النتائج
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'وُجد ${state.companies.length} شركة',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onPrimaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // قائمة الشركات
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.companies.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return CompanyResultCard(company: state.companies[index]);
          },
        ),
      ],
    );
  }

  /// نتائج البحث عن المندوبين
  Widget _buildDelegateResults(
    BuildContext context,
    DelegateSearchSuccess state,
  ) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عدد النتائج
        Container(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
          decoration: BoxDecoration(
            color: colorScheme.secondaryContainer,
            borderRadius: BorderRadius.circular(8),
          ),
          child: Text(
            'وُجد ${state.delegates.length} مندوب',
            style: theme.textTheme.bodySmall?.copyWith(
              color: colorScheme.onSecondaryContainer,
              fontWeight: FontWeight.w600,
            ),
          ),
        ),

        const SizedBox(height: 12),

        // قائمة المندوبين
        ListView.separated(
          shrinkWrap: true,
          physics: const NeverScrollableScrollPhysics(),
          itemCount: state.delegates.length,
          separatorBuilder: (context, index) => const SizedBox(height: 12),
          itemBuilder: (context, index) {
            return DelegateResultCard(delegate: state.delegates[index]);
          },
        ),
      ],
    );
  }

  /// حالة عدم وجود نتائج
  Widget _buildEmptyState(BuildContext context, MarketingSearchEmpty state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final isCompany = state.searchType == 'company';

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant, width: 1),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              isCompany
                  ? Icons.business_rounded
                  : Icons.person_outline_rounded,
              size: 48,
              color: colorScheme.outline,
            ),
            const SizedBox(height: 12),
            Text(
              isCompany ? 'لا توجد شركات مطابقة' : 'لا يوجد مندوبين مطابقين',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.onSurfaceVariant,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              'البحث: "${state.searchQuery}"',
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.outline,
              ),
            ),
          ],
        ),
      ),
    );
  }

  /// حالة الخطأ
  Widget _buildErrorState(BuildContext context, MarketingSearchError state) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.all(32),
      decoration: BoxDecoration(
        color: colorScheme.errorContainer.withValues(alpha: 0.3),
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.error.withValues(alpha: 0.3),
          width: 1,
        ),
      ),
      child: Center(
        child: Column(
          children: [
            Icon(
              Icons.error_outline_rounded,
              size: 48,
              color: colorScheme.error,
            ),
            const SizedBox(height: 12),
            Text(
              'حدث خطأ',
              style: theme.textTheme.titleSmall?.copyWith(
                color: colorScheme.error,
                fontWeight: FontWeight.w600,
              ),
            ),
            const SizedBox(height: 4),
            Text(
              state.message,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onErrorContainer,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }
}
