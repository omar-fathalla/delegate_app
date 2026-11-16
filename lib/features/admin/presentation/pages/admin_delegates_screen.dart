import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_profile_edit_access.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_delegate_form_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/datasources/delegate_hold_remote.dart';
import 'package:delegate_app/core/security/delegate_status_policy.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_hold_access.dart';
import 'package:delegate_app/features/admin/presentation/widgets/link_delegate_to_org_sheet.dart';
import 'package:delegate_app/features/admin/presentation/widgets/delete_delegate_request_sheet.dart';
import 'package:delegate_app/features/admin/presentation/pages/edit_delegate_profile_screen.dart';

class AdminDelegatesScreen extends StatelessWidget {
  final Delegate adminDelegate;

  const AdminDelegatesScreen({super.key, required this.adminDelegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AdminDelegatesBloc>()
        ..add(
          LoadCompanyDelegates(
            organizationUID: adminDelegate.companyUID.isNotEmpty
                ? ''
                : adminDelegate.organizationUID,
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
  String? _selectedOrgUID;
  List<Map<String, String>> _availableOrganizations = [];

  @override
  void initState() {
    super.initState();
    _loadOrganizations();
  }

  Future<void> _loadOrganizations() async {
    try {
      final snap =
          await FirebaseFirestore.instance.collection('organizations').get();
      final companyUID = widget.adminDelegate.companyUID;
      final List<Map<String, String>> orgs = [];
      if (companyUID.isEmpty) {
        orgs.addAll(snap.docs.map((d) {
          final name = formatChainDisplayName(
            d.data()['name']?.toString() ?? d.id,
          );
          return {'id': d.id, 'name': name};
        }));
      } else {
        final checks = await Future.wait(snap.docs.map((d) async {
          try {
            final cDoc = await FirebaseFirestore.instance
                .collection('organizations')
                .doc(d.id)
                .collection('companies')
                .doc(companyUID)
                .get();
            if (!cDoc.exists) return null;
            final name = formatChainDisplayName(
              d.data()['name']?.toString() ?? d.id,
            );
            return {'id': d.id, 'name': name};
          } catch (_) {
            return null;
          }
        }));
        orgs.addAll(checks.whereType<Map<String, String>>());
      }
      if (mounted) {
        setState(() => _availableOrganizations = orgs);
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Delegate> _filterDelegates(
    List<Delegate> delegates,
    Map<String, String> orgsMap,
  ) {
    final query = _searchController.text.toLowerCase().trim();
    final selectedOrgName =
        _selectedOrgUID != null ? orgsMap[_selectedOrgUID] : null;

    return delegates.where((delegate) {
      final matchesName = query.isEmpty ||
          delegate.fullName.toLowerCase().contains(query) ||
          delegate.phoneNumber.contains(query);
      final matchesStatus =
          _selectedStatus == null || delegate.status == _selectedStatus;
      final matchesOrg = _selectedOrgUID == null ||
          delegate.organizationUID == _selectedOrgUID ||
          (selectedOrgName != null &&
              (formatChainDisplayName(delegate.organizationName) ==
                      selectedOrgName ||
                  delegate.allOrganizationNames.any(
                    (o) => formatChainDisplayName(o) == selectedOrgName,
                  )));
      return matchesName && matchesStatus && matchesOrg;
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
                Icon(
                  Icons.error_outline_rounded,
                  color: theme.colorScheme.error,
                  size: 48,
                ),
                const SizedBox(height: 16),
                Text(state.message, style: TextStyle(color: theme.colorScheme.error)),
                const SizedBox(height: 16),
                FilledButton.tonal(
                  onPressed: () {
                    AdminDelegatesBloc.clearCache();
                    context.read<AdminDelegatesBloc>().add(
                      LoadCompanyDelegates(
                        organizationUID:
                            widget.adminDelegate.companyUID.isNotEmpty
                                ? ''
                                : widget.adminDelegate.organizationUID,
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
          final fetchWarning = state.warning;

          // Build dynamic map of organizations from fetched orgs + loaded delegates
          final orgsMap = <String, String>{};
          for (final org in _availableOrganizations) {
            orgsMap[org['id']!] = formatChainDisplayName(org['name']!);
          }
          for (final d in allDelegates) {
            if (d.organizationUID.isNotEmpty) {
              orgsMap.putIfAbsent(
                d.organizationUID,
                () => formatChainDisplayName(
                  d.organizationName.isNotEmpty
                      ? d.organizationName
                      : d.organizationUID,
                ),
              );
            }
          }
          final filteredDelegates = _filterDelegates(allDelegates, orgsMap);

          return Scaffold(
            body: Column(
              children: [
                if (fetchWarning != null && fetchWarning.isNotEmpty)
                  MaterialBanner(
                    content: Text(fetchWarning),
                    actions: [
                      TextButton(
                        onPressed: () {
                          AdminDelegatesBloc.clearCache();
                          context.read<AdminDelegatesBloc>().add(
                            LoadCompanyDelegates(
                              organizationUID:
                                  widget.adminDelegate.companyUID.isNotEmpty
                                      ? ''
                                      : widget.adminDelegate.organizationUID,
                              companyUID: widget.adminDelegate.companyUID,
                            ),
                          );
                        },
                        child: Text(l10n.retry),
                      ),
                    ],
                  ),
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
                        color: theme.colorScheme.shadow.withValues(alpha: 0.04),
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

                      // ── Dropdown Menus: Organization & Request Status ──
                      const SizedBox(height: 10),
                      Row(
                        children: [
                          // 1. Organization Drop Menu
                          Expanded(
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedOrgUID != null
                                      ? theme.colorScheme.primary.withValues(alpha: 0.7)
                                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                                  width: _selectedOrgUID != null ? 1.4 : 1.0,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<String?>(
                                  value: _selectedOrgUID,
                                  isExpanded: true,
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: _selectedOrgUID != null
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  hint: Row(
                                    children: [
                                      Icon(
                                        Icons.storefront_rounded,
                                        size: 16,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      const Expanded(
                                        child: Text(
                                          'كل السلاسل',
                                          style: TextStyle(fontSize: 12.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  items: [
                                    DropdownMenuItem<String?>(
                                      value: null,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.storefront_rounded,
                                            size: 16,
                                            color: _selectedOrgUID == null
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'جميع السلاسل (${allDelegates.length})',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: _selectedOrgUID == null
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...orgsMap.entries.map((entry) {
                                      final isSelected = _selectedOrgUID == entry.key;
                                      final (_, badgeFg, _) =
                                          getOrgBadgeColors(context, entry.value);
                                      final count = allDelegates.where((d) =>
                                          d.organizationUID == entry.key ||
                                          formatChainDisplayName(d.organizationName) == entry.value ||
                                          d.allOrganizationNames.any((o) => formatChainDisplayName(o) == entry.value)).length;
                                      return DropdownMenuItem<String?>(
                                        value: entry.key,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(
                                                color: badgeFg,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${entry.value} ($count)',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? theme.colorScheme.primary
                                                      : null,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) {
                                    setState(() => _selectedOrgUID = val);
                                  },
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(width: 8),

                          // 2. Request / Status Drop Menu
                          Expanded(
                            child: Container(
                              height: 44,
                              padding: const EdgeInsets.symmetric(horizontal: 10),
                              decoration: BoxDecoration(
                                color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(12),
                                border: Border.all(
                                  color: _selectedStatus != null
                                      ? theme.colorScheme.primary.withValues(alpha: 0.7)
                                      : theme.colorScheme.outlineVariant.withValues(alpha: 0.6),
                                  width: _selectedStatus != null ? 1.4 : 1.0,
                                ),
                              ),
                              child: DropdownButtonHideUnderline(
                                child: DropdownButton<DelegateStatus?>(
                                  value: _selectedStatus,
                                  isExpanded: true,
                                  icon: Icon(
                                    Icons.keyboard_arrow_down_rounded,
                                    size: 20,
                                    color: _selectedStatus != null
                                        ? theme.colorScheme.primary
                                        : theme.colorScheme.onSurfaceVariant,
                                  ),
                                  hint: Row(
                                    children: [
                                      Icon(
                                        Icons.filter_list_rounded,
                                        size: 16,
                                        color: theme.colorScheme.onSurfaceVariant,
                                      ),
                                      const SizedBox(width: 6),
                                      const Expanded(
                                        child: Text(
                                          'كل الحالات',
                                          style: TextStyle(fontSize: 12.5),
                                          overflow: TextOverflow.ellipsis,
                                        ),
                                      ),
                                    ],
                                  ),
                                  items: [
                                    DropdownMenuItem<DelegateStatus?>(
                                      value: null,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.rule_rounded,
                                            size: 16,
                                            color: _selectedStatus == null
                                                ? theme.colorScheme.primary
                                                : theme.colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 8),
                                          Text(
                                            'جميع الحالات (${allDelegates.length})',
                                            style: TextStyle(
                                              fontSize: 12.5,
                                              fontWeight: _selectedStatus == null
                                                  ? FontWeight.bold
                                                  : FontWeight.normal,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                    ...DelegateStatus.values.map((status) {
                                      final isSelected = _selectedStatus == status;
                                      final statusColor = _getStatusColor(context, status);
                                      final count = allDelegates.where((d) => d.status == status).length;
                                      return DropdownMenuItem<DelegateStatus?>(
                                        value: status,
                                        child: Row(
                                          children: [
                                            Container(
                                              width: 9,
                                              height: 9,
                                              decoration: BoxDecoration(
                                                color: statusColor,
                                                shape: BoxShape.circle,
                                              ),
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                '${_getStatusLabel(context, status)} ($count)',
                                                style: TextStyle(
                                                  fontSize: 12.5,
                                                  fontWeight: isSelected
                                                      ? FontWeight.bold
                                                      : FontWeight.normal,
                                                  color: isSelected
                                                      ? theme.colorScheme.primary
                                                      : null,
                                                ),
                                                overflow: TextOverflow.ellipsis,
                                              ),
                                            ),
                                          ],
                                        ),
                                      );
                                    }),
                                  ],
                                  onChanged: (val) {
                                    setState(() => _selectedStatus = val);
                                  },
                                ),
                              ),
                            ),
                          ),
                        ],
                      ),

                      // ── Approvals & Requests Quick Banner ──
                      const SizedBox(height: 8),
                      InkWell(
                        onTap: () {
                          Navigator.of(context).push(
                            MaterialPageRoute(
                              builder: (_) => DelegateSubscriptionRequestsPage(
                                currentAdmin: widget.adminDelegate,
                              ),
                            ),
                          );
                        },
                        borderRadius: BorderRadius.circular(12),
                        child: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                          decoration: BoxDecoration(
                            color: theme.brightness == Brightness.dark
                                ? const Color(0xFF282006)
                                : const Color(0xFFFFFBEB),
                            borderRadius: BorderRadius.circular(12),
                            border: Border.all(
                              color: const Color(0xFFD4AF37).withValues(alpha: 0.5),
                              width: 1,
                            ),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(4),
                                decoration: BoxDecoration(
                                  color: const Color(0xFFB8860B).withValues(alpha: 0.2),
                                  borderRadius: BorderRadius.circular(8),
                                ),
                                child: const Icon(
                                  Icons.how_to_reg_rounded,
                                  size: 16,
                                  color: Color(0xFFB8860B),
                                ),
                              ),
                              const SizedBox(width: 8),
                              Expanded(
                                child: Text(
                                  'متابعة طلبات الاعتمادات والمناديب الجدد (قيد الانتظار / المعتمدة)',
                                  style: TextStyle(
                                    fontSize: 11.5,
                                    fontWeight: FontWeight.w600,
                                    color: theme.brightness == Brightness.dark
                                        ? const Color(0xFFFFE082)
                                        : const Color(0xFF8D6200),
                                  ),
                                ),
                              ),
                              const Icon(
                                Icons.arrow_forward_ios_rounded,
                                size: 12,
                                color: Color(0xFFB8860B),
                              ),
                            ],
                          ),
                        ),
                      ),
                    ],
                  ),
                ),

                // ── Compact Delegate List ──
                Expanded(
                  child: RefreshIndicator(
                    onRefresh: () async {
                      AdminDelegatesBloc.clearCache();
                      context.read<AdminDelegatesBloc>().add(
                        LoadCompanyDelegates(
                          organizationUID:
                              widget.adminDelegate.companyUID.isNotEmpty
                                  ? ''
                                  : widget.adminDelegate.organizationUID,
                          companyUID: widget.adminDelegate.companyUID,
                        ),
                      );
                      await _loadOrganizations();
                    },
                    child: filteredDelegates.isEmpty
                        ? SingleChildScrollView(
                            physics: const AlwaysScrollableScrollPhysics(),
                            child: SizedBox(
                              height: MediaQuery.of(context).size.height * 0.5,
                              child: _NoResultsView(
                                isSearching:
                                    _searchController.text.isNotEmpty ||
                                        _selectedStatus != null ||
                                        _selectedOrgUID != null,
                                allEmpty: allDelegates.isEmpty,
                              ),
                            ),
                          )
                        : ListView.separated(
                            physics: const AlwaysScrollableScrollPhysics(),
                            padding: const EdgeInsets.only(
                              left: 14,
                              right: 14,
                              top: 8,
                              bottom: 88,
                            ),
                            itemCount: filteredDelegates.length,
                            separatorBuilder: (context, index) =>
                                const SizedBox(height: 6),
                            itemBuilder: (context, index) {
                              final delegate = filteredDelegates[index];
                              return _CompactDelegateTile(
                                delegate: delegate,
                                adminDelegate: widget.adminDelegate,
                                onRefresh: () {
                                  AdminDelegatesBloc.clearCache();
                                  context.read<AdminDelegatesBloc>().add(
                                        LoadCompanyDelegates(
                                          organizationUID:
                                              widget.adminDelegate.companyUID.isNotEmpty
                                                  ? ''
                                                  : widget.adminDelegate.organizationUID,
                                          companyUID: widget.adminDelegate.companyUID,
                                        ),
                                      );
                                },
                              );
                            },
                          ),
                  ),
                ),
              ],
            ),
            floatingActionButton: FloatingActionButton.extended(
              onPressed: () async {
                final result = await Navigator.of(context).push<bool>(
                  MaterialPageRoute(
                    builder: (_) => AddDelegateFormScreen(
                      supervisor: widget.adminDelegate,
                    ),
                  ),
                );
                if (result == true && context.mounted) {
                  AdminDelegatesBloc.clearCache();
                  context.read<AdminDelegatesBloc>().add(
                        LoadCompanyDelegates(
                          organizationUID:
                              widget.adminDelegate.companyUID.isNotEmpty
                                  ? ''
                                  : widget.adminDelegate.organizationUID,
                          companyUID: widget.adminDelegate.companyUID,
                        ),
                      );
                }
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
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case DelegateStatus.active:
      case DelegateStatus.approved:
        return colorScheme.primary;
      case DelegateStatus.suspended:
      case DelegateStatus.rejected:
        return colorScheme.error;
      case DelegateStatus.pending:
        return colorScheme.secondary;
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

/// Normalizes raw organization / retail chain names into clean Arabic display names.
String formatChainDisplayName(String raw) {
  final clean = raw.trim();
  final lower = clean.toLowerCase();
  if (lower.contains('fathalla') ||
      clean.contains('فتح الله') ||
      clean.contains('فتح_الله')) {
    return 'فتح الله ماركت';
  }
  if (lower.contains('gomla') ||
      lower.contains('jomla') ||
      clean.contains('جملة') ||
      clean.contains('جمله')) {
    return 'جملة ماركت';
  }
  if (lower.contains('zahran') || clean.contains('زهران')) {
    return 'زهران ماركت';
  }
  if (lower.contains('carrefour') || clean.contains('كارفور')) {
    return 'كارفور';
  }
  if (lower.contains('beit') || clean.contains('بيت الجملة')) {
    return 'بيت الجملة';
  }
  return clean;
}

/// Returns a tuple of (backgroundColor, foregroundColor, borderColor) for an organization
/// with distinct, recognizable colors for quick visual differentiation.
(Color bg, Color fg, Color border) getOrgBadgeColors(
  BuildContext context,
  String orgName,
) {
  final isDark = Theme.of(context).brightness == Brightness.dark;
  final lower = orgName.toLowerCase().trim();

  // Gomla Market (Emerald Green)
  if (lower.contains('جملة') || lower.contains('gomla') || lower.contains('jomla')) {
    return isDark
        ? (
            const Color(0xFF143823),
            const Color(0xFF81C784),
            const Color(0xFF2E7D32),
          )
        : (
            const Color(0xFFE8F5E9),
            const Color(0xFF1B5E20),
            const Color(0xFFA5D6A7),
          );
  }

  // Fathalla Market (Royal Blue)
  if (lower.contains('فتح الله') || lower.contains('fathalla')) {
    return isDark
        ? (
            const Color(0xFF102844),
            const Color(0xFF90CAF9),
            const Color(0xFF1976D2),
          )
        : (
            const Color(0xFFE3F2FD),
            const Color(0xFF0D47A1),
            const Color(0xFF90CAF9),
          );
  }

  // Zahran Market (Warm Amber / Orange)
  if (lower.contains('زهران') || lower.contains('zahran')) {
    return isDark
        ? (
            const Color(0xFF3E240D),
            const Color(0xFFFFB74D),
            const Color(0xFFF57C00),
          )
        : (
            const Color(0xFFFFF3E0),
            const Color(0xFFE65100),
            const Color(0xFFFFCC80),
          );
  }

  // Carrefour (Deep Purple / Violet)
  if (lower.contains('كارفور') || lower.contains('carrefour')) {
    return isDark
        ? (
            const Color(0xFF2D1B44),
            const Color(0xFFCE93D8),
            const Color(0xFF8E24AA),
          )
        : (
            const Color(0xFFF3E5F5),
            const Color(0xFF6A1B9A),
            const Color(0xFFCE93D8),
          );
  }

  // Metro Market (Ruby Crimson)
  if (lower.contains('مترو') || lower.contains('metro')) {
    return isDark
        ? (
            const Color(0xFF3A171D),
            const Color(0xFFEF9A9A),
            const Color(0xFFC62828),
          )
        : (
            const Color(0xFFFFEBEE),
            const Color(0xFFB71C1C),
            const Color(0xFFEF9A9A),
          );
  }

  // Spinneys (Teal / Cyan)
  if (lower.contains('سبينس') || lower.contains('spinneys')) {
    return isDark
        ? (
            const Color(0xFF103338),
            const Color(0xFF80DEEA),
            const Color(0xFF00838F),
          )
        : (
            const Color(0xFFE0F7FA),
            const Color(0xFF006064),
            const Color(0xFF80DEEA),
          );
  }

  // Kheir Zaman (Warm Brown)
  if (lower.contains('خير زمان') || lower.contains('kheir')) {
    return isDark
        ? (
            const Color(0xFF332724),
            const Color(0xFFBCAAA4),
            const Color(0xFF6D4C41),
          )
        : (
            const Color(0xFFEFEBE9),
            const Color(0xFF4E342E),
            const Color(0xFFBCAAA4),
          );
  }

  // Seoudi Market (Navy / Indigo)
  if (lower.contains('سعودي') || lower.contains('seoudi')) {
    return isDark
        ? (
            const Color(0xFF1A2238),
            const Color(0xFF9FA8DA),
            const Color(0xFF3949AB),
          )
        : (
            const Color(0xFFE8EAF6),
            const Color(0xFF1A237E),
            const Color(0xFF9FA8DA),
          );
  }

  // Deterministic palette fallback for any other organization name
  final palettes = isDark
      ? [
          (const Color(0xFF263238), const Color(0xFFB0BEC5), const Color(0xFF546E7A)), // Blue Grey
          (const Color(0xFF37203A), const Color(0xFFF48FB1), const Color(0xFFAD1457)), // Pink
          (const Color(0xFF312613), const Color(0xFFFFE082), const Color(0xFFFFB300)), // Amber
          (const Color(0xFF162D2D), const Color(0xFFA7FFEB), const Color(0xFF00BFA5)), // Mint
          (const Color(0xFF2A1C35), const Color(0xFFD1C4E9), const Color(0xFF7E57C2)), // Deep Purple
        ]
      : [
          (const Color(0xFFECEFF1), const Color(0xFF37474F), const Color(0xFFB0BEC5)), // Blue Grey
          (const Color(0xFFFCE4EC), const Color(0xFF880E4F), const Color(0xFFF48FB1)), // Pink
          (const Color(0xFFFFF8E1), const Color(0xFFFF6F00), const Color(0xFFFFE082)), // Amber
          (const Color(0xFFE0F2F1), const Color(0xFF004D40), const Color(0xFF80CBC4)), // Mint
          (const Color(0xFFEDE7F6), const Color(0xFF4A148C), const Color(0xFFD1C4E9)), // Deep Purple
        ];

  final index = orgName.isEmpty ? 0 : (orgName.hashCode.abs() % palettes.length);
  return palettes[index];
}

/// A compact, high-density delegate row tile that minimizes vertical space.
/// Replaces large buttons with compact icon buttons and text badges with status dots.
class _CompactDelegateTile extends StatelessWidget {
  final Delegate delegate;
  final Delegate? adminDelegate;
  final VoidCallback? onRefresh;

  const _CompactDelegateTile({
    required this.delegate,
    this.adminDelegate,
    this.onRefresh,
  });

  bool get _canSetHold =>
      adminDelegate != null &&
      canSetDelegateHold(
        role: adminDelegate!.role,
        callerOrganizationUID: adminDelegate!.organizationUID,
        callerCompanyUID: adminDelegate!.companyUID,
        targetOrganizationUID: delegate.organizationUID,
        targetCompanyUID: delegate.companyUID,
      );

  bool get _showHoldControl => delegateHoldShowsReactivate(
        canSetHold: _canSetHold,
        delegateSuspended: _isVisiblySuspended,
        viewerRole: adminDelegate?.role,
      );

  bool get _isVisiblySuspended => delegate.status == DelegateStatus.suspended;

  Future<void> _confirmSetHold(BuildContext context, {required bool suspend}) async {
    final action = suspend ? 'إيقاف' : 'إعادة تفعيل';
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Text('$action المندوب'),
          content: Text(
            suspend
                ? 'هل تريد إيقاف المندوب "${delegate.fullName}"؟\n\n'
                    'سيتم إيقاف حساب المندوب وتسجيل خروجه. إذا كان عليه إيقاف آخر '
                    '(مثل انتهاء الاشتراك) فسيبقى موقوفاً حتى تُرفع كل أسباب الإيقاف.'
                : 'هل تريد إعادة تفعيل المندوب "${delegate.fullName}"؟\n\n'
                    'سيتم رفع إيقاف الإدارة فقط. إذا كان المندوب موقوفاً لسبب آخر '
                    '(مثل انتهاء الاشتراك) فسيبقى موقوفاً.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              style: FilledButton.styleFrom(
                backgroundColor: suspend ? colorScheme.error : colorScheme.primary,
                foregroundColor: suspend ? colorScheme.onError : colorScheme.onPrimary,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              child: Text('تأكيد $action'),
            ),
          ],
        );
      },
    );
    if (confirmed != true || !context.mounted) return;
    final op = delegateHoldOpFor(
      callerRole: adminDelegate?.role,
      suspend: suspend,
    );
    if (op == null) {
      AppSnackBar.showError(context, delegateHoldNotAllowedMessage);
      return;
    }
    final payload = buildDelegateHoldPayload(
      callerRole: adminDelegate?.role,
      callerOrganizationUID: adminDelegate?.organizationUID ?? '',
      callerCompanyUID: adminDelegate?.companyUID ?? '',
      uid: delegate.uid,
      organizationUID: delegate.organizationUID,
      companyUID: delegate.companyUID,
      op: op,
    );
    if (payload == null) {
      AppSnackBar.showError(context, 'هذا المندوب خارج نطاق صلاحيتك.');
      return;
    }
    try {
      final result = await DelegateHoldRemote().setDelegateHold(
        uid: payload['uid'] as String,
        organizationUID: payload['orgId'] as String,
        companyUID: payload['companyId'] as String,
        op: payload['op'] as String,
        hold: payload['hold'] as String,
      );
      if (!context.mounted) return;
      final reason = result['reason']?.toString();
      final derived = result['derivedStatus']?.toString();
      if (reason == 'hold_not_present') {
        AppSnackBar.showSuccess(
          context,
          derived == 'suspended'
              ? 'هذا الإيقاف غير موجود. المندوب ما زال موقوفاً لسبب آخر.'
              : 'هذا الإيقاف غير موجود على حساب المندوب.',
        );
      } else if (suspend) {
        AppSnackBar.showSuccess(context, 'تم إيقاف المندوب.');
      } else if (derived == 'suspended') {
        AppSnackBar.showSuccess(
          context,
          'تم رفع إيقاف الإدارة. المندوب ما زال موقوفاً لسبب آخر.',
        );
      } else {
        AppSnackBar.showSuccess(context, 'تم إعادة تفعيل المندوب.');
      }
      onRefresh?.call();
    } on DelegateHoldException catch (e) {
      if (context.mounted) AppSnackBar.showError(context, e.message);
    }
  }

  Future<void> _confirmForceLogout(BuildContext context) async {
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final colorScheme = Theme.of(ctx).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: Row(
            children: [
              Icon(Icons.logout_rounded, color: colorScheme.error),
              const SizedBox(width: 8),
              const Text('تسجيل خروج إجباري'),
            ],
          ),
          content: Text(
            'هل تريد إجبار المندوب "${delegate.fullName}" على تسجيل الخروج؟\n\n'
            'سيتم إعادته لشاشة تسجيل الدخول لإدخال رقم الهاتف والرقم القومي للتحقق من شركته الحالية وتحديث بياناته.',
            style: const TextStyle(fontSize: 14, height: 1.4),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(ctx).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.icon(
              style: FilledButton.styleFrom(
                backgroundColor: colorScheme.error,
                foregroundColor: colorScheme.onError,
              ),
              onPressed: () => Navigator.of(ctx).pop(true),
              icon: const Icon(Icons.logout_rounded, size: 18),
              label: const Text('تأكيد الخروج الإجباري'),
            ),
          ],
        );
      },
    );

    if (confirmed == true && context.mounted) {
      final colorScheme = Theme.of(context).colorScheme;
      final success = await SessionManagementService.forceLogoutDelegate(
        delegateUid: delegate.uid,
        organizationUID: delegate.organizationUID,
        companyUID: delegate.companyUID,
        delegateName: delegate.fullName,
        delegatePhone: delegate.phoneNumber,
        reason: 'إعادة التحقق من الشركة عبر الإدارة',
        adminUid: adminDelegate?.uid,
      );

      if (context.mounted) {
        if (success) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                'تم تسجيل خروج المندوب "${delegate.fullName}" بنجاح.',
                style: TextStyle(color: colorScheme.onPrimaryContainer),
              ),
              backgroundColor: colorScheme.primaryContainer,
            ),
          );
          onRefresh?.call();
        } else {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: const Text('فشل تنفيذ تسجيل الخروج الإجباري'),
              backgroundColor: colorScheme.error,
            ),
          );
        }
      }
    }
  }


  Widget _buildOrgBadge(
    BuildContext context,
    String orgName, {
    double? maxWidth,
  }) {
    final displayOrg = formatChainDisplayName(orgName);
    if (displayOrg.isEmpty) return const SizedBox.shrink();
    final (bg, fg, border) = getOrgBadgeColors(context, displayOrg);
    Widget badge = Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        displayOrg,
        style: TextStyle(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
    );

    if (maxWidth != null) {
      badge = ConstrainedBox(
        constraints: BoxConstraints(maxWidth: maxWidth),
        child: badge,
      );
    }
    return badge;
  }

  Widget _buildMoreBadge(
    BuildContext context,
    int count,
    VoidCallback onTap,
  ) {
    final theme = Theme.of(context);
    final isDark = theme.brightness == Brightness.dark;
    return InkWell(
      onTap: onTap,
      borderRadius: BorderRadius.circular(6),
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
        decoration: BoxDecoration(
          color: isDark
              ? theme.colorScheme.secondaryContainer.withValues(alpha: 0.5)
              : theme.colorScheme.secondaryContainer,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(
            color: theme.colorScheme.secondary.withValues(alpha: 0.35),
            width: 0.8,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text(
              '+$count',
              style: TextStyle(
                color: theme.colorScheme.onSecondaryContainer,
                fontSize: 10.5,
                fontWeight: FontWeight.bold,
              ),
            ),
            const SizedBox(width: 2),
            Icon(
              Icons.arrow_drop_down_rounded,
              size: 13,
              color: theme.colorScheme.onSecondaryContainer,
            ),
          ],
        ),
      ),
    );
  }

  void _showAllOrgsSheet(BuildContext context, List<String> allOrgs) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: theme.scaffoldBackgroundColor,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(20)),
      ),
      builder: (ctx) {
        return SafeArea(
          child: Padding(
            padding: const EdgeInsets.fromLTRB(16, 12, 16, 20),
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Handle bar
                Center(
                  child: Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant,
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                ),
                const SizedBox(height: 14),

                // Title row
                Row(
                  children: [
                    AppAvatar(
                      imageUrl: delegate.personalPhotoUrl,
                      fallbackText: delegate.firstName,
                      radius: 20,
                      backgroundColor: colorScheme.primaryContainer,
                      foregroundColor: colorScheme.onPrimaryContainer,
                    ),
                    const SizedBox(width: 10),
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
                          Text(
                            'السلاسل والمنظمات التابع لها (${allOrgs.length})',
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),
                const Divider(height: 1),
                const SizedBox(height: 12),

                // List of organizations
                Flexible(
                  child: SingleChildScrollView(
                    child: Column(
                      mainAxisSize: MainAxisSize.min,
                      children: allOrgs.asMap().entries.map((entry) {
                        final idx = entry.key;
                        final name = formatChainDisplayName(entry.value);
                        final isPrimary = (idx == 0 &&
                            formatChainDisplayName(delegate.organizationName) ==
                                name);
                        final (bg, fg, border) = getOrgBadgeColors(context, name);

                        return Container(
                          margin: const EdgeInsets.only(bottom: 8),
                          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                          decoration: BoxDecoration(
                            color: bg.withValues(alpha: 0.15),
                            borderRadius: BorderRadius.circular(10),
                            border: Border.all(color: border, width: 1),
                          ),
                          child: Row(
                            children: [
                              Container(
                                width: 26,
                                height: 26,
                                decoration: BoxDecoration(
                                  color: bg,
                                  shape: BoxShape.circle,
                                  border: Border.all(color: border),
                                ),
                                alignment: Alignment.center,
                                child: Text(
                                  '${idx + 1}',
                                  style: TextStyle(
                                    color: fg,
                                    fontSize: 12,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Text(
                                  name,
                                  style: theme.textTheme.bodyMedium?.copyWith(
                                    fontWeight: FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                ),
                              ),
                              if (isPrimary) ...[
                                Container(
                                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer,
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    'الأساسية',
                                    style: TextStyle(
                                      color: colorScheme.onPrimaryContainer,
                                      fontSize: 11,
                                      fontWeight: FontWeight.bold,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                        );
                      }).toList(),
                    ),
                  ),
                ),
                const SizedBox(height: 12),

                // Action to link another organization (if supervisor)
                if (adminDelegate != null) ...[
                  FilledButton.icon(
                    style: FilledButton.styleFrom(
                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                    onPressed: () async {
                      Navigator.of(ctx).pop();
                      final result = await LinkDelegateToOrgSheet.show(
                        context,
                        delegate: delegate,
                        supervisor: adminDelegate!,
                      );
                      if (result == true) {
                        onRefresh?.call();
                      }
                    },
                    icon: const Icon(Icons.add_business_rounded, size: 18),
                    label: const Text('ربط بسلسلة / منظمة إضافية'),
                  ),
                ],
              ],
            ),
          ),
        );
      },
    );
  }

  Widget _buildMarketsRow(BuildContext context) {
    final rawList = delegate.allOrganizationNames.isNotEmpty
        ? delegate.allOrganizationNames
        : (delegate.organizationName.isNotEmpty
            ? [delegate.organizationName]
            : <String>[]);
    final allOrgs = rawList
        .map(formatChainDisplayName)
        .where((name) => name.isNotEmpty)
        .toSet()
        .toList();

    if (allOrgs.isEmpty) {
      return const SizedBox.shrink();
    }

    if (allOrgs.length == 1) {
      return Align(
        alignment: AlignmentDirectional.centerStart,
        child: _buildOrgBadge(context, allOrgs.first, maxWidth: 170),
      );
    }

    final int visibleCount = allOrgs.length > 2 ? 1 : 2;
    final int remainingCount = allOrgs.length - visibleCount;

    return InkWell(
      onTap: () => _showAllOrgsSheet(context, allOrgs),
      borderRadius: BorderRadius.circular(6),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          for (int i = 0; i < visibleCount; i++) ...[
            if (i > 0) const SizedBox(width: 4),
            Flexible(
              child: _buildOrgBadge(
                context,
                allOrgs[i],
                maxWidth: visibleCount == 1 ? 120 : 90,
              ),
            ),
          ],
          if (remainingCount > 0) ...[
            const SizedBox(width: 4),
            _buildMoreBadge(
              context,
              remainingCount,
              () => _showAllOrgsSheet(context, allOrgs),
            ),
          ],
        ],
      ),
    );
  }

  bool _isFathallaDelegate(Delegate delegate) {
    final orgName = delegate.organizationName.toLowerCase().trim();
    final orgUid = delegate.organizationUID.toLowerCase().trim();
    final allOrgs = delegate.allOrganizationNames.map((e) => e.toLowerCase().trim());
    return orgName.contains('fathalla') ||
        orgName.contains('فتح الله') ||
        orgName.contains('فتح_الله') ||
        orgUid.contains('fathalla') ||
        orgUid.contains('فتح الله') ||
        orgUid.contains('فتح_الله') ||
        orgUid == 'piiobfgxahaeurdjldgj' ||
        allOrgs.any((name) =>
            name.contains('fathalla') ||
            name.contains('فتح الله') ||
            name.contains('فتح_الله'));
  }

  Widget _buildActionPill({
    required BuildContext context,
    required Widget icon,
    required String label,
    required VoidCallback? onPressed,
    required String tooltip,
    required Color backgroundColor,
    required Color borderColor,
    required Color foregroundColor,
    double height = 30,
    double? width,
    double fontSize = 11,
  }) {
    return Tooltip(
      message: tooltip,
      child: Material(
        color: backgroundColor,
        borderRadius: BorderRadius.circular(10),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: onPressed,
          child: Container(
            height: height,
            width: width,
            padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(10),
              border: Border.all(color: borderColor, width: 1),
            ),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              mainAxisAlignment: MainAxisAlignment.center,
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                IconTheme(
                  data: IconThemeData(
                    color: foregroundColor,
                    size: height > 34 ? 17 : 14.5,
                  ),
                  child: icon,
                ),
                const SizedBox(width: 5),
                Text(
                  label,
                  style: TextStyle(
                    color: foregroundColor,
                    fontSize: fontSize,
                    fontWeight: FontWeight.bold,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildActionButtons(
    BuildContext context,
    ThemeData theme,
    AppLocalizations l10n,
  ) {
    final isSuperAdmin = adminDelegate?.role == UserRole.superAdmin;
    final isSupervisor = adminDelegate?.role == UserRole.admin ||
        adminDelegate?.position == DelegatePosition.supervisor;
    final isFathalla = _isFathallaDelegate(delegate);
    final canRequestDelete = isSupervisor && !isFathalla;
    final canEditProfile = adminDelegate != null &&
        canShowEditDelegateProfile(
          role: adminDelegate!.role,
          callerCompanyUID: adminDelegate!.companyUID,
          targetCompanyUID: delegate.companyUID,
          targetEditableStatus:
              isEditableDelegateProfileStatus(delegate.status),
        );

    final isDark = theme.brightness == Brightness.dark;
    final goldBg = const Color(0xFFB8860B).withValues(alpha: isDark ? 0.28 : 0.12);
    final goldBorder = const Color(0xFFD4AF37).withValues(alpha: isDark ? 0.6 : 0.45);
    final goldFg = isDark ? const Color(0xFFFFE082) : const Color(0xFF8D6200);

    // 1. Link Org Button
    final linkOrgBtn = _buildActionPill(
      context: context,
      icon: const Icon(Icons.add_business_rounded),
      label: canRequestDelete ? 'ربط بسلسلة' : 'ربط بسلاسل إضافية',
      backgroundColor: goldBg,
      borderColor: goldBorder,
      foregroundColor: goldFg,
      tooltip: 'ربط بسلسلة إضافية وسداد الاشتراك',
      height: canRequestDelete ? 30 : 40,
      width: canRequestDelete ? 104 : null,
      fontSize: canRequestDelete ? 10.5 : 11.5,
      onPressed: adminDelegate != null
          ? () async {
              final result = await LinkDelegateToOrgSheet.show(
                context,
                delegate: delegate,
                supervisor: adminDelegate!,
              );
              if (result == true) {
                onRefresh?.call();
              }
            }
          : null,
    );

    // 2. Delete Request Button (Supervisor only, non-Fathalla delegates)
    final deleteRequestBtn = canRequestDelete
        ? _buildActionPill(
            context: context,
            icon: const Icon(Icons.person_remove_rounded),
            label: 'طلب حذف',
            backgroundColor: Colors.red.withValues(alpha: isDark ? 0.22 : 0.10),
            borderColor: Colors.red.withValues(alpha: 0.4),
            foregroundColor: isDark ? Colors.red.shade300 : Colors.red.shade700,
            tooltip: 'إرسال طلب للإدارة العليا لحذف المندوب نهائياً',
            height: 30,
            width: 104,
            fontSize: 10.5,
            onPressed: () async {
              final result = await DeleteDelegateRequestSheet.show(
                context,
                delegate: delegate,
                supervisor: adminDelegate!,
              );
              if (result == true) {
                onRefresh?.call();
              }
            },
          )
        : null;

    final editBtn = canEditProfile
        ? _buildActionPill(
            context: context,
            icon: const Icon(Icons.edit_rounded),
            label: 'تعديل البيانات',
            backgroundColor: theme.colorScheme.primary.withValues(
              alpha: isDark ? 0.22 : 0.10,
            ),
            borderColor: theme.colorScheme.primary.withValues(alpha: 0.4),
            foregroundColor: isDark
                ? theme.colorScheme.primary
                : theme.colorScheme.primary,
            tooltip: 'تعديل الاسم أو الموبايل أو الصور',
            height: 30,
            width: 104,
            fontSize: 10.5,
            onPressed: () async {
              final result = await Navigator.of(context).push<bool>(
                MaterialPageRoute(
                  builder: (_) => EditDelegateProfileScreen(
                    supervisor: adminDelegate!,
                    delegate: delegate,
                  ),
                ),
              );
              if (result == true) {
                onRefresh?.call();
              }
            },
          )
        : null;

    // 3. Force Logout Button (SuperAdmin only)
    final logoutBtn = isSuperAdmin
        ? _buildActionPill(
            context: context,
            icon: const Icon(Icons.logout_rounded),
            label: 'خروج إجباري',
            backgroundColor: theme.colorScheme.error.withValues(
              alpha: isDark ? 0.25 : 0.12,
            ),
            borderColor: theme.colorScheme.error.withValues(alpha: 0.4),
            foregroundColor: theme.colorScheme.error,
            tooltip: 'تسجيل خروج إجباري للتحقق من الشركة',
            height: 30,
            width: 104,
            fontSize: 10.5,
            onPressed: () => _confirmForceLogout(context),
          )
        : null;

    final holdBtn = _showHoldControl
        ? _buildActionPill(
            context: context,
            icon: Icon(_isVisiblySuspended
                ? Icons.play_circle_outline_rounded
                : Icons.pause_circle_outline_rounded),
            label: _isVisiblySuspended ? 'إعادة تفعيل' : 'إيقاف المندوب',
            backgroundColor: theme.colorScheme.error.withValues(
              alpha: isDark ? 0.22 : 0.10,
            ),
            borderColor: theme.colorScheme.error.withValues(alpha: 0.4),
            foregroundColor: isDark
                ? theme.colorScheme.error
                : theme.colorScheme.error,
            tooltip: _isVisiblySuspended
                ? 'إعادة تفعيل المندوب (إزالة إيقاف الإدارة)'
                : 'إيقاف المندوب من قبل الإدارة',
            height: canRequestDelete ? 30 : 40,
            width: canRequestDelete ? 104 : null,
            fontSize: canRequestDelete ? 10.5 : 11.5,
            onPressed: () => _confirmSetHold(
              context,
              suspend: !_isVisiblySuspended,
            ),
          )
        : null;

    final extras = <Widget>[
      ?editBtn,
      if (canRequestDelete) ?deleteRequestBtn,
      if (isSuperAdmin) ?logoutBtn,
      if (_showHoldControl) ?holdBtn,
    ];
    if (extras.isEmpty) return linkOrgBtn;
    return Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.end,
      children: [
        linkOrgBtn,
        for (final extra in extras) ...[
          const SizedBox(height: 5),
          extra,
        ],
      ],
    );
  }

  Color _getStatusColor(BuildContext context, DelegateStatus status) {
    final colorScheme = Theme.of(context).colorScheme;
    switch (status) {
      case DelegateStatus.active:
      case DelegateStatus.approved:
        return colorScheme.primary;
      case DelegateStatus.suspended:
      case DelegateStatus.rejected:
        return colorScheme.error;
      case DelegateStatus.pending:
        return colorScheme.secondary;
    }
  }

  IconData _getStatusIcon(DelegateStatus status) {
    switch (status) {
      case DelegateStatus.active:
      case DelegateStatus.approved:
        return Icons.check_circle_rounded;
      case DelegateStatus.suspended:
      case DelegateStatus.rejected:
        return Icons.cancel_rounded;
      case DelegateStatus.pending:
        return Icons.schedule_rounded;
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
    final photoUrl = delegate.personalPhotoUrl;

    final selection = AdminDelegateSelectionScope.maybeOf(context);
    final isSelected = selection != null && selection.selectedUid == delegate.uid;
    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
        // Desktop list-detail: select instead of pushing the full page.
        if (selection != null) {
          selection.onSelect(delegate);
          return;
        }
        final result = await Navigator.of(context).push<bool>(
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
        if (result == true) {
          onRefresh?.call();
        }
      },
      child: Container(
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
        decoration: BoxDecoration(
          color: isSelected
              ? theme.colorScheme.secondaryContainer
              : theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.center,
          children: [
            // ── Avatar with Status Dot ──
            AppAvatar(
              imageUrl: photoUrl,
              fallbackText: delegate.firstName,
              radius: 20,
              backgroundColor: theme.colorScheme.primaryContainer,
              foregroundColor: theme.colorScheme.onPrimaryContainer,
              badge: Container(
                width: 11,
                height: 11,
                decoration: BoxDecoration(
                  color: statusColor,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: theme.colorScheme.surface,
                    width: 2,
                  ),
                ),
              ),
            ),
            const SizedBox(width: 10),

            // ── Delegate Info ──
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Row(
                    children: [
                      Flexible(
                        child: Text(
                          delegate.fullName,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            fontSize: 14,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 6),
                      Tooltip(
                        message: _getStatusText(context, delegate.status),
                        child: Icon(
                          _getStatusIcon(delegate.status),
                          size: 14,
                          color: statusColor,
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 5),
                  _buildMarketsRow(context),
                ],
              ),
            ),

            const SizedBox(width: 8),

            // ── Action Icons (2x2 Grid) ──
            _buildActionButtons(context, theme, l10n),
          ],
        ),
      ),
    );
  }
}



/// Optional selection hook for a list-detail layout (used by the web-only
/// desktop shell). When absent (mobile), tapping a delegate pushes the full
/// profile page exactly as before.
class AdminDelegateSelectionScope extends InheritedWidget {
  final String? selectedUid;
  final ValueChanged<Delegate> onSelect;

  const AdminDelegateSelectionScope({
    super.key,
    required this.selectedUid,
    required this.onSelect,
    required super.child,
  });

  static AdminDelegateSelectionScope? maybeOf(BuildContext context) =>
      context.dependOnInheritedWidgetOfExactType<AdminDelegateSelectionScope>();

  @override
  bool updateShouldNotify(AdminDelegateSelectionScope oldWidget) =>
      oldWidget.selectedUid != selectedUid || oldWidget.onSelect != onSelect;
}

/// Public detail view for one delegate: the same profile page the mobile
/// list pushes, embedded (no back button).
class AdminDelegateDetailView extends StatelessWidget {
  final Delegate delegate;

  const AdminDelegateDetailView({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      key: ValueKey(delegate.uid),
      create: (_) => sl<ProfileBloc>(),
      child: ProfileScreen(delegate: delegate, showBackButton: false),
    );
  }
}
