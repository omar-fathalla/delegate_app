import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_delegate_form_screen.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:delegate_app/core/services/session_management_service.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';

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
      if (mounted) {
        setState(() {
          _availableOrganizations = snap.docs.map((d) {
            final name = d.data()['name']?.toString() ?? d.id;
            return {'id': d.id, 'name': name};
          }).toList();
        });
      }
    } catch (_) {}
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  List<Delegate> _filterDelegates(List<Delegate> delegates) {
    final query = _searchController.text.toLowerCase().trim();
    return delegates.where((delegate) {
      final matchesName = delegate.fullName.toLowerCase().contains(query) ||
          delegate.phoneNumber.contains(query);
      final matchesStatus =
          _selectedStatus == null || delegate.status == _selectedStatus;
      final matchesOrg = _selectedOrgUID == null ||
          delegate.organizationUID == _selectedOrgUID;
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
          final filteredDelegates = _filterDelegates(allDelegates);

          // Build dynamic map of organizations from fetched orgs + loaded delegates
          final orgsMap = <String, String>{};
          for (final org in _availableOrganizations) {
            orgsMap[org['id']!] = org['name']!;
          }
          for (final d in allDelegates) {
            if (d.organizationUID.isNotEmpty) {
              orgsMap.putIfAbsent(
                d.organizationUID,
                () => d.organizationName.isNotEmpty
                    ? d.organizationName
                    : d.organizationUID,
              );
            }
          }

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

                      // ── Organization Filter Chips ──
                      if (orgsMap.length > 1) ...[
                        const SizedBox(height: 8),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: Row(
                            children: [
                              FilterChip(
                                avatar: _selectedOrgUID == null
                                    ? const Icon(Icons.check_rounded, size: 14)
                                    : const Icon(Icons.business_rounded,
                                        size: 14),
                                label: Text(l10n.all),
                                selected: _selectedOrgUID == null,
                                onSelected: (_) =>
                                    setState(() => _selectedOrgUID = null),
                              ),
                              ...orgsMap.entries.map((entry) {
                                final isSelected = _selectedOrgUID == entry.key;
                                final (chipBg, chipFg, chipBorder) =
                                    _getOrgBadgeColors(context, entry.value);
                                return Padding(
                                  padding:
                                      const EdgeInsetsDirectional.only(start: 6),
                                  child: FilterChip(
                                    avatar: isSelected
                                        ? Icon(Icons.check_rounded, size: 14, color: chipFg)
                                        : null,
                                    label: Text(entry.value),
                                    labelStyle: TextStyle(
                                      color: isSelected ? chipFg : null,
                                      fontWeight: isSelected
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                    ),
                                    selected: isSelected,
                                    selectedColor: chipBg,
                                    side: isSelected
                                        ? BorderSide(color: chipBorder)
                                        : null,
                                    onSelected: (_) => setState(() {
                                      _selectedOrgUID =
                                          isSelected ? null : entry.key;
                                    }),
                                  ),
                                );
                              }),
                            ],
                          ),
                        ),
                      ],

                      // ── Status Filter Chips ──
                      const SizedBox(height: 8),
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
                            const SizedBox(width: 6),
                            ...DelegateStatus.values.map((status) {
                              return Padding(
                                padding:
                                    const EdgeInsetsDirectional.only(end: 6),
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

/// Returns a tuple of (backgroundColor, foregroundColor, borderColor) for an organization
/// with distinct, recognizable colors for quick visual differentiation.
(Color bg, Color fg, Color border) _getOrgBadgeColors(
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

  Future<void> _makePhoneCall(BuildContext context, String rawPhone) async {
    final cleanPhone = rawPhone.replaceAll(RegExp(r'\s+'), '').trim();
    if (cleanPhone.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(
          content: Text('رقم الهاتف غير متوفر'),
          duration: Duration(seconds: 2),
        ),
      );
      return;
    }
    final uri = Uri.parse('tel:$cleanPhone');
    try {
      if (await canLaunchUrl(uri)) {
        await launchUrl(uri);
      } else {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text('تعذر إجراء المكالمة بالرقم $cleanPhone'),
              duration: const Duration(seconds: 2),
            ),
          );
        }
      }
    } catch (e) {
      if (context.mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('حدث خطأ أثناء محاولة الاتصال: $e'),
            duration: const Duration(seconds: 2),
          ),
        );
      }
    }
  }

  Widget _buildOrgBadge(BuildContext context, String orgName) {
    if (orgName.isEmpty) return const SizedBox.shrink();
    final (bg, fg, border) = _getOrgBadgeColors(context, orgName);
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(6),
        border: Border.all(color: border, width: 0.8),
      ),
      child: Text(
        orgName,
        style: TextStyle(
          color: fg,
          fontSize: 10.5,
          fontWeight: FontWeight.w600,
        ),
      ),
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

    return InkWell(
      borderRadius: BorderRadius.circular(12),
      onTap: () async {
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
          color: theme.colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
          borderRadius: BorderRadius.circular(12),
          border: Border.all(
            color: theme.colorScheme.outlineVariant.withValues(alpha: 0.35),
          ),
        ),
        child: Row(
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
                  if (delegate.organizationName.isNotEmpty) ...[
                    const SizedBox(height: 4),
                    _buildOrgBadge(context, delegate.organizationName),
                  ],
                ],
              ),
            ),

            const SizedBox(width: 6),

            // ── Action Icons (Call, Attendance & Profile) ──
            Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primary.withValues(
                      alpha: theme.brightness == Brightness.dark ? 0.25 : 0.15,
                    ),
                    foregroundColor: theme.colorScheme.primary,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                  onPressed: delegate.phoneNumber.trim().isNotEmpty
                      ? () => _makePhoneCall(context, delegate.phoneNumber)
                      : null,
                  tooltip: delegate.phoneNumber.trim().isNotEmpty
                      ? 'اتصال بالمندوب (${delegate.phoneNumber})'
                      : 'رقم الهاتف غير متوفر',
                  icon: const Icon(Icons.phone_in_talk_rounded, size: 18),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.primaryContainer
                        .withValues(alpha: 0.7),
                    foregroundColor: theme.colorScheme.onPrimaryContainer,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
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
                  tooltip: l10n.viewAttendance,
                  icon: const Icon(Icons.history_rounded, size: 18),
                ),
                const SizedBox(width: 6),
                IconButton.filledTonal(
                  visualDensity: VisualDensity.compact,
                  style: IconButton.styleFrom(
                    backgroundColor: theme.colorScheme.surfaceContainerHighest,
                    foregroundColor: theme.colorScheme.onSurfaceVariant,
                    padding: const EdgeInsets.all(8),
                    minimumSize: const Size(36, 36),
                  ),
                  onPressed: () async {
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
                  tooltip: l10n.viewProfileData,
                  icon: const Icon(Icons.person_search_rounded, size: 18),
                ),
                if (adminDelegate?.role == UserRole.superAdmin) ...[
                  const SizedBox(width: 6),
                  IconButton.filledTonal(
                    visualDensity: VisualDensity.compact,
                    style: IconButton.styleFrom(
                      backgroundColor: theme.colorScheme.error.withValues(
                        alpha: theme.brightness == Brightness.dark ? 0.25 : 0.15,
                      ),
                      foregroundColor: theme.colorScheme.error,
                      padding: const EdgeInsets.all(8),
                      minimumSize: const Size(36, 36),
                    ),
                    onPressed: () => _confirmForceLogout(context),
                    tooltip: 'تسجيل خروج إجباري للتحقق من الشركة',
                    icon: const Icon(Icons.logout_rounded, size: 18),
                  ),
                ],
              ],
            ),
          ],
        ),
      ),
    );
  }
}
