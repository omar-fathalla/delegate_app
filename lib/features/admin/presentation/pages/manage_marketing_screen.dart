import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_marketing_bloc.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';

class ManageMarketingScreen extends StatelessWidget {
  const ManageMarketingScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ManageMarketingBloc>()
        ..add(LoadMarketingEmployeesRequested()),
      child: const _ManageMarketingView(),
    );
  }
}

class _ManageMarketingView extends StatefulWidget {
  const _ManageMarketingView();

  @override
  State<_ManageMarketingView> createState() => _ManageMarketingViewState();
}

class _ManageMarketingViewState extends State<_ManageMarketingView> {
  final TextEditingController _searchController = TextEditingController();
  String? _selectedOrganizationUID;
  String _selectedRoleFilter = 'all';

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AdminUser> _filterEmployees(List<AdminUser> employees) {
    final query = _searchController.text.trim().toLowerCase();
    return employees.where((e) {
      final matchesPhone = e.phoneNumber.toLowerCase().contains(query);
      final matchesName = e.displayName.toLowerCase().contains(query);
      final matchesEmail = e.email.toLowerCase().contains(query);
      final matchesRoleQuery = e.role.toLowerCase().contains(query);

      final matchesQuery = query.isEmpty ||
          matchesPhone ||
          matchesName ||
          matchesEmail ||
          matchesRoleQuery;

      final matchesOrg = _selectedOrganizationUID == null ||
          e.organizationUID == _selectedOrganizationUID;

      final matchesRole = _selectedRoleFilter == 'all' ||
          e.role == _selectedRoleFilter;

      return matchesQuery && matchesOrg && matchesRole;
    }).toList();
  }

