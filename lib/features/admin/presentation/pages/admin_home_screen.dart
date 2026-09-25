import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_state.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/delegate_camera_capture_screen.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/pages/company_penalties_settings_page.dart';
import 'package:delegate_app/features/admin/domain/entities/delegate_subscription_request.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/admin/presentation/pages/delegate_subscription_requests_page.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/admin/presentation/pages/add_delegate_form_screen.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/attendance/presentation/pages/attendance_screen.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';

class AdminHomeScreen extends StatelessWidget {
  final Delegate adminDelegate;

  const AdminHomeScreen({super.key, required this.adminDelegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AdminDashboardBloc>()
        ..add(
          LoadDashboard(
            organizationUID: adminDelegate.companyUID.isNotEmpty
                ? ''
                : adminDelegate.organizationUID,
            companyUID: adminDelegate.companyUID,
          ),
        ),
      child: _AdminHomeBody(adminDelegate: adminDelegate),
    );
  }
}

class _AdminHomeBody extends StatefulWidget {
  final Delegate adminDelegate;

  const _AdminHomeBody({required this.adminDelegate});

  @override
  State<_AdminHomeBody> createState() => _AdminHomeBodyState();
}

class _AdminHomeBodyState extends State<_AdminHomeBody> {
  static final Map<String, List<String>> _orgsMemoryCache = {};
  List<String> _supervisorOrganizations = [];

  Delegate get adminDelegate => widget.adminDelegate;

  @override
  void initState() {
    super.initState();
    _loadCachedAndFreshOrganizations();
  }

  String get _cacheKey =>
      widget.adminDelegate.companyUID.isNotEmpty
          ? widget.adminDelegate.companyUID
          : (widget.adminDelegate.companyName.isNotEmpty
              ? widget.adminDelegate.companyName
              : widget.adminDelegate.organizationUID);

  bool get _isArabic => sl<LocaleProvider>().isArabic;

  Future<void> _loadCachedAndFreshOrganizations({bool forceRefresh = false}) async {
    final key = _cacheKey;
    if (key.isEmpty) return;
    final isArabic = _isArabic;

    // 1. In-memory cache first (0ms)
    if (!forceRefresh && _orgsMemoryCache.containsKey(key)) {
      if (mounted) {
        setState(() {
          _supervisorOrganizations = List.from(_orgsMemoryCache[key]!);
        });
      }
      return;
    }

    // 2. Persistent cache (SharedPreferences)
    if (!forceRefresh) {
      try {
        final prefs = await SharedPreferences.getInstance();
        final cached = prefs.getStringList('supervisor_orgs_$key');
        if (cached != null && cached.isNotEmpty) {
          _orgsMemoryCache[key] = cached;
          if (mounted) {
            setState(() {
              _supervisorOrganizations = cached;
            });
          }
        }
      } catch (_) {}
    }

    // 3. Fallback to supervisor's own organization if empty
    if (_supervisorOrganizations.isEmpty &&
        widget.adminDelegate.organizationName.isNotEmpty) {
      final initialOrg = _normalizeOrgName(
        widget.adminDelegate.organizationName,
        isArabic,
      );
      if (initialOrg.isNotEmpty) {
        _supervisorOrganizations = [initialOrg];
      }
    }

    // 4. Background revalidation from Firestore & Delegate usecase
    _fetchFreshOrganizations(key, isArabic);
  }

  Future<void> _fetchFreshOrganizations(String key, bool isArabic) async {
    try {
      final Set<String> collected = {};

      // Add supervisor's own org
      if (widget.adminDelegate.organizationName.isNotEmpty) {
        final norm = _normalizeOrgName(widget.adminDelegate.organizationName, isArabic);
        if (norm.isNotEmpty) collected.add(norm);
      }

      // Query delegates via GetCompanyDelegates
      if (widget.adminDelegate.companyUID.isNotEmpty) {
        try {
          final result = await sl<GetCompanyDelegates>()(
            GetCompanyDelegatesParams(
              organizationUID: '',
              companyUID: widget.adminDelegate.companyUID,
            ),
          );
          result.fold(
            (_) {},
            (delegates) {
              for (final d in delegates) {
                if (d.organizationName.isNotEmpty) {
                  final norm = _normalizeOrgName(d.organizationName, isArabic);
                  if (norm.isNotEmpty) collected.add(norm);
                }
              }
            },
          );
        } catch (_) {}
      }

      // Also query users collection by companyUID and companyName
      try {
        final List<Future<QuerySnapshot<Map<String, dynamic>>>> queries = [];
        if (widget.adminDelegate.companyUID.isNotEmpty) {
          queries.add(
            FirebaseFirestore.instance
                .collection('users')
                .where('companyUID', isEqualTo: widget.adminDelegate.companyUID)
                .get(),
          );
        }
        if (widget.adminDelegate.companyName.isNotEmpty) {
          queries.add(
            FirebaseFirestore.instance
                .collection('users')
                .where('companyName', isEqualTo: widget.adminDelegate.companyName)
                .get(),
          );
        }
        final snapshots = await Future.wait(queries);
        for (final snap in snapshots) {
          for (final doc in snap.docs) {
            final data = doc.data();
            final org = data['organizationName']?.toString().trim() ?? '';
            if (org.isNotEmpty) {
              final norm = _normalizeOrgName(org, isArabic);
              if (norm.isNotEmpty) collected.add(norm);
            }
          }
        }
      } catch (_) {}

      // If still only 1 org, check if company is registered in other organizations
      if (widget.adminDelegate.companyUID.isNotEmpty) {
        try {
          final orgsSnap = await FirebaseFirestore.instance
              .collection('organizations')
              .get()
              .timeout(const Duration(seconds: 4));
          final futures = orgsSnap.docs.map((orgDoc) async {
            try {
              final cDoc = await FirebaseFirestore.instance
                  .collection('organizations')
                  .doc(orgDoc.id)
                  .collection('companies')
                  .doc(widget.adminDelegate.companyUID)
                  .get()
                  .timeout(const Duration(seconds: 3));
              if (cDoc.exists) {
                final orgName = orgDoc.data()['name']?.toString() ?? '';
                final norm = _normalizeOrgName(orgName, isArabic);
                if (norm.isNotEmpty) return norm;
              }
            } catch (_) {}
            return null;
          });
          final results = await Future.wait(futures);
          for (final norm in results) {
            if (norm != null && norm.isNotEmpty) collected.add(norm);
          }
        } catch (_) {}
      }

      final list = collected.toList();
      if (list.isNotEmpty && mounted) {
        _orgsMemoryCache[key] = list;
        try {
          final prefs = await SharedPreferences.getInstance();
          await prefs.setStringList('supervisor_orgs_$key', list);
        } catch (_) {}
        setState(() {
          _supervisorOrganizations = list;
        });
      }
    } catch (_) {}
  }

  String _normalizeOrgName(String raw, bool isArabic) {
    final clean = raw.trim();
    final lower = clean.toLowerCase();
    if (lower.contains('fathalla') || clean.contains('فتح الله') || clean.contains('فتح_الله')) {
      return isArabic ? 'فتح الله ماركت' : 'Fathalla Market';
    }
    if (lower.contains('gomla') || clean.contains('جملة')) {
      return isArabic ? 'جملة ماركت' : 'Gomla Market';
    }
    if (lower.contains('zahran') || clean.contains('زهران')) {
      return isArabic ? 'زهران ماركت' : 'Zahran Market';
    }
    if (lower.contains('carrefour') || clean.contains('كارفور')) {
      return isArabic ? 'كارفور' : 'Carrefour';
    }
    if (lower.contains('beit') || clean.contains('بيت الجملة')) {
      return isArabic ? 'بيت الجملة' : 'Beit El Gomla';
    }
    return clean;
  }

