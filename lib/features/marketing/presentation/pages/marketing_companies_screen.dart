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

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.removeListener(_onScroll);
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    // Check if user scrolled to bottom (with 200px threshold)
    if (_scrollController.position.pixels >=
        _scrollController.position.maxScrollExtent - 200) {
      // Load more companies
      context.read<MarketingBloc>().add(
        LoadCompaniesPaginated(organizationUID: widget.organizationUID),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: BlocBuilder<MarketingBloc, MarketingState>(
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
                    style: TextStyle(
                      color: Theme.of(context).colorScheme.error,
                    ),
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
                    onPressed: () {
                      context.read<MarketingBloc>().add(
                        LoadCompaniesPaginated(
                          organizationUID: widget.organizationUID,
                          isInitialLoad: true,
                        ),
                      );
                    },
                    child: const Text('إعادة المحاولة'),
                  ),
                ],
              ),
            );
          } else if (state is CompaniesLoaded) {
            if (state.companies.isEmpty) {
              return const Center(
                child: Text('لا توجد شركات مسجلة في المنظمة.'),
              );
            }
            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.all(16),
              itemCount: state.companies.length + (state.hasMore ? 1 : 0),
              itemBuilder: (context, index) {
                // Show loading indicator at the end if there are more companies
                if (index == state.companies.length) {
                  return Padding(
                    padding: const EdgeInsets.symmetric(vertical: 16),
                    child: Center(
                      child: state.isLoadingMore
                          ? const CircularProgressIndicator()
                          : const SizedBox.shrink(),
                    ),
                  );
                }

                final company = state.companies[index];
                return Card(
                  margin: const EdgeInsets.only(bottom: 12),
                  child: ListTile(
                    leading: CircleAvatar(
                      backgroundColor: Theme.of(
                        context,
                      ).colorScheme.primaryContainer,
                      child: Icon(
                        Icons.business,
                        color: Theme.of(context).colorScheme.onPrimaryContainer,
                      ),
                    ),
                    title: Text(
                      company['name'] ?? 'شركة بدون اسم',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    subtitle: Text(
                      company['marketingUserName'] != null
                          ? 'موظف التسويق: ${company['marketingUserName']}'
                          : company['address'] ?? 'لا يوجد عنوان',
                    ),
                    trailing: const Icon(Icons.chevron_right),
                    onTap: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => MarketingDelegatesScreen(
                            organizationUID: widget.organizationUID,
                            companyUID: company['uid'],
                            companyName: company['name'] ?? 'الشركة',
                          ),
                        ),
                      );
                    },
                  ),
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }
}
