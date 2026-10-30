import 'dart:io';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:path_provider/path_provider.dart';
import 'package:share_plus/share_plus.dart';
import 'package:url_launcher/url_launcher.dart';
import 'package:cloud_firestore/cloud_firestore.dart';

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/services/photo_cache_manager.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/photo_permission/presentation/widgets/company_name_with_code.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission_departments.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/supervisor_permissions_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// شاشة موحدة وشاملة للسوبر أدمن تدمج:
/// 1. أذونات التصوير والاعتمادات المباشرة (الموافقة والرفض)
/// 2. الصور والزيارات الميدانية الملتقطة
/// 3. تقرير الاشتراكات والفواتير المالية وتصدير Excel/CSV
class SuperAdminPhotosAndPermissionsScreen extends StatefulWidget {
  final Delegate delegate;
  final int initialTabIndex;

  const SuperAdminPhotosAndPermissionsScreen({
    super.key,
    required this.delegate,
    this.initialTabIndex = 0,
  });

  @override
  State<SuperAdminPhotosAndPermissionsScreen> createState() =>
      _SuperAdminPhotosAndPermissionsScreenState();
}

class _SuperAdminPhotosAndPermissionsScreenState
    extends State<SuperAdminPhotosAndPermissionsScreen> {
  late int _selectedTab;
  late PhotoPermissionBloc _permissionsBloc;
  late PhotoPermissionBloc _photosBloc;

  // ── فلاتر وبحث أذونات التصوير ──
  final TextEditingController _permissionsSearchController = TextEditingController();
  String _permissionsSearchQuery = '';
  String _selectedStatusFilter = 'pending'; // all, pending, active, disabled, expired, rejected (افتراضي: في انتظار الاعتماد)
  Set<String> _selectedDepartments = {}; // فارغة = كل الأقسام
  String _selectedCompanyFilter = 'all'; // all أو companyUID محدد
  final Set<String> _expandedPermissionIds = {};

  // ── فلاتر وبحث الصور الميدانية ──
  final TextEditingController _photosSearchController = TextEditingController();
  String _photosSearchQuery = '';
  String _selectedPhotoDateFilter = 'all'; // all, today, week, month, custom
  DateTime? _customPhotoDate;
  bool _isPhotoGridView = true;

  // ── التسلسل الهرمي للصور الميدانية (3-Level Hierarchical Drill-Down) ──
  String? _selectedBranchDrillDown; // المستوى 1: الفرع المختار
  Map<String, dynamic>? _selectedCompanyDrillDown; // المستوى 2: الشركة المختارة في الفرع
  int _photosLimit = 20; // حد الصور المعروضة مبدئياً
  bool _isLoadingMorePhotos = false;

  final TextEditingController _branchSearchController = TextEditingController();
  String _branchSearchQuery = '';

  final TextEditingController _branchCompanySearchController = TextEditingController();
  String _branchCompanySearchQuery = '';

  // إحصائيات صور النظام عبر Firestore count (سريعة وخفيفة بدون جلب داتا الصور)
  int _totalPhotosCount = 0;
  int _todayPhotosCount = 0;
  List<String> _firestoreBranches = [];

  // ── التقرير المالي وأكواد الشركات ──
  final Map<String, int?> _companyCodesCache = {};

  @override
  void initState() {
    super.initState();
    _selectedTab = widget.initialTabIndex;
    _permissionsBloc = di.sl<PhotoPermissionBloc>();
    _photosBloc = di.sl<PhotoPermissionBloc>();

    _loadPermissionsData();
    _fetchBranchesAndKPIs();
  }

  @override
  void dispose() {
    _permissionsSearchController.dispose();
    _photosSearchController.dispose();
    _branchSearchController.dispose();
    _branchCompanySearchController.dispose();
    _permissionsBloc.close();
    _photosBloc.close();
    super.dispose();
  }

  Future<void> _fetchBranchesAndKPIs() async {
    try {
      final firestore = FirebaseFirestore.instance;

      // 1. جلب الفروع المسجلة بالنظام
      final branchesSnap = await firestore.collection('branches').get();
      final branchSet = <String>{};
      for (final doc in branchesSnap.docs) {
        final data = doc.data();
        final name = ((data['branchName'] as String?) ?? (data['name'] as String?) ?? '').trim();
        if (name.isNotEmpty) branchSet.add(name);
      }
      _firestoreBranches = branchSet.toList()..sort();

      // 2. إجمالي الصور (Count aggregate - 0 documents downloaded)
      final totalSnap = await firestore.collectionGroup('captured_photos').count().get();
      _totalPhotosCount = totalSnap.count ?? 0;

      // 3. صور اليوم (Count aggregate)
      final now = DateTime.now();
      final todayStart = DateTime(now.year, now.month, now.day);
      final todaySnap = await firestore
          .collectionGroup('captured_photos')
          .where('capturedAt', isGreaterThanOrEqualTo: Timestamp.fromDate(todayStart))
          .count()
          .get();
      _todayPhotosCount = todaySnap.count ?? 0;
    } catch (e) {
      debugPrint('Error fetching branches and KPIs: $e');
    }
    if (mounted) {
      setState(() {});
    }
  }

  void _loadPermissionsData() {
    _permissionsBloc.add(
      LoadPermissionsRequested(
        organizationUID: widget.delegate.organizationUID,
        companyUID: '', // لجميع الشركات عبر النظام
      ),
    );
  }

  void _loadPhotosData({String? branchName, String? companyUID, int? limit}) {
    final compUID = companyUID ?? _selectedCompanyDrillDown?['uid'] ?? '';
    final brName = branchName ?? _selectedBranchDrillDown;
    final lim = limit ?? _photosLimit;
    _photosBloc.add(
      LoadCompanyCapturedPhotosRequested(
        companyUID: compUID,
        branchName: brName,
        limit: lim,
      ),
    );
  }

  void _refreshAll() {
    _loadPermissionsData();
    _fetchBranchesAndKPIs();
    if (_selectedBranchDrillDown != null && _selectedCompanyDrillDown != null) {
      _loadPhotosData();
    }
  }

  // ── جلب أكواد الشركات للتقرير المالي ──
  Future<void> _fetchCompanyCodes(List<PhotoPermission> permissions) async {
    final firestore = FirebaseFirestore.instance;
    bool updated = false;
    for (final p in permissions) {
      if (!_companyCodesCache.containsKey(p.companyUID)) {
        try {
          final compDoc = await firestore
              .collection('organizations')
              .doc(p.organizationUID.isNotEmpty ? p.organizationUID : widget.delegate.organizationUID)
              .collection('companies')
              .doc(p.companyUID)
              .get();
          final data = compDoc.data();
          if (data != null && data['code'] != null) {
            _companyCodesCache[p.companyUID] = int.tryParse(data['code'].toString());
          } else {
            _companyCodesCache[p.companyUID] = p.companyCode;
          }
        } catch (_) {
          _companyCodesCache[p.companyUID] = p.companyCode;
        }
        updated = true;
      }
    }
    if (updated && mounted) {
      setState(() {});
    }
  }

  // ── تصدير التقرير المالي إلى Excel / CSV ──
  Future<void> _exportToCSV(List<PhotoPermission> activePermissions) async {
    try {
      final csvHeader = '\uFEFFاسم الشركة,كود الشركة,القسم,قيمة الاشتراك الشهري (ج.م),تاريخ البدء,تاريخ الانتهاء\n';
      final csvRows = activePermissions.map((p) {
        final name = p.companyName.replaceAll(',', ' ');
        final code = _companyCodesCache[p.companyUID]?.toString() ?? p.companyCode?.toString() ?? '-';
        final dept = (p.department ?? 'عام').replaceAll(',', ' ');
        final start = DateFormat('yyyy-MM-dd').format(p.startDate);
        final end = DateFormat('yyyy-MM-dd').format(p.endDate);
        return '$name,$code,$dept,500,$start,$end';
      }).join('\n');

      final csvContent = '$csvHeader$csvRows';
      final directory = await getTemporaryDirectory();
      final file = File('${directory.path}/photo_permissions_billing.csv');
      await file.writeAsString(csvContent);

      if (mounted) {
        // ignore: deprecated_member_use
        await Share.shareXFiles(
          [XFile(file.path)],
          text: 'تقرير فواتير واشتراكات أذونات التصوير للشركات',
        );
      }
    } catch (e) {
      if (mounted) {
        final colorScheme = Theme.of(context).colorScheme;
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text(
              'فشل في تصدير التقرير، يرجى المحاولة لاحقاً: $e',
              style: TextStyle(color: colorScheme.onError),
            ),
            backgroundColor: colorScheme.error,
          ),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Directionality.of(context) == TextDirection.rtl;

    return MultiBlocProvider(
      providers: [
        BlocProvider.value(value: _permissionsBloc),
        BlocProvider.value(value: _photosBloc),
      ],
      child: MultiBlocListener(
        listeners: [
          BlocListener<PhotoPermissionBloc, PhotoPermissionState>(
            bloc: _permissionsBloc,
            listener: (context, state) {
              if (state is PermissionActionSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _loadPermissionsData();
              } else if (state is PhotoPermissionActionSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _loadPermissionsData();
              } else if (state is PhotoPermissionError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: colorScheme.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
          BlocListener<PhotoPermissionBloc, PhotoPermissionState>(
            bloc: _photosBloc,
            listener: (context, state) {
              if (state is PhotoDeleteSuccess) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: const Text('تم حذف الصورة الميدانية بنجاح.'),
                    backgroundColor: colorScheme.primary,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
                _loadPhotosData();
              } else if (state is PhotoPermissionError) {
                ScaffoldMessenger.of(context).showSnackBar(
                  SnackBar(
                    content: Text(state.message),
                    backgroundColor: colorScheme.error,
                    behavior: SnackBarBehavior.floating,
                  ),
                );
              }
            },
          ),
        ],
        child: PopScope(
          canPop: _selectedTab != 1 ||
              (_selectedBranchDrillDown == null && _selectedCompanyDrillDown == null),
          onPopInvokedWithResult: (didPop, result) {
            if (didPop) return;
            if (_selectedCompanyDrillDown != null) {
              setState(() => _selectedCompanyDrillDown = null);
            } else if (_selectedBranchDrillDown != null) {
              setState(() => _selectedBranchDrillDown = null);
            }
          },
          child: Scaffold(
          backgroundColor: colorScheme.surfaceContainerLowest,
          appBar: AppBar(
            backgroundColor: colorScheme.surfaceContainer,
            surfaceTintColor: Colors.transparent,
            elevation: 0,
            scrolledUnderElevation: 2.0,
            shape: Border(
              bottom: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                width: 0.8,
              ),
            ),
            titleSpacing: 0,
            title: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      isArabic ? 'الصور وأذونات التصوير' : 'Photos & Permissions Hub',
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14.5,
                        letterSpacing: -0.2,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    const SizedBox(width: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.primary.withValues(alpha: 0.12),
                        borderRadius: BorderRadius.circular(6),
                        border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
                      ),
                      child: Text(
                        'سوبر أدمن',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontSize: 10.5,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ),
                Text(
                  isArabic
                      ? 'إدارة واعتماد الأذونات والزيارات الميدانية والفواتير'
                      : 'Field Visits, Permissions Approvals & Billing',
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.85),
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ],
            ),
            actions: [
              IconButton(
                icon: const Icon(Icons.refresh_rounded),
                tooltip: 'تحديث البيانات',
                onPressed: _refreshAll,
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: Column(
            children: [
              // ── شريط التبديل المتصل M3 ──
              _buildTopConnectedTabBar(colorScheme),

              // ── المحتوى التفاعلي للتبويب النشط ──
              Expanded(
                child: AnimatedSwitcher(
                  duration: AppMotionDurations.medium2,
                  switchInCurve: AppMotionCurves.emphasized,
                  switchOutCurve: AppMotionCurves.emphasizedAccelerate,
                  child: _buildActiveTabContent(colorScheme, theme),
                ),
              ),
            ],
          ),
        ),
      ),
    ),
  );
}

  // ══════════════════════════════════════════════════════════════════════════
  // ── شريط التبديل المتصل M3 (Tab Switcher) ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildTopConnectedTabBar(ColorScheme colorScheme) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        border: Border(
          bottom: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.3),
            width: 0.8,
          ),
        ),
      ),
      child: Center(
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 620),
          child: TashilConnectedButtonGroup<int>(
            height: 42,
            isScrollable: false,
            selectedValue: _selectedTab,
            onSelected: (val) {
              setState(() {
                _selectedTab = val;
              });
            },
            items: const [
              TashilConnectedButtonItem<int>(
                value: 0,
                label: 'أذونات التصوير',
                icon: Icons.verified_user_rounded,
              ),
              TashilConnectedButtonItem<int>(
                value: 1,
                label: 'الصور الميدانية',
                icon: Icons.photo_library_rounded,
              ),
              TashilConnectedButtonItem<int>(
                value: 2,
                label: 'التقرير المالي',
                icon: Icons.analytics_rounded,
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── اختيار محتوى التبويب ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildActiveTabContent(ColorScheme colorScheme, ThemeData theme) {
    switch (_selectedTab) {
      case 0:
        return KeyedSubtree(
          key: const ValueKey('tab_permissions'),
          child: _buildPermissionsView(colorScheme, theme),
        );
      case 1:
        return KeyedSubtree(
          key: const ValueKey('tab_photos'),
          child: _buildPhotosView(colorScheme, theme),
        );
      case 2:
      default:
        return KeyedSubtree(
          key: const ValueKey('tab_billing'),
          child: _buildBillingReportView(colorScheme, theme),
        );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── التبويب الأول: أذونات التصوير والاعتمادات ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildPermissionsView(ColorScheme colorScheme, ThemeData theme) {
    return BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
      bloc: _permissionsBloc,
      builder: (context, state) {
        if (state is PhotoPermissionLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is PhotoPermissionError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(state.message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loadPermissionsData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        if (state is PhotoPermissionsLoaded) {
          final allPermissions = state.permissions;
          _fetchCompanyCodes(allPermissions);

          // جمع أسماء الشركات الفريدة للفلتر
          final companiesMap = <String, String>{};
          for (final p in allPermissions) {
            if (p.companyUID.isNotEmpty && p.companyName.isNotEmpty) {
              companiesMap[p.companyUID] = p.companyName;
            }
          }

          // تطبيق الفلاتر
          final filtered = allPermissions.where((p) {
            // فلتر البحث (اسم الشركة أو الكود)
            if (_permissionsSearchQuery.isNotEmpty) {
              final query = _permissionsSearchQuery.toLowerCase();
              final nameMatch = p.companyName.toLowerCase().contains(query);
              final codeMatch = p.companyCode?.toString().contains(query) ?? false;
              if (!nameMatch && !codeMatch) return false;
            }

            // فلتر الحالة
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day);
            final status = p.status.toLowerCase();
            final isExpired = p.endDate.isBefore(todayStart);

            if (_selectedStatusFilter == 'pending') {
              if (status != 'pending') return false;
            } else if (_selectedStatusFilter == 'active') {
              if (status != 'approved' || isExpired || p.isSupervisorEnabled == false) return false;
            } else if (_selectedStatusFilter == 'disabled') {
              if (status != 'approved' || p.isSupervisorEnabled != false) return false;
            } else if (_selectedStatusFilter == 'expired') {
              if (!isExpired || status == 'rejected') return false;
            } else if (_selectedStatusFilter == 'rejected') {
              if (status != 'rejected') return false;
            }

            // فلتر الأقسام المتعدد
            if (_selectedDepartments.isNotEmpty) {
              if (p.department == null || !_selectedDepartments.contains(p.department)) {
                return false;
              }
            }

            // فلتر الشركة
            if (_selectedCompanyFilter != 'all') {
              if (p.companyUID != _selectedCompanyFilter) return false;
            }

            return true;
          }).toList();

          // حساب العدادات
          final pendingCount = allPermissions.where((p) => p.status.toLowerCase() == 'pending').length;
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);
          final activeCount = allPermissions
              .where((p) => p.status.toLowerCase() == 'approved' && !p.endDate.isBefore(todayStart))
              .length;

          return RefreshIndicator(
            onRefresh: () async => _loadPermissionsData(),
            child: ListView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              children: [
                // ── ملخص العدادات السريع ──
                _buildPermissionsKPIHeader(
                  colorScheme,
                  total: allPermissions.length,
                  active: activeCount,
                  pending: pendingCount,
                ),
                const SizedBox(height: 12),

                // ── شريط البحث والفلاتر ──
                _buildPermissionsFilterBar(colorScheme, companiesMap),
                const SizedBox(height: 12),

                // ── قائمة الكروت ──
                if (filtered.isEmpty)
                  Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.assignment_outlined, size: 56, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            'لا توجد أذونات تصوير مطابقة للفلاتر المحددة.',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  )
                else
                  ...filtered.map((permission) => _buildPermissionCard(permission, colorScheme, theme)),
              ],
            ),
          );
        }

        return const SizedBox.shrink();
      },
    );
  }

  // ── بطاقات KPI لأذونات التصوير ──
  Widget _buildPermissionsKPIHeader(ColorScheme colorScheme,
      {required int total, required int active, required int pending}) {
    return Row(
      children: [
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedStatusFilter = 'all';
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: _buildMiniKPICard(
              colorScheme,
              title: 'إجمالي الأذونات',
              count: '$total',
              icon: Icons.assignment_rounded,
              color: colorScheme.primary,
              highlight: _selectedStatusFilter == 'all',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedStatusFilter = 'active';
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: _buildMiniKPICard(
              colorScheme,
              title: 'أذونات نشطة',
              count: '$active',
              icon: Icons.check_circle_rounded,
              color: colorScheme.primary,
              highlight: _selectedStatusFilter == 'active',
            ),
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: InkWell(
            onTap: () {
              setState(() {
                _selectedStatusFilter = 'pending';
              });
            },
            borderRadius: BorderRadius.circular(12),
            child: _buildMiniKPICard(
              colorScheme,
              title: 'قيد الاعتماد',
              count: '$pending',
              icon: Icons.hourglass_top_rounded,
              color: colorScheme.tertiary,
              highlight: _selectedStatusFilter == 'pending' || pending > 0,
            ),
          ),
        ),
      ],
    );
  }

  Widget _buildMiniKPICard(ColorScheme colorScheme,
      {required String title,
      required String count,
      required IconData icon,
      required Color color,
      bool highlight = false}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: highlight ? color.withValues(alpha: 0.12) : colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: highlight ? color.withValues(alpha: 0.4) : colorScheme.outlineVariant.withValues(alpha: 0.4),
          width: highlight ? 1.4 : 0.8,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 14, color: color),
              const SizedBox(width: 4),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11,
                    color: colorScheme.onSurfaceVariant,
                    fontWeight: FontWeight.w600,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Text(
            count,
            style: TextStyle(
              fontSize: 16,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── شريط فلاتر أذونات التصوير ──
  Widget _buildPermissionsFilterBar(ColorScheme colorScheme, Map<String, String> companiesMap) {
    final hasActiveFilters = _selectedStatusFilter != 'all' ||
        _selectedDepartments.isNotEmpty ||
        _selectedCompanyFilter != 'all' ||
        _permissionsSearchQuery.isNotEmpty;

    return Column(
      children: [
        // ── الصف الأول: البحث باسم الشركة أو كودها + دروب داون كل الشركات ──
        Row(
          children: [
            Expanded(
              child: SizedBox(
                height: 40,
                child: TextField(
                  controller: _permissionsSearchController,
                  decoration: InputDecoration(
                    hintText: 'البحث باسم الشركة أو كودها...',
                    hintStyle: TextStyle(
                      fontSize: 12,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                    ),
                    prefixIcon: const Icon(Icons.search_rounded, size: 20),
                    suffixIcon: _permissionsSearchQuery.isNotEmpty
                        ? IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 16),
                            padding: EdgeInsets.zero,
                            onPressed: () {
                              _permissionsSearchController.clear();
                              setState(() {
                                _permissionsSearchQuery = '';
                              });
                            },
                          )
                        : null,
                    filled: true,
                    fillColor: colorScheme.surface,
                    contentPadding: const EdgeInsets.symmetric(horizontal: 10, vertical: 0),
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.outlineVariant),
                    ),
                    enabledBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.7)),
                    ),
                    focusedBorder: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(10),
                      borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                    ),
                  ),
                  style: const TextStyle(fontSize: 12.5),
                  onChanged: (val) {
                    setState(() {
                      _permissionsSearchQuery = val.trim();
                    });
                  },
                ),
              ),
            ),
            if (companiesMap.isNotEmpty) ...[
              const SizedBox(width: 8),
              _buildCompanyFilterDropdown(colorScheme, companiesMap),
            ],
          ],
        ),
        const SizedBox(height: 8),

        // ── الصف الثاني: دروب داون الحالة (في انتظار الاعتماد) + دروب داون الأقسام (+ زر إعادة الضبط إن وجد) ──
        Row(
          children: [
            Expanded(
              child: _buildStatusFilterDropdown(colorScheme),
            ),
            const SizedBox(width: 8),
            Expanded(
              child: _buildDepartmentFilterDropdown(colorScheme),
            ),
            if (hasActiveFilters) ...[
              const SizedBox(width: 6),
              Tooltip(
                message: 'إعادة ضبط كل الفلاتر',
                child: InkWell(
                  onTap: () {
                    setState(() {
                      _selectedStatusFilter = 'all';
                      _selectedDepartments.clear();
                      _selectedCompanyFilter = 'all';
                      _permissionsSearchQuery = '';
                      _permissionsSearchController.clear();
                    });
                  },
                  borderRadius: BorderRadius.circular(10),
                  child: Container(
                    height: 40,
                    padding: const EdgeInsets.symmetric(horizontal: 10),
                    decoration: BoxDecoration(
                      color: colorScheme.errorContainer.withValues(alpha: 0.35),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: colorScheme.error.withValues(alpha: 0.35)),
                    ),
                    child: Row(
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Icon(Icons.filter_alt_off_rounded, size: 16, color: colorScheme.error),
                      ],
                    ),
                  ),
                ),
              ),
            ],
          ],
        ),
      ],
    );
  }

  // ── دروب داون فلتر الحالة (M3 PopupMenu) ──
  Widget _buildStatusFilterDropdown(ColorScheme colorScheme) {
    final statusLabels = {
      'all': 'كل الحالات',
      'pending': 'في انتظار الاعتماد',
      'active': 'أذونات نشطة',
      'disabled': 'معطلة مؤقتاً',
      'expired': 'منتهية',
      'rejected': 'مرفوضة',
    };

    return PopupMenuButton<String>(
      initialValue: _selectedStatusFilter,
      tooltip: 'تصفية حسب الحالة',
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (val) => setState(() => _selectedStatusFilter = val),
      itemBuilder: (context) => [
        _buildPopupCheckItem('all', statusLabels['all']!, Icons.list_alt_rounded, colorScheme),
        _buildPopupCheckItem('pending', statusLabels['pending']!, Icons.hourglass_top_rounded, colorScheme),
        _buildPopupCheckItem('active', statusLabels['active']!, Icons.check_circle_rounded, colorScheme),
        _buildPopupCheckItem('disabled', statusLabels['disabled']!, Icons.pause_circle_rounded, colorScheme),
        _buildPopupCheckItem('expired', statusLabels['expired']!, Icons.history_rounded, colorScheme),
        _buildPopupCheckItem('rejected', statusLabels['rejected']!, Icons.cancel_rounded, colorScheme),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _selectedStatusFilter != 'all'
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _selectedStatusFilter != 'all'
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.filter_list_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                statusLabels[_selectedStatusFilter] ?? 'الحالة',
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _selectedStatusFilter != 'all' ? colorScheme.primary : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ── دروب داون فلتر الأقسام (M3 PopupMenu) ──
  Widget _buildDepartmentFilterDropdown(ColorScheme colorScheme) {
    String label;
    if (_selectedDepartments.isEmpty) {
      label = 'كل الأقسام';
    } else if (_selectedDepartments.length == 1) {
      label = _selectedDepartments.first;
    } else if (_selectedDepartments.length == 2) {
      label = _selectedDepartments.join(' + ');
    } else {
      label = '${_selectedDepartments.length} أقسام محددة';
    }

    final isFiltered = _selectedDepartments.isNotEmpty;

    return PopupMenuButton<String>(
      tooltip: 'تصفية حسب القسم',
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (val) {
        if (val == '__all__') {
          setState(() {
            _selectedDepartments.clear();
          });
        } else if (val == '__multi__') {
          _showDepartmentFilterPicker(context, colorScheme);
        } else {
          setState(() {
            _selectedDepartments = {val};
          });
        }
      },
      itemBuilder: (context) => [
        _buildPopupCheckItem(
          '__all__',
          'كل الأقسام (عرض الكل)',
          Icons.all_inclusive_rounded,
          colorScheme,
          isSelectedOverride: _selectedDepartments.isEmpty,
        ),
        const PopupMenuDivider(),
        ...kPhotoPermissionDepartments.map(
          (dept) => _buildPopupCheckItem(
            dept,
            dept,
            Icons.category_rounded,
            colorScheme,
            isSelectedOverride: _selectedDepartments.contains(dept),
          ),
        ),
        const PopupMenuDivider(),
        _buildPopupCheckItem(
          '__multi__',
          'تحديد أقسام متعددة...',
          Icons.checklist_rounded,
          colorScheme,
          isSelectedOverride: _selectedDepartments.length > 1,
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: isFiltered
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: isFiltered
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          children: [
            Icon(Icons.category_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            Expanded(
              child: Text(
                label,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: isFiltered ? colorScheme.primary : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  // ── نافذة اختيار الأقسام المتعددة ──
  void _showDepartmentFilterPicker(BuildContext context, ColorScheme colorScheme) {
    final availableDepts = kPhotoPermissionDepartments;
    final tempSelected = Set<String>.from(_selectedDepartments);

    final isMobile = MediaQuery.of(context).size.width <= 768;

    Widget buildPickerContent(StateSetter modalSetState) {
      final isAll = tempSelected.isEmpty;
      final isRtl = Directionality.of(context) == TextDirection.rtl;

      return Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Row(
            children: [
              Icon(Icons.category_rounded, color: colorScheme.primary, size: 22),
              const SizedBox(width: 8),
              const Text(
                'تصفية أذونات التصوير حسب القسم',
                style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
              ),
            ],
          ),
          const SizedBox(height: 14),
          // زر "كل الأقسام"
          FilterChip(
            selected: isAll,
            label: const Text('كل الأقسام (عرض الكل)'),
            avatar: Icon(
              isAll ? Icons.check_circle_rounded : Icons.all_inclusive_rounded,
              size: 16,
              color: isAll ? colorScheme.onPrimary : colorScheme.primary,
            ),
            selectedColor: colorScheme.primary,
            labelStyle: TextStyle(
              fontWeight: FontWeight.bold,
              color: isAll ? colorScheme.onPrimary : colorScheme.onSurface,
            ),
            onSelected: (_) {
              modalSetState(() {
                tempSelected.clear();
              });
            },
          ),
          const SizedBox(height: 10),
          const Divider(height: 1),
          const SizedBox(height: 10),
          // رقائق الأقسام
          Wrap(
            spacing: 8,
            runSpacing: 8,
            children: availableDepts.map((dept) {
              final isSelected = tempSelected.contains(dept);
              return FilterChip(
                selected: isSelected,
                label: Text(dept),
                selectedColor: colorScheme.primaryContainer,
                checkmarkColor: colorScheme.primary,
                labelStyle: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                  color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                ),
                onSelected: (selected) {
                  modalSetState(() {
                    if (selected) {
                      tempSelected.add(dept);
                    } else {
                      tempSelected.remove(dept);
                    }
                  });
                },
              );
            }).toList(),
          ),
          const SizedBox(height: 20),
          // أزرار الإجراءات المتصلة (Connected Action Button Group)
          Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: colorScheme.outlineVariant),
            ),
            child: Row(
              children: [
                Expanded(
                  child: InkWell(
                    onTap: () => Navigator.pop(context),
                    borderRadius: BorderRadius.horizontal(
                      right: isRtl ? const Radius.circular(24) : Radius.zero,
                      left: isRtl ? Radius.zero : const Radius.circular(24),
                    ),
                    child: const Center(
                      child: Text(
                        'إلغاء',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ),
                VerticalDivider(
                  width: 1,
                  thickness: 1,
                  color: colorScheme.outlineVariant,
                ),
                Expanded(
                  child: Material(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.horizontal(
                      left: isRtl ? const Radius.circular(24) : Radius.zero,
                      right: isRtl ? Radius.zero : const Radius.circular(24),
                    ),
                    child: InkWell(
                      onTap: () {
                        setState(() {
                          _selectedDepartments = Set<String>.from(tempSelected);
                        });
                        Navigator.pop(context);
                      },
                      borderRadius: BorderRadius.horizontal(
                        left: isRtl ? const Radius.circular(24) : Radius.zero,
                        right: isRtl ? Radius.zero : const Radius.circular(24),
                      ),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.check_rounded, size: 18, color: colorScheme.onPrimary),
                            const SizedBox(width: 6),
                            Text(
                              'تطبيق الفلتر',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),
              ],
            ),
          ),
        ],
      );
    }

    if (isMobile) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => StatefulBuilder(
          builder: (ctx, modalSetState) => Padding(
            padding: EdgeInsets.only(
              top: 16,
              left: 16,
              right: 16,
              bottom: MediaQuery.of(ctx).viewInsets.bottom + 24,
            ),
            child: SingleChildScrollView(
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Container(
                    width: 36,
                    height: 4,
                    decoration: BoxDecoration(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                      borderRadius: BorderRadius.circular(2),
                    ),
                  ),
                  const SizedBox(height: 14),
                  buildPickerContent(modalSetState),
                ],
              ),
            ),
          ),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          backgroundColor: colorScheme.surface,
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 480),
            child: StatefulBuilder(
              builder: (ctx, modalSetState) => Padding(
                padding: const EdgeInsets.all(20),
                child: buildPickerContent(modalSetState),
              ),
            ),
          ),
        ),
      );
    }
  }

  // ── دروب داون فلتر الشركة ──
  Widget _buildCompanyFilterDropdown(ColorScheme colorScheme, Map<String, String> companiesMap) {
    final selectedName = companiesMap[_selectedCompanyFilter] ?? 'كل الشركات';

    return PopupMenuButton<String>(
      initialValue: _selectedCompanyFilter,
      tooltip: 'تصفية حسب الشركة',
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (val) => setState(() => _selectedCompanyFilter = val),
      itemBuilder: (context) => [
        _buildPopupCheckItem('all', 'كل الشركات', Icons.domain_rounded, colorScheme),
        const PopupMenuDivider(),
        ...companiesMap.entries.map(
          (entry) => _buildPopupCheckItem(entry.key, entry.value, Icons.business_rounded, colorScheme),
        ),
      ],
      child: Container(
        height: 40,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _selectedCompanyFilter != 'all'
              ? colorScheme.primaryContainer.withValues(alpha: 0.4)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _selectedCompanyFilter != 'all'
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.business_rounded, size: 16, color: colorScheme.primary),
            const SizedBox(width: 6),
            ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 120),
              child: Text(
                selectedName,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.bold,
                  color: _selectedCompanyFilter != 'all' ? colorScheme.primary : colorScheme.onSurface,
                ),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildPopupCheckItem(
      String value, String label, IconData icon, ColorScheme colorScheme,
      {bool? isSelectedOverride}) {
    final isSelected = isSelectedOverride ??
        (_selectedStatusFilter == value || _selectedCompanyFilter == value);
    return PopupMenuItem<String>(
      value: value,
      child: Row(
        children: [
          Icon(icon, size: 18, color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant),
          const SizedBox(width: 8),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_rounded, size: 18, color: colorScheme.primary),
        ],
      ),
    );
  }

  // ── كارت إذن التصوير الشامل مع أزرار الموافقة والرفض ──
  Widget _buildPermissionCard(PhotoPermission permission, ColorScheme colorScheme, ThemeData theme) {
    final isExpanded = _expandedPermissionIds.contains(permission.uid);
    final status = permission.status.toLowerCase();
    final isPending = status == 'pending';
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final isExpired = permission.endDate.isBefore(todayStart);

    // لون الخط الجانبي وفقاً لـ M3 Single-Seed Theme
    Color statusLineColor;
    if (isPending) {
      statusLineColor = colorScheme.tertiary;
    } else if (status == 'rejected') {
      statusLineColor = colorScheme.error;
    } else if (isExpired) {
      statusLineColor = colorScheme.outline;
    } else if (permission.isSupervisorEnabled == false) {
      statusLineColor = colorScheme.secondary;
    } else {
      statusLineColor = colorScheme.primary;
    }

    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 10),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // خط جانبي 3.5px
            Container(width: 3.5, color: statusLineColor),
            // محتوى الكارت
            Expanded(
              child: Padding(
                padding: const EdgeInsets.all(12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // الصف العلوي: اسم الشركة وكودها + شارة الحالة وأيقونة التوسيع
                    Row(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Expanded(
                          child: CompanyNameWithCode(
                            organizationUID: permission.organizationUID.isNotEmpty
                                ? permission.organizationUID
                                : widget.delegate.organizationUID,
                            companyUID: permission.companyUID,
                            companyName: permission.companyName,
                            companyCode: permission.companyCode,
                            twoLines: true,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 14.5,
                            ),
                            codeStyle: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w500,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            _buildStatusBadge(permission, colorScheme),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: AnimatedRotation(
                                turns: isExpanded ? 0.5 : 0.0,
                                duration: AppMotionDurations.short4,
                                curve: AppMotionCurves.emphasized,
                                child: const Icon(Icons.expand_more_rounded, size: 22),
                              ),
                              onPressed: () {
                                setState(() {
                                  if (isExpanded) {
                                    _expandedPermissionIds.remove(permission.uid);
                                  } else {
                                    _expandedPermissionIds.add(permission.uid);
                                  }
                                });
                              },
                            ),
                          ],
                        ),
                      ],
                    ),

                    // السطر الثاني: القسم على اليمين وشيبس "بواسطة" على أقصى الشمال
                    if ((permission.department != null && permission.department!.isNotEmpty) ||
                        (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty)) ...[
                      const SizedBox(height: 8),
                      Row(
                        children: [
                          if (permission.department != null && permission.department!.isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.25)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.category_rounded, size: 11, color: colorScheme.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    'القسم: ${permission.department}',
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          const Spacer(),
                          if (permission.approvedBy != null && permission.approvedBy!.trim().isNotEmpty)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: colorScheme.primary,
                                borderRadius: BorderRadius.circular(6),
                                boxShadow: [
                                  BoxShadow(
                                    color: colorScheme.primary.withValues(alpha: 0.25),
                                    blurRadius: 3,
                                    offset: const Offset(0, 1),
                                  ),
                                ],
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_rounded, size: 11, color: colorScheme.onPrimary),
                                  const SizedBox(width: 4),
                                  ConstrainedBox(
                                    constraints: BoxConstraints(
                                      maxWidth: MediaQuery.sizeOf(context).width * 0.48,
                                    ),
                                    child: ApproverNameText(
                                      approvedBy: permission.approvedBy!,
                                      organizationUID: permission.organizationUID.isNotEmpty
                                          ? permission.organizationUID
                                          : widget.delegate.organizationUID,
                                      companyUID: permission.companyUID,
                                      currentUserUid: widget.delegate.uid,
                                      currentUserName: widget.delegate.fullName,
                                      prefix: '',
                                      overflow: TextOverflow.ellipsis,
                                      maxLines: 1,
                                      style: TextStyle(
                                        color: colorScheme.onPrimary,
                                        fontSize: 10.5,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],

                    // ── شريط وأزرار الموافقة والرفض المتصلة (Connected Action Button Group) للطلبات المعلقة ──
                    if (isPending) ...[
                      const SizedBox(height: 10),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 7),
                        decoration: BoxDecoration(
                          color: colorScheme.tertiaryContainer.withValues(alpha: 0.35),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.pending_actions_rounded, size: 16, color: colorScheme.onTertiaryContainer),
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                'طلب إذن تصوير ينتظر قرار السوبر أدمن:',
                                style: TextStyle(
                                  fontSize: 11,
                                  fontWeight: FontWeight.w600,
                                  color: colorScheme.onTertiaryContainer,
                                ),
                              ),
                            ),
                            const SizedBox(width: 8),
                            _buildPendingActionButtonsGroup(permission, colorScheme),
                          ],
                        ),
                      ),
                    ],

                    // ── تفاصيل الصلاحية والفروع ──
                    const SizedBox(height: 8),
                    Row(
                      children: [
                        Icon(Icons.date_range_rounded, size: 13, color: colorScheme.onSurfaceVariant),
                        const SizedBox(width: 4),
                        Text(
                          'الصلاحية: ${DateFormat('yyyy/MM/dd').format(permission.startDate)} - ${DateFormat('yyyy/MM/dd').format(permission.endDate)}',
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                        const Spacer(),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Icons.storefront_rounded, size: 11, color: colorScheme.onSurfaceVariant),
                              const SizedBox(width: 3),
                              Text(
                                '${permission.branchIds.length} فروع',
                                style: TextStyle(fontSize: 10.5, fontWeight: FontWeight.bold, color: colorScheme.onSurfaceVariant),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),

                    // ── القسم الموسع ──
                    AnimatedSize(
                      duration: AppMotionDurations.medium2,
                      curve: AppMotionCurves.emphasized,
                      child: isExpanded
                          ? Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Divider(height: 16),
                                const Text(
                                  'الفروع المشمولة بالإذن:',
                                  style: TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                                ),
                                const SizedBox(height: 6),
                                Wrap(
                                  spacing: 4,
                                  runSpacing: 4,
                                  children: permission.branchNames.map((name) {
                                    return Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                                      decoration: BoxDecoration(
                                        color: colorScheme.surfaceContainerHighest,
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(BranchDisplayCache.instance.displayName(name), style: const TextStyle(fontSize: 10.5)),
                                    );
                                  }).toList(),
                                ),
                                const SizedBox(height: 12),
                                // صف إجراءات المشرف الموسع
                                Row(
                                  mainAxisAlignment: MainAxisAlignment.end,
                                  children: [
                                    if (!isPending) ...[
                                      if (status != 'approved')
                                        FilledButton.icon(
                                          onPressed: () => _confirmApprovePermission(permission),
                                          style: FilledButton.styleFrom(
                                            backgroundColor: colorScheme.primary,
                                            foregroundColor: colorScheme.onPrimary,
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          icon: const Icon(Icons.check_circle_outline_rounded, size: 14),
                                          label: const Text('إعادة التفعيل والموافقة', style: TextStyle(fontSize: 11)),
                                        )
                                      else
                                        OutlinedButton.icon(
                                          onPressed: () => _confirmRejectPermission(permission),
                                          style: OutlinedButton.styleFrom(
                                            foregroundColor: colorScheme.error,
                                            side: BorderSide(color: colorScheme.error.withValues(alpha: 0.5)),
                                            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                                          ),
                                          icon: const Icon(Icons.cancel_outlined, size: 14),
                                          label: const Text('إلغاء الاعتماد / رفض', style: TextStyle(fontSize: 11)),
                                        ),
                                      const SizedBox(width: 8),
                                    ],
                                    // زر تمديد الصلاحية
                                    TextButton.icon(
                                      onPressed: () => _showExtendDatesDialog(permission),
                                      icon: const Icon(Icons.update_rounded, size: 15),
                                      label: const Text('تعديل الصلاحية', style: TextStyle(fontSize: 11)),
                                    ),
                                    const SizedBox(width: 4),
                                    // زر الحذف
                                    IconButton(
                                      icon: Icon(Icons.delete_outline_rounded, size: 18, color: colorScheme.error),
                                      tooltip: 'حذف الإذن نهائياً',
                                      onPressed: () => _confirmDeletePermission(permission),
                                    ),
                                  ],
                                ),
                              ],
                            )
                          : const SizedBox.shrink(),
                    ),
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── أزرار الموافقة والرفض المتصلة (Connected Action Button Group) ──
  Widget _buildPendingActionButtonsGroup(PhotoPermission permission, ColorScheme colorScheme) {
    final isRtl = Directionality.of(context) == TextDirection.rtl;
    final rejectRadius = BorderRadius.horizontal(
      right: isRtl ? const Radius.circular(8) : Radius.zero,
      left: isRtl ? Radius.zero : const Radius.circular(8),
    );
    final approveRadius = BorderRadius.horizontal(
      left: isRtl ? const Radius.circular(8) : Radius.zero,
      right: isRtl ? Radius.zero : const Radius.circular(8),
    );

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(8),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // زر الرفض
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: () => _confirmRejectPermission(permission),
              borderRadius: rejectRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.close_rounded, size: 14, color: colorScheme.error),
                    const SizedBox(width: 4),
                    Text(
                      'رفض',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.error,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
          // فاصل رأسي متصل
          Container(
            width: 1,
            height: 20,
            color: colorScheme.outlineVariant,
          ),
          // زر الاعتماد
          Material(
            color: colorScheme.primary,
            borderRadius: approveRadius,
            child: InkWell(
              onTap: () => _confirmApprovePermission(permission),
              borderRadius: approveRadius,
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 5),
                child: Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.check_rounded, size: 14, color: colorScheme.onPrimary),
                    const SizedBox(width: 4),
                    Text(
                      'اعتماد',
                      style: TextStyle(
                        fontSize: 11.5,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onPrimary,
                      ),
                    ),
                  ],
                ),
              ),
            ),
          ),
        ],
      ),
    );
  }

  // ── شارة الحالة المنعزلة بدون اسم المعتمد تحتها ──
  Widget _buildStatusBadge(PhotoPermission permission, ColorScheme colorScheme) {
    final now = DateTime.now();
    final todayStart = DateTime(now.year, now.month, now.day);
    final status = permission.status.toLowerCase();

    if (status == 'pending') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.tertiaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.tertiary.withValues(alpha: 0.3)),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.hourglass_top_rounded, size: 11, color: colorScheme.onTertiaryContainer),
            const SizedBox(width: 4),
            Text(
              'في انتظار الاعتماد',
              style: TextStyle(
                color: colorScheme.onTertiaryContainer,
                fontSize: 11,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      );
    } else if (status == 'rejected') {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
        ),
        child: Text(
          'مرفوض',
          style: TextStyle(color: colorScheme.onErrorContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else if (permission.endDate.isBefore(todayStart)) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.surfaceContainerHighest,
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.outlineVariant),
        ),
        child: Text(
          'منتهي',
          style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else if (permission.isSupervisorEnabled == false) {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.secondaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.secondary.withValues(alpha: 0.3)),
        ),
        child: Text(
          'معطل مؤقتاً',
          style: TextStyle(color: colorScheme.onSecondaryContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    } else {
      return Container(
        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
        decoration: BoxDecoration(
          color: colorScheme.primaryContainer.withValues(alpha: 0.7),
          borderRadius: BorderRadius.circular(6),
          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.3)),
        ),
        child: Text(
          'نشط',
          style: TextStyle(color: colorScheme.onPrimaryContainer, fontSize: 11, fontWeight: FontWeight.bold),
        ),
      );
    }
  }

  // ── إجراءات الموافقة والرفض والتعديل والحذف ──
  Future<void> _confirmApprovePermission(PhotoPermission permission) async {
    final confirmed = await _showActionConfirmDialog(
      title: 'اعتماد وموافقة إذن التصوير',
      content: 'هل أنت متأكد من الموافقة على إذن التصوير لشركة "${permission.companyName}" وتفعيله فورياً عبر الفروع المحددة؟',
      confirmLabel: 'تأكيد الموافقة',
      confirmIcon: Icons.check_circle_rounded,
      confirmColor: Theme.of(context).colorScheme.primary,
    );

    if (confirmed == true && mounted) {
      _permissionsBloc.add(
        ApprovePermissionRequested(
          organizationUID: permission.organizationUID.isNotEmpty
              ? permission.organizationUID
              : widget.delegate.organizationUID,
          companyUID: permission.companyUID,
          permissionId: permission.uid,
          status: 'approved',
          approvedBy: widget.delegate.fullName,
        ),
      );
    }
  }

  Future<void> _confirmRejectPermission(PhotoPermission permission) async {
    final confirmed = await _showActionConfirmDialog(
      title: 'رفض طلب إذن التصوير',
      content: 'هل أنت متأكد من رفض طلب إذن التصوير لشركة "${permission.companyName}"؟',
      confirmLabel: 'تأكيد الرفض',
      confirmIcon: Icons.cancel_rounded,
      confirmColor: Theme.of(context).colorScheme.error,
    );

    if (confirmed == true && mounted) {
      _permissionsBloc.add(
        ApprovePermissionRequested(
          organizationUID: permission.organizationUID.isNotEmpty
              ? permission.organizationUID
              : widget.delegate.organizationUID,
          companyUID: permission.companyUID,
          permissionId: permission.uid,
          status: 'rejected',
          approvedBy: widget.delegate.fullName,
        ),
      );
    }
  }

  Future<void> _confirmDeletePermission(PhotoPermission permission) async {
    final confirmed = await _showActionConfirmDialog(
      title: 'حذف إذن التصوير نهائياً',
      content: 'سيؤدي هذا الإجراء إلى حذف هذا الإذن وسجلاته نهائياً من قاعدة البيانات.',
      confirmLabel: 'حذف نهائي',
      confirmIcon: Icons.delete_forever_rounded,
      confirmColor: Theme.of(context).colorScheme.error,
    );

    if (confirmed == true && mounted) {
      _permissionsBloc.add(
        DeletePhotoPermissionRequested(
          organizationUID: permission.organizationUID.isNotEmpty
              ? permission.organizationUID
              : widget.delegate.organizationUID,
          companyUID: permission.companyUID,
          permissionId: permission.uid,
        ),
      );
    }
  }

  Future<void> _showExtendDatesDialog(PhotoPermission permission) async {
    DateTime start = permission.startDate;
    DateTime end = permission.endDate;

    final pickedRange = await showDateRangePicker(
      context: context,
      initialDateRange: DateTimeRange(start: start, end: end),
      firstDate: DateTime(2023),
      lastDate: DateTime(2030),
      helpText: 'اختر فترة الصلاحية الجديدة للإذن',
      cancelText: 'إلغاء',
      confirmText: 'تحديث',
    );

    if (pickedRange != null && mounted) {
      _permissionsBloc.add(
        UpdatePhotoPermissionDatesRequested(
          organizationUID: permission.organizationUID.isNotEmpty
              ? permission.organizationUID
              : widget.delegate.organizationUID,
          companyUID: permission.companyUID,
          permissionId: permission.uid,
          startDate: pickedRange.start,
          endDate: pickedRange.end,
        ),
      );
    }
  }

  Future<bool?> _showActionConfirmDialog({
    required String title,
    required String content,
    required String confirmLabel,
    required IconData confirmIcon,
    required Color confirmColor,
  }) {
    final isMobile = MediaQuery.of(context).size.width <= 768;

    if (isMobile) {
      final colorScheme = Theme.of(context).colorScheme;
      final isRtl = Directionality.of(context) == TextDirection.rtl;
      return showModalBottomSheet<bool>(
        context: context,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
        ),
        builder: (ctx) => Padding(
          padding: const EdgeInsets.all(20),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                width: 36,
                height: 4,
                decoration: BoxDecoration(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(height: 16),
              Icon(confirmIcon, color: confirmColor, size: 36),
              const SizedBox(height: 10),
              Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 17)),
              const SizedBox(height: 10),
              Text(content, textAlign: TextAlign.center, style: const TextStyle(fontSize: 13)),
              const SizedBox(height: 20),
              // أزرار متصلة Connected Button Group
              Container(
                height: 48,
                decoration: BoxDecoration(
                  borderRadius: BorderRadius.circular(24),
                  border: Border.all(color: colorScheme.outlineVariant),
                ),
                child: Row(
                  children: [
                    Expanded(
                      child: InkWell(
                        onTap: () => Navigator.pop(ctx, false),
                        borderRadius: BorderRadius.horizontal(
                          right: isRtl ? const Radius.circular(24) : Radius.zero,
                          left: isRtl ? Radius.zero : const Radius.circular(24),
                        ),
                        child: const Center(
                          child: Text(
                            'إلغاء',
                            style: TextStyle(fontWeight: FontWeight.bold),
                          ),
                        ),
                      ),
                    ),
                    VerticalDivider(
                      width: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant,
                    ),
                    Expanded(
                      child: Material(
                        color: confirmColor,
                        borderRadius: BorderRadius.horizontal(
                          left: isRtl ? const Radius.circular(24) : Radius.zero,
                          right: isRtl ? Radius.zero : const Radius.circular(24),
                        ),
                        child: InkWell(
                          onTap: () => Navigator.pop(ctx, true),
                          borderRadius: BorderRadius.horizontal(
                            left: isRtl ? const Radius.circular(24) : Radius.zero,
                            right: isRtl ? Radius.zero : const Radius.circular(24),
                          ),
                          child: Center(
                            child: Row(
                              mainAxisAlignment: MainAxisAlignment.center,
                              children: [
                                Icon(confirmIcon, size: 16, color: colorScheme.onPrimary),
                                const SizedBox(width: 6),
                                Text(
                                  confirmLabel,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.onPrimary,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
              ),
            ],
          ),
        ),
      );
    }

    return showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(confirmIcon, color: confirmColor, size: 24),
            const SizedBox(width: 8),
            Text(title, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
          ],
        ),
        content: Text(content),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton.icon(
            style: FilledButton.styleFrom(backgroundColor: confirmColor),
            onPressed: () => Navigator.pop(ctx, true),
            icon: Icon(confirmIcon, size: 16),
            label: Text(confirmLabel),
          ),
        ],
      ),
    );
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── التبويب الثاني: الصور والزيارات الميدانية (التسلسل الهرمي الذكي) ──
  // ══════════════════════════════════════════════════════════════════════════

  List<PhotoPermission> _getPermissions() {
    final state = _permissionsBloc.state;
    if (state is PhotoPermissionsLoaded) {
      return state.permissions;
    }
    return [];
  }

  List<String> _getAllBranches(List<PhotoPermission> permissions) {
    final set = <String>{..._firestoreBranches};
    for (final p in permissions) {
      for (final b in p.branchNames) {
        if (b.trim().isNotEmpty) set.add(b.trim());
      }
    }
    return set.toList()..sort();
  }

  Map<String, Map<String, dynamic>> _getCompaniesForBranch(
      String branchName, List<PhotoPermission> permissions) {
    final map = <String, Map<String, dynamic>>{};
    for (final p in permissions) {
      final matches = p.branchNames
          .any((b) => b.trim().toLowerCase() == branchName.trim().toLowerCase());
      if (matches && p.companyUID.isNotEmpty) {
        map[p.companyUID] = {
          'uid': p.companyUID,
          'name': p.companyName,
          'code': p.companyCode ?? _companyCodesCache[p.companyUID],
          'department': p.department,
          'status': p.status,
        };
      }
    }
    return map;
  }

  Map<String, Map<String, dynamic>> _getAllCompanies(List<PhotoPermission> permissions) {
    final map = <String, Map<String, dynamic>>{};
    for (final p in permissions) {
      if (p.companyUID.isNotEmpty && !map.containsKey(p.companyUID)) {
        map[p.companyUID] = {
          'uid': p.companyUID,
          'name': p.companyName,
          'code': p.companyCode ?? _companyCodesCache[p.companyUID],
          'department': p.department,
          'status': p.status,
        };
      }
    }
    return map;
  }

  Widget _buildPhotosView(ColorScheme colorScheme, ThemeData theme) {
    final permissions = _getPermissions();
    final allBranches = _getAllBranches(permissions);

    // المستوى 1: عرض الفروع (Branches)
    if (_selectedBranchDrillDown == null) {
      return _buildLevel1BranchesView(colorScheme, theme, permissions, allBranches);
    }

    // المستوى 2: عرض شركات الفرع المختار (Companies in selected branch)
    if (_selectedCompanyDrillDown == null) {
      return _buildLevel2CompaniesView(
          colorScheme, theme, permissions, _selectedBranchDrillDown!);
    }

    // المستوى 3: عرض صور الشركة بالفرع مع تحميل 20 صورة فقط (Photos with limit 20)
    return _buildLevel3PhotosView(colorScheme, theme);
  }

  // ── المستوى 1: عرض الفروع ──
  Widget _buildLevel1BranchesView(
    ColorScheme colorScheme,
    ThemeData theme,
    List<PhotoPermission> permissions,
    List<String> allBranches,
  ) {
    final filteredBranches = allBranches.where((b) {
      if (_branchSearchQuery.isEmpty) return true;
      return b.toLowerCase().contains(_branchSearchQuery.toLowerCase());
    }).toList();

    return RefreshIndicator(
      onRefresh: () async {
        await _fetchBranchesAndKPIs();
        _loadPermissionsData();
      },
      child: ListView(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 14),
        children: [
          // ── بطاقات الإحصائيات السريعة (0 صور محملة على الجهاز) ──
          _buildPhotosKPIHeader(
            colorScheme,
            totalPhotos: _totalPhotosCount,
            todayPhotos: _todayPhotosCount,
            branchesCount: allBranches.length,
          ),
          const SizedBox(height: 16),

          // ── شريط عنوان المستوى 1 ──
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(Icons.storefront_rounded, size: 20, color: colorScheme.primary),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'فروع الزيارات والتصوير الميداني',
                      style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                    ),
                    Text(
                      'اختر الفرع لعرض الشركات المعتمدة واستعراض الصور الملتقطة',
                      style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),

          // حقل البحث في الفروع
          TextField(
            controller: _branchSearchController,
            decoration: InputDecoration(
              hintText: 'البحث في الفروع (${allBranches.length} فرع)...',
              prefixIcon: const Icon(Icons.search_rounded),
              suffixIcon: _branchSearchQuery.isNotEmpty
                  ? IconButton(
                      icon: const Icon(Icons.clear_rounded, size: 18),
                      onPressed: () {
                        _branchSearchController.clear();
                        setState(() => _branchSearchQuery = '');
                      },
                    )
                  : null,
              filled: true,
              fillColor: colorScheme.surface,
              contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
              border: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant),
              ),
              enabledBorder: OutlineInputBorder(
                borderRadius: BorderRadius.circular(12),
                borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
              ),
            ),
            onChanged: (val) => setState(() => _branchSearchQuery = val.trim()),
          ),
          const SizedBox(height: 14),

          // شبكة الفروع
          if (filteredBranches.isEmpty)
            Padding(
              padding: const EdgeInsets.symmetric(vertical: 48),
              child: Center(
                child: Column(
                  children: [
                    Icon(Icons.storefront_outlined, size: 48, color: colorScheme.outline),
                    const SizedBox(height: 10),
                    Text(
                      'لا توجد فروع مطابقة للبحث "$_branchSearchQuery"',
                      style: TextStyle(color: colorScheme.onSurfaceVariant),
                    ),
                  ],
                ),
              ),
            )
          else
            LayoutBuilder(
              builder: (context, constraints) {
                final isDesktop = constraints.maxWidth >= 768;
                return GridView.builder(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: filteredBranches.length,
                  gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                    crossAxisCount: isDesktop ? 3 : (constraints.maxWidth > 480 ? 2 : 1),
                    childAspectRatio: isDesktop ? 2.8 : (constraints.maxWidth > 480 ? 2.2 : 3.6),
                    crossAxisSpacing: 10,
                    mainAxisSpacing: 10,
                  ),
                  itemBuilder: (context, index) {
                    final branch = filteredBranches[index];
                    final companiesCount = permissions
                        .where((p) => p.branchNames.any(
                            (b) => b.trim().toLowerCase() == branch.toLowerCase()))
                        .map((p) => p.companyUID)
                        .toSet()
                        .length;

                    return _buildBranchCard(branch, companiesCount, colorScheme);
                  },
                );
              },
            ),
        ],
      ),
    );
  }

  Widget _buildBranchCard(String branch, int companiesCount, ColorScheme colorScheme) {
    return InkWell(
      onTap: () {
        setState(() {
          _selectedBranchDrillDown = branch;
          _selectedCompanyDrillDown = null;
          _branchCompanySearchQuery = '';
          _branchCompanySearchController.clear();
        });
      },
      borderRadius: BorderRadius.circular(14),
      child: Container(
        padding: const EdgeInsets.all(12),
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(14),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.025),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        child: Row(
          children: [
            Container(
              width: 44,
              height: 44,
              decoration: BoxDecoration(
                color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
              ),
              child: Icon(Icons.storefront_rounded, color: colorScheme.primary, size: 22),
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Text(
                    branch,
                    style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  const SizedBox(height: 4),
                  Row(
                    children: [
                      Icon(Icons.business_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 4),
                      Text(
                        companiesCount > 0 ? '$companiesCount شركات مسجلة' : 'تصفح الصور',
                        style: TextStyle(
                          fontSize: 12,
                          color: companiesCount > 0
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                          fontWeight: companiesCount > 0 ? FontWeight.w600 : FontWeight.normal,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.outlineVariant),
          ],
        ),
      ),
    );
  }

  // ── المستوى 2: عرض شركات الفرع المختار ──
  Widget _buildLevel2CompaniesView(
    ColorScheme colorScheme,
    ThemeData theme,
    List<PhotoPermission> permissions,
    String branchName,
  ) {
    final branchCompaniesMap = _getCompaniesForBranch(branchName, permissions);
    final allSystemCompaniesMap = _getAllCompanies(permissions);

    // تصفية الشركات حسب البحث
    final filteredCompanies = branchCompaniesMap.values.where((c) {
      if (_branchCompanySearchQuery.isEmpty) return true;
      final query = _branchCompanySearchQuery.toLowerCase();
      final name = (c['name'] as String).toLowerCase();
      final code = (c['code']?.toString() ?? '').toLowerCase();
      final dept = (c['department'] as String? ?? '').toLowerCase();
      return name.contains(query) || code.contains(query) || dept.contains(query);
    }).toList();

    return ListView(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
      children: [
        // ── مسار التنقل (Breadcrumbs Bar) ──
        _buildBreadcrumbBar(
          colorScheme,
          items: [
            _BreadcrumbItem(
              label: 'الفروع',
              icon: Icons.storefront_rounded,
              onTap: () => setState(() {
                _selectedBranchDrillDown = null;
                _selectedCompanyDrillDown = null;
              }),
            ),
            _BreadcrumbItem(
              label: 'فرع ${BranchDisplayCache.instance.displayName(branchName)}',
              icon: Icons.place_rounded,
              isActive: true,
            ),
          ],
        ),
        const SizedBox(height: 12),

        // ── بطاقة الخيار العام: عرض جميع صور هذا الفرع مباشرة ──
        InkWell(
          onTap: () {
            setState(() {
              _selectedCompanyDrillDown = {
                'uid': '',
                'name': 'جميع الشركات بالفرع',
                'code': null,
              };
              _photosLimit = 20;
            });
            _loadPhotosData(
              branchName: branchName,
              companyUID: '',
              limit: 20,
            );
          },
          borderRadius: BorderRadius.circular(14),
          child: Container(
            padding: const EdgeInsets.all(14),
            decoration: BoxDecoration(
              gradient: LinearGradient(
                colors: [
                  colorScheme.primaryContainer.withValues(alpha: 0.45),
                  colorScheme.surface,
                ],
                begin: Alignment.topRight,
                end: Alignment.bottomLeft,
              ),
              borderRadius: BorderRadius.circular(14),
              border: Border.all(color: colorScheme.primary.withValues(alpha: 0.35)),
            ),
            child: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.primary,
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: const Icon(Icons.photo_library_rounded, color: Colors.white, size: 22),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'عرض جميع صور هذا الفرع (لكل الشركات)',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
                      ),
                      const SizedBox(height: 3),
                      Text(
                        'استعراض أحدث 20 صورة تم التقاطها في فرع "${BranchDisplayCache.instance.displayName(branchName)}"',
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                      ),
                    ],
                  ),
                ),
                Icon(Icons.arrow_forward_ios_rounded, size: 14, color: colorScheme.primary),
              ],
            ),
          ),
        ),
        const SizedBox(height: 14),

        // ── شريط بحث الشركات ──
        TextField(
          controller: _branchCompanySearchController,
          decoration: InputDecoration(
            hintText: 'البحث عن شركة في فرع ${BranchDisplayCache.instance.displayName(branchName)}...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _branchCompanySearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _branchCompanySearchController.clear();
                      setState(() => _branchCompanySearchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
          onChanged: (val) => setState(() => _branchCompanySearchQuery = val.trim()),
        ),
        const SizedBox(height: 14),

        // ── عنوان قائمة الشركات ──
        Row(
          children: [
            Icon(Icons.business_rounded, size: 18, color: colorScheme.primary),
            const SizedBox(width: 8),
            Text(
              'الشركات المسجلة بهذا الفرع (${filteredCompanies.length})',
              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
            ),
          ],
        ),
        const SizedBox(height: 10),

        if (filteredCompanies.isEmpty) ...[
          Padding(
            padding: const EdgeInsets.symmetric(vertical: 24),
            child: Center(
              child: Column(
                children: [
                  Icon(Icons.business_outlined, size: 44, color: colorScheme.outline),
                  const SizedBox(height: 8),
                  Text(
                    branchCompaniesMap.isEmpty
                        ? 'لم يتم تسجيل أذونات تصوير مسبقة لشركات بهذا الفرع.'
                        : 'لا توجد شركات مطابقة للبحث.',
                    style: TextStyle(color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ),
          if (allSystemCompaniesMap.isNotEmpty) ...[
            const Divider(),
            const SizedBox(height: 8),
            Text(
              'أو يمكنك اختيار أي شركة مسجلة بالنظام للاستعلام:',
              style: TextStyle(
                  fontSize: 12.5, fontWeight: FontWeight.bold, color: colorScheme.primary),
            ),
            const SizedBox(height: 10),
            ...allSystemCompaniesMap.values.map(
              (c) => _buildCompanyItemCard(c, colorScheme, branchName),
            ),
          ],
        ] else
          ...filteredCompanies.map(
            (c) => _buildCompanyItemCard(c, colorScheme, branchName),
          ),
      ],
    );
  }

  Widget _buildCompanyItemCard(
      Map<String, dynamic> comp, ColorScheme colorScheme, String branchName) {
    final companyName = comp['name'] as String? ?? '';
    final companyCode = comp['code'] as int?;
    final department = comp['department'] as String?;

    return Container(
      margin: const EdgeInsets.only(bottom: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
        boxShadow: [
          BoxShadow(
            color: Colors.black.withValues(alpha: 0.02),
            blurRadius: 4,
            offset: const Offset(0, 1.5),
          ),
        ],
      ),
      child: ListTile(
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
        leading: Container(
          width: 40,
          height: 40,
          decoration: BoxDecoration(
            color: colorScheme.primaryContainer.withValues(alpha: 0.4),
            borderRadius: BorderRadius.circular(10),
          ),
          child: Icon(Icons.business_rounded, color: colorScheme.primary, size: 20),
        ),
        title: CompanyNameWithCode(
          organizationUID: widget.delegate.organizationUID,
          companyUID: comp['uid'] as String? ?? '',
          companyName: companyName,
          companyCode: companyCode,
          style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14.5),
        ),
        subtitle: department != null && department.isNotEmpty
            ? Padding(
                padding: const EdgeInsets.only(top: 4),
                child: Row(
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh,
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Text(
                        department,
                        style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                      ),
                    ),
                  ],
                ),
              )
            : null,
        trailing: FilledButton.tonalIcon(
          onPressed: () {
            setState(() {
              _selectedCompanyDrillDown = comp;
              _photosLimit = 20;
            });
            _loadPhotosData(
              branchName: branchName,
              companyUID: comp['uid'] as String? ?? '',
              limit: 20,
            );
          },
          icon: const Icon(Icons.photo_library_outlined, size: 16),
          label: const Text('عرض الصور', style: TextStyle(fontSize: 12)),
          style: FilledButton.styleFrom(
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
          ),
        ),
        onTap: () {
          setState(() {
            _selectedCompanyDrillDown = comp;
            _photosLimit = 20;
          });
          _loadPhotosData(
            branchName: branchName,
            companyUID: comp['uid'] as String? ?? '',
            limit: 20,
          );
        },
      ),
    );
  }

  // ── المستوى 3: عرض صور الشركة بالفرع (بحد 20 صورة مبدئياً) ──
  Widget _buildLevel3PhotosView(ColorScheme colorScheme, ThemeData theme) {
    final branchName = _selectedBranchDrillDown!;
    final companyName = _selectedCompanyDrillDown!['name'] as String? ?? 'الشركة';
    final companyUID = _selectedCompanyDrillDown!['uid'] as String? ?? '';

    return BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
      bloc: _photosBloc,
      builder: (context, state) {
        List<CapturedPhoto> filtered = [];
        if (state is CapturedPhotosLoaded) {
          filtered = state.photos.where((photo) {
            if (_photosSearchQuery.isNotEmpty) {
              final q = _photosSearchQuery.toLowerCase();
              final matchDel = photo.delegateName.toLowerCase().contains(q);
              final matchComm = photo.comment.toLowerCase().contains(q);
              if (!matchDel && !matchComm) return false;
            }
            final now = DateTime.now();
            final todayStart = DateTime(now.year, now.month, now.day);
            if (_selectedPhotoDateFilter == 'today') {
              if (photo.capturedAt.isBefore(todayStart)) return false;
            } else if (_selectedPhotoDateFilter == 'week') {
              final weekAgo = todayStart.subtract(const Duration(days: 7));
              if (photo.capturedAt.isBefore(weekAgo)) return false;
            } else if (_selectedPhotoDateFilter == 'month') {
              final monthAgo = todayStart.subtract(const Duration(days: 30));
              if (photo.capturedAt.isBefore(monthAgo)) return false;
            } else if (_selectedPhotoDateFilter == 'custom' && _customPhotoDate != null) {
              final customStart = DateTime(
                  _customPhotoDate!.year, _customPhotoDate!.month, _customPhotoDate!.day);
              final customEnd = customStart.add(const Duration(days: 1));
              if (photo.capturedAt.isBefore(customStart) ||
                  photo.capturedAt.isAfter(customEnd)) {
                return false;
              }
            }
            return true;
          }).toList();
        }

        return RefreshIndicator(
          onRefresh: () async {
            _loadPhotosData(
              branchName: branchName,
              companyUID: companyUID,
              limit: _photosLimit,
            );
          },
          child: CustomScrollView(
            slivers: [
              // ── مسار التنقل وشريط البحث والفلاتر ──
              SliverPadding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 0),
                sliver: SliverToBoxAdapter(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildBreadcrumbBar(
                        colorScheme,
                        items: [
                          _BreadcrumbItem(
                            label: 'الفروع',
                            icon: Icons.storefront_rounded,
                            onTap: () => setState(() {
                              _selectedBranchDrillDown = null;
                              _selectedCompanyDrillDown = null;
                            }),
                          ),
                          _BreadcrumbItem(
                            label: BranchDisplayCache.instance.displayName(branchName),
                            icon: Icons.place_rounded,
                            onTap: () => setState(() {
                              _selectedCompanyDrillDown = null;
                            }),
                          ),
                          _BreadcrumbItem(
                            label: companyName,
                            icon: Icons.business_rounded,
                            isActive: true,
                          ),
                        ],
                      ),
                      const SizedBox(height: 12),
                      _buildLevel3PhotoFilters(colorScheme),
                      const SizedBox(height: 12),
                    ],
                  ),
                ),
              ),

              // ── حالة التحميل أو الخطأ أو القائمة الفارغة ──
              if (state is PhotoPermissionLoading)
                const SliverToBoxAdapter(
                  child: Padding(
                    padding: EdgeInsets.symmetric(vertical: 48),
                    child: Center(child: CircularProgressIndicator()),
                  ),
                )
              else if (state is PhotoPermissionError)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                          const SizedBox(height: 10),
                          Text(state.message, textAlign: TextAlign.center),
                          const SizedBox(height: 12),
                          FilledButton.icon(
                            onPressed: () => _loadPhotosData(
                              branchName: branchName,
                              companyUID: companyUID,
                              limit: _photosLimit,
                            ),
                            icon: const Icon(Icons.refresh_rounded),
                            label: const Text('إعادة المحاولة'),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (state is CapturedPhotosLoaded && filtered.isEmpty)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.symmetric(vertical: 48),
                    child: Center(
                      child: Column(
                        children: [
                          Icon(Icons.photo_library_outlined,
                              size: 52, color: colorScheme.outline),
                          const SizedBox(height: 12),
                          Text(
                            state.photos.isEmpty
                                ? 'لا توجد صور ملتقطة لـ "$companyName" في فرع "${BranchDisplayCache.instance.displayName(branchName)}".'
                                : 'لا توجد صور مطابقة لفلاتر البحث المحددة.',
                            style: TextStyle(color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
                  ),
                )
              else if (state is CapturedPhotosLoaded) ...[
                // ── شبكة أو قائمة الصور مع المحاكاة الافتراضية (Slivers) ──
                if (_isPhotoGridView)
                  SliverLayoutBuilder(
                    builder: (context, constraints) {
                      final crossAxisCount = constraints.crossAxisExtent > 900
                          ? 4
                          : constraints.crossAxisExtent > 600
                              ? 3
                              : 2;
                      return SliverPadding(
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        sliver: SliverGrid(
                          gridDelegate: SliverGridDelegateWithFixedCrossAxisCount(
                            crossAxisCount: crossAxisCount,
                            crossAxisSpacing: 10,
                            mainAxisSpacing: 10,
                            childAspectRatio: 0.78,
                          ),
                          delegate: SliverChildBuilderDelegate(
                            (context, index) => _buildPhotoGridCard(filtered[index], colorScheme),
                            childCount: filtered.length,
                          ),
                        ),
                      );
                    },
                  )
                else
                  SliverPadding(
                    padding: const EdgeInsets.symmetric(horizontal: 16),
                    sliver: SliverList(
                      delegate: SliverChildBuilderDelegate(
                        (context, index) => _buildPhotoListItem(filtered[index], colorScheme),
                        childCount: filtered.length,
                      ),
                    ),
                  ),

                // ── زر التصفح وتنزيل المزيد (Pagination: +20) ──
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsets.fromLTRB(16, 16, 16, 24),
                    child: state.photos.length >= _photosLimit
                        ? Center(
                            child: OutlinedButton.icon(
                              onPressed: _isLoadingMorePhotos
                                  ? null
                                  : () async {
                                      setState(() {
                                        _photosLimit += 20;
                                        _isLoadingMorePhotos = true;
                                      });
                                      _loadPhotosData(
                                        branchName: branchName,
                                        companyUID: companyUID,
                                        limit: _photosLimit,
                                      );
                                      setState(() => _isLoadingMorePhotos = false);
                                    },
                              icon: _isLoadingMorePhotos
                                  ? const SizedBox(
                                      width: 16,
                                      height: 16,
                                      child: CircularProgressIndicator(strokeWidth: 2),
                                    )
                                  : const Icon(Icons.add_photo_alternate_rounded, size: 18),
                              label: Text(
                                  'تحميل المزيد من الصور (+20) • المعروض: ${state.photos.length}'),
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(
                                    horizontal: 20, vertical: 12),
                                shape: RoundedRectangleBorder(
                                    borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          )
                        : Center(
                            child: Text(
                              'تم عرض جميع الصور المتاحة (${state.photos.length} صورة)',
                              style: TextStyle(
                                  fontSize: 12, color: colorScheme.onSurfaceVariant),
                            ),
                          ),
                  ),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildLevel3PhotoFilters(ColorScheme colorScheme) {
    return Column(
      children: [
        TextField(
          controller: _photosSearchController,
          decoration: InputDecoration(
            hintText: 'البحث باسم المندوب أو الملاحظة...',
            prefixIcon: const Icon(Icons.search_rounded),
            suffixIcon: _photosSearchQuery.isNotEmpty
                ? IconButton(
                    icon: const Icon(Icons.clear_rounded, size: 18),
                    onPressed: () {
                      _photosSearchController.clear();
                      setState(() => _photosSearchQuery = '');
                    },
                  )
                : null,
            filled: true,
            fillColor: colorScheme.surface,
            contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
            border: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant),
            ),
            enabledBorder: OutlineInputBorder(
              borderRadius: BorderRadius.circular(12),
              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
            ),
          ),
          onChanged: (val) => setState(() => _photosSearchQuery = val.trim()),
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            _buildDateFilterDropdown(colorScheme),
            const Spacer(),
            IconButton.filledTonal(
              icon: Icon(_isPhotoGridView ? Icons.view_list_rounded : Icons.grid_view_rounded,
                  size: 18),
              tooltip: _isPhotoGridView ? 'عرض كقائمة' : 'عرض كشبكة صور',
              onPressed: () => setState(() => _isPhotoGridView = !_isPhotoGridView),
            ),
            const SizedBox(width: 8),
            IconButton.filledTonal(
              icon: const Icon(Icons.refresh_rounded, size: 18),
              tooltip: 'تحديث الصور',
              onPressed: () => _loadPhotosData(),
            ),
          ],
        ),
      ],
    );
  }

  Widget _buildBreadcrumbBar(ColorScheme colorScheme,
      {required List<_BreadcrumbItem> items}) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: SingleChildScrollView(
        scrollDirection: Axis.horizontal,
        child: Row(
          children: [
            for (int i = 0; i < items.length; i++) ...[
              if (i > 0)
                Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 4),
                  child: Icon(Icons.chevron_left_rounded,
                      size: 18, color: colorScheme.outlineVariant),
                ),
              InkWell(
                onTap: items[i].onTap,
                borderRadius: BorderRadius.circular(8),
                child: Container(
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                  decoration: BoxDecoration(
                    color: items[i].isActive
                        ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                        : Colors.transparent,
                    borderRadius: BorderRadius.circular(8),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        items[i].icon,
                        size: 15,
                        color: items[i].isActive
                            ? colorScheme.primary
                            : colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        items[i].label,
                        style: TextStyle(
                          fontSize: 12.5,
                          fontWeight:
                              items[i].isActive ? FontWeight.bold : FontWeight.w500,
                          color: items[i].isActive
                              ? colorScheme.primary
                              : colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ],
          ],
        ),
      ),
    );
  }

  Widget _buildPhotosKPIHeader(ColorScheme colorScheme,
      {required int totalPhotos, required int todayPhotos, required int branchesCount}) {
    return Row(
      children: [
        Expanded(
          child: _buildMiniKPICard(
            colorScheme,
            title: 'إجمالي الصور',
            count: '$totalPhotos',
            icon: Icons.photo_library_rounded,
            color: colorScheme.primary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMiniKPICard(
            colorScheme,
            title: 'صور اليوم',
            count: '$todayPhotos',
            icon: Icons.today_rounded,
            color: colorScheme.secondary,
          ),
        ),
        const SizedBox(width: 8),
        Expanded(
          child: _buildMiniKPICard(
            colorScheme,
            title: 'الفروع المغطاة',
            count: '$branchesCount',
            icon: Icons.storefront_rounded,
            color: colorScheme.tertiary,
          ),
        ),
      ],
    );
  }

  Widget _buildDateFilterDropdown(ColorScheme colorScheme) {
    final dateLabels = {
      'all': 'كل التواريخ',
      'today': 'اليوم',
      'week': 'آخر 7 أيام',
      'month': 'هذا الشهر',
      'custom': _customPhotoDate != null
          ? DateFormat('yyyy/MM/dd').format(_customPhotoDate!)
          : 'تاريخ محدد...',
    };

    return PopupMenuButton<String>(
      initialValue: _selectedPhotoDateFilter,
      tooltip: 'تصفية حسب التاريخ',
      color: colorScheme.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (val) async {
        if (val == 'custom') {
          final picked = await showDatePicker(
            context: context,
            initialDate: _customPhotoDate ?? DateTime.now(),
            firstDate: DateTime(2023),
            lastDate: DateTime.now(),
          );
          if (picked != null) {
            setState(() {
              _customPhotoDate = picked;
              _selectedPhotoDateFilter = 'custom';
            });
          }
        } else {
          setState(() {
            _selectedPhotoDateFilter = val;
            _customPhotoDate = null;
          });
        }
      },
      itemBuilder: (context) => [
        _buildPopupCheckItem('all', dateLabels['all']!, Icons.event_note_rounded, colorScheme),
        _buildPopupCheckItem('today', dateLabels['today']!, Icons.today_rounded, colorScheme),
        _buildPopupCheckItem('week', dateLabels['week']!, Icons.date_range_rounded, colorScheme),
        _buildPopupCheckItem('month', dateLabels['month']!, Icons.calendar_month_rounded, colorScheme),
        _buildPopupCheckItem('custom', dateLabels['custom']!, Icons.edit_calendar_rounded, colorScheme),
      ],
      child: Container(
        height: 38,
        padding: const EdgeInsets.symmetric(horizontal: 10),
        decoration: BoxDecoration(
          color: _selectedPhotoDateFilter != 'all'
              ? colorScheme.primaryContainer.withValues(alpha: 0.5)
              : colorScheme.surface,
          borderRadius: BorderRadius.circular(10),
          border: Border.all(
            color: _selectedPhotoDateFilter != 'all'
                ? colorScheme.primary.withValues(alpha: 0.5)
                : colorScheme.outlineVariant,
          ),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.calendar_today_rounded, size: 15, color: colorScheme.primary),
            const SizedBox(width: 6),
            Text(
              dateLabels[_selectedPhotoDateFilter] ?? 'التاريخ',
              style: TextStyle(
                fontSize: 12,
                fontWeight: FontWeight.bold,
                color: _selectedPhotoDateFilter != 'all' ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
            const SizedBox(width: 4),
            Icon(Icons.expand_more_rounded, size: 16, color: colorScheme.onSurfaceVariant),
          ],
        ),
      ),
    );
  }


  Widget _buildPhotoGridCard(CapturedPhoto photo, ColorScheme colorScheme) {
    return InkWell(
      onTap: () => _openPhotoDetailModal(photo),
      borderRadius: BorderRadius.circular(12),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(12),
          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
          boxShadow: [
            BoxShadow(
              color: Colors.black.withValues(alpha: 0.04),
              blurRadius: 4,
              offset: const Offset(0, 2),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // الصورة
            Expanded(
              child: Stack(
                fit: StackFit.expand,
                children: [
                  AppPhotoImage(
                    photoUrl: photo.photoUrl,
                    fit: BoxFit.cover,
                    isThumbnail: true,
                  ),
                  // شارة الفرع أعلى الصورة
                  Positioned(
                    top: 6,
                    right: 6,
                    child: Container(
                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                      decoration: BoxDecoration(
                        color: Colors.black.withValues(alpha: 0.65),
                        borderRadius: BorderRadius.circular(6),
                      ),
                      child: Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          const Icon(Icons.storefront_rounded, size: 10, color: Colors.amber),
                          const SizedBox(width: 3),
                          ConstrainedBox(
                            constraints: const BoxConstraints(maxWidth: 80),
                            child: Text(
                              BranchDisplayCache.instance.displayName(photo.branchName),
                              style: const TextStyle(color: Colors.white, fontSize: 9.5, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
            ),

            // بيانات الصورة أسفلها
            Padding(
              padding: const EdgeInsets.all(8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    photo.delegateName,
                    style: const TextStyle(fontSize: 11.5, fontWeight: FontWeight.bold),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  if (photo.companyName.isNotEmpty) ...[
                    const SizedBox(height: 2),
                    Text(
                      photo.companyName,
                      style: TextStyle(fontSize: 10.5, color: colorScheme.primary, fontWeight: FontWeight.w600),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                  const SizedBox(height: 2),
                  Row(
                    children: [
                      Icon(Icons.schedule_rounded, size: 10, color: colorScheme.onSurfaceVariant),
                      const SizedBox(width: 3),
                      Expanded(
                        child: Text(
                          DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(photo.capturedAt),
                          style: TextStyle(fontSize: 9.5, color: colorScheme.onSurfaceVariant),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── عنصر قائمة الصورة الواحدة (Photo List Item) ──
  Widget _buildPhotoListItem(CapturedPhoto photo, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      margin: const EdgeInsets.only(bottom: 8),
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => _openPhotoDetailModal(photo),
        child: Padding(
          padding: const EdgeInsets.all(10),
          child: Row(
            children: [
              // صورة مصغرة
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: SizedBox(
                  width: 64,
                  height: 64,
                  child: AppPhotoImage(
                    photoUrl: photo.photoUrl,
                    fit: BoxFit.cover,
                    isThumbnail: true,
                  ),
                ),
              ),
              const SizedBox(width: 12),
              // تفاصيل
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      photo.delegateName,
                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                    ),
                    const SizedBox(height: 3),
                    Row(
                      children: [
                        Icon(Icons.storefront_rounded, size: 12, color: colorScheme.primary),
                        const SizedBox(width: 4),
                        Text(
                          BranchDisplayCache.instance.displayName(photo.branchName),
                          style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
                        ),
                        if (photo.companyName.isNotEmpty) ...[
                          const SizedBox(width: 8),
                          Icon(Icons.business_rounded, size: 12, color: colorScheme.primary),
                          const SizedBox(width: 4),
                          Expanded(
                            child: Text(
                              photo.companyName,
                              style: TextStyle(fontSize: 11, color: colorScheme.primary, fontWeight: FontWeight.bold),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                        ],
                      ],
                    ),
                    const SizedBox(height: 3),
                    Text(
                      DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(photo.capturedAt),
                      style: TextStyle(fontSize: 10, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
                    ),
                    if (photo.comment.isNotEmpty) ...[
                      const SizedBox(height: 2),
                      Text(
                        photo.comment,
                        style: TextStyle(fontSize: 10.5, fontStyle: FontStyle.italic, color: colorScheme.onSurface),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ],
                ),
              ),
              const Icon(Icons.arrow_forward_ios_rounded, size: 14),
            ],
          ),
        ),
      ),
    );
  }

  // ── نافذة معاينة الصورة عالية الدقة مع Pan & Zoom والحفظ والمشاركة ──
  void _openPhotoDetailModal(CapturedPhoto photo) {
    showDialog(
      context: context,
      barrierColor: Colors.black87,
      builder: (dialogContext) {
        bool isSaving = false;
        bool saveSuccess = false;
        String? statusText;

        return StatefulBuilder(
          builder: (dialogContentContext, setDialogState) {
            final colorScheme = Theme.of(dialogContentContext).colorScheme;

            return Dialog(
              backgroundColor: Colors.transparent,
              insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 20),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                children: [
                  // شريط العنوان والإغلاق
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        photo.delegateName.isNotEmpty ? photo.delegateName : 'معاينة الصورة الميدانية',
                        style: const TextStyle(color: Colors.white, fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      IconButton(
                        icon: const Icon(Icons.close_rounded, color: Colors.white, size: 28),
                        onPressed: () => Navigator.pop(dialogContext),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),

                  // الصورة التفاعلية (Zoom & Pan)
                  Flexible(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(16),
                      child: InteractiveViewer(
                        panEnabled: true,
                        minScale: 0.5,
                        maxScale: 4.0,
                        child: AppPhotoImage(
                          photoUrl: photo.photoUrl,
                          fit: BoxFit.contain,
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 12),

                  // كارت بيانات الصورة
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                    decoration: BoxDecoration(
                      color: Colors.black.withValues(alpha: 0.8),
                      borderRadius: BorderRadius.circular(12),
                      border: Border.all(color: Colors.white24),
                    ),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Row(
                          children: [
                            const Icon(Icons.storefront_rounded, size: 14, color: Colors.amber),
                            const SizedBox(width: 4),
                            Text(
                              BranchDisplayCache.instance.displayName(photo.branchName),
                              style: const TextStyle(color: Colors.white, fontSize: 12, fontWeight: FontWeight.bold),
                            ),
                            if (photo.companyName.isNotEmpty) ...[
                              const SizedBox(width: 10),
                              const Icon(Icons.business_rounded, size: 14, color: Colors.cyanAccent),
                              const SizedBox(width: 4),
                              Text(
                                photo.companyName,
                                style: const TextStyle(color: Colors.cyanAccent, fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                            ],
                            const Spacer(),
                            Text(
                              DateFormat('yyyy/MM/dd - hh:mm a', 'ar').format(photo.capturedAt),
                              style: const TextStyle(color: Colors.white70, fontSize: 11),
                            ),
                          ],
                        ),
                        if (photo.comment.isNotEmpty) ...[
                          const SizedBox(height: 6),
                          Text(
                            'ملاحظات: ${photo.comment}',
                            style: const TextStyle(color: Colors.white, fontSize: 11.5),
                          ),
                        ],
                        if (photo.latitude != 0.0 && photo.longitude != 0.0) ...[
                          const SizedBox(height: 6),
                          InkWell(
                            onTap: () {
                              final mapUrl = 'https://www.google.com/maps/search/?api=1&query=${photo.latitude},${photo.longitude}';
                              launchUrl(Uri.parse(mapUrl), mode: LaunchMode.externalApplication);
                            },
                            child: Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                const Icon(Icons.location_on_rounded, size: 13, color: Colors.greenAccent),
                                const SizedBox(width: 4),
                                Text(
                                  'الموقع الجغرافي: ${photo.latitude.toStringAsFixed(4)}, ${photo.longitude.toStringAsFixed(4)} (فتح الخريطة)',
                                  style: const TextStyle(color: Colors.greenAccent, fontSize: 11, decoration: TextDecoration.underline),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ],
                    ),
                  ),
                  const SizedBox(height: 10),

                  // أزرار الإجراءات (حفظ، مشاركة، حذف)
                  Row(
                    children: [
                      // زر الحذف
                      IconButton.filledTonal(
                        onPressed: () {
                          Navigator.pop(dialogContext);
                          _confirmDeletePhoto(photo);
                        },
                        style: IconButton.styleFrom(
                          backgroundColor: Colors.red.withValues(alpha: 0.2),
                          foregroundColor: Colors.redAccent,
                        ),
                        icon: const Icon(Icons.delete_forever_rounded, size: 20),
                        tooltip: 'حذف الصورة نهائياً',
                      ),
                      const SizedBox(width: 8),

                      // زر المشاركة
                      IconButton.filledTonal(
                        onPressed: () async {
                          try {
                            File? file;
                            if (photo.photoUrl.startsWith('http://') || photo.photoUrl.startsWith('https://')) {
                              file = await PhotoCacheManager.instance.getSingleFile(photo.photoUrl);
                            } else {
                              file = await PhotoCacheManager.resolveLocalPhotoFile(photo.photoUrl);
                            }
                            if (file != null && await file.exists()) {
                              // ignore: deprecated_member_use
                              await Share.shareXFiles([XFile(file.path)], text: 'صورة ميدانية - ${BranchDisplayCache.instance.displayName(photo.branchName)}');
                            }
                          } catch (_) {}
                        },
                        icon: const Icon(Icons.share_rounded, size: 20),
                        tooltip: 'مشاركة الصورة',
                      ),
                      const SizedBox(width: 8),

                      // زر الحفظ في الهاتف
                      Expanded(
                        child: FilledButton.icon(
                          onPressed: isSaving
                              ? null
                              : () async {
                                  setDialogState(() {
                                    isSaving = true;
                                    statusText = null;
                                  });
                                  try {
                                    final success = await PhotoCacheManager.savePhotoToGallery(
                                      context,
                                      photoUrl: photo.photoUrl,
                                    );
                                    if (dialogContentContext.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                        saveSuccess = success;
                                        statusText = success
                                            ? 'تم حفظ الصورة في الهاتف بنجاح'
                                            : 'يرجى منح إذن الوصول للصور من الإعدادات.';
                                      });
                                    }
                                  } catch (e) {
                                    if (dialogContentContext.mounted) {
                                      setDialogState(() {
                                        isSaving = false;
                                        saveSuccess = false;
                                        statusText = 'تعذر حفظ الصورة: $e';
                                      });
                                    }
                                  }
                                },
                          icon: isSaving
                              ? const SizedBox(
                                  width: 18,
                                  height: 18,
                                  child: CircularProgressIndicator(strokeWidth: 2, color: Colors.white),
                                )
                              : Icon(saveSuccess ? Icons.check_circle_rounded : Icons.download_rounded, size: 18),
                          label: Text(
                            isSaving
                                ? 'جاري الحفظ...'
                                : saveSuccess
                                    ? 'تم الحفظ في الهاتف'
                                    : 'حفظ الصورة',
                            style: const TextStyle(fontWeight: FontWeight.bold),
                          ),
                          style: FilledButton.styleFrom(
                            backgroundColor: saveSuccess ? Colors.green.shade700 : colorScheme.primary,
                          ),
                        ),
                      ),
                    ],
                  ),
                  if (statusText != null) ...[
                    const SizedBox(height: 8),
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                      decoration: BoxDecoration(
                        color: saveSuccess ? Colors.green.shade800 : colorScheme.errorContainer,
                        borderRadius: BorderRadius.circular(8),
                      ),
                      child: Text(
                        statusText!,
                        style: TextStyle(
                          color: saveSuccess ? Colors.white : colorScheme.onErrorContainer,
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ),
                  ],
                ],
              ),
            );
          },
        );
      },
    );
  }

  Future<void> _confirmDeletePhoto(CapturedPhoto photo) async {
    final confirmed = await _showActionConfirmDialog(
      title: 'تأكيد حذف الصورة الميدانية',
      content: 'هل أنت متأكد من حذف هذه الصورة الملتقطة بواسطة "${photo.delegateName}" بفرع "${BranchDisplayCache.instance.displayName(photo.branchName)}" نهائياً؟',
      confirmLabel: 'حذف نهائي',
      confirmIcon: Icons.delete_forever_rounded,
      confirmColor: Colors.red.shade700,
    );

    if (confirmed == true && mounted) {
      _photosBloc.add(
        DeleteCapturedPhotoRequested(
          photoId: photo.uid,
          organizationUID: photo.organizationUID.isNotEmpty
              ? photo.organizationUID
              : widget.delegate.organizationUID,
          companyUID: photo.companyUID,
          permissionId: photo.permissionId,
          photoUrl: photo.photoUrl,
        ),
      );
    }
  }

  // ══════════════════════════════════════════════════════════════════════════
  // ── التبويب الثالث: التقرير المالي والفواتير ──
  // ══════════════════════════════════════════════════════════════════════════
  Widget _buildBillingReportView(ColorScheme colorScheme, ThemeData theme) {
    return BlocBuilder<PhotoPermissionBloc, PhotoPermissionState>(
      bloc: _permissionsBloc,
      builder: (context, state) {
        if (state is PhotoPermissionLoading) {
          return const Center(child: CircularProgressIndicator());
        }

        if (state is PhotoPermissionError) {
          return Center(
            child: Column(
              mainAxisAlignment: MainAxisAlignment.center,
              children: [
                Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
                const SizedBox(height: 12),
                Text(state.message, textAlign: TextAlign.center),
                const SizedBox(height: 12),
                FilledButton.icon(
                  onPressed: _loadPermissionsData,
                  icon: const Icon(Icons.refresh_rounded),
                  label: const Text('إعادة المحاولة'),
                ),
              ],
            ),
          );
        }

        if (state is PhotoPermissionsLoaded) {
          final now = DateTime.now();
          final todayStart = DateTime(now.year, now.month, now.day);

          // تصفية الشركات ذات الأذونات النشطة والموافَق عليها
          final activeApproved = state.permissions.where((p) {
            return p.status.toLowerCase() == 'approved' && !p.endDate.isBefore(todayStart);
          }).toList();

          // تجميع الشركات الفريدة لاحتساب الفاتورة الشهرية بدقة (500 ج.م لكل شركة)
          final Map<String, PhotoPermission> uniqueCompanies = {};
          for (final perm in activeApproved) {
            if (!uniqueCompanies.containsKey(perm.companyUID)) {
              uniqueCompanies[perm.companyUID] = perm;
            }
          }
          final activeCompaniesList = uniqueCompanies.values.toList();
          _fetchCompanyCodes(activeCompaniesList);

          final totalMonthlyBilling = activeCompaniesList.length * 500;

          return ListView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            children: [
              // ── بطاقات مؤشرات التقرير المالي ──
              Row(
                children: [
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.primaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'الشركات المشتركة المفعّلة',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Text(
                            '${activeCompaniesList.length}',
                            style: TextStyle(
                              fontSize: 26,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onPrimaryContainer,
                            ),
                          ),
                          const SizedBox(height: 2),
                          Text(
                            'اشتراك شهري سارٍ',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onPrimaryContainer.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Container(
                      padding: const EdgeInsets.all(16),
                      decoration: BoxDecoration(
                        color: colorScheme.secondaryContainer,
                        borderRadius: BorderRadius.circular(16),
                      ),
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'إجمالي الفواتير الشهرية',
                            style: TextStyle(
                              fontSize: 12.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSecondaryContainer,
                            ),
                          ),
                          const SizedBox(height: 8),
                          Row(
                            crossAxisAlignment: CrossAxisAlignment.baseline,
                            textBaseline: TextBaseline.alphabetic,
                            children: [
                              Text(
                                '$totalMonthlyBilling',
                                style: TextStyle(
                                  fontSize: 26,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                              const SizedBox(width: 4),
                              Text(
                                'ج.م',
                                style: TextStyle(
                                  fontSize: 12,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSecondaryContainer,
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 2),
                          Text(
                            '500 ج.م / شركة شهرياً',
                            style: TextStyle(
                              fontSize: 11,
                              color: colorScheme.onSecondaryContainer.withValues(alpha: 0.8),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),

              // ── جدول الشركات النشطة وتصدير Excel ──
              Card(
                elevation: 0,
                color: colorScheme.surface,
                shape: RoundedRectangleBorder(
                  borderRadius: BorderRadius.circular(16),
                  side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                ),
                clipBehavior: Clip.antiAlias,
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    Container(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                      color: colorScheme.surfaceContainerHigh,
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Row(
                            children: [
                              Icon(Icons.receipt_long_rounded, color: colorScheme.primary, size: 20),
                              const SizedBox(width: 8),
                              const Text(
                                'تفاصيل فواتير الشركات النشطة',
                                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                              ),
                            ],
                          ),
                          FilledButton.icon(
                            onPressed: activeCompaniesList.isEmpty ? null : () => _exportToCSV(activeCompaniesList),
                            style: FilledButton.styleFrom(
                              backgroundColor: colorScheme.primary,
                              foregroundColor: colorScheme.onPrimary,
                              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                            ),
                            icon: const Icon(Icons.file_download_rounded, size: 16),
                            label: const Text('تصدير Excel', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                          ),
                        ],
                      ),
                    ),
                    if (activeCompaniesList.isEmpty)
                      const Padding(
                        padding: EdgeInsets.symmetric(vertical: 40),
                        child: Center(
                          child: Text(
                            'لا توجد شركات لديها اشتراكات أذونات تصوير نشطة حالياً.',
                            style: TextStyle(fontSize: 13),
                          ),
                        ),
                      )
                    else
                      SingleChildScrollView(
                        scrollDirection: Axis.horizontal,
                        child: DataTable(
                          columnSpacing: 24,
                          columns: const [
                            DataColumn(label: Text('اسم الشركة', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('كود الشركة', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('القسم', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('قيمة الإذن شهرياً', style: TextStyle(fontWeight: FontWeight.bold))),
                            DataColumn(label: Text('تاريخ الانتهاء', style: TextStyle(fontWeight: FontWeight.bold))),
                          ],
                          rows: activeCompaniesList.map((p) {
                            final code = _companyCodesCache[p.companyUID]?.toString() ?? p.companyCode?.toString() ?? '-';
                            return DataRow(
                              cells: [
                                DataCell(Text(p.companyName, style: const TextStyle(fontWeight: FontWeight.w600))),
                                DataCell(Text(code, style: const TextStyle(fontFamily: 'monospace'))),
                                DataCell(Text(p.department ?? 'عام')),
                                DataCell(
                                  Text(
                                    '500 ج.م',
                                    style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold),
                                  ),
                                ),
                                DataCell(Text(DateFormat('yyyy/MM/dd').format(p.endDate))),
                              ],
                            );
                          }).toList(),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          );
        }

        return const SizedBox.shrink();
      },
    );
  }
}

class _BreadcrumbItem {
  final String label;
  final IconData icon;
  final VoidCallback? onTap;
  final bool isActive;

  const _BreadcrumbItem({
    required this.label,
    required this.icon,
    this.onTap,
    this.isActive = false,
  });
}
