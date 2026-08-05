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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<AdminUser> _filterAdmins(List<AdminUser> admins) {
    final query = _searchController.text.trim().toLowerCase();

    return admins.where((admin) {
      final matchesName = admin.displayName.toLowerCase().contains(query);
      final matchesPhone = admin.phoneNumber.toLowerCase().contains(query);
      final matchesEmail = admin.email.toLowerCase().contains(query);
      final matchesRole = admin.role.toLowerCase().contains(query);

      final matchesQuery =
          query.isEmpty ||
          matchesName ||
          matchesPhone ||
          matchesEmail ||
          matchesRole;

      final matchesStatus =
          _selectedStatusFilter == 'all' ||
          (_selectedStatusFilter == 'active' && admin.isActive) ||
          (_selectedStatusFilter == 'suspended' && !admin.isActive);

      return matchesQuery && matchesStatus;
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
            final filteredAdmins = _filterAdmins(allAdmins);
            final isSearchingOrFiltering =
                _searchController.text.isNotEmpty ||
                _selectedStatusFilter != 'all';

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
                            ? 'البحث باسم المستخدم، الاسم، أو رقم الموبايل...'
                            : 'Search by username, name, or phone...',
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

                      // Filter Chips
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
                              selectedColor:
                                  Colors.green.withValues(alpha: 0.2),
                              checkmarkColor: Colors.green,
                            ),
                            const SizedBox(width: 8),
                            FilterChip(
                              label: Text(l10n.suspended),
                              selected: _selectedStatusFilter == 'suspended',
                              onSelected: (_) => setState(
                                  () => _selectedStatusFilter = 'suspended'),
                              selectedColor:
                                  colorScheme.error.withValues(alpha: 0.2),
                              checkmarkColor: colorScheme.error,
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
                              setState(() => _selectedStatusFilter = 'all');
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
                                    : Icons.admin_panel_settings_outlined,
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
    final isSuspended = !admin.isActive;

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      color: isSuspended
          ? colorScheme.errorContainer.withValues(alpha: 0.3)
          : colorScheme.surfaceContainerHighest,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
      child: InkWell(
        borderRadius: BorderRadius.circular(12),
        onTap: () => _showActionsSheet(context),
        child: Padding(
          padding: const EdgeInsets.all(16),
          child: Row(
            children: [
              CircleAvatar(
                backgroundColor: isSuspended
                    ? colorScheme.error.withValues(alpha: 0.15)
                    : colorScheme.primaryContainer,
                child: Icon(
                  Icons.person_rounded,
                  color: isSuspended
                      ? colorScheme.error
                      : colorScheme.onPrimaryContainer,
                ),
              ),
              const SizedBox(width: 16),
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
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                        ),
                        if (isSuspended)
                          Container(
                            padding: const EdgeInsets.symmetric(
                              horizontal: 8,
                              vertical: 2,
                            ),
                            decoration: BoxDecoration(
                              color: colorScheme.error.withValues(alpha: 0.15),
                              borderRadius: BorderRadius.circular(12),
                            ),
                            child: Text(
                              l10n.suspended,
                              style: TextStyle(
                                fontSize: 11,
                                fontWeight: FontWeight.w600,
                                color: colorScheme.error,
                              ),
                            ),
                          ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      admin.phoneNumber,
                      style: TextStyle(
                        fontSize: 14,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                    if (admin.email.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        admin.email,
                        style: TextStyle(
                          fontSize: 13,
                          color: colorScheme.onSurfaceVariant.withValues(
                            alpha: 0.7,
                          ),
                        ),
                      ),
                    ],
                  ],
                ),
              ),
              Icon(
                Icons.more_vert_rounded,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  void _showActionsSheet(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final bloc = context.read<ManageAdminsBloc>();
    final isSuspended = !admin.isActive;

    showModalBottomSheet(
      context: context,
      showDragHandle: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (sheetContext) {
        return SafeArea(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 24),
                child: Row(
                  children: [
                    CircleAvatar(
                      backgroundColor: colorScheme.primaryContainer,
                      child: Icon(
                        Icons.person_rounded,
                        color: colorScheme.onPrimaryContainer,
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            admin.displayName,
                            style: TextStyle(
                              fontSize: 16,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          Text(
                            admin.phoneNumber,
                            style: TextStyle(
                              fontSize: 13,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 16),
              const Divider(height: 1),
              // Edit
              ListTile(
                leading: Icon(Icons.edit_rounded, color: colorScheme.primary),
                title: Text(l10n.editAdmin),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showEditDialog(context, bloc);
                },
              ),
              // Suspend / Activate
              ListTile(
                leading: Icon(
                  isSuspended ? Icons.play_arrow_rounded : Icons.pause_rounded,
                  color: isSuspended ? Colors.green : Colors.orange,
                ),
                title: Text(
                  isSuspended ? l10n.activateAdmin : l10n.suspendAdmin,
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  bloc.add(
                    SuspendAdminRequested(
                      adminId: admin.uid,
                      suspend: !isSuspended,
                    ),
                  );
                },
              ),
              // Delete
              ListTile(
                leading: Icon(Icons.delete_rounded, color: colorScheme.error),
                title: Text(
                  l10n.deleteAdmin,
                  style: TextStyle(color: colorScheme.error),
                ),
                onTap: () {
                  Navigator.pop(sheetContext);
                  _showDeleteConfirmation(context, bloc);
                },
              ),
              const SizedBox(height: 8),
            ],
          ),
        );
      },
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
