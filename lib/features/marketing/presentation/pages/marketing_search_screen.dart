import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MarketingSearchScreen extends StatelessWidget {
  final String organizationUID;

  const MarketingSearchScreen({super.key, required this.organizationUID});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<MarketingBloc>(),
      child: _MarketingSearchView(organizationUID: organizationUID),
    );
  }
}

class _MarketingSearchView extends StatefulWidget {
  final String organizationUID;

  const _MarketingSearchView({required this.organizationUID});

  @override
  State<_MarketingSearchView> createState() => _MarketingSearchViewState();
}

class _MarketingSearchViewState extends State<_MarketingSearchView> {
  final TextEditingController _searchController = TextEditingController();

  @override
  void initState() {
    super.initState();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  void _onSearchChanged(String query) {
    context.read<MarketingBloc>().add(
      SearchDelegates(organizationUID: widget.organizationUID, query: query),
    );
  }

  @override
  Widget build(BuildContext context) {
    return Scaffold(
      body: Column(
        children: [
          Padding(
            padding: const EdgeInsets.all(16.0),
            child: SizedBox(
              height: 44,
              child: TextField(
                controller: _searchController,
                onChanged: _onSearchChanged,
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.normal,
                ),
                decoration: InputDecoration(
                  hintText: 'ابحث عن مندوب في المنظمة بالاسم أو الهاتف...',
                  hintStyle: TextStyle(
                    fontSize: 13,
                    fontWeight: FontWeight.normal,
                    color: Theme.of(
                      context,
                    ).colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                  ),
                  prefixIcon: const Icon(Icons.search_rounded, size: 20),
                  filled: true,
                  fillColor: Theme.of(context).colorScheme.surfaceContainerLow,
                  border: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  enabledBorder: OutlineInputBorder(
                    borderRadius: BorderRadius.circular(14),
                    borderSide: BorderSide(
                      color: Theme.of(context).colorScheme.outlineVariant,
                    ),
                  ),
                  contentPadding: const EdgeInsets.symmetric(horizontal: 16),
                ),
              ),
            ),
          ),
          Expanded(
            child: BlocBuilder<MarketingBloc, MarketingState>(
              builder: (context, state) {
                if (state is DelegatesLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is DelegatesError) {
                  return Center(
                    child: Text(
                      state.message,
                      style: TextStyle(
                        color: Theme.of(context).colorScheme.error,
                      ),
                    ),
                  );
                } else if (state is DelegatesLoaded) {
                  if (state.delegates.isEmpty) {
                    return const Center(
                      child: Text('لا يوجد مناديب مطابقين للبحث.'),
                    );
                  }
                  final colorScheme = Theme.of(context).colorScheme;
                  return ListView.builder(
                    padding: const EdgeInsets.only(
                      bottom: 16,
                      left: 16,
                      right: 16,
                    ),
                    itemCount: state.delegates.length,
                    itemBuilder: (context, index) {
                      final delegate = state.delegates[index];
                      final trimmedName = delegate.fullName.trim();
                      final initial = trimmedName.isNotEmpty
                          ? trimmedName.substring(0, 1)
                          : '؟';
                      return Card(
                        elevation: 0,
                        color: colorScheme.surfaceContainerLow,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                          side: BorderSide(
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.6,
                            ),
                          ),
                        ),
                        margin: const EdgeInsets.only(bottom: 12),
                        child: Padding(
                          padding: const EdgeInsets.all(16.0),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              Row(
                                children: [
                                  CircleAvatar(
                                    backgroundColor:
                                        colorScheme.primaryContainer,
                                    child: Text(
                                      initial,
                                      style: TextStyle(
                                        color: colorScheme.onPrimaryContainer,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                  const SizedBox(width: 12),
                                  Expanded(
                                    child: Column(
                                      crossAxisAlignment:
                                          CrossAxisAlignment.start,
                                      children: [
                                        Text(
                                          delegate.fullName,
                                          style: const TextStyle(
                                            fontWeight: FontWeight.bold,
                                            fontSize: 16,
                                          ),
                                        ),
                                        Text(
                                          '${delegate.companyName} • ${delegate.phoneNumber}',
                                          style: TextStyle(
                                            color: Theme.of(
                                              context,
                                            ).colorScheme.onSurfaceVariant,
                                            fontSize: 13,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                  Container(
                                    padding: const EdgeInsets.symmetric(
                                      horizontal: 8,
                                      vertical: 4,
                                    ),
                                    decoration: BoxDecoration(
                                      color:
                                          delegate.status.name == 'active' ||
                                              delegate.status.name == 'approved'
                                          ? Colors.green.withValues(alpha: 0.1)
                                          : Colors.orange.withValues(
                                              alpha: 0.1,
                                            ),
                                      borderRadius: BorderRadius.circular(12),
                                    ),
                                    child: Text(
                                      delegate.status.name,
                                      style: TextStyle(
                                        color:
                                            delegate.status.name == 'active' ||
                                                delegate.status.name ==
                                                    'approved'
                                            ? Colors.green
                                            : Colors.orange,
                                        fontSize: 12,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                              const Divider(height: 24),
                              Row(
                                mainAxisAlignment:
                                    MainAxisAlignment.spaceEvenly,
                                children: [
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => BlocProvider(
                                            create: (_) => di.sl<ProfileBloc>(),
                                            child: ProfileScreen(
                                              delegate: delegate,
                                              showBackButton: true,
                                            ),
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.person_outline),
                                    label: const Text('الملف'),
                                  ),
                                  TextButton.icon(
                                    onPressed: () {
                                      Navigator.push(
                                        context,
                                        MaterialPageRoute(
                                          builder: (_) => AttendanceScreen(
                                            delegate: delegate,
                                            viewOnly: true,
                                          ),
                                        ),
                                      );
                                    },
                                    icon: const Icon(Icons.history),
                                    label: const Text('الحضور'),
                                  ),
                                ],
                              ),
                            ],
                          ),
                        ),
                      );
                    },
                  );
                }
                return const Center(child: Text('اكتب للبحث...'));
              },
            ),
          ),
        ],
      ),
    );
  }
}
