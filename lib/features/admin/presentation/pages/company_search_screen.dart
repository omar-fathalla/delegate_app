import 'dart:developer' as developer;

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

import '../../../../injection_container.dart' as di;
import '../../../../l10n/app_localizations.dart';
import '../../../auth/data/datasources/auth_local_data_source.dart';
import '../bloc/company_search_bloc.dart';
import '../bloc/company_search_event.dart';
import '../bloc/company_search_state.dart';
import '../widgets/company_search_list.dart';
import '../widgets/company_search_bar.dart';

/// Screen for searching companies by company code
class CompanySearchScreen extends StatelessWidget {
  final String? organizationUID;

  const CompanySearchScreen({super.key, this.organizationUID});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<CompanySearchBloc>(),
      child: _CompanySearchView(organizationUID: organizationUID),
    );
  }
}

class _CompanySearchView extends StatefulWidget {
  final String? organizationUID;

  const _CompanySearchView({required this.organizationUID});

  @override
  State<_CompanySearchView> createState() => _CompanySearchViewState();
}

class _CompanySearchViewState extends State<_CompanySearchView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String? _actualOrganizationUID;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
    _initializeOrganizationUID();
  }

  /// Initialize organization UID from parameter or cached user data
  void _initializeOrganizationUID() {
    if (widget.organizationUID != null) {
      _actualOrganizationUID = widget.organizationUID;
      developer.log(
        '🏢 استخدام organizationUID من المعامل: $_actualOrganizationUID',
      );
    } else {
      final authLocalDataSource = di.sl<AuthLocalDataSource>();
      final cachedDelegate = authLocalDataSource.getCachedDelegateData();
      if (cachedDelegate != null) {
        _actualOrganizationUID = cachedDelegate.organizationUID;
        developer.log(
          '🏢 استخدام organizationUID من البيانات المحفوظة: $_actualOrganizationUID',
        );
      } else {
        developer.log('❌ لم يتم العثور على organizationUID');
      }
    }
  }

  @override
  void dispose() {
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  /// Handle scroll events for infinite scroll
  void _onScroll() {
    if (_isBottom) {
      context.read<CompanySearchBloc>().add(const LoadMoreCompaniesRequested());
    }
  }

  /// Check if user has scrolled to bottom (90% of max scroll)
  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  /// Handle search submission
  void _onSearchSubmitted(String query) {
    if (query.trim().isEmpty || _actualOrganizationUID == null) {
      developer.log('⚠️ لا يمكن البحث:');
      developer.log('   - Query: "${query.trim()}"');
      developer.log('   - Organization UID: $_actualOrganizationUID');
      return;
    }

    developer.log('═══════════════════════════════════════════════════');
    developer.log('🔍 [UI] بدء البحث');
    developer.log('   - Query: "${query.trim()}"');
    developer.log('   - Organization UID: $_actualOrganizationUID');
    developer.log('═══════════════════════════════════════════════════');

    context.read<CompanySearchBloc>().add(
      SearchCompaniesRequested(
        organizationUID: _actualOrganizationUID!,
        companyCode: query.trim(),
      ),
    );
  }

  /// Handle clear search
  void _onClearSearch() {
    _searchController.clear();
    context.read<CompanySearchBloc>().add(const ClearSearchRequested());
  }

  /// Handle refresh
  Future<void> _onRefresh() async {
    context.read<CompanySearchBloc>().add(const RefreshSearchRequested());
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    // Show error if no organization UID
    if (_actualOrganizationUID == null) {
      return Scaffold(
        backgroundColor: colorScheme.surface,
        appBar: AppBar(
          title: Text(l10n.searchCompanies),
          backgroundColor: colorScheme.surface,
        ),
        body: Center(
          child: Column(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(Icons.error_outline_rounded, size: 64, color: colorScheme.error),
              const SizedBox(height: 16),
              Text(
                'لم يتم العثور على معرف المنظمة',
                style: theme.textTheme.titleMedium?.copyWith(
                  color: colorScheme.error,
                ),
              ),
              const SizedBox(height: 8),
              Text(
                'يرجى تسجيل الدخول مرة أخرى',
                style: theme.textTheme.bodyMedium?.copyWith(
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      );
    }

    return Scaffold(
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        titleSpacing: 0,
        title: Text(
          l10n.searchCompanies,
          style: TextStyle(
            color: colorScheme.onSurface,
            fontSize: 15,
            fontWeight: FontWeight.bold,
            letterSpacing: -0.2,
          ),
        ),
        backgroundColor: colorScheme.surface,
        surfaceTintColor: Colors.transparent,
        elevation: 0,
        scrolledUnderElevation: 1,
        iconTheme: IconThemeData(color: colorScheme.onSurface),
      ),
      body: Column(
        children: [
          // Search Bar
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: CompanySearchBar(
              controller: _searchController,
              onSubmitted: _onSearchSubmitted,
              onClear: _onClearSearch,
            ),
          ),

          // Search Results
          Expanded(
            child: BlocBuilder<CompanySearchBloc, CompanySearchState>(
              builder: (context, state) {
                return switch (state) {
                  CompanySearchInitial() => _buildInitialState(context),
                  CompanySearchLoading() => _buildLoadingState(context),
                  CompanySearchSuccess() => _buildSuccessState(context, state),
                  CompanySearchLoadingMore() => _buildLoadingMoreState(
                    context,
                    state,
                  ),
                  CompanySearchEmpty() => _buildEmptyState(context, state),
                  CompanySearchError() => _buildErrorState(context, state),
                  _ => _buildInitialState(context), // Default case
                };
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Build initial state (no search performed)
  Widget _buildInitialState(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(Icons.search_rounded, size: 64, color: colorScheme.outline),
          const SizedBox(height: 16),
          Text(
            l10n.searchCompaniesHint,
            style: theme.textTheme.bodyLarge?.copyWith(
              color: colorScheme.onSurfaceVariant,
            ),
            textAlign: TextAlign.center,
          ),
        ],
      ),
    );
  }

  /// Build loading state
  Widget _buildLoadingState(BuildContext context) {
    return const Center(child: CircularProgressIndicator());
  }

  /// Build success state with results
  Widget _buildSuccessState(BuildContext context, CompanySearchSuccess state) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CompanySearchList(
        companies: state.companies,
        scrollController: _scrollController,
        hasReachedMax: state.hasReachedMax,
      ),
    );
  }

  /// Build loading more state (pagination)
  Widget _buildLoadingMoreState(
    BuildContext context,
    CompanySearchLoadingMore state,
  ) {
    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: CompanySearchList(
        companies: state.companies,
        scrollController: _scrollController,
        hasReachedMax: state.hasReachedMax,
        isLoadingMore: true,
      ),
    );
  }

  /// Build empty state (no results)
  Widget _buildEmptyState(BuildContext context, CompanySearchEmpty state) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.business_rounded,
                  size: 64,
                  color: colorScheme.outline,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.noCompaniesFound,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                const SizedBox(height: 8),
                Text(
                  '${l10n.searchQuery}: "${state.searchQuery}"',
                  style: theme.textTheme.bodyMedium?.copyWith(
                    color: colorScheme.outline,
                  ),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Build error state
  Widget _buildErrorState(BuildContext context, CompanySearchError state) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return RefreshIndicator(
      onRefresh: _onRefresh,
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        child: SizedBox(
          height: MediaQuery.of(context).size.height * 0.6,
          child: Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(
                  Icons.error_outline_rounded,
                  size: 64,
                  color: colorScheme.error,
                ),
                const SizedBox(height: 16),
                Text(
                  l10n.errorOccurred,
                  style: theme.textTheme.titleMedium?.copyWith(
                    color: colorScheme.error,
                  ),
                ),
                const SizedBox(height: 8),
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 32),
                  child: Text(
                    state.message,
                    style: theme.textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    textAlign: TextAlign.center,
                  ),
                ),
                const SizedBox(height: 24),
                FilledButton.icon(
                  onPressed: _onRefresh,
                  icon: const Icon(Icons.refresh_rounded),
                  label: Text(l10n.tryAgain),
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }
}
