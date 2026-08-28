import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_delegate_web_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';

class AdminDelegatesScreen extends StatelessWidget {
  final Delegate adminDelegate;

  const AdminDelegatesScreen({super.key, required this.adminDelegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AdminDelegatesBloc>()
        ..add(
          LoadCompanyDelegates(
            organizationUID: adminDelegate.organizationUID,
            companyUID: adminDelegate.companyUID,
          ),
        ),
      child: AdminDelegatesView(adminDelegate: adminDelegate),
    );
  }
}

class AdminDelegatesView extends StatefulWidget {
  final Delegate adminDelegate;
  const AdminDelegatesView({super.key, required this.adminDelegate});

  @override
  State<AdminDelegatesView> createState() => _AdminDelegatesViewState();
}

class _AdminDelegatesViewState extends State<AdminDelegatesView> {
  final TextEditingController _searchController = TextEditingController();
  DelegateStatus? _selectedStatus;

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Delegate> _filterDelegates(List<Delegate> delegates) {
    final query = _searchController.text.toLowerCase().trim();
    return delegates.where((delegate) {
      final matchesName = delegate.fullName.toLowerCase().contains(query);
      final matchesStatus =
          _selectedStatus == null || delegate.status == _selectedStatus;
      return matchesName && matchesStatus;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BlocBuilder<AdminDelegatesBloc, AdminDelegatesState>(
      builder: (context, state) {
        if (state is AdminDelegatesLoading) {
          return const Center(child: CircularProgressIndicator());
        } else if (state is AdminDelegatesError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                const Icon(
                  Icons.error_outline_rounded,
                  color: Colors.red,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(state.message, style: const TextStyle(color: Colors.red)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () {
                    context.read<AdminDelegatesBloc>().add(
                      LoadCompanyDelegates(
                        organizationUID: widget.adminDelegate.organizationUID,
                        companyUID: widget.adminDelegate.companyUID,
                      ),
                    );
                  },
                  child: Text(l10n.retry),
                ),
              ],
            ),
          );
        } else if (state is AdminDelegatesLoaded) {
          final allDelegates = state.delegates;
          final filteredDelegates = _filterDelegates(allDelegates);

          return Scaffold(
            body: Column(
              children: [
                // ── Search & Filter Bar ──
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  decoration: BoxDecoration(
                    color: theme.colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    children: [
                      SearchBar(
                        controller: _searchController,
                        hintText: l10n.searchDelegates,
                        elevation: WidgetStateProperty.all(0),
                        backgroundColor: WidgetStateProperty.all(
                          theme.colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.4,
                          ),
                        ),
                        leading: const Icon(Icons.search_rounded),
                        trailing: _searchController.text.isNotEmpty
                            ? [
                                IconButton(
                                  icon: const Icon(Icons.clear_rounded),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() {});
                                  },
                                ),
                              ]
                            : null,
                        padding: WidgetStateProperty.all(
                          const EdgeInsets.symmetric(horizontal: 12),
                        ),
                        onChanged: (_) => setState(() {}),
                      ),
                      const SizedBox(height: 12),
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: Text(l10n.all),
                              selected: _selectedStatus == null,
                              onSelected: (_) =>
                                  setState(() => _selectedStatus = null),
                            ),
                            const SizedBox(width: 8),
                            ...DelegateStatus.values.map((status) {
                              return Padding(
                                padding: const EdgeInsets.only(right: 8),
                                child: FilterChip(
                                  label: Text(_getStatusLabel(context, status)),
                                  selected: _selectedStatus == status,
                                  onSelected: (_) =>
                                      setState(() => _selectedStatus = status),
                                  selectedColor: _getStatusColor(
                                    context,
                                    status,
                                  ).withValues(alpha: 0.2),
                                  checkmarkColor: _getStatusColor(
                                    context,
                                    status,
                                  ),
                                ),
                              );
                            }),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Delegate List ──
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      context.read<AdminDelegatesBloc>().add(
                        LoadCompanyDelegates(
                          organizationUID: widget.adminDelegate.organizationUID,
                          companyUID: widget.adminDelegate.companyUID,
                        ),
                      );
                    },
                    child: filteredDelegates.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: _NoResultsView(
                                isSearching:
                                    _searchController.text.isNotEmpty ||
                                    _selectedStatus != null,
                                allEmpty: allDelegates.isEmpty,
                              ),
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              left: 16,
                              right: 16,
                              top: 12,
                              bottom: 88,
                            ),
                            itemCount: filteredDelegates.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 12),
                            itemBuilder: (context, index) {
                              final delegate = filteredDelegates[index];
                              return _DelegateCard(delegate: delegate);
                            },
                          ),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () {
                Navigator.of(context).push(
                  MaterialPageRoute(
                    builder: (_) => const AddDelegateWebScreen(),
                  ),
                );
              },
              icon: const Icon(Icons.person_add_rounded),
              label: Text(l10n.addDelegate),
            ),
          );
        }
        return const SizedBox();
      },
    );
  }

  String _getStatusLabel(BuildContext context, DelegateStatus status) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case DelegateStatus.active:
        return l10n.active;
      case DelegateStatus.approved:
        return l10n.approvedStatus;
      case DelegateStatus.suspended:
        return l10n.suspended;
      case DelegateStatus.rejected:
        return l10n.rejectedStatus;
      case DelegateStatus.pending:
        return l10n.pendingStatus;
    }
  }

  Color _getStatusColor(BuildContext context, DelegateStatus status) {
    switch (status) {
      case DelegateStatus.active:
      case DelegateStatus.approved:
        return Colors.green;
      case DelegateStatus.suspended:
      case DelegateStatus.rejected:
        return Theme.of(context).colorScheme.error;
      case DelegateStatus.pending:
        return Colors.orange;
    }
  }
}

