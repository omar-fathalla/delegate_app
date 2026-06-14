import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_delegates_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingCompaniesScreen extends StatelessWidget {
  final String organizationUID;

  const MarketingCompaniesScreen({super.key, required this.organizationUID});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<MarketingBloc>()
        ..add(
          LoadCompaniesPaginated(
            organizationUID: organizationUID,
            isInitialLoad: true,
          ),
        ),
      child: _MarketingCompaniesView(organizationUID: organizationUID),
    );
  }
}

class _MarketingCompaniesView extends StatefulWidget {
  final String organizationUID;

  const _MarketingCompaniesView({required this.organizationUID});

  @override
  State<_MarketingCompaniesView> createState() =>
      _MarketingCompaniesViewState();
}

class _MarketingCompaniesViewState extends State<_MarketingCompaniesView> {
  final ScrollController _scrollController = ScrollController();
  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    _searchController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      context.read<MarketingBloc>().add(
        LoadCompaniesPaginated(organizationUID: widget.organizationUID),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      body: Column(
        children: [
          // Search bar
          Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
            child: TextField(
              controller: _searchController,
              onChanged: (v) =>
                  setState(() => _searchQuery = v.trim().toLowerCase()),
              decoration: InputDecoration(
                hintText: 'ابحث باسم الشركة أو الكود...',
                prefixIcon: const Icon(Icons.search_rounded),
                suffixIcon: _searchQuery.isNotEmpty
                    ? IconButton(
                        tooltip: MaterialLocalizations.of(
                          context,
                        ).closeButtonTooltip,
                        icon: const Icon(Icons.clear_rounded),
                        onPressed: () {
                          _searchController.clear();
                          setState(() => _searchQuery = '');
                        },
                      )
                    : null,
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest,
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide.none,
                ),
                contentPadding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 12,
                ),
              ),
            ),
          ),

          // Companies list
          Expanded(
            child: BlocBuilder<MarketingBloc, MarketingState>(
              builder: (context, state) {
                if (state is CompaniesLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is CompaniesError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Text(
                          state.message,
                          style: TextStyle(color: colorScheme.error),
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        ElevatedButton(
                          onPressed: () => context.read<MarketingBloc>().add(
                            LoadCompaniesPaginated(
                              organizationUID: widget.organizationUID,
                              isInitialLoad: true,
                            ),
                          ),
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                } else if (state is CompaniesLoaded) {
                  // Filter by search query (name or code)
                  final filtered = _searchQuery.isEmpty
                      ? state.companies
                      : state.companies.where((c) {
                          final name = (c['name'] as String? ?? '')
                              .toLowerCase();
                          final code = (c['code'] as String? ?? '')
                              .toLowerCase();
                          final uid = (c['uid'] as String? ?? '').toLowerCase();
                          return name.contains(_searchQuery) ||
                              code.contains(_searchQuery) ||
                              uid.contains(_searchQuery);
                        }).toList();

                  if (filtered.isEmpty) {
                    return const Center(child: Text('لا توجد شركات مطابقة.'));
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.fromLTRB(16, 4, 16, 16),
                    itemCount:
                        filtered.length +
                        (state.hasMore && _searchQuery.isEmpty ? 1 : 0),
                    itemBuilder: (context, index) {
                      if (index == filtered.length) {
                        return Padding(
                          padding: const EdgeInsets.symmetric(vertical: 16),
                          child: Center(
                            child: state.isLoadingMore
                                ? const CircularProgressIndicator()
                                : const SizedBox.shrink(),
                          ),
                        );
                      }

                      final company = filtered[index];
                      final marketingUser =
                          company['marketingUserName'] as String?;

                      return Card(
                        margin: const EdgeInsets.only(bottom: 10),
                        child: ListTile(
                          leading: CircleAvatar(
                            backgroundColor: colorScheme.primaryContainer,
                            child: Icon(
                              Icons.business_rounded,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          title: Text(
                            company['name'] ?? 'شركة بدون اسم',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          subtitle: marketingUser != null
                              ? Text(
                                  'موظف التسويق: $marketingUser',
                                  style: TextStyle(
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                )
                              : null,
                          trailing: const Icon(Icons.chevron_right_rounded),
                          onTap: () => Navigator.push(
                            context,
                            MaterialPageRoute(
                              builder: (_) => MarketingDelegatesScreen(
                                organizationUID: widget.organizationUID,
                                companyUID: company['uid'],
                                companyName: company['name'] ?? 'الشركة',
                              ),
                            ),
                          ),
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }
}
