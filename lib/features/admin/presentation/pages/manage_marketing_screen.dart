import 'dart:async';
import 'package:cloud_firestore/cloud_firestore.dart';
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

  Map<String, String> _organizationNamesMap = {};
  List<_OrgOption> _liveOrganizations = [];
  StreamSubscription<QuerySnapshot>? _orgsSubscription;

  @override
  void initState() {
    super.initState();
    _subscribeToOrganizations();
  }

  void _subscribeToOrganizations() {
    _orgsSubscription = FirebaseFirestore.instance
        .collection('organizations')
        .snapshots()
        .listen((snapshot) {
      if (!mounted) return;
      final map = <String, String>{};
      final options = <_OrgOption>[];

      for (final doc in snapshot.docs) {
        final data = doc.data() as Map<String, dynamic>? ?? {};
        final uid = (data['uid'] ?? data['organizationUID'] ?? doc.id).toString().trim();
        final name = (data['name'] ?? data['title'] ?? '').toString().trim();

        if (name.isNotEmpty) {
          map[doc.id] = name;
          if (uid.isNotEmpty) {
            map[uid] = name;
          }
          final actualUid = uid.isNotEmpty ? uid : doc.id;
          options.add(_OrgOption(uid: actualUid, name: name));
        }
      }

      options.sort((a, b) => a.name.compareTo(b.name));

      setState(() {
        _organizationNamesMap = map;
        _liveOrganizations = options;
      });
    }, onError: (_) {});
  }

  @override
  void dispose() {
    _orgsSubscription?.cancel();
    _searchController.dispose();
    super.dispose();
  }

  void _resetFilters() {
    _searchController.clear();
    setState(() {
      _selectedRoleFilter = 'all';
      _selectedOrganizationUID = null;
    });
  }

  List<AdminUser> _filterEmployees(List<AdminUser> employees, BuildContext context) {
    final query = _searchController.text.trim().toLowerCase();
    return employees.where((e) {
      final roleInfo = _getRoleInfo(context, e.role);
      final orgName = (e.organizationName != null && e.organizationName!.isNotEmpty)
          ? e.organizationName!
          : (_organizationNamesMap[e.organizationUID] ?? '');
      final matchesPhone = e.phoneNumber.toLowerCase().contains(query);
      final matchesName = e.displayName.toLowerCase().contains(query);
      final matchesEmail = e.email.toLowerCase().contains(query);
      final matchesRoleQuery = e.role.toLowerCase().contains(query) ||
          roleInfo.label.toLowerCase().contains(query);
      final matchesOrgQuery = (e.organizationUID?.toLowerCase().contains(query) ?? false) ||
          orgName.toLowerCase().contains(query);
      final matchesCompanyQuery = (e.companyUID?.toLowerCase().contains(query) ?? false) ||
          (e.companyName?.toLowerCase().contains(query) ?? false);

      final matchesQuery = query.isEmpty ||
          matchesPhone ||
          matchesName ||
          matchesEmail ||
          matchesRoleQuery ||
          matchesOrgQuery ||
          matchesCompanyQuery;

      final matchesOrg = _selectedOrganizationUID == null ||
          e.organizationUID == _selectedOrganizationUID;

      final matchesRole = _matchesRole(e.role, _selectedRoleFilter);

      return matchesQuery && matchesOrg && matchesRole;
    }).toList();
  }

  /// Combine live organizations from Firestore with any found in employees
  List<_OrgOption> _extractOrganizations(List<AdminUser> employees) {
    final map = Map<String, String>.from(_organizationNamesMap);
    final list = List<_OrgOption>.from(_liveOrganizations);

    for (final e in employees) {
      final uid = e.organizationUID?.trim();
      if (uid != null && uid.isNotEmpty && !map.containsKey(uid)) {
        final name = (e.organizationName != null && e.organizationName!.isNotEmpty)
            ? e.organizationName!.trim()
            : null;
        if (name != null && name.isNotEmpty) {
          map[uid] = name;
          list.add(_OrgOption(uid: uid, name: name));
        }
      }
    }
    list.sort((a, b) => a.name.compareTo(b.name));
    return list;
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
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: isArabic ? 'تحديث البيانات' : 'Refresh Data',
            onPressed: () {
              context
                  .read<ManageMarketingBloc>()
                  .add(LoadMarketingEmployeesRequested());
            },
          ),
        ],
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
            final filteredEmployees = _filterEmployees(allEmployees, context);
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
                  onResetFilters: _resetFilters,
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
                  child: RefreshIndicator(
                    onRefresh: () async {
                      context
                          .read<ManageMarketingBloc>()
                          .add(LoadMarketingEmployeesRequested());
                    },
                    child: filteredEmployees.isEmpty
                        ? LayoutBuilder(
                            builder: (context, constraints) =>
                                SingleChildScrollView(
                              physics: const AlwaysScrollableScrollPhysics(),
                              child: ConstrainedBox(
                                constraints: BoxConstraints(
                                  minHeight: constraints.maxHeight,
                                ),
                                child: _EmptyView(
                                  isFiltering: _searchController.text.isNotEmpty ||
                                      _selectedOrganizationUID != null ||
                                      _selectedRoleFilter != 'all',
                                  allEmpty: allEmployees.isEmpty,
                                  onResetFilters: _resetFilters,
                                  onRefresh: () {
                                    context
                                        .read<ManageMarketingBloc>()
                                        .add(LoadMarketingEmployeesRequested());
                                  },
                                ),
                              ),
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
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
                              return _EmployeeCard(
                                employee: employee,
                                resolvedOrgName: _organizationNamesMap[employee.organizationUID],
                              );
                            },
                          ),
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
// Role & Filter Helpers
// ─────────────────────────────────────────────────────────────

class _RoleDropdownItem {
  final String key;
  final String label;
  final IconData icon;

  const _RoleDropdownItem({
    required this.key,
    required this.label,
    required this.icon,
  });
}

class _RoleInfo {
  final String label;
  final IconData icon;
  final Color bg;
  final Color fg;

  const _RoleInfo({
    required this.label,
    required this.icon,
    required this.bg,
    required this.fg,
  });
}

bool _matchesRole(String userRole, String selectedFilter) {
  if (selectedFilter == 'all') return true;
  final norm = userRole.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');
  switch (selectedFilter) {
    case 'super_admin':
      return norm == 'super_admin' || norm == 'superadmin' || norm.contains('super');
    case 'technical_support':
      return norm == 'technical_support' ||
          norm == 'technicalsupport' ||
          norm == 'tech_support' ||
          norm == 'techsupport' ||
          norm.contains('technical') ||
          norm.contains('support');
    case 'organization_admin':
      return norm == 'organization_admin' ||
          norm == 'organizationadmin' ||
          norm == 'org_admin' ||
          norm.contains('organization');
    case 'company_admin':
      return norm == 'company_admin' ||
          norm == 'companyadmin' ||
          norm == 'admin' ||
          norm.contains('company');
    case 'branches_marketing':
      return norm == 'branches_marketing' ||
          norm == 'branches_marketing_manager' ||
          norm == 'branchesmarketing' ||
          norm == 'branchesmarketingmanager' ||
          norm.contains('branches');
    case 'marketing':
      return norm == 'marketing' ||
          norm == 'branch_marketing' ||
          norm == 'branchmarketing' ||
          (norm.contains('marketing') &&
              !norm.contains('promotion') &&
              !norm.contains('branches'));
    case 'marketing_promotion':
      return norm == 'marketing_promotion' ||
          norm == 'marketingpromotion' ||
          norm.contains('promotion');
    case 'supervisor':
      return norm == 'supervisor' || norm.contains('supervisor');
    case 'delegate':
      return norm == 'delegate' ||
          norm == 'promoter' ||
          norm.contains('delegate') ||
          norm.contains('promoter');
    default:
      return norm == selectedFilter.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');
  }
}

_RoleInfo _getRoleInfo(BuildContext context, String role) {
  final isArabic = localeProvider.isArabic;
  final colorScheme = Theme.of(context).colorScheme;
  final norm = role.toLowerCase().trim().replaceAll('-', '_').replaceAll(' ', '_');

  if (norm.contains('tech') || norm.contains('support')) {
    return _RoleInfo(
      label: isArabic ? 'دعم فني' : 'Technical Support',
      icon: Icons.support_agent_rounded,
      bg: colorScheme.secondaryContainer,
      fg: colorScheme.onSecondaryContainer,
    );
  }
  if (norm.contains('super')) {
    return _RoleInfo(
      label: isArabic ? 'مشرف عام' : 'Super Admin',
      icon: Icons.verified_user_rounded,
      bg: colorScheme.tertiaryContainer,
      fg: colorScheme.onTertiaryContainer,
    );
  }
  if (norm.contains('organization') || norm.contains('org_admin')) {
    return _RoleInfo(
      label: isArabic ? 'مدير عام' : 'Organization Admin',
      icon: Icons.corporate_fare_rounded,
      bg: colorScheme.surfaceContainerHighest,
      fg: colorScheme.primary,
    );
  }
  if (norm.contains('branches')) {
    return _RoleInfo(
      label: AppLocalizations.of(context)!.roleBranchesMarketingMgrShort,
      icon: Icons.storefront_rounded,
      bg: colorScheme.tertiaryContainer,
      fg: colorScheme.onTertiaryContainer,
    );
  }
  if (norm.contains('promotion')) {
    return _RoleInfo(
      label: isArabic ? 'تسويق عروض' : 'Marketing Promotion',
      icon: Icons.photo_library_rounded,
      bg: colorScheme.surfaceContainerHighest,
      fg: colorScheme.tertiary,
    );
  }
  if (norm.contains('company') || norm == 'admin') {
    return _RoleInfo(
      label: isArabic ? 'مدير قطاع' : 'Company Admin',
      icon: Icons.business_rounded,
      bg: colorScheme.primaryContainer,
      fg: colorScheme.onPrimaryContainer,
    );
  }
  if (norm.contains('marketing')) {
    return _RoleInfo(
      label: AppLocalizations.of(context)!.roleBranchMarketing,
      icon: Icons.campaign_rounded,
      bg: colorScheme.secondaryContainer,
      fg: colorScheme.onSecondaryContainer,
    );
  }
  if (norm.contains('supervisor')) {
    return _RoleInfo(
      label: isArabic ? 'مشرف' : 'Supervisor',
      icon: Icons.supervisor_account_rounded,
      bg: colorScheme.primaryContainer.withValues(alpha: 0.8),
      fg: colorScheme.primary,
    );
  }
  if (norm.contains('promoter')) {
    return _RoleInfo(
      label: isArabic ? 'بروموتر' : 'Promoter',
      icon: Icons.badge_rounded,
      bg: colorScheme.secondaryContainer.withValues(alpha: 0.8),
      fg: colorScheme.secondary,
    );
  }
  if (norm.contains('delegate')) {
    return _RoleInfo(
      label: isArabic ? 'مندوب' : 'Delegate',
      icon: Icons.badge_rounded,
      bg: colorScheme.secondaryContainer.withValues(alpha: 0.8),
      fg: colorScheme.secondary,
    );
  }
  return _RoleInfo(
    label: role,
    icon: Icons.person_rounded,
    bg: colorScheme.surfaceContainerHighest,
    fg: colorScheme.onSurfaceVariant,
  );
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
  final VoidCallback onResetFilters;

  const _SearchFilterBar({
    required this.searchController,
    required this.selectedOrganizationUID,
    required this.selectedRoleFilter,
    required this.organizations,
    required this.onSearchChanged,
    required this.onSearchCleared,
    required this.onOrganizationChanged,
    required this.onRoleFilterChanged,
    required this.onResetFilters,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = localeProvider.isArabic;

    final roleOptions = [
      _RoleDropdownItem(
        key: 'all',
        label: isArabic ? 'جميع المستخدمين (الكل)' : 'All Users',
        icon: Icons.people_alt_rounded,
      ),
      _RoleDropdownItem(
        key: 'super_admin',
        label: isArabic ? 'المشرف العام (Super Admin)' : 'Super Admin',
        icon: Icons.verified_user_rounded,
      ),
      _RoleDropdownItem(
        key: 'technical_support',
        label: isArabic ? 'الدعم الفني (Tech Support)' : 'Technical Support',
        icon: Icons.support_agent_rounded,
      ),
      _RoleDropdownItem(
        key: 'organization_admin',
        label: isArabic ? 'مدير عام (Organization Admin)' : 'Organization Admin',
        icon: Icons.corporate_fare_rounded,
      ),
      _RoleDropdownItem(
        key: 'company_admin',
        label: isArabic ? 'مدير قطاع / مشرف شركة' : 'Company Admin',
        icon: Icons.business_rounded,
      ),
      _RoleDropdownItem(
        key: 'branches_marketing',
        label: AppLocalizations.of(context)!.roleBranchesMarketingManager,
        icon: Icons.storefront_rounded,
      ),
      _RoleDropdownItem(
        key: 'marketing',
        label: AppLocalizations.of(context)!.roleBranchMarketing,
        icon: Icons.campaign_rounded,
      ),
      _RoleDropdownItem(
        key: 'marketing_promotion',
        label: isArabic ? 'تسويق العروض' : 'Marketing Promotion',
        icon: Icons.photo_library_rounded,
      ),
      _RoleDropdownItem(
        key: 'supervisor',
        label: isArabic ? 'مشرف' : 'Supervisor',
        icon: Icons.supervisor_account_rounded,
      ),
      _RoleDropdownItem(
        key: 'delegate',
        label: isArabic ? 'مندوب / بروموتر' : 'Delegate / Promoter',
        icon: Icons.badge_rounded,
      ),
    ];

    final hasActiveFilters = searchController.text.isNotEmpty ||
        selectedRoleFilter != 'all' ||
        selectedOrganizationUID != null;

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
          const SizedBox(height: 12),

          // Role Dropdown Menu
          DropdownButtonFormField<String>(
            key: ValueKey('role_filter_$selectedRoleFilter'),
            initialValue: selectedRoleFilter,
            isExpanded: true,
            dropdownColor: colorScheme.surfaceContainerHigh,
            borderRadius: BorderRadius.circular(16),
            menuMaxHeight: 380,
            alignment: AlignmentDirectional.centerStart,
            icon: Icon(
              Icons.arrow_drop_down_rounded,
              color: colorScheme.primary,
            ),
            decoration: InputDecoration(
              labelText: isArabic ? 'نوع المستخدم' : 'User Role',
              labelStyle: TextStyle(
                color: colorScheme.onSurfaceVariant,
                fontSize: 13,
              ),
              prefixIcon: Icon(
                Icons.badge_rounded,
                size: 20,
                color: colorScheme.primary,
              ),
              filled: true,
              fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                ),
              ),
              focusedBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(
                  color: colorScheme.primary,
                  width: 1.5,
                ),
              ),
            ),
            items: roleOptions.map((opt) {
              final isSelected = selectedRoleFilter == opt.key;
              return DropdownMenuItem<String>(
                value: opt.key,
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(
                      opt.icon,
                      size: 18,
                      color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: 10),
                    Flexible(
                      child: Text(
                        opt.label,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }).toList(),
            onChanged: (val) {
              if (val != null) {
                onRoleFilterChanged(val);
              }
            },
          ),

          if (organizations.isNotEmpty) ...[
            const SizedBox(height: 10),
            // Organization Dropdown Menu
            DropdownButtonFormField<String?>(
              key: ValueKey('org_filter_$selectedOrganizationUID'),
              initialValue: selectedOrganizationUID,
              isExpanded: true,
              dropdownColor: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(16),
              menuMaxHeight: 350,
              alignment: AlignmentDirectional.centerStart,
              icon: Icon(
                Icons.arrow_drop_down_rounded,
                color: colorScheme.primary,
              ),
              decoration: InputDecoration(
                labelText: isArabic ? 'المنظمة' : 'Organization',
                labelStyle: TextStyle(
                  color: colorScheme.onSurfaceVariant,
                  fontSize: 13,
                ),
                prefixIcon: Icon(
                  Icons.corporate_fare_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                enabledBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                  ),
                ),
                focusedBorder: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(
                    color: colorScheme.primary,
                    width: 1.5,
                  ),
                ),
              ),
              items: [
                DropdownMenuItem<String?>(
                  value: null,
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.domain_rounded,
                        size: 18,
                        color: selectedOrganizationUID == null
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 10),
                      Text(
                        isArabic ? 'جميع المنظمات' : 'All Organizations',
                        style: TextStyle(
                          fontSize: 13,
                          fontWeight: selectedOrganizationUID == null
                              ? FontWeight.bold
                              : FontWeight.normal,
                          color: selectedOrganizationUID == null
                              ? colorScheme.primary
                              : colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
                ...organizations.map((org) {
                  final isSelected = selectedOrganizationUID == org.uid;
                  return DropdownMenuItem<String?>(
                    value: org.uid,
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(
                          Icons.business_rounded,
                          size: 18,
                          color: isSelected
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(width: 10),
                        Flexible(
                          child: Text(
                            org.name,
                            overflow: TextOverflow.ellipsis,
                            style: TextStyle(
                              fontSize: 13,
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected
                                  ? colorScheme.primary
                                  : colorScheme.onSurface,
                            ),
                          ),
                        ),
                      ],
                    ),
                  );
                }),
              ],
              onChanged: (val) {
                onOrganizationChanged(val);
              },
            ),
          ],

          if (hasActiveFilters) ...[
            const SizedBox(height: 8),
            Row(
              mainAxisAlignment: MainAxisAlignment.end,
              children: [
                TextButton.icon(
                  onPressed: onResetFilters,
                  icon: const Icon(Icons.filter_alt_off_rounded, size: 16),
                  label: Text(
                    isArabic ? 'إعادة ضبط الفلاتر' : 'Reset Filters',
                    style: const TextStyle(fontSize: 12),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: colorScheme.error,
                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  ),
                ),
              ],
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
  final VoidCallback? onResetFilters;
  final VoidCallback? onRefresh;

  const _EmptyView({
    required this.isFiltering,
    required this.allEmpty,
    this.onResetFilters,
    this.onRefresh,
  });

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isArabic = localeProvider.isArabic;

    return Center(
      child: SingleChildScrollView(
        physics: const AlwaysScrollableScrollPhysics(),
        padding: const EdgeInsets.all(24),
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
              textAlign: TextAlign.center,
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
            if (isFiltering && onResetFilters != null) ...[
              const SizedBox(height: 16),
              FilledButton.tonalIcon(
                onPressed: onResetFilters,
                icon: const Icon(Icons.filter_alt_off_rounded, size: 18),
                label: Text(isArabic ? 'إعادة ضبط الفلاتر' : 'Reset Filters'),
              ),
            ],
            if (onRefresh != null) ...[
              const SizedBox(height: 12),
              TextButton.icon(
                onPressed: onRefresh,
                icon: const Icon(Icons.refresh_rounded, size: 18),
                label: Text(isArabic ? 'تحديث البيانات من السيرفر' : 'Refresh from Server'),
              ),
            ],
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────────────────────────────────────────
// Employee Card
// ─────────────────────────────────────────────────────────────

class _EmployeeCard extends StatelessWidget {
  final AdminUser employee;
  final String? resolvedOrgName;

  const _EmployeeCard({
    required this.employee,
    this.resolvedOrgName,
  });

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;
    final isSuspended = !employee.isActive;
    final roleInfo = _getRoleInfo(context, employee.role);
    final orgDisplay = (employee.organizationName != null &&
            employee.organizationName!.isNotEmpty)
        ? employee.organizationName!
        : (resolvedOrgName != null && resolvedOrgName!.isNotEmpty)
            ? resolvedOrgName!
            : '';

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
                // Avatar with role-based styling
                CircleAvatar(
                  radius: 22,
                  backgroundColor: isSuspended
                      ? colorScheme.errorContainer
                      : roleInfo.bg,
                  child: Icon(
                    roleInfo.icon,
                    color: isSuspended
                        ? colorScheme.onErrorContainer
                        : roleInfo.fg,
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
                            employee.displayName.isNotEmpty
                                ? employee.displayName
                                : (employee.email.isNotEmpty
                                    ? employee.email
                                    : employee.phoneNumber),
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
                      if (employee.phoneNumber.isNotEmpty) ...[
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
                      ],
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
                      if (orgDisplay.isNotEmpty) ...[
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
                                orgDisplay,
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
                      if (employee.companyName != null &&
                          employee.companyName!.isNotEmpty) ...[
                        const SizedBox(height: 4),
                        Row(
                          children: [
                            Icon(
                              Icons.business_rounded,
                              size: 14,
                              color: colorScheme.outline,
                            ),
                            const SizedBox(width: 4),
                            Flexible(
                              child: Text(
                                employee.companyName!,
                                style: theme.textTheme.bodySmall?.copyWith(
                                  color: colorScheme.outline,
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
    final roleInfo = _getRoleInfo(context, role);

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
      decoration: BoxDecoration(
        color: roleInfo.bg,
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(roleInfo.icon, size: 13, color: roleInfo.fg),
          const SizedBox(width: 4),
          Text(
            roleInfo.label,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: roleInfo.fg,
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
                      organizationName: employee.organizationName,
                      companyUID: employee.companyUID,
                      companyName: employee.companyName,
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