  /// Extract unique organizations from employees for the filter
  List<_OrgOption> _extractOrganizations(List<AdminUser> employees) {
    final orgMap = <String, String>{};
    for (final e in employees) {
      if (e.organizationUID != null && e.organizationUID!.isNotEmpty) {
        orgMap.putIfAbsent(e.organizationUID!, () => e.organizationUID!);
      }
    }
    return orgMap.entries
        .map((e) => _OrgOption(uid: e.key, name: e.value))
        .toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    return Scaffold(
      appBar: AdminHeader(
        subtitle: isArabic ? 'إدارة المستخدمين والتسويق' : l10n.manageMarketing,
        showBackButton: true,
      ),
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: BlocConsumer<ManageMarketingBloc, ManageMarketingState>(
        listener: (context, state) {
          if (state is ManageMarketingError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is ManageMarketingLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ManageMarketingLoaded) {
            final allEmployees = state.employees;
            final filteredEmployees = _filterEmployees(allEmployees);
            final organizations = _extractOrganizations(allEmployees);

            return Column(
              children: [
                // ── Search & Filter Section ──
                _SearchFilterBar(
                  searchController: _searchController,
                  selectedOrganizationUID: _selectedOrganizationUID,
                  selectedRoleFilter: _selectedRoleFilter,
                  organizations: organizations,
                  onSearchChanged: (_) => setState(() {}),
                  onSearchCleared: () {
                    _searchController.clear();
                    setState(() {});
                  },
                  onOrganizationChanged: (uid) {
                    setState(() => _selectedOrganizationUID = uid);
                  },
                  onRoleFilterChanged: (role) {
                    setState(() => _selectedRoleFilter = role);
                  },
                ),

                // ── Results Count ──
                Padding(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 16,
                    vertical: 8,
                  ),
                  child: Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 12,
                          vertical: 6,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.primaryContainer,
                          borderRadius: BorderRadius.circular(20),
                        ),
                        child: Text(
                          '${filteredEmployees.length}',
                          style: TextStyle(
                            color: colorScheme.onPrimaryContainer,
                            fontWeight: FontWeight.bold,
                            fontSize: 13,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        isArabic ? 'مستخدم' : 'Users',
                        style: TextStyle(
                          color: colorScheme.onSurfaceVariant,
                          fontSize: 14,
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Employee List ──
                Expanded(
                  child: filteredEmployees.isEmpty
                      ? _EmptyView(
                          isFiltering: _searchController.text.isNotEmpty ||
                              _selectedOrganizationUID != null ||
                              _selectedRoleFilter != 'all',
                          allEmpty: allEmployees.isEmpty,
                        )
                      : ListView.separated(
                          padding: const EdgeInsets.only(
                            left: 16,
                            right: 16,
                            top: 4,
                            bottom: 88,
                          ),
                          itemCount: filteredEmployees.length,
                          separatorBuilder: (ctx, i) =>
                              const SizedBox(height: 10),
                          itemBuilder: (context, index) {
                            final employee = filteredEmployees[index];
                            return _EmployeeCard(employee: employee);
                          },
                        ),
                ),
              ],
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Search & Filter Bar widget
// ─────────────────────────────────────────────────────────────

class _SearchFilterBar extends StatelessWidget {
  final TextEditingController searchController;
  final String? selectedOrganizationUID;
  final String selectedRoleFilter;
  final List<_OrgOption> organizations;
  final ValueChanged<String> onSearchChanged;
  final VoidCallback onSearchCleared;
  final ValueChanged<String?> onOrganizationChanged;
  final ValueChanged<String> onRoleFilterChanged;

  const _SearchFilterBar({
    required this.searchController,
    required this.selectedOrganizationUID,
    required this.selectedRoleFilter,
    required this.organizations,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onOrganizationChanged,
    required this.onRoleFilterChanged,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isArabic = localeProvider.isArabic;

    final roles = [
      {'key': 'all', 'label': isArabic ? 'الكل' : 'All'},
      {'key': 'marketing', 'label': isArabic ? 'تسويق الفروع' : 'Branch Marketing'},
      {'key': 'marketing_promotion', 'label': isArabic ? 'تسويق العروض' : 'Marketing Promotion'},
      {'key': 'company-admin', 'label': isArabic ? 'مدير قطاع' : 'Company Admin'},
      {'key': 'organization-admin', 'label': isArabic ? 'مدير عام' : 'Organization Admin'},
    ];

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      decoration: BoxDecoration(
        color: theme.colorScheme.surface,
        boxShadow: [
          BoxShadow(
            color: theme.colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 10,
            offset: const Offset(0, 4),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // Search bar
          SearchBar(
            controller: searchController,
            hintText: isArabic
                ? 'البحث باسم المستخدم، الاسم، أو رقم الموبايل...'
                : 'Search by username, name, or phone...',
            elevation: WidgetStateProperty.all(0),
            backgroundColor: WidgetStateProperty.all(
              theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.4),
            ),
            leading: const Icon(Icons.search_rounded),
            trailing: searchController.text.isNotEmpty
                ? [
                    IconButton(
                      icon: const Icon(Icons.clear_rounded),
                      onPressed: onSearchCleared,
                    ),
                  ]
                : null,
            padding: WidgetStateProperty.all(
              const EdgeInsets.symmetric(horizontal: 12),
            ),
            onChanged: onSearchChanged,
          ),
          const SizedBox(height: 10),

          // Role Filter Chips
          SingleChildScrollView(
            scrollDirection: Axis.horizontal,
            child: Row(
              children: roles.map((role) {
                final key = role['key'] as String;
                final label = role['label'] as String;
                final isSelected = selectedRoleFilter == key;
                return Padding(
                  padding: const EdgeInsets.only(right: 8),
                  child: FilterChip(
                    label: Text(label),
                    selected: isSelected,
                    onSelected: (_) => onRoleFilterChanged(key),
                    selectedColor: theme.colorScheme.primaryContainer,
                    checkmarkColor: theme.colorScheme.onPrimaryContainer,
                  ),
                );
              }).toList(),
            ),
          ),

          if (organizations.isNotEmpty) ...[
            const SizedBox(height: 8),
            // Organization Filter Chips
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  FilterChip(
                    avatar: const Icon(Icons.business_rounded, size: 18),
                    label: Text(l10n.allOrganizations),
                    selected: selectedOrganizationUID == null,
                    onSelected: (_) => onOrganizationChanged(null),
                  ),
                  const SizedBox(width: 8),
                  ...organizations.map((org) {
                    return Padding(
                      padding: const EdgeInsets.only(right: 8),
                      child: FilterChip(
                        label: Text(org.name),
                        selected: selectedOrganizationUID == org.uid,
                        onSelected: (_) => onOrganizationChanged(org.uid),
                        selectedColor: theme.colorScheme.secondaryContainer,
                        checkmarkColor: theme.colorScheme.onSecondaryContainer,
                      ),
                    );
                  }),
                ],
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Empty State
// ─────────────────────────────────────────────────────────────

class _EmptyView extends StatelessWidget {
  final bool isFiltering;
  final bool allEmpty;

  const _EmptyView({required this.isFiltering, required this.allEmpty});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            width: 80,
            height: 80,
            decoration: BoxDecoration(
              color: theme.colorScheme.surfaceContainerHighest
                  .withValues(alpha: 0.5),
              shape: BoxShape.circle,
            ),
            child: Icon(
              allEmpty
                  ? Icons.campaign_rounded
                  : Icons.search_off_rounded,
              size: 40,
              color: theme.colorScheme.outline,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            allEmpty
                ? l10n.noMarketingEmployeesFound
                : l10n.noDelegateSearchResults,
            style: TextStyle(
              fontSize: 16,
              color: theme.colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
          ),
          if (!allEmpty) ...[
            const SizedBox(height: 8),
            Text(
              l10n.searchByPhone,
              style: TextStyle(
                fontSize: 13,
                color: theme.colorScheme.outline,
              ),
            ),
          ],
        ],
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Employee Card
// ─────────────────────────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  final AdminUser employee;

  const _EmployeeCard({required this.employee});

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isSuspended = !employee.isActive;

    return Card(
      elevation: 0,
      color: isSuspended
          ? colorScheme.errorContainer.withValues(alpha: 0.2)
          : colorScheme.surfaceContainerLow,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: isSuspended
              ? colorScheme.error.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.4),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Avatar
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isSuspended
                      ? colorScheme.errorContainer
                      : colorScheme.primaryContainer,
                  child: Icon(
                    Icons.campaign_rounded,
                    color: isSuspended
                        ? colorScheme.onErrorContainer
                        : colorScheme.onPrimaryContainer,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Wrap(
                        crossAxisAlignment: WrapCrossAlignment.center,
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          Text(
                            employee.displayName,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          _buildRoleBadge(context, employee.role),
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: isSuspended
                                  ? colorScheme.errorContainer
                                  : colorScheme.primaryContainer,
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              isSuspended ? l10n.suspended : l10n.active,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: isSuspended
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.onPrimaryContainer,
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Icons.phone_rounded,
                            size: 14,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          const SizedBox(width: 4),
                          Text(
                            employee.phoneNumber,
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                      if (employee.email.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.email_rounded,
                              size: 14,
                              color: colorScheme.onSurfaceVariant
                                  .withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                employee.email,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant
                                      .withValues(alpha: 0.7),
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                      if (employee.organizationUID != null &&
                          employee.organizationUID!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.corporate_fare_rounded,
                              size: 14,
                              color: colorScheme.primary.withValues(alpha: 0.7),
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                employee.organizationUID!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w500,
                                ),
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 8),
            const Divider(height: 1),
            const SizedBox(height: 4),
            // Inline compact action buttons
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                IconButton(
                  tooltip: l10n.editMarketingEmployee,
                  icon: Icon(Icons.edit_rounded, color: colorScheme.primary, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final bloc = context.read<ManageMarketingBloc>();
                    _showEditDialog(context, bloc);
                  },
                ),
                IconButton(
                  tooltip: isSuspended
                      ? l10n.activateMarketingEmployee
                      : l10n.suspendMarketingEmployee,
                  icon: Icon(
                    isSuspended
                        ? Icons.play_arrow_rounded
                        : Icons.pause_circle_rounded,
                    color: isSuspended
                        ? colorScheme.primary
                        : colorScheme.tertiary,
                    size: 20,
                  ),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final bloc = context.read<ManageMarketingBloc>();
                    bloc.add(
                      SuspendMarketingEmployeeRequested(
                        employeeId: employee.uid,
                        suspend: !isSuspended,
                      ),
                    );
                    ScaffoldMessenger.of(context).showSnackBar(
                      SnackBar(
                        content: Text(
                          isSuspended
                              ? l10n.employeeActivated
                              : l10n.employeeSuspended,
                          style: TextStyle(
                            color: isSuspended
                                ? colorScheme.onPrimaryContainer
                                : colorScheme.onTertiaryContainer,
                          ),
                        ),
                        backgroundColor: isSuspended
                            ? colorScheme.primaryContainer
                            : colorScheme.tertiaryContainer,
                        behavior: SnackBarBehavior.floating,
                      ),
                    );
                  },
                ),
                IconButton(
                  tooltip: l10n.deleteMarketingEmployee,
                  icon: Icon(Icons.delete_rounded, color: colorScheme.error, size: 20),
                  visualDensity: VisualDensity.compact,
                  onPressed: () {
                    final bloc = context.read<ManageMarketingBloc>();
                    _showDeleteConfirmation(context, bloc);
                  },
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildRoleBadge(BuildContext context, String role) {
    final isArabic = localeProvider.isArabic;
    final colorScheme = Theme.of(context).colorScheme;
    String label;
    IconData icon;
    Color bg;
    Color fg;

    switch (role) {
      case 'marketing':
        label = isArabic ? 'تسويق الفروع' : 'Branch Marketing';
        icon = Icons.campaign_rounded;
        bg = colorScheme.secondaryContainer;
        fg = colorScheme.onSecondaryContainer;
        break;
      case 'marketing_promotion':
        label = isArabic ? 'تسويق العروض' : 'Marketing Promotion';
        icon = Icons.photo_library_rounded;
        bg = colorScheme.tertiaryContainer;
        fg = colorScheme.onTertiaryContainer;
        break;
      case 'company-admin':
        label = isArabic ? 'مدير قطاع' : 'Company Admin';
        icon = Icons.business_rounded;
        bg = colorScheme.primaryContainer;
        fg = colorScheme.onPrimaryContainer;
        break;
      case 'organization-admin':
        label = isArabic ? 'مدير عام' : 'Organization Admin';
        icon = Icons.corporate_fare_rounded;
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.primary;
        break;
      default:
        label = role;
        icon = Icons.person_rounded;
        bg = colorScheme.surfaceContainerHighest;
        fg = colorScheme.onSurfaceVariant;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 13, color: fg),
          const SizedBox(width: 4),
          Text(
            label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: fg,
            ),
          ),
        ],
      ),
    );
  }

  void _showEditDialog(BuildContext context, ManageMarketingBloc bloc) {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: employee.displayName);
    final phoneController = TextEditingController(text: employee.phoneNumber);
    final emailController = TextEditingController(text: employee.email);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.edit_rounded,
            color: Theme.of(context).colorScheme.primary,
            size: 32,
          ),
          title: Text(l10n.editMarketingEmployee),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(
                    labelText: l10n.employeeName,
                    prefixIcon: const Icon(Icons.person_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l10n.pleaseEnterAdminName
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: InputDecoration(
                    labelText: l10n.employeePhone,
                    prefixIcon: const Icon(Icons.phone_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l10n.pleaseEnterAdminPhone
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(
                    labelText: l10n.employeeEmail,
                    prefixIcon: const Icon(Icons.email_rounded),
                    border: const OutlineInputBorder(),
                  ),
                  keyboardType: TextInputType.emailAddress,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              onPressed: () {
                if (!formKey.currentState!.validate()) return;
                Navigator.pop(dialogContext);
                bloc.add(
                  UpdateMarketingEmployeeRequested(
                    employee: AdminUser(
                      uid: employee.uid,
                      phoneNumber: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      displayName: nameController.text.trim(),
                      role: employee.role,
                      organizationUID: employee.organizationUID,
                      companyUID: employee.companyUID,
                      createdAt: employee.createdAt,
                      createdBy: employee.createdBy,
                      temporaryPassword: employee.temporaryPassword,
                      isActive: employee.isActive,
                    ),
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.employeeUpdated),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text(l10n.saveChanges),
            ),
          ],
        );
      },
    );
  }

  void _showDeleteConfirmation(
    BuildContext context,
    ManageMarketingBloc bloc,
  ) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(
            Icons.warning_rounded,
            color: colorScheme.error,
            size: 40,
          ),
          title: Text(l10n.deleteMarketingEmployee),
          content: Text(l10n.deleteMarketingEmployeeConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style:
                  FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () {
                Navigator.pop(dialogContext);
                bloc.add(
                  DeleteMarketingEmployeeRequested(
                    employeeId: employee.uid,
                  ),
                );
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(l10n.employeeDeleted),
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              },
              child: Text(l10n.deleteMarketingEmployee),
            ),
          ],
        );
      },
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Organization option helper
// ─────────────────────────────────────────────────────────────

class _OrgOption {
  final String uid;
  final String name;

  _OrgOption({required this.uid, required this.name});
}