  Color _getOrgAccentColor(String orgName) {
    final lower = orgName.toLowerCase();
    if (lower.contains('fathalla') || orgName.contains('فتح الله') || orgName.contains('فتح_الله')) {
      return const Color(0xFFEF4444); // Crimson red
    }
    if (lower.contains('gomla') || orgName.contains('جملة')) {
      return const Color(0xFFF59E0B); // Warm amber/gold
    }
    if (lower.contains('zahran') || orgName.contains('زهران')) {
      return const Color(0xFF10B981); // Emerald green
    }
    if (lower.contains('carrefour') || orgName.contains('كارفور')) {
      return const Color(0xFF0EA5E9); // Sky blue
    }
    if (lower.contains('beit') || orgName.contains('بيت الجملة')) {
      return const Color(0xFF8B5CF6); // Purple
    }
    return const Color(0xFF14B8A6); // Teal fallback
  }

  Widget _buildOrgBadgeChip(String orgName, bool isArabic) {
    final accentColor = _getOrgAccentColor(orgName);
    return Container(
      padding: const EdgeInsets.symmetric(
        horizontal: 10,
        vertical: 4,
      ),
      decoration: BoxDecoration(
        color: accentColor.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(20),
        border: Border.all(
          color: accentColor.withValues(alpha: 0.7),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.storefront_rounded,
            size: 13,
            color: accentColor.withValues(alpha: 0.95),
          ),
          const SizedBox(width: 5),
          Text(
            orgName,
            style: const TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: Colors.white,
              letterSpacing: 0.2,
            ),
          ),
        ],
      ),
    );
  }

  void _showAttendanceDetailsSheet(BuildContext context, String initialFilter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return _AttendanceDetailsBottomSheet(
          adminDelegate: adminDelegate,
          initialFilter: initialFilter,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return RefreshIndicator(
      onRefresh: () async {
        AdminDashboardBloc.clearCache();
        _loadCachedAndFreshOrganizations(forceRefresh: true);
        context.read<AdminDashboardBloc>().add(
          LoadDashboard(
            organizationUID: adminDelegate.companyUID.isNotEmpty
                ? ''
                : adminDelegate.organizationUID,
            companyUID: adminDelegate.companyUID,
          ),
        );
      },
      child: ListView(
        padding: const EdgeInsets.fromLTRB(16, 12, 16, 32),
        children: [
          // 1. الكارت الترحيبي والتعريفي الرئيسي بمسؤوليات مشرف الشركة / المدير
          _buildRoleWelcomeBanner(context, theme.colorScheme, isArabic),

          // 2. كارت ميزة إضافة مناديب السلاسل والمنظمات الأخرى لمشرفي الشركات
          if (_isCompanySupervisor) ...[
            const SizedBox(height: 16),
            _buildMultiOrgDelegatesBanner(context, theme.colorScheme, isArabic),
          ],

          const SizedBox(height: 20),

          // Section title: نظرة عامة اليوم
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: theme.colorScheme.primary,
                size: 24,
              ),
              const SizedBox(width: 8),
              Text(
                l10n.todayOverview,
                style: theme.textTheme.titleMedium?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            _formatDate(context),
            style: theme.textTheme.bodySmall?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 16),

          // Summary Cards
          BlocBuilder<AdminDashboardBloc, AdminDashboardState>(
            builder: (context, state) {
              if (state is AdminDashboardLoading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (state is AdminDashboardError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.message,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            AdminDashboardBloc.clearCache();
                            context.read<AdminDashboardBloc>().add(
                              LoadDashboard(
                                organizationUID: adminDelegate.companyUID.isNotEmpty
                                    ? ''
                                    : adminDelegate.organizationUID,
                                companyUID: adminDelegate.companyUID,
                              ),
                            );
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (state is AdminDashboardLoaded) {
                final summary = state.summary;
                final canSeeCompaniesCount =
                    adminDelegate.role == UserRole.superAdmin ||
                    adminDelegate.role == UserRole.marketing;
                return Column(
                  children: [
                    // بطاقة "عدد الشركات" تظهر فقط للمدير العام والتسويق
                    if (canSeeCompaniesCount) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _CompactSummaryCard(
                              icon: Icons.business_rounded,
                              title: 'عدد الشركات',
                              value: '${summary.totalCompanies}',
                              color: theme.colorScheme.tertiary,
                              backgroundColor: theme
                                  .colorScheme
                                  .tertiaryContainer
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _CompactSummaryCard(
                              icon: Icons.groups_rounded,
                              title: l10n.totalDelegates,
                              value: '${summary.totalDelegates}',
                              color: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.5),
                              onTap: () =>
                                  _showAttendanceDetailsSheet(context, 'all'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // مشرفين: 3 بطاقات في صف واحد بشكل مضغوط
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _CompactSummaryCard(
                                icon: Icons.groups_rounded,
                                title: l10n.totalDelegates,
                                value: '${summary.totalDelegates}',
                                color: theme.colorScheme.primary,
                                backgroundColor: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
                                onTap: () =>
                                    _showAttendanceDetailsSheet(context, 'all'),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactSummaryCard(
                                icon: Icons.check_circle_rounded,
                                title: l10n.checkedInToday,
                                value: '${summary.checkedInToday}',
                                color: theme.colorScheme.secondary,
                                backgroundColor: theme
                                    .colorScheme
                                    .secondaryContainer
                                    .withValues(alpha: 0.5),
                                onTap: () => _showAttendanceDetailsSheet(
                                    context, 'checked_in'),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactSummaryCard(
                                icon: Icons.cancel_rounded,
                                title: l10n.absentToday,
                                value: '${summary.absentToday}',
                                color: theme.colorScheme.onSurfaceVariant,
                                backgroundColor: theme
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.7),
                                onTap: () =>
                                    _showAttendanceDetailsSheet(context, 'absent'),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),

          // ── Quick Actions for Company Admin / Supervisor ──
          if (adminDelegate.role == UserRole.admin || adminDelegate.role == UserRole.organizationAdmin) ...[
            const SizedBox(height: 22),
            Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  color: theme.colorScheme.primary,
                  size: 24,
                ),
                const SizedBox(width: 8),
                Text(
                  'إجراءات سريعة',
                  style: theme.textTheme.titleMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            // ── 1. Delegate Subscription & Approval Requests (شاشة الاعتمادات وطلبات المناديب) ──
            Card(
              elevation: 0,
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
                side: BorderSide(
                  color: const Color(0xFFD4AF37).withValues(alpha: 0.45),
                  width: 1.2,
                ),
              ),
              color: theme.brightness == Brightness.dark
                  ? const Color(0xFF2B2108)
                  : const Color(0xFFFFFDF5),
              child: InkWell(
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => DelegateSubscriptionRequestsPage(
                        currentAdmin: adminDelegate,
                      ),
                    ),
                  );
                },
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          gradient: const LinearGradient(
                            colors: [Color(0xFFB8860B), Color(0xFF8B6508)],
                            begin: Alignment.topLeft,
                            end: Alignment.bottomRight,
                          ),
                          borderRadius: BorderRadius.circular(12),
                          boxShadow: [
                            BoxShadow(
                              color: const Color(0xFFB8860B).withValues(alpha: 0.3),
                              blurRadius: 6,
                              offset: const Offset(0, 3),
                            ),
                          ],
                        ),
                        child: const Icon(
                          Icons.how_to_reg_rounded,
                          color: Colors.white,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              children: [
                                Flexible(
                                  child: Text(
                                    'شاشة الاعتمادات وطلبات المناديب',
                                    style: TextStyle(
                                      fontWeight: FontWeight.bold,
                                      fontSize: 14.5,
                                      color: theme.colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                StreamBuilder<List<DelegateSubscriptionRequest>>(
                                  stream: sl<DelegateSubscriptionRepository>().getSubscriptionRequestsStream(
                                    statusFilter: SubscriptionRequestStatus.pending,
                                    companyUID: adminDelegate.role == UserRole.admin ? adminDelegate.companyUID : null,
                                    organizationUID: adminDelegate.role == UserRole.organizationAdmin ? adminDelegate.organizationUID : null,
                                  ),
                                  builder: (context, snapshot) {
                                    final count = snapshot.data?.length ?? 0;
                                    if (count == 0) return const SizedBox.shrink();
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                                      decoration: BoxDecoration(
                                        color: const Color(0xFFD97706),
                                        borderRadius: BorderRadius.circular(10),
                                      ),
                                      child: Text(
                                        '$count معلقة',
                                        style: const TextStyle(
                                          color: Colors.white,
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                        ),
                                      ),
                                    );
                                  },
                                ),
                              ],
                            ),
                            const SizedBox(height: 3),
                            Text(
                              adminDelegate.role == UserRole.admin
                                  ? 'متابعة حالة طلبات المناديب: تم الاعتماد، قيد الانتظار، والمرفوضة'
                                  : 'مراجعة واعتماد طلبات تسجيل واشتراكات المناديب الجديدة',
                              style: TextStyle(
                                fontSize: 12,
                                color: theme.colorScheme.onSurfaceVariant,
                                height: 1.25,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      Icon(
                        Icons.arrow_forward_ios_rounded,
                        size: 16,
                        color: theme.colorScheme.outline,
                      ),
                    ],
                  ),
                ),
              ),
            ),
            const SizedBox(height: 10),

            // ── 2. Camera Field Capture ──
            if (adminDelegate.role != UserRole.organizationAdmin) ...[
              Card(
                clipBehavior: Clip.antiAlias,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: theme.colorScheme.primary.withValues(alpha: 0.3)),
                ),
                color: theme.colorScheme.primaryContainer.withValues(alpha: 0.2),
                child: ListTile(
                  leading: Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: theme.colorScheme.primary,
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: const Icon(
                      Icons.photo_camera_rounded,
                      color: Colors.white,
                      size: 24,
                    ),
                  ),
                  title: const Text(
                    'تصوير العروض الميدانية بالكاميرا',
                    style: TextStyle(fontWeight: FontWeight.bold),
                  ),
                  subtitle: const Text('التقاط وتوثيق صور العروض الميدانية والمنتجات مباشرة لشركتكم'),
                  trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                  onTap: () {
                    Navigator.of(context).push(
                      MaterialPageRoute(
                        builder: (_) => BlocProvider(
                          create: (_) => sl<PhotoPermissionBloc>(),
                          child: DelegateCameraCaptureScreen(delegate: adminDelegate),
                        ),
                      ),
                    );
                  },
                ),
              ),
              const SizedBox(height: 10),
            ],
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.camera_alt_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                title: const Text(
                  'إدارة أذونات التصوير',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  adminDelegate.role == UserRole.organizationAdmin
                      ? 'استعراض أذونات التصوير ومتابعة تقارير المناديب (للعلم فقط)'
                      : 'طلب إذن تصوير جديد، تفعيل/تعطيل الأذونات، ومتابعة تقارير المناديب',
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  context.push('/photo-permissions/supervisor', extra: adminDelegate);
                },
              ),
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.photo_library_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                title: const Text(
                  'تقارير الصور',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('استعراض تقارير الصور الشهرية المرفوعة بواسطة مناديب الشركة'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider(
                        create: (context) => sl<PhotoPermissionBloc>(),
                        child: MonthlyPhotoReportScreen(
                          delegate: adminDelegate,
                          showAppBar: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
            const SizedBox(height: 10),
            Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.gavel_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                title: const Text(
                  'سجل المخالفات والغرامات',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('متابعة الغرامات والإشعارات الصادرة بحق مناديب الشركة وتفاصيلها'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider(
                        create: (_) => sl<PenaltyBloc>(),
                        child: CompanyPenaltiesSettingsPage(
                          delegate: adminDelegate,
                          showAppBar: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // ── Quick Actions for Marketing / Super Admin ──
          if (adminDelegate.role == UserRole.marketing || adminDelegate.role == UserRole.superAdmin) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.dashboard_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'الإجراءات السريعة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Action Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/admin/company-search');
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('البحث عن الشركات'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // يمكن إضافة إجراءات أخرى هنا
                    },
                    icon: const Icon(Icons.business_rounded),
                    label: const Text('إدارة الشركات'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],
        ],
      ),
    );
  }

  /// الكارت الترحيبي والتعريفي الرئيسي بمسؤوليات الدور
  Widget _buildRoleWelcomeBanner(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    final displayName = adminDelegate.fullName.isNotEmpty
        ? adminDelegate.fullName
        : 'مشرف الشركة';
    final companyName = adminDelegate.companyName.isNotEmpty
        ? adminDelegate.companyName
        : (adminDelegate.organizationName.isNotEmpty ? adminDelegate.organizationName : '');
    final isOrgAdmin = adminDelegate.role == UserRole.organizationAdmin;
    final isSuperAdmin = adminDelegate.role == UserRole.superAdmin;
    final isMarketing = adminDelegate.role == UserRole.marketing;

    String roleBadge = isArabic ? 'مشرف الشركة' : 'Company Supervisor';
    IconData roleIcon = Icons.supervised_user_circle_rounded;

    if (isOrgAdmin) {
      roleBadge = isArabic ? 'المدير العام للمؤسسة' : 'General Manager';
      roleIcon = Icons.admin_panel_settings_rounded;
    } else if (isSuperAdmin) {
      roleBadge = isArabic ? 'المشرف العام' : 'Super Admin';
      roleIcon = Icons.security_rounded;
    } else if (isMarketing) {
      roleBadge = isArabic ? 'إدارة التسويق' : 'Marketing Admin';
      roleIcon = Icons.campaign_rounded;
    }

    return Container(
      width: double.infinity,
      decoration: BoxDecoration(
        gradient: LinearGradient(
          colors: [
            colorScheme.primary,
            colorScheme.primary.withValues(alpha: 0.85),
            colorScheme.secondary.withValues(alpha: 0.9),
          ],
          begin: AlignmentDirectional.topStart,
          end: AlignmentDirectional.bottomEnd,
        ),
        borderRadius: BorderRadius.circular(24),
        boxShadow: [
          BoxShadow(
            color: colorScheme.primary.withValues(alpha: 0.25),
            blurRadius: 16,
            offset: const Offset(0, 8),
          ),
        ],
      ),
      padding: const EdgeInsets.all(20),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          // رأس الكارت: الترحيب والاسم وشارة الشركة والوظيفة
          Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      isArabic ? 'أهلاً بك، $displayName' : 'Welcome, $displayName',
                      style: const TextStyle(
                        fontSize: 20,
                        fontWeight: FontWeight.bold,
                        color: Colors.white,
                        letterSpacing: 0.3,
                      ),
                    ),
                    const SizedBox(height: 6),
                    // شارة الشركة / المنظمة
                    if (companyName.isNotEmpty) ...[
                      Row(
                        children: [
                          Icon(
                            Icons.business_rounded,
                            size: 14,
                            color: Colors.white.withValues(alpha: 0.85),
                          ),
                          const SizedBox(width: 6),
                          Flexible(
                            child: Text(
                              companyName,
                              style: TextStyle(
                                fontSize: 13,
                                fontWeight: FontWeight.w600,
                                color: Colors.white.withValues(alpha: 0.95),
                              ),
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 8),
                    ],
                    // شارة المسمى الوظيفي (على صف بمفرده)
                    Container(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 4,
                      ),
                      decoration: BoxDecoration(
                        color: Colors.white.withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(20),
                        border: Border.all(
                          color: Colors.white.withValues(alpha: 0.3),
                          width: 1,
                        ),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(
                            roleIcon,
                            size: 14,
                            color: Colors.white,
                          ),
                          const SizedBox(width: 6),
                          Text(
                            roleBadge,
                            style: const TextStyle(
                              fontSize: 11,
                              fontWeight: FontWeight.bold,
                              color: Colors.white,
                            ),
                          ),
                        ],
                      ),
                    ),
                    // رُقاقات سلاسل المنظمات التابع لها مناديب المشرف (صف منفصل متصل يلتف معاً)
                    if (_isCompanySupervisor && _supervisorOrganizations.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 8,
                        runSpacing: 6,
                        crossAxisAlignment: WrapCrossAlignment.center,
                        children: _supervisorOrganizations.map(
                          (org) => _buildOrgBadgeChip(org, isArabic),
                        ).toList(),
                      ),
                    ],
                  ],
                ),
              ),
              // صورة البروفايل بالأفاتار الدائري
              Builder(
                builder: (context) {
                  final photoUrl = widget.adminDelegate.personalPhotoUrl ??
                      (widget.adminDelegate.documents
                          .where((d) =>
                              d.documentKey == DocumentKey.personalPhoto &&
                              d.documentURL.isNotEmpty)
                          .firstOrNull
                          ?.documentURL) ??
                      FirebaseAuth.instance.currentUser?.photoURL;

                  return Container(
                    decoration: BoxDecoration(
                      shape: BoxShape.circle,
                      border: Border.all(
                        color: Colors.white.withValues(alpha: 0.4),
                        width: 2,
                      ),
                      boxShadow: [
                        BoxShadow(
                          color: Colors.black.withValues(alpha: 0.15),
                          blurRadius: 8,
                          offset: const Offset(0, 2),
                        ),
                      ],
                    ),
                    child: AppAvatar(
                      imageUrl: photoUrl,
                      fallbackText: widget.adminDelegate.firstName,
                      radius: 26,
                      backgroundColor: Colors.white.withValues(alpha: 0.22),
                      foregroundColor: Colors.white,
                      fallbackIcon: isOrgAdmin || isSuperAdmin
                          ? Icons.shield_rounded
                          : Icons.person_pin_rounded,
                    ),
                  );
                },
              ),
            ],
          ),

          const SizedBox(height: 16),
          Divider(color: Colors.white.withValues(alpha: 0.25), height: 1),
          const SizedBox(height: 14),

          // دليل المهام والمسؤوليات
          Text(
            isArabic
                ? (isOrgAdmin
                    ? '📋 دليل المهام والمسؤوليات للمدير العام:'
                    : '📋 دليل المهام والمسؤوليات لمشرف الشركة:')
                : '📋 Your Core Responsibilities:',
            style: const TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.bold,
              color: Colors.white,
            ),
          ),
          const SizedBox(height: 10),

          if (isOrgAdmin) ...[
            _buildDutyBullet(
              icon: Icons.corporate_fare_rounded,
              title: isArabic
                  ? '1. الإشراف العام على العمليات والفروع:'
                  : '1. Overall Operations & Branch Oversight:',
              desc: isArabic
                  ? 'متابعة تقارير الفروع وسير العمل اليومي للمناديب والشركات على مستوى المؤسسة بالكامل.'
                  : 'Monitor branch performance and delegate attendance across all operating companies.',
            ),
            const SizedBox(height: 8),
            _buildDutyBullet(
              icon: Icons.gavel_rounded,
              title: isArabic
                  ? '2. الاعتماد النهائي للمخالفات والغرامات:'
                  : '2. Final Approval on Significant Penalties:',
              desc: isArabic
                  ? 'مراجعة واعتماد الغرامات والمخالفات الميدانية الكبرى المحالة من إدارة التسويق (> 1000 ج.م).'
                  : 'Review and grant final authorization on large penalties escalated by marketing (> 1000 EGP).',
            ),
            const SizedBox(height: 8),
            _buildDutyBullet(
              icon: Icons.analytics_rounded,
              title: isArabic
                  ? '3. متابعة تقارير الحضور والإنجاز:'
                  : '3. Performance & Attendance Analytics:',
              desc: isArabic
                  ? 'تحليل مؤشرات الأداء ونسب حضور المناديب والتقارير الشهرية المصورة على مستوى الفروع.'
                  : 'Analyze key performance metrics, check-in compliance, and monthly photo reports.',
            ),
          ] else ...[
            _buildDutyBullet(
              icon: Icons.groups_rounded,
              title: isArabic
                  ? '1. متابعة حضور وانضباط مناديب الشركة:'
                  : '1. Delegate Attendance & Compliance Tracking:',
              desc: isArabic
                  ? 'الإشراف اليومي على تسجيل حضور وغياب مناديب شركتكم بالفرع ومتابعة نسب التواجد والالتزام بمواعيد العمل.'
                  : 'Daily oversight of vendor delegates check-ins, attendance rates, and adherence to working hours.',
            ),
            const SizedBox(height: 8),
            _buildDutyBullet(
              icon: Icons.camera_enhance_rounded,
              title: isArabic
                  ? '2. إدارة وتفعيل أذونات التصوير:'
                  : '2. Manage & Activate Photo Permissions:',
              desc: isArabic
                  ? 'تقديم طلبات إذن التصوير، وتفعيل أو تعطيل الأذونات لمناديب الشركة، ومتابعة رفع التقارير الشهرية المصورة.'
                  : 'Request, activate, or disable photo permits for delegates, and inspect monthly uploaded photo reports.',
            ),
            const SizedBox(height: 8),
            _buildDutyBullet(
              icon: Icons.gavel_rounded,
              title: isArabic
                  ? '3. متابعة وضبط المخالفات والغرامات:'
                  : '3. Track Penalties & Rule Enforcement:',
              desc: isArabic
                  ? 'مراجعة المخالفات والغرامات المسجلة على مناديب الشركة، والتحقق من تفاصيلها لتلافي الخصومات وضمان الالتزام.'
                  : 'Review penalties recorded on vendor delegates, verify incident details, and prevent fine deductions.',
            ),
            const SizedBox(height: 8),
            _buildDutyBullet(
              icon: Icons.assignment_turned_in_rounded,
              title: isArabic
                  ? '4. توجيه وتكليف مهام العمل:'
                  : '4. Assign & Supervise Field Tasks:',
              desc: isArabic
                  ? 'توزيع المهام الميدانية والتعليمات الترويجية على المناديب ومتابعة نسب الإنجاز عبر تبويب المهام.'
                  : 'Distribute field assignments to company delegates and monitor task completion status in real time.',
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildDutyBullet({
    required IconData icon,
    required String title,
    required String desc,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: Colors.black.withValues(alpha: 0.12),
        borderRadius: BorderRadius.circular(12),
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(
            icon,
            color: Colors.white,
            size: 18,
          ),
          const SizedBox(width: 8),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  title,
                  style: const TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: Colors.white,
                  ),
                ),
                const SizedBox(height: 2),
                Text(
                  desc,
                  style: TextStyle(
                    fontSize: 11,
                    color: Colors.white.withValues(alpha: 0.9),
                    height: 1.3,
                  ),
                ),
              ],
            ),
          ),
        ],
      ),
    );
  }

  bool get _isCompanySupervisor {
    final isOrgAdmin = adminDelegate.role == UserRole.organizationAdmin;
    final isSuperAdmin = adminDelegate.role == UserRole.superAdmin;
    final isMarketing = adminDelegate.role == UserRole.marketing;
    return !isOrgAdmin && !isSuperAdmin && !isMarketing;
  }

  /// كارت ميزة إضافة مناديب السلاسل والمنظمات التجارية الأخرى للشركات
  Widget _buildMultiOrgDelegatesBanner(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    return M3StaggeredItem(
      index: 1,
      child: Container(
        width: double.infinity,
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainer,
          borderRadius: BorderRadius.circular(20),
          border: Border.all(
            color: colorScheme.primary.withValues(alpha: 0.2),
            width: 1.5,
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.04),
              blurRadius: 10,
              offset: const Offset(0, 3),
            ),
          ],
        ),
        padding: const EdgeInsets.all(18),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // الشارة الترويجية (Badge) - ميزة حصرية للشركات بأيقونة جوجل
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                  decoration: BoxDecoration(
                    color: colorScheme.primaryContainer,
                    borderRadius: BorderRadius.circular(20),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.business_rounded,
                        size: 14,
                        color: colorScheme.onPrimaryContainer,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        isArabic ? 'ميزة حصرية للشركات' : 'Exclusive for Companies',
                        style: TextStyle(
                          fontSize: 11.5,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.onPrimaryContainer,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // عنوان الكارت بأيقونة جوجل ماتيريال (بدون إيموجي)
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(7),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    Icons.hub_rounded,
                    color: colorScheme.primary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Text(
                    isArabic
                        ? 'متابعة مناديبك في كافة السلاسل من مكان واحد'
                        : 'Track Your Delegates Across All Retail Chains',
                    style: TextStyle(
                      fontSize: 15.5,
                      fontWeight: FontWeight.bold,
                      color: colorScheme.onSurface,
                      letterSpacing: 0.1,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // نص الوصف
            Text(
              isArabic
                  ? 'الآن يمكن لشركتك إضافة ومتابعة حضور وانصراف مناديبها المتواجدين في فروع السلاسل التجارية والمنظمات الأخرى، مع تقارير انضباط ميداني موحدة ولحظية.'
                  : 'Your company can now add and track delegate attendance across partner retail chains and organizations in real time from this dashboard.',
              style: TextStyle(
                fontSize: 13,
                height: 1.5,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 14),

            // عنوان فرعي للسلاسل المدعومة بأيقونة جوجل ماتيريال
            Row(
              children: [
                Icon(
                  Icons.storefront_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 6),
                Text(
                  isArabic ? 'السلاسل والمنظمات المتاحة للربط:' : 'Supported Chains & Organizations:',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.primary,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // قائمة الـ Chips للسلاسل المدعومة بأيقونات جوجل فقط (بدون أي إيموجي)
            Wrap(
              spacing: 8,
              runSpacing: 8,
              children: [
                _buildM3ChainChip(
                  context,
                  colorScheme,
                  label: 'زهران ماركت',
                  icon: Icons.storefront_rounded,
                ),
                _buildM3ChainChip(
                  context,
                  colorScheme,
                  label: 'جملة ماركت',
                  icon: Icons.storefront_rounded,
                ),
                _buildM3ChainChip(
                  context,
                  colorScheme,
                  label: 'كارفور',
                  icon: Icons.storefront_rounded,
                ),
                _buildM3ChainChip(
                  context,
                  colorScheme,
                  label: 'بيت الجملة',
                  icon: Icons.storefront_rounded,
                ),
                _buildM3ChainChip(
                  context,
                  colorScheme,
                  label: isArabic ? 'سلاسل أخرى قريباً' : 'More chains soon',
                  icon: Icons.schedule_rounded,
                  isMuted: true,
                ),
              ],
            ),
            const SizedBox(height: 16),

            // أزرار الإجراء السريع (CTA) بمواصفات Material 3
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.push(
                        context,
                        MaterialPageRoute(
                          builder: (_) => AddDelegateFormScreen(
                            supervisor: adminDelegate,
                          ),
                        ),
                      );
                    },
                    icon: const Icon(Icons.person_add_alt_1_rounded, size: 18),
                    label: Text(
                      isArabic ? 'إضافة مندوب' : 'Add Delegate',
                      style: const TextStyle(fontWeight: FontWeight.bold),
                    ),
                    style: FilledButton.styleFrom(
                      shape: const StadiumBorder(),
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 10),
                OutlinedButton.icon(
                  onPressed: () => _showHowItWorksDialog(context, colorScheme, isArabic),
                  icon: const Icon(Icons.info_outline_rounded, size: 18),
                  label: Text(
                    isArabic ? 'كيفية الربط' : 'Guide',
                    style: const TextStyle(fontWeight: FontWeight.w600),
                  ),
                  style: OutlinedButton.styleFrom(
                    shape: const StadiumBorder(),
                    side: BorderSide(
                      color: colorScheme.outline.withValues(alpha: 0.5),
                    ),
                    padding: const EdgeInsets.symmetric(vertical: 12, horizontal: 16),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// رقاقة عرض السلسلة التجارية وفق معايير Material 3 وبأيقونات جوجل
  Widget _buildM3ChainChip(
    BuildContext context,
    ColorScheme colorScheme, {
    required String label,
    required IconData icon,
    bool isMuted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
      decoration: BoxDecoration(
        color: isMuted
            ? colorScheme.surfaceContainerHighest.withValues(alpha: 0.4)
            : colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMuted
              ? colorScheme.outlineVariant.withValues(alpha: 0.3)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: 1,
        ),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            icon,
            size: 14,
            color: isMuted
                ? colorScheme.onSurfaceVariant.withValues(alpha: 0.7)
                : colorScheme.primary,
          ),
          const SizedBox(width: 6),
          Text(
            label,
            style: TextStyle(
              fontSize: 12,
              fontWeight: isMuted ? FontWeight.normal : FontWeight.w600,
              color: isMuted
                  ? colorScheme.onSurfaceVariant.withValues(alpha: 0.75)
                  : colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  void _showHowItWorksDialog(
    BuildContext context,
    ColorScheme colorScheme,
    bool isArabic,
  ) {
    showM3Dialog(
      context: context,
      builder: (dialogCtx) {
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Row(
            children: [
              Icon(Icons.hub_rounded, color: colorScheme.primary),
              const SizedBox(width: 10),
              Text(
                isArabic ? 'كيفية ربط مناديبك بالسلاسل' : 'How Multi-Org Linking Works',
                style: const TextStyle(fontSize: 17, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  isArabic
                      ? 'خطوات بسيطة لمتابعة مناديبك في أي سلسلة تجارية:'
                      : 'Follow these steps to connect your delegates in other chains:',
                  style: TextStyle(
                    fontSize: 13.5,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurface,
                  ),
                ),
                const SizedBox(height: 14),
                _buildStepItem(
                  colorScheme,
                  '1',
                  isArabic ? 'الضغط على زر إضافة مندوب' : 'Tap Add Delegate',
                  isArabic
                      ? 'افتح نموذج إضافة المندوب من هذا الكارت أو من تبويب المناديب.'
                      : 'Open the delegate form from this card or the delegates tab.',
                ),
                const SizedBox(height: 10),
                _buildStepItem(
                  colorScheme,
                  '2',
                  isArabic ? 'اختيار المنظمة أو السلسلة' : 'Select Chain / Organization',
                  isArabic
                      ? 'اختر السلسلة التي يعمل بها المندوب (مثل: زهران، جملة ماركت، كارفور، بيت الجملة).'
                      : 'Pick the retail chain where the delegate works (e.g. Zahran, Gomla, Carrefour, Beit El-Gomla).',
                ),
                const SizedBox(height: 10),
                _buildStepItem(
                  colorScheme,
                  '3',
                  isArabic ? 'تحديد الفرع والبيانات' : 'Set Branch & Details',
                  isArabic
                      ? 'حدد اسم الفرع ورقم هاتف المندوب وبياناته الشخصية لإتمام التسجيل.'
                      : 'Specify the branch name and delegate contact info.',
                ),
                const SizedBox(height: 10),
                _buildStepItem(
                  colorScheme,
                  '4',
                  isArabic ? 'متابعة لحظية وموحدة' : 'Instant Real-time Tracking',
                  isArabic
                      ? 'بمجرد تسجيل حضور المندوب في الفرع، ستظهر بياناته وسجل حضوره وانصرافه فوراً في تقاريرك.'
                      : 'Once the delegate checks in at the store, their attendance appears directly on your dashboard.',
                ),
              ],
            ),
          ),
          actions: [
            FilledButton(
              onPressed: () {
                Navigator.pop(dialogCtx);
                Navigator.push(
                  context,
                  MaterialPageRoute(
                    builder: (_) => AddDelegateFormScreen(
                      supervisor: adminDelegate,
                    ),
                  ),
                );
              },
              child: Text(isArabic ? 'ابدأ الإضافة الآن' : 'Start Adding Now'),
            ),
            TextButton(
              onPressed: () => Navigator.pop(dialogCtx),
              child: Text(isArabic ? 'إغلاق' : 'Close'),
            ),
          ],
        );
      },
    );
  }

  Widget _buildStepItem(
    ColorScheme colorScheme,
    String number,
    String title,
    String desc,
  ) {
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        CircleAvatar(
          radius: 12,
          backgroundColor: colorScheme.primaryContainer,
          child: Text(
            number,
            style: TextStyle(
              fontSize: 11,
              fontWeight: FontWeight.bold,
              color: colorScheme.onPrimaryContainer,
            ),
          ),
        ),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  color: colorScheme.onSurface,
                ),
              ),
              const SizedBox(height: 2),
              Text(
                desc,
                style: TextStyle(
                  fontSize: 12,
                  color: colorScheme.onSurfaceVariant,
                  height: 1.4,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }

  String _formatDate(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).languageCode;
    final months = locale == 'ar'
        ? [
            'يناير',
            'فبراير',
            'مارس',
            'أبريل',
            'مايو',
            'يونيو',
            'يوليو',
            'أغسطس',
            'سبتمبر',
            'أكتوبر',
            'نوفمبر',
            'ديسمبر',
          ]
        : [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
    final days = locale == 'ar'
        ? [
            'الأحد',
            'الإثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
          ]
        : [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ];

    final dayName = days[now.weekday % 7];
    return '$dayName, ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}



/// Compact vertical card for the two side-by-side summary cards
class _CompactSummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final bool isDense;

  const _CompactSummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.onTap,
    this.isDense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(isDense ? 10 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isDense ? 36 : 44,
                height: isDense ? 36 : 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: isDense ? 20 : 24),
              ),
              SizedBox(height: isDense ? 8 : 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    fontSize: isDense ? 11 : null,
                  ),
                ),
              ),
              SizedBox(height: isDense ? 4 : 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: isDense ? 22 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceDetailsBottomSheet extends StatefulWidget {
  final Delegate adminDelegate;
  final String initialFilter;

  const _AttendanceDetailsBottomSheet({
    required this.adminDelegate,
    required this.initialFilter,
  });

  @override
  State<_AttendanceDetailsBottomSheet> createState() =>
      _AttendanceDetailsBottomSheetState();
}

class _AttendanceDetailsBottomSheetState
    extends State<_AttendanceDetailsBottomSheet> {
  bool _isLoading = true;
  late String _filter;
  String _selectedOrgId = 'all';
  String _searchQuery = '';
  List<_DelegateAttendanceData> _allData = [];
  Map<String, String> _availableOrgs = {'all': 'جميع السلاسل'};

  @override
  void initState() {
    super.initState();
    // Default to 'checked_in' (الحاضرون اليوم) as requested
    _filter = (widget.initialFilter.isNotEmpty && widget.initialFilter != 'all')
        ? widget.initialFilter
        : 'checked_in';
    _fetchAttendanceData();
  }

  Future<void> _fetchAttendanceData() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      final List<DelegateModel> delegates = [];
      final Map<String, String> orgNamesById = {};
      final Map<String, String> discoveredOrgs = {'all': 'جميع السلاسل'};

      // 1. Fetch delegates for the company across organizations
      if (widget.adminDelegate.companyUID.isNotEmpty) {
        final orgsSnap = await firestore.collection('organizations').get();
        for (final doc in orgsSnap.docs) {
          final data = doc.data();
          final name = (data['name'] ?? data['title'] ?? doc.id).toString();
          orgNamesById[doc.id] = name;
        }

        final futures = orgsSnap.docs.map((orgDoc) => firestore
            .collection('organizations')
            .doc(orgDoc.id)
            .collection('companies')
            .doc(widget.adminDelegate.companyUID)
            .collection('delegates')
            .get());
        final results = await Future.wait(futures);

        final Map<String, DelegateModel> unique = {};
        final Map<String, Set<String>> delegateOrgs = {};
        for (var i = 0; i < results.length; i++) {
          final orgId = orgsSnap.docs[i].id;
          final orgName = orgNamesById[orgId] ?? orgId;
          final res = results[i];
          if (res.docs.isNotEmpty) {
            discoveredOrgs[orgId] = orgName;
          }
          for (final doc in res.docs) {
            delegateOrgs.putIfAbsent(doc.id, () => {}).add(orgName);
            unique[doc.id] = DelegateModel.fromJson(doc.data(), doc.id);
          }
        }
        for (final entry in unique.entries) {
          final orgsList = delegateOrgs[entry.key]?.toList() ?? [];
          delegates.add(entry.value.copyWith(
            allOrganizationNames:
                orgsList.isNotEmpty ? orgsList : entry.value.allOrganizationNames,
          ));
        }
      } else {
        final delegatesSnapshot = await firestore
            .collection('organizations')
            .doc(widget.adminDelegate.organizationUID)
            .collection('companies')
            .doc(widget.adminDelegate.companyUID)
            .collection('delegates')
            .get();
        delegates.addAll(
          delegatesSnapshot.docs
              .map((doc) => DelegateModel.fromJson(doc.data(), doc.id)),
        );
        if (widget.adminDelegate.organizationUID.isNotEmpty) {
          final name = widget.adminDelegate.organizationName.isNotEmpty
              ? widget.adminDelegate.organizationName
              : widget.adminDelegate.organizationUID;
          discoveredOrgs[widget.adminDelegate.organizationUID] = name;
          orgNamesById[widget.adminDelegate.organizationUID] = name;
        }
      }

      // 2. Fetch today's attendance logs
      Query<Map<String, dynamic>> attendanceQuery =
          firestore.collection(kAttendanceCollection);
      if (widget.adminDelegate.companyUID.isNotEmpty) {
        attendanceQuery = attendanceQuery.where(
          'companyId',
          isEqualTo: widget.adminDelegate.companyUID,
        );
      } else if (widget.adminDelegate.organizationUID.isNotEmpty) {
        attendanceQuery = attendanceQuery.where(
          'organizationId',
          isEqualTo: widget.adminDelegate.organizationUID,
        );
      }
      final attendanceSnapshot = await attendanceQuery.get();

      final Map<String, List<Map<String, dynamic>>> logsByDelegate = {};
      for (var doc in attendanceSnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'];
        if (timestamp is Timestamp) {
          final date = timestamp.toDate();
          if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) continue;
        }

        final delegateId =
            (data['delegateId'] ?? data['userId'] ?? '').toString();
        if (delegateId.isNotEmpty) {
          logsByDelegate.putIfAbsent(delegateId, () => []).add(data);
        }
      }

      final List<_DelegateAttendanceData> list = [];
      for (var d in delegates) {
        final logs = logsByDelegate[d.uid] ?? [];
        DateTime? checkIn;
        DateTime? checkOut;
        String? branch;
        String? orgId;
        String? orgName;

        for (var log in logs) {
          final type = (log['type'] ?? '').toString();
          final ts = log['timestamp'];
          DateTime? logTime;
          if (ts is Timestamp) logTime = ts.toDate();

          if (type == 'check_in') {
            if (checkIn == null ||
                (logTime != null && logTime.isBefore(checkIn))) {
              checkIn = logTime;
            }
            if (branch == null && log['branchName'] != null) {
              branch = log['branchName'].toString();
            }
            if (orgId == null && log['organizationId'] != null) {
              orgId = log['organizationId'].toString();
              orgName = log['organizationName']?.toString() ??
                  orgNamesById[orgId] ??
                  orgId;
            }
          } else if (type == 'check_out') {
            if (checkOut == null ||
                (logTime != null && logTime.isAfter(checkOut))) {
              checkOut = logTime;
            }
          }
        }

        // Fallbacks for organization metadata if not checked-in today
        orgId ??= d.organizationUID;
        orgName ??= (d.organizationName.isNotEmpty
            ? d.organizationName
            : (orgNamesById[d.organizationUID] ?? ''));

        list.add(_DelegateAttendanceData(
          delegate: d,
          checkInTime: checkIn,
          checkOutTime: checkOut,
          branchName: branch,
          organizationId: orgId,
          organizationName: orgName,
        ));
      }

      if (mounted) {
        setState(() {
          _allData = list;
          _availableOrgs = discoveredOrgs;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<_DelegateAttendanceData> get _filteredData {
    return _allData.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.delegate.fullName
              .toLowerCase()
              .contains(_searchQuery.toLowerCase()) ||
          item.delegate.phoneNumber.contains(_searchQuery);

      if (!matchesSearch) return false;

      // Status filter
      if (_filter == 'checked_in') {
        if (item.checkInTime == null) return false;
      } else if (_filter == 'absent') {
        if (item.checkInTime != null) return false;
      }

      // Organization chain filter
      if (_selectedOrgId != 'all') {
        final targetOrgName = _availableOrgs[_selectedOrgId] ?? '';
        final matchesCheckedInOrg = item.organizationId == _selectedOrgId ||
            (targetOrgName.isNotEmpty && item.organizationName == targetOrgName);
        final matchesAssignedOrg = item.delegate.organizationUID == _selectedOrgId ||
            (targetOrgName.isNotEmpty &&
                item.delegate.allOrganizationNames.contains(targetOrgName)) ||
            (targetOrgName.isNotEmpty &&
                item.delegate.organizationName == targetOrgName);

        if (!matchesCheckedInOrg && !matchesAssignedOrg) return false;
      }

      return true;
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    final checkedInCount = _allData.where((i) => i.checkInTime != null).length;
    final absentCount = _allData.where((i) => i.checkInTime == null).length;

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: media.size.height * 0.85,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Title & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.badge_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'سجل حضور وانصراف اليوم',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Dual Dropdown Menu Bar (Attendance Status + Chain Filter)
            Row(
              children: [
                // 1. Attendance Status Dropdown (الحاضرون اليوم، الغائبون اليوم، إجمالي المناديب)
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _filter != 'all'
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.6),
                        width: _filter != 'all' ? 1.4 : 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _filter,
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                        items: [
                          DropdownMenuItem<String>(
                            value: 'checked_in',
                            child: Row(
                              children: [
                                const Icon(
                                  Icons.check_circle_rounded,
                                  size: 16,
                                  color: Color(0xFF16A34A),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'الحاضرون اليوم ($checkedInCount)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _filter == 'checked_in'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _filter == 'checked_in'
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'absent',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.cancel_rounded,
                                  size: 16,
                                  color: colorScheme.error,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'الغائبون اليوم ($absentCount)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _filter == 'absent'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _filter == 'absent'
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                          DropdownMenuItem<String>(
                            value: 'all',
                            child: Row(
                              children: [
                                Icon(
                                  Icons.people_alt_rounded,
                                  size: 16,
                                  color: colorScheme.primary,
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    'إجمالي المناديب (${_allData.length})',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: _filter == 'all'
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: _filter == 'all'
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                        onChanged: (val) {
                          if (val != null) setState(() => _filter = val);
                        },
                      ),
                    ),
                  ),
                ),

                const SizedBox(width: 8),

                // 2. Organization Chain Dropdown
                Expanded(
                  child: Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(
                        color: _selectedOrgId != 'all'
                            ? colorScheme.primary
                            : colorScheme.outlineVariant.withValues(alpha: 0.6),
                        width: _selectedOrgId != 'all' ? 1.4 : 1,
                      ),
                    ),
                    child: DropdownButtonHideUnderline(
                      child: DropdownButton<String>(
                        value: _availableOrgs.containsKey(_selectedOrgId) ? _selectedOrgId : 'all',
                        isExpanded: true,
                        icon: const Icon(Icons.keyboard_arrow_down_rounded, size: 20),
                        items: _availableOrgs.entries.map((entry) {
                          final isAll = entry.key == 'all';
                          final count = isAll
                              ? _allData.length
                              : _allData.where((item) {
                                  final targetName = entry.value;
                                  return item.organizationId == entry.key ||
                                      (targetName.isNotEmpty && item.organizationName == targetName) ||
                                      item.delegate.organizationUID == entry.key ||
                                      (targetName.isNotEmpty &&
                                          item.delegate.allOrganizationNames.contains(targetName)) ||
                                      (targetName.isNotEmpty && item.delegate.organizationName == targetName);
                                }).length;

                          return DropdownMenuItem<String>(
                            value: entry.key,
                            child: Row(
                              children: [
                                Icon(
                                  isAll ? Icons.storefront_rounded : Icons.business_rounded,
                                  size: 16,
                                  color: isAll
                                      ? colorScheme.primary
                                      : (_selectedOrgId == entry.key
                                          ? colorScheme.primary
                                          : colorScheme.onSurfaceVariant),
                                ),
                                const SizedBox(width: 6),
                                Expanded(
                                  child: Text(
                                    '${entry.value} ($count)',
                                    style: TextStyle(
                                      fontSize: 12.5,
                                      fontWeight: entry.key == _selectedOrgId
                                          ? FontWeight.bold
                                          : FontWeight.normal,
                                      color: entry.key == _selectedOrgId
                                          ? colorScheme.primary
                                          : colorScheme.onSurface,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          );
                        }).toList(),
                        onChanged: (val) {
                          if (val != null) {
                            setState(() => _selectedOrgId = val);
                          }
                        },
                      ),
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 10),

            // Search Bar
            TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المندوب أو رقم الهاتف...',
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 16),

            // Content List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_off_rounded,
                                size: 56,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'لا توجد بيانات مناديب تطابق هذا البحث',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredData.length,
                          itemBuilder: (context, index) {
                            final item = _filteredData[index];
                            final isCheckedIn = item.checkInTime != null;
                            final timeFormat = DateFormat('hh:mm a');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              clipBehavior: Clip.antiAlias,
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isCheckedIn
                                      ? colorScheme.primary.withValues(alpha: 0.3)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              child: InkWell(
                                borderRadius: BorderRadius.circular(14),
                                onTap: () {
                                  Navigator.of(context).push(
                                    MaterialPageRoute(
                                      builder: (_) => AttendanceScreen(
                                        delegate: item.delegate,
                                        viewOnly: true,
                                      ),
                                    ),
                                  );
                                },
                                child: Padding(
                                  padding: const EdgeInsets.all(14),
                                  child: Column(
                                    crossAxisAlignment: CrossAxisAlignment.start,
                                    children: [
                                      Row(
                                        children: [
                                          AppAvatar(
                                            imageUrl: item.delegate.personalPhotoUrl,
                                            fallbackText: item.delegate.firstName.isNotEmpty
                                                ? item.delegate.firstName
                                                : item.delegate.fullName,
                                            radius: 20,
                                            backgroundColor: isCheckedIn
                                                ? colorScheme.primaryContainer
                                                : colorScheme.surfaceContainerHighest,
                                            foregroundColor: isCheckedIn
                                                ? colorScheme.primary
                                                : colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 12),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              children: [
                                                Text(
                                                  item.delegate.fullName,
                                                  style: theme.textTheme.titleMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                  ),
                                                ),
                                                const SizedBox(height: 2),
                                                Row(
                                                  children: [
                                                    Text(
                                                      'الهاتف: ${item.delegate.phoneNumber}',
                                                      style: theme.textTheme.bodySmall?.copyWith(
                                                        color: colorScheme.onSurfaceVariant,
                                                      ),
                                                    ),
                                                    if (item.organizationName != null &&
                                                        item.organizationName!.isNotEmpty &&
                                                        !isCheckedIn) ...[
                                                      const SizedBox(width: 8),
                                                      Flexible(
                                                        child: Container(
                                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                                                          decoration: BoxDecoration(
                                                            color: colorScheme.secondaryContainer.withValues(alpha: 0.5),
                                                            borderRadius: BorderRadius.circular(6),
                                                          ),
                                                          child: Text(
                                                            item.organizationName!,
                                                            style: TextStyle(
                                                              fontSize: 10,
                                                              fontWeight: FontWeight.w600,
                                                              color: colorScheme.onSecondaryContainer,
                                                            ),
                                                            overflow: TextOverflow.ellipsis,
                                                          ),
                                                        ),
                                                      ),
                                                    ],
                                                  ],
                                                ),
                                              ],
                                            ),
                                          ),
                                          Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                            decoration: BoxDecoration(
                                              color: isCheckedIn
                                                  ? colorScheme.primaryContainer
                                                  : colorScheme.errorContainer,
                                              borderRadius: BorderRadius.circular(8),
                                            ),
                                            child: Text(
                                              isCheckedIn ? 'حاضر' : 'غائب',
                                              style: TextStyle(
                                                color: isCheckedIn ? colorScheme.onPrimaryContainer : colorScheme.onErrorContainer,
                                                fontSize: 12,
                                                fontWeight: FontWeight.bold,
                                              ),
                                            ),
                                          ),
                                          const SizedBox(width: 6),
                                          Icon(
                                            Icons.arrow_forward_ios_rounded,
                                            size: 14,
                                            color: colorScheme.outline.withValues(alpha: 0.6),
                                          ),
                                        ],
                                      ),
                                      if (isCheckedIn) ...[
                                        const Divider(height: 20),
                                        Row(
                                          children: [
                                            Icon(Icons.login_rounded, size: 16, color: colorScheme.primary),
                                            const SizedBox(width: 6),
                                            Text(
                                              'الحضور: ${timeFormat.format(item.checkInTime!)}',
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: 13,
                                              ),
                                            ),
                                            const SizedBox(width: 16),
                                            Icon(
                                              Icons.logout_rounded,
                                              size: 16,
                                              color: item.checkOutTime != null ? colorScheme.secondary : colorScheme.outline,
                                            ),
                                            const SizedBox(width: 6),
                                            Text(
                                              item.checkOutTime != null
                                                  ? 'الانصراف: ${timeFormat.format(item.checkOutTime!)}'
                                                  : 'لم يسجل انصراف بعد',
                                              style: TextStyle(
                                                fontWeight: item.checkOutTime != null ? FontWeight.bold : FontWeight.normal,
                                                fontSize: 13,
                                                color: item.checkOutTime != null ? colorScheme.onSurface : colorScheme.onSurfaceVariant,
                                              ),
                                            ),
                                          ],
                                        ),
                                        const SizedBox(height: 8),
                                        Row(
                                          children: [
                                            if (item.organizationName != null && item.organizationName!.isNotEmpty) ...[
                                              Builder(
                                                builder: (ctx) {
                                                  final (bg, fg, border) = getOrgBadgeColors(ctx, item.organizationName!);
                                                  return Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                                    decoration: BoxDecoration(
                                                      color: bg,
                                                      borderRadius: BorderRadius.circular(6),
                                                      border: Border.all(color: border, width: 0.5),
                                                    ),
                                                    child: Row(
                                                      mainAxisSize: MainAxisSize.min,
                                                      children: [
                                                        Icon(Icons.storefront_rounded, size: 13, color: fg),
                                                        const SizedBox(width: 4),
                                                        Text(
                                                          item.organizationName!,
                                                          style: TextStyle(
                                                            fontSize: 11,
                                                            fontWeight: FontWeight.bold,
                                                            color: fg,
                                                          ),
                                                        ),
                                                      ],
                                                    ),
                                                  );
                                                },
                                              ),
                                              const SizedBox(width: 8),
                                            ],
                                            if (item.branchName != null && item.branchName!.isNotEmpty) ...[
                                              Icon(Icons.location_on_rounded, size: 16, color: colorScheme.primary),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  'الفرع: ${item.branchName}',
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                              ),
                                            ],
                                          ],
                                        ),
                                      ] else if (item.delegate.allOrganizationNames.isNotEmpty) ...[
                                        const SizedBox(height: 8),
                                        Wrap(
                                          spacing: 6,
                                          runSpacing: 4,
                                          children: item.delegate.allOrganizationNames.map((orgName) {
                                            final (bg, fg, border) = getOrgBadgeColors(context, orgName);
                                            return Container(
                                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                                              decoration: BoxDecoration(
                                                color: bg,
                                                borderRadius: BorderRadius.circular(6),
                                                border: Border.all(color: border, width: 0.5),
                                              ),
                                              child: Text(
                                                orgName,
                                                style: TextStyle(
                                                  fontSize: 10,
                                                  fontWeight: FontWeight.bold,
                                                  color: fg,
                                                ),
                                              ),
                                            );
                                          }).toList(),
                                        ),
                                      ],
                                    ],
                                  ),
                                ),
                              ),
                            );
                          },
                        ),
            ),
          ],
        ),
      ),
    );
  }
}

class _DelegateAttendanceData {
  final Delegate delegate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? branchName;
  final String? organizationId;
  final String? organizationName;

  _DelegateAttendanceData({
    required this.delegate,
    this.checkInTime,
    this.checkOutTime,
    this.branchName,
    this.organizationId,
    this.organizationName,
  });
}
