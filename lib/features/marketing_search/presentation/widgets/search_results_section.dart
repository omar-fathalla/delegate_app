import 'package:material_ui/material_ui.dart';

import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';

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

    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        // عنوان القسم
        Text(
          'النتائج',
          style: theme.textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.w700,
          ),
        ),
        const SizedBox(height: TashilSpacing.sm),

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

  /// حالة البداية - لم يتم البحث بعد (TAS-392: kit EmptyState).
  Widget _buildInitialState(BuildContext context) {
    return const EmptyState(
      icon: Icons.search_rounded,
      title: 'لم يتم البحث بعد',
      message: 'استخدم حقول البحث أعلاه',
    );
  }

  Widget _buildLoadingState(BuildContext context) {
    return Padding(
      padding: const EdgeInsets.all(TashilSpacing.xl),
      child: Column(
        children: [
          const LoadingIndicator(),
          const SizedBox(height: TashilSpacing.md),
          Text(
            'جاري البحث...',
            style: Theme.of(context).textTheme.bodyMedium?.copyWith(
              color: Theme.of(context).colorScheme.onSurfaceVariant,
            ),
          ),
        ],
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
    final isCompany = state.searchType == 'company';
    return EmptyState(
      icon: Icons.search_off_rounded,
      title: isCompany ? 'لا توجد شركات مطابقة' : 'لا يوجد مندوبين مطابقين',
      message: 'البحث: "${state.searchQuery}"',
    );
  }

  Widget _buildErrorState(BuildContext context, MarketingSearchError state) {
    return EmptyState(
      icon: Icons.error_outline_rounded,
      title: 'حدث خطأ',
      message: state.message,
    );
  }
}
