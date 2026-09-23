import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/main.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_admins_bloc.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';

class ManageAdminsScreen extends StatelessWidget {
  const ManageAdminsScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<ManageAdminsBloc>()..add(LoadAdminsRequested()),
      child: const _ManageAdminsView(),
    );
  }
}

class _ManageAdminsView extends StatefulWidget {
  const _ManageAdminsView();

  @override
  State<_ManageAdminsView> createState() => _ManageAdminsViewState();
}

class _ManageAdminsViewState extends State<_ManageAdminsView> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'all'; // 'all', 'active', 'suspended'
  String _selectedRoleFilter = 'all'; // 'all', 'technical_support', 'super_admin', 'organization_admin', 'company_admin', 'marketing', 'supervisor'

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  static (String label, IconData icon, Color Function(ColorScheme) bgColor, Color Function(ColorScheme) fgColor) getRoleInfo(String rawRole, bool isArabic) {
    final norm = rawRole.toLowerCase().replaceAll('-', '_');
    if (norm.contains('technical') || norm.contains('support')) {
      return (
        isArabic ? 'الدعم الفني' : 'Technical Support',
        Icons.support_agent_rounded,
        (cs) => cs.tertiaryContainer,
        (cs) => cs.onTertiaryContainer,
      );
    }
    if (norm.contains('accountant') || norm.contains('accounting')) {
      return (
        isArabic ? 'إدارة الحسابات' : 'Accountant',
        Icons.account_balance_wallet_rounded,
        (cs) => cs.primaryContainer,
        (cs) => cs.onPrimaryContainer,
      );
    }
    if (norm.contains('super')) {
      return (
        isArabic ? 'المشرف العام' : 'Super Admin',
        Icons.verified_user_rounded,
        (cs) => cs.primaryContainer,
        (cs) => cs.onPrimaryContainer,
      );
    }
    if (norm.contains('organization')) {
      return (
        isArabic ? 'مدير عام' : 'Organization Admin',
        Icons.corporate_fare_rounded,
        (cs) => cs.secondaryContainer,
        (cs) => cs.onSecondaryContainer,
      );
    }
    if (norm == 'company_admin' || norm == 'admin') {
      return (
        isArabic ? 'مشرف شركة' : 'Company Admin',
        Icons.business_rounded,
        (cs) => cs.surfaceContainerHighest,
        (cs) => cs.onSurfaceVariant,
      );
    }
    if (norm.contains('marketing')) {
      return (
        isArabic ? 'تسويق' : 'Marketing',
        Icons.campaign_rounded,
        (cs) => cs.surfaceContainerHighest,
        (cs) => cs.onSurfaceVariant,
      );
    }
    if (norm == 'supervisor') {
      return (
        isArabic ? 'مشرف' : 'Supervisor',
        Icons.supervisor_account_rounded,
        (cs) => cs.surfaceContainerHighest,
        (cs) => cs.onSurfaceVariant,
      );
    }
    return (
      rawRole,
      Icons.person_rounded,
      (cs) => cs.surfaceContainerHighest,
      (cs) => cs.onSurfaceVariant,
    );
  }

  List<AdminUser> _filterAdmins(List<AdminUser> admins, bool isArabic) {
    final query = _searchController.text.trim().toLowerCase();

    return admins.where((admin) {
      final matchesName = admin.displayName.toLowerCase().contains(query);
      final matchesPhone = admin.phoneNumber.toLowerCase().contains(query);
      final matchesEmail = admin.email.toLowerCase().contains(query);
      final matchesRole = admin.role.toLowerCase().contains(query);
      final roleInfo = getRoleInfo(admin.role, isArabic);
      final matchesRoleLabel = roleInfo.$1.toLowerCase().contains(query);

      final matchesQuery =
          query.isEmpty ||
          matchesName ||
          matchesPhone ||
          matchesEmail ||
          matchesRole ||
          matchesRoleLabel;

      final matchesStatus =
          _selectedStatusFilter == 'all' ||
          (_selectedStatusFilter == 'active' && admin.isActive) ||
          (_selectedStatusFilter == 'suspended' && !admin.isActive);

      final normRole = admin.role.toLowerCase().replaceAll('-', '_');
      final matchesRoleFilter = () {
        if (_selectedRoleFilter == 'all') return true;
        if (_selectedRoleFilter == 'technical_support') {
          return normRole.contains('technical') || normRole.contains('support');
        }
        if (_selectedRoleFilter == 'super_admin') {
          return normRole.contains('super');
        }
        if (_selectedRoleFilter == 'organization_admin') {
          return normRole.contains('organization');
        }
        if (_selectedRoleFilter == 'company_admin') {
          return normRole == 'company_admin' || normRole == 'admin';
        }
        if (_selectedRoleFilter == 'marketing') {
          return normRole.contains('marketing');
        }
        if (_selectedRoleFilter == 'supervisor') {
          return normRole == 'supervisor';
        }
        return true;
      }();

      return matchesQuery && matchesStatus && matchesRoleFilter;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;
    final isArabic = localeProvider.isArabic;

    return Scaffold(
      appBar: AdminHeader(subtitle: l10n.manageAdmins, showBackButton: true),
      backgroundColor: colorScheme.surface,
      body: BlocConsumer<ManageAdminsBloc, ManageAdminsState>(
        listener: (context, state) {
          if (state is ManageAdminsError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.error,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is ManageAdminsLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is ManageAdminsLoaded) {
            final allAdmins = state.admins;
            final filteredAdmins = _filterAdmins(allAdmins, isArabic);
            final isSearchingOrFiltering =
                _searchController.text.isNotEmpty ||
                _selectedStatusFilter != 'all' ||
                _selectedRoleFilter != 'all';

            return Column(
              children: [
                // ── Search & Filter Section ──
                Container(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    boxShadow: [
                      BoxShadow(
                        color: Colors.black.withValues(alpha: 0.03),
                        blurRadius: 10,
                        offset: const Offset(0, 4),
                      ),
                    ],
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // Search Bar
                      SearchBar(
                        controller: _searchController,
                        hintText: isArabic
                            ? 'البحث بالاسم، الدعم الفني، الرقم، أو البريد...'
                            : 'Search by name, technical support, phone, email...',
                        elevation: WidgetStateProperty.all(0),
                        backgroundColor: WidgetStateProperty.all(
                          colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.5,
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

                      // Status & Role Filter Chips
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: Text(l10n.all),
                              selected: _selectedStatusFilter == 'all',
                              onSelected: (_) =>
                                  setState(() => _selectedStatusFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: Text(isArabic ? 'نشط' : 'Active'),
                              selected: _selectedStatusFilter == 'active',
                              onSelected: (_) => setState(
                                  () => _selectedStatusFilter = 'active'),
                              selectedColor: colorScheme.primaryContainer,
                              checkmarkColor: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: Text(l10n.suspended),
                              selected: _selectedStatusFilter == 'suspended',
                              onSelected: (_) => setState(
                                  () => _selectedStatusFilter = 'suspended'),
                              selectedColor: colorScheme.errorContainer,
                              checkmarkColor: colorScheme.error,
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(height: 8),

                      // Role Filter Chips Row
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: Row(
                          children: [
                            FilterChip(
                              label: Text(isArabic ? 'جميع الأدوار' : 'All Roles'),
                              selected: _selectedRoleFilter == 'all',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'all'),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: Icon(
                                Icons.support_agent_rounded,
                                size: 16,
                                color: _selectedRoleFilter == 'technical_support'
                                    ? colorScheme.onTertiaryContainer
                                    : colorScheme.tertiary,
                              ),
                              label: Text(isArabic ? 'الدعم الفني' : 'Technical Support'),
                              selected: _selectedRoleFilter == 'technical_support',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'technical_support'),
                              selectedColor: colorScheme.tertiaryContainer,
                              checkmarkColor: colorScheme.onTertiaryContainer,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: Icon(
                                Icons.verified_user_rounded,
                                size: 16,
                                color: _selectedRoleFilter == 'super_admin'
                                    ? colorScheme.onPrimaryContainer
                                    : colorScheme.primary,
                              ),
                              label: Text(isArabic ? 'المشرف العام' : 'Super Admin'),
                              selected: _selectedRoleFilter == 'super_admin',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'super_admin'),
                              selectedColor: colorScheme.primaryContainer,
                              checkmarkColor: colorScheme.primary,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: Icon(
                                Icons.corporate_fare_rounded,
                                size: 16,
                                color: _selectedRoleFilter == 'organization_admin'
                                    ? colorScheme.onSecondaryContainer
                                    : colorScheme.secondary,
                              ),
                              label: Text(isArabic ? 'مدير عام' : 'Org Admin'),
                              selected: _selectedRoleFilter == 'organization_admin',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'organization_admin'),
                              selectedColor: colorScheme.secondaryContainer,
                              checkmarkColor: colorScheme.secondary,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: const Icon(Icons.business_rounded, size: 16),
                              label: Text(isArabic ? 'مشرف شركة' : 'Company Admin'),
                              selected: _selectedRoleFilter == 'company_admin',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'company_admin'),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: const Icon(Icons.campaign_rounded, size: 16),
                              label: Text(isArabic ? 'تسويق' : 'Marketing'),
                              selected: _selectedRoleFilter == 'marketing',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'marketing'),
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              avatar: const Icon(Icons.supervisor_account_rounded, size: 16),
                              label: Text(isArabic ? 'مشرف' : 'Supervisor'),
                              selected: _selectedRoleFilter == 'supervisor',
                              onSelected: (_) => setState(() => _selectedRoleFilter = 'supervisor'),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Results Summary Header ──
                if (allAdmins.isNotEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(
                      horizontal: 16,
                      vertical: 8,
                    ),
                    child: Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Text(
                          isArabic
                              ? 'عدد النتائج: ${filteredAdmins.length}'
                              : 'Results count: ${filteredAdmins.length}',
                          style: TextStyle(
                            fontSize: 13,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        if (isSearchingOrFiltering)
                          TextButton.icon(
                            style: TextButton.styleFrom(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 8,
                              ),
                              visualDensity: VisualDensity.compact,
                            ),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {
                                _selectedStatusFilter = 'all';
                                _selectedRoleFilter = 'all';
                              });
                            },
                            icon: const Icon(Icons.refresh_rounded, size: 16),
                            label: Text(
                              isArabic ? 'إعادة ضبط' : 'Reset',
                              style: const TextStyle(fontSize: 12),
                            ),
                          ),
                      ],
                    ),
                  ),

                // ── Admins List or Empty View ──
                Expanded(
                  child: filteredAdmins.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                                Icon(
                                  isSearchingOrFiltering
                                      ? Icons.search_off_rounded
                                      : Icons.admin_panel_settings_rounded,
                                  size: 64,
                                  color: colorScheme.onSurfaceVariant.withValues(
                                    alpha: 0.5,
                                  ),
                                ),
                                const SizedBox(height: 16),
                                Text(
                                  isSearchingOrFiltering
                                      ? (isArabic
                                          ? 'لا توجد نتائج تطابق البحث أو الفلتر'
                                          : 'No matching admins found')
                                      : l10n.noAdminsFound,
                                  style: TextStyle(
                                    fontSize: 16,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          )
                        : ListView.builder(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 8,
                            ),
                            itemCount: filteredAdmins.length,
                            itemBuilder: (context, index) {
                              final admin = filteredAdmins[index];
                              return _AdminCard(admin: admin);
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

  class _AdminCard extends StatelessWidget {
    final AdminUser admin;
    const _AdminCard({required this.admin});

    @override
    Widget build(BuildContext context) {
      final colorScheme = Theme.of(context).colorScheme;
      final l10n = AppLocalizations.of(context)!;
      final isArabic = localeProvider.isArabic;
      final isSuspended = !admin.isActive;
      final bloc = context.read<ManageAdminsBloc>();
      final roleInfo = _ManageAdminsViewState.getRoleInfo(admin.role, isArabic);

      return Card(
        margin: const EdgeInsets.only(bottom: 12),
        elevation: 0,
        color: isSuspended
            ? colorScheme.errorContainer.withValues(alpha: 0.25)
            : colorScheme.surfaceContainerLow,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isSuspended
                ? colorScheme.error.withValues(alpha: 0.3)
                : colorScheme.outlineVariant.withValues(alpha: 0.5),
          ),
        ),
        child: Padding(
          padding: const EdgeInsets.all(12),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isSuspended
                    ? colorScheme.error.withValues(alpha: 0.15)
                    : roleInfo.$3(colorScheme),
                child: Icon(
                  isSuspended ? Icons.person_off_rounded : roleInfo.$2,
                  color: isSuspended
                      ? colorScheme.error
                      : roleInfo.$4(colorScheme),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Expanded(
                          child: Text(
                            admin.displayName,
                            style: TextStyle(
                              fontSize: 15,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        if (isSuspended) ...[
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 6,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(8),
                            ),
                            child: Text(
                              l10n.suspended,
                              style: TextStyle(
                                fontSize: 10.5,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                          const SizedBox(width: 6),
                        ],
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 6,
                            vertical: 2,
                          ),
                          decoration: BoxDecoration(
                            color: roleInfo.$3(colorScheme).withValues(alpha: isSuspended ? 0.35 : 0.9),
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: roleInfo.$4(colorScheme).withValues(alpha: 0.25),
                              width: 0.6,
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(roleInfo.$2, size: 11, color: roleInfo.$4(colorScheme)),
                              const SizedBox(width: 4),
                              Text(
                                roleInfo.$1,
                                style: TextStyle(
                                  fontSize: 10.5,
                                  fontWeight: FontWeight.bold,
                                  color: roleInfo.$4(colorScheme),
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 2),
                    Text(
                      admin.phoneNumber,
                      style: TextStyle(
                        fontSize: 13,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (admin.email.isNotEmpty) ...[
                      const SizedBox(height: 1),
                      Text(
                        admin.email,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const SizedBox(width: 4),
              Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.edit_rounded, size: 18, color: colorScheme.primary),
                    tooltip: l10n.editAdmin,
                    onPressed: () => _showEditDialog(context, bloc),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(
                      isSuspended ? Icons.play_arrow_rounded : Icons.pause_rounded,
                      size: 18,
                      color: isSuspended ? colorScheme.primary : colorScheme.error,
                    ),
                    tooltip: isSuspended ? l10n.activateAdmin : l10n.suspendAdmin,
                    onPressed: () => bloc.add(
                      SuspendAdminRequested(
                        adminId: admin.uid,
                        suspend: !isSuspended,
                      ),
                    ),
                  ),
                  IconButton(
                    visualDensity: VisualDensity.compact,
                    icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
                    tooltip: l10n.deleteAdmin,
                    onPressed: () => _showDeleteConfirmation(context, bloc),
                  ),
                ],
              ),
            ],
          ),
        ),
      );
    }

  void _showEditDialog(BuildContext context, ManageAdminsBloc bloc) {
    final l10n = AppLocalizations.of(context)!;
    final nameController = TextEditingController(text: admin.displayName);
    final phoneController = TextEditingController(text: admin.phoneNumber);
    final emailController = TextEditingController(text: admin.email);
    final formKey = GlobalKey<FormState>();

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          title: Text(l10n.editAdmin),
          content: Form(
            key: formKey,
            child: Column(
              mainAxisSize: MainAxisSize.min,
              children: [
                TextFormField(
                  controller: nameController,
                  decoration: InputDecoration(labelText: l10n.adminName),
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l10n.pleaseEnterAdminName
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: phoneController,
                  decoration: InputDecoration(labelText: l10n.adminPhone),
                  keyboardType: TextInputType.phone,
                  validator: (v) => v == null || v.trim().isEmpty
                      ? l10n.pleaseEnterAdminPhone
                      : null,
                ),
                const SizedBox(height: 12),
                TextFormField(
                  controller: emailController,
                  decoration: InputDecoration(labelText: l10n.adminEmail),
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
                  UpdateAdminRequested(
                    admin: AdminUser(
                      uid: admin.uid,
                      phoneNumber: phoneController.text.trim(),
                      email: emailController.text.trim(),
                      displayName: nameController.text.trim(),
                      role: admin.role,
                      createdAt: admin.createdAt,
                      createdBy: admin.createdBy,
                      temporaryPassword: admin.temporaryPassword,
                      isActive: admin.isActive,
                    ),
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

  void _showDeleteConfirmation(BuildContext context, ManageAdminsBloc bloc) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogContext) {
        return AlertDialog(
          icon: Icon(Icons.warning_rounded, color: colorScheme.error, size: 40),
          title: Text(l10n.deleteAdmin),
          content: Text(l10n.deleteAdminConfirmation),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(dialogContext),
              child: Text(l10n.cancel),
            ),
            FilledButton(
              style: FilledButton.styleFrom(backgroundColor: colorScheme.error),
              onPressed: () {
                Navigator.pop(dialogContext);
                bloc.add(DeleteAdminRequested(adminId: admin.uid));
              },
              child: Text(l10n.deleteAdmin),
            ),
          ],
        );
      },
    );
  }
}