class _NoResultsView extends StatelessWidget {
  final bool isSearching;
  final bool allEmpty;

  const _NoResultsView({required this.isSearching, required this.allEmpty});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Icon(
            allEmpty ? Icons.people_outline_rounded : Icons.search_off_rounded,
            size: 64,
            color: theme.colorScheme.outline,
          ),
          const SizedBox(height: 16),
          Text(
            allEmpty ? l10n.noDelegatesFound : l10n.noDelegateSearchResults,
            style: TextStyle(
              fontSize: 18,
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      ),
    );
  }
}

class _DelegateCard extends StatelessWidget {
  final Delegate delegate;

  const _DelegateCard({required this.delegate});

  Color _getStatusColor(BuildContext context, DelegateStatus status) {
    switch (status) {
      case DelegateStatus.active:
      case DelegateStatus.approved:
        return Colors.green;
      case DelegateStatus.suspended:
      case DelegateStatus.rejected:
        return Theme.of(context).colorScheme.error;
      case DelegateStatus.pending:
        return Colors.orange;
    }
  }

  String _getStatusText(BuildContext context, DelegateStatus status) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case DelegateStatus.active:
        return l10n.active;
      case DelegateStatus.approved:
        return l10n.approvedStatus;
      case DelegateStatus.suspended:
        return l10n.suspended;
      case DelegateStatus.rejected:
        return l10n.rejectedStatus;
      case DelegateStatus.pending:
        return l10n.pendingStatus;
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final statusColor = _getStatusColor(context, delegate.status);

    return Card(
      elevation: 0,
      color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: Padding(
        padding: const EdgeInsets.all(16.0),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                CircleAvatar(
                  radius: 24,
                  backgroundColor: theme.colorScheme.primaryContainer,
                  child: Text(
                    delegate.firstName.isNotEmpty
                        ? delegate.firstName[0].toUpperCase()
                        : '?',
                    style: TextStyle(
                      color: theme.colorScheme.onPrimaryContainer,
                      fontWeight: FontWeight.bold,
                      fontSize: 20,
                    ),
                  ),
                ),
                const SizedBox(width: 16),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delegate.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Text(
                        delegate.phoneNumber,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                      ),
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.secondaryContainer,
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Text(
                          delegate.position.name.toUpperCase(),
                          style: theme.textTheme.labelSmall?.copyWith(
                            color: theme.colorScheme.onSecondaryContainer,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      ),
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 5,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Text(
                    _getStatusText(context, delegate.status),
                    style: theme.textTheme.labelSmall?.copyWith(
                      color: statusColor,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Row(
              children: [
                Expanded(
                  child: OutlinedButton.icon(
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => BlocProvider(
                            create: (_) => sl<ProfileBloc>(),
                            child: ProfileScreen(
                              delegate: delegate,
                              showBackButton: true,
                            ),
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_search_rounded, size: 18),
                    label: Text(
                      l10n.viewProfileData,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: FilledButton.icon(
                    style: FilledButton.styleFrom(
                      backgroundColor: theme.colorScheme.primary,
                      foregroundColor: theme.colorScheme.onPrimary,
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () {
                      Navigator.of(context).push(
                        MaterialPageRoute(
                          builder: (_) => AttendanceScreen(
                            delegate: delegate,
                            viewOnly: true,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.history_rounded, size: 18),
                    label: Text(
                      l10n.viewAttendance,
                      style: const TextStyle(fontSize: 13),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }


}
