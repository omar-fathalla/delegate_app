import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../profile/domain/entities/delegate.dart';
import '../../data/services/delegate_tracking_service.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import '../widgets/delegate_tracking_table.dart';
import '../widgets/tracking_live_map_view.dart';
import '../widgets/tracking_stats_overview.dart';
import '../../../../core/widgets/tashil_button_group.dart';

class DelegateTrackingScreen extends StatefulWidget {
  final Delegate adminDelegate;
  final bool initialMapView;
  final bool showAppBar;

  const DelegateTrackingScreen({
    super.key,
    required this.adminDelegate,
    this.initialMapView = false,
    this.showAppBar = true,
  });

  @override
  State<DelegateTrackingScreen> createState() => _DelegateTrackingScreenState();
}

class _DelegateTrackingScreenState extends State<DelegateTrackingScreen> {
  late final DelegateTrackingService _trackingService;

  /// Read-reduction Phase 2: the sessions listener is created once per
  /// company/org scope and reused across rebuilds. Creating it inside
  /// `build()` re-subscribed (and re-billed every doc) on each setState.
  Stream<List<DelegateTrackingSession>>? _sessionsStream;
  String? _sessionsStreamScope;

  Stream<List<DelegateTrackingSession>> _sessionsStreamFor({
    required String companyId,
    required String orgId,
  }) {
    final scope = '$companyId|$orgId';
    final existing = _sessionsStream;
    if (existing != null && _sessionsStreamScope == scope) return existing;
    _sessionsStreamScope = scope;
    return _sessionsStream = _trackingService.streamTrackingSessions(
      companyId: companyId.isNotEmpty ? companyId : null,
      organizationId: companyId.isEmpty ? orgId : null,
    );
  }
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedStatusFilter = 'all'; // all, tracking_active, inside, outside, offline
  String _selectedBranch = 'all';

  bool _isSyncing = false;
  late bool _isMapView;
  bool _isBulkUpdating = false;
  String? _selectedDelegateId;

  @override
  void initState() {
    super.initState();
    _isMapView = widget.initialMapView;
    _trackingService = DelegateTrackingService();
    _populateInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  final Map<String, String> _delegateNamesMap = {};
  final Map<String, String> _delegatePhonesMap = {};
  final Map<String, String> _delegatePhotosMap = {};

  Future<void> _populateInitialData() async {
    setState(() => _isSyncing = true);
    try {
      // 1. مزامنة بيانات المناديب (الاسم ورقم الهاتف والصورة) من GetCompanyDelegates
      try {
        final delegatesResult = await di.sl<GetCompanyDelegates>()(
          GetCompanyDelegatesParams(
            organizationUID: widget.adminDelegate.organizationUID,
            companyUID: widget.adminDelegate.companyUID,
          ),
        );
        delegatesResult.fold(
          (_) {},
          (delegates) {
            for (final d in delegates) {
              final rawFull = d.fullName.trim();
              final combined = '${d.firstName} ${d.lastName}'.trim();
              final effective = rawFull.isNotEmpty ? rawFull : combined;
              if (effective.isNotEmpty) {
                _delegateNamesMap[d.uid] = effective;
              }
              if (d.phoneNumber.trim().isNotEmpty) {
                _delegatePhonesMap[d.uid] = d.phoneNumber.trim();
              }
              if (d.personalPhotoUrl != null && d.personalPhotoUrl!.isNotEmpty) {
                _delegatePhotosMap[d.uid] = d.personalPhotoUrl!;
              }
            }
          },
        );
      } catch (_) {}

      // 2. البحث المباشر في Firestore للتأكيد
      try {
        final cUid = widget.adminDelegate.companyUID;
        final oUid = widget.adminDelegate.organizationUID;
        if (cUid.isNotEmpty && oUid.isNotEmpty) {
          final snap = await FirebaseFirestore.instance
              .collection('organizations')
              .doc(oUid)
              .collection('companies')
              .doc(cUid)
              .collection('delegates')
              .get();
          for (final doc in snap.docs) {
            final d = doc.data();
            final rawFull = (d['fullName'] ?? d['name'])?.toString().trim();
            final combined =
                '${d['firstName'] ?? ''} ${d['lastName'] ?? ''}'.trim();
            final effective =
                (rawFull != null && rawFull.isNotEmpty) ? rawFull : combined;
            if (effective.isNotEmpty) {
              _delegateNamesMap[doc.id] = effective;
            }
            final ph = (d['phoneNumber'] ?? d['phone'] ?? '').toString().trim();
            if (ph.isNotEmpty) {
              _delegatePhonesMap[doc.id] = ph;
            }
            final photo = DelegateTrackingService.extractPhotoUrl(d);
            if (photo.isNotEmpty) {
              _delegatePhotosMap[doc.id] = photo;
            }
          }
        }
      } catch (_) {}

      if (mounted) setState(() {});

      // 3. تحديث الحاضرين في خدمة التتبع
      await _trackingService.populateTodayAttendanceToTracking(
        companyId: widget.adminDelegate.companyUID,
        organizationId: widget.adminDelegate.organizationUID,
      );
    } catch (e) {
      debugPrint('Error populating tracking data: $e');
    } finally {
      if (mounted) setState(() => _isSyncing = false);
    }
  }

  Future<void> _handleToggleTracking(
      DelegateTrackingSession session, bool newValue) async {
    try {
      await _trackingService.toggleTracking(
        delegateId: session.delegateId,
        enabled: newValue,
        supervisorId: widget.adminDelegate.uid,
        supervisorName: widget.adminDelegate.fullName.isNotEmpty
            ? widget.adminDelegate.fullName
            : widget.adminDelegate.firstName,
      );

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          newValue
              ? 'تم تفعيل التتبع الميداني للمندوب ${session.delegateName}'
              : 'تم إيقاف التتبع الميداني للمندوب ${session.delegateName}',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'فشل تحديث حالة التتبع للمندوب. يرجى المحاولة لاحقاً.',
        );
      }
    }
  }

  Future<void> _handleBulkToggle(
    List<DelegateTrackingSession> sessions,
    bool enable,
  ) async {
    if (sessions.isEmpty) return;

    final confirmed = await showDialog<bool>(
      context: context,
      builder: (ctx) {
        final ctxTheme = Theme.of(ctx);
        final ctxColorScheme = ctxTheme.colorScheme;

        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(28)),
          title: Row(
            children: [
              Icon(
                enable ? Icons.radar_rounded : Icons.power_settings_new_rounded,
                color: enable ? ctxColorScheme.primary : ctxColorScheme.error,
              ),
              const SizedBox(width: 10),
              Text(
                enable ? 'تفعيل التتبع للجميع' : 'إيقاف التتبع للجميع',
                style: ctxTheme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
              ),
            ],
          ),
          content: Text(
            enable
                ? 'هل ترغب في تفعيل التتبع الميداني الحي لجميع المناديب الحاضرين اليوم (${sessions.length} مندوب)؟'
                : 'هل ترغب في إيقاف التتبع الميداني لجميع المناديب الحاضرين (${sessions.length} مندوب)؟',
            style: ctxTheme.textTheme.bodyMedium,
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx, false),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () => Navigator.pop(ctx, true),
              style: FilledButton.styleFrom(
                shape: const StadiumBorder(),
                backgroundColor: enable ? ctxColorScheme.primary : ctxColorScheme.error,
                foregroundColor: enable ? ctxColorScheme.onPrimary : ctxColorScheme.onError,
              ),
              child: Text(enable ? 'تأكيد التفعيل' : 'تأكيد الإيقاف'),
            ),
          ],
        );
      },
    );

    if (confirmed != true || !mounted) return;

    setState(() => _isBulkUpdating = true);
    try {
      final ids = sessions.map((s) => s.delegateId).toList();
      await _trackingService.bulkToggleTracking(
        delegateIds: ids,
        enabled: enable,
        supervisorId: widget.adminDelegate.uid,
        supervisorName: widget.adminDelegate.fullName.isNotEmpty
            ? widget.adminDelegate.fullName
            : widget.adminDelegate.firstName,
      );

      if (mounted) {
        AppSnackBar.showSuccess(
          context,
          enable
              ? 'تم تفعيل التتبع الميداني لـ ${ids.length} مندوب بنجاح.'
              : 'تم إيقاف التتبع الميداني لجميع المناديب بنجاح.',
        );
      }
    } catch (e) {
      if (mounted) {
        AppSnackBar.showError(
          context,
          'حدث خطأ أثناء تنفيذ الإجراء الجماعي. حاول مرة أخرى.',
        );
      }
    } finally {
      if (mounted) setState(() => _isBulkUpdating = false);
    }
  }

  List<DelegateTrackingSession> _filterSessions(
      List<DelegateTrackingSession> sessions) {
    return sessions.where((s) {
      // 1. Search query
      final matchesSearch = _searchQuery.isEmpty ||
          s.delegateName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          s.delegatePhone.contains(_searchQuery) ||
          s.branchName.toLowerCase().contains(_searchQuery.toLowerCase());

      if (!matchesSearch) return false;

      // 2. Branch filter
      if (_selectedBranch != 'all' && s.branchName != _selectedBranch) {
        return false;
      }

      // 3. Status filter
      switch (_selectedStatusFilter) {
        case 'tracking_active':
          return s.isTrackingEnabled;
        case 'inside':
          return s.isInside;
        case 'outside':
          return s.isOutside;
        case 'offline':
          return s.isOffline;
        default:
          return true;
      }
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final textTheme = theme.textTheme;

    final companyId = widget.adminDelegate.companyUID;
    final orgId = widget.adminDelegate.organizationUID;

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
        title: Text(
          'Live Tracking',
          style: textTheme.titleMedium?.copyWith(
            fontWeight: FontWeight.bold,
            color: colorScheme.onSurface,
          ),
        ),
        elevation: 0,
        scrolledUnderElevation: 2,
        backgroundColor: colorScheme.surface,
        actions: [
          // Toggle View: List vs Map
          IconButton(
            icon: Icon(
              _isMapView ? Icons.view_list_rounded : Icons.map_rounded,
            ),
            tooltip: _isMapView ? 'عرض القائمة' : 'عرض الخريطة الحية',
            onPressed: () {
              setState(() {
                if (_isMapView) {
                  _selectedDelegateId = null;
                }
                _isMapView = !_isMapView;
              });
            },
          ),
          if (_isSyncing || _isBulkUpdating)
            const Padding(
              padding: EdgeInsetsDirectional.symmetric(horizontal: 16.0),
              child: Center(
                child: SizedBox(
                  width: 18,
                  height: 18,
                  child: CircularProgressIndicator(strokeWidth: 2),
                ),
              ),
            )
          else
            IconButton(
              icon: const Icon(Icons.sync_rounded),
              tooltip: 'تحديث الحاضرين',
              onPressed: _populateInitialData,
            ),
        ],
      )
          : null,
      body: StreamBuilder<List<DelegateTrackingSession>>(
        stream: _sessionsStreamFor(companyId: companyId, orgId: orgId),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final rawSessions = snapshot.data ?? [];
          final allSessions = rawSessions.map((s) {
            final realName = _delegateNamesMap[s.delegateId];
            final realPhone = _delegatePhonesMap[s.delegateId];
            final realPhoto = _delegatePhotosMap[s.delegateId];
            final isGeneric = s.delegateName == 'مندوب' ||
                s.delegateName == 'مندوب غير محدد' ||
                s.delegateName.trim().isEmpty ||
                s.delegateName.trim() == 'مندوب';

            final effectiveName = (realName != null &&
                    realName.isNotEmpty &&
                    (isGeneric || s.delegateName != realName))
                ? realName
                : s.delegateName;
            final effectivePhone = (s.delegatePhone.isEmpty && realPhone != null)
                ? realPhone
                : (realPhone != null && realPhone.isNotEmpty
                    ? realPhone
                    : s.delegatePhone);
            final effectivePhoto = (realPhoto != null && realPhoto.isNotEmpty)
                ? realPhoto
                : s.avatarUrl;

            return s.copyWith(
              delegateName: effectiveName,
              delegatePhone: effectivePhone,
              avatarUrl: effectivePhoto,
            );
          }).toList();
          final filteredSessions = _filterSessions(allSessions);

          // حساب الإحصائيات الحية
          final totalCount = allSessions.length;
          final activeTrackingCount =
              allSessions.where((s) => s.isTrackingEnabled).length;
          final insideCount = allSessions.where((s) => s.isInside).length;
          final outsideCount = allSessions.where((s) => s.isOutside).length;
          final offlineCount = allSessions.where((s) => s.isOffline).length;

          final bool allAreActive =
              totalCount > 0 && activeTrackingCount == totalCount;

          // جمع الفروع المتاحة للفلترة
          final branches = <String>{'all'};
          for (final s in allSessions) {
            if (s.branchName.isNotEmpty) branches.add(s.branchName);
          }

          final Widget content;
          if (_isMapView) {
            content = TrackingLiveMapView(
              sessions: filteredSessions,
              initialSelectedDelegateId: _selectedDelegateId,
              onToggleTracking: (session) {
                _handleToggleTracking(session, !session.isTrackingEnabled);
              },
              onRefresh: _populateInitialData,
            );
          } else {
            content = RefreshIndicator(
              onRefresh: _populateInitialData,
              child: CustomScrollView(
                slivers: [
                  // 1. Stats Overview Cards
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          16.0, 12.0, 16.0, 8.0),
                      child: TrackingStatsOverview(
                        totalCount: totalCount,
                        activeTrackingCount: activeTrackingCount,
                        insideCount: insideCount,
                        outsideCount: outsideCount,
                        offlineCount: offlineCount,
                        selectedFilter: _selectedStatusFilter,
                        onFilterChanged: (filter) {
                          setState(() => _selectedStatusFilter = filter);
                        },
                      ),
                    ),
                  ),

                  // 2. Search, M3 Filter Dropdowns & Bulk Actions (Single Web Row)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          16.0, 6.0, 16.0, 8.0),
                      child: LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth >= 768;

                          if (isDesktop) {
                            return Row(
                              crossAxisAlignment: CrossAxisAlignment.center,
                              children: [
                                // 1. Search Bar
                                Expanded(
                                  flex: 4,
                                  child: _buildSearchField(colorScheme),
                                ),
                                const SizedBox(width: 10),

                                // 2. Status Filter Dropdown (M3 Dropdown)
                                Expanded(
                                  flex: 3,
                                  child: _buildM3StatusMenu(
                                    colorScheme: colorScheme,
                                    totalCount: totalCount,
                                    activeTrackingCount: activeTrackingCount,
                                    insideCount: insideCount,
                                    outsideCount: outsideCount,
                                    offlineCount: offlineCount,
                                  ),
                                ),

                                // 3. Branch Filter Dropdown (M3 Dropdown)
                                if (branches.length > 1) ...[
                                  const SizedBox(width: 10),
                                  Expanded(
                                    flex: 3,
                                    child: _buildM3BranchMenu(
                                      colorScheme: colorScheme,
                                      branches: branches,
                                    ),
                                  ),
                                ],

                                // 4. Bulk Toggle Button (Responsive natural-sized button)
                                if (allSessions.isNotEmpty) ...[
                                  const SizedBox(width: 10),
                                  _buildBulkActionButton(
                                    colorScheme: colorScheme,
                                    allAreActive: allAreActive,
                                    totalCount: totalCount,
                                    allSessions: allSessions,
                                  ),
                                ],
                              ],
                            );
                          }

                          // Compact view for narrow screens / mobile
                          return Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _buildSearchField(colorScheme),
                              const SizedBox(height: 8),
                              Row(
                                children: [
                                  Expanded(
                                    child: _buildM3StatusMenu(
                                      colorScheme: colorScheme,
                                      totalCount: totalCount,
                                      activeTrackingCount: activeTrackingCount,
                                      insideCount: insideCount,
                                      outsideCount: outsideCount,
                                      offlineCount: offlineCount,
                                    ),
                                  ),
                                  if (branches.length > 1) ...[
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: _buildM3BranchMenu(
                                        colorScheme: colorScheme,
                                        branches: branches,
                                      ),
                                    ),
                                  ],
                                ],
                              ),
                              if (allSessions.isNotEmpty) ...[
                                const SizedBox(height: 8),
                                SizedBox(
                                  width: double.infinity,
                                  child: _buildBulkActionButton(
                                    colorScheme: colorScheme,
                                    allAreActive: allAreActive,
                                    totalCount: totalCount,
                                    allSessions: allSessions,
                                    isFullWidth: true,
                                  ),
                                ),
                              ],
                            ],
                          );
                        },
                      ),
                    ),
                  ),

                  const SliverToBoxAdapter(child: SizedBox(height: 8)),

                // 4. Delegate Tracking List / Empty State
                if (filteredSessions.isEmpty)
                  SliverFillRemaining(
                    hasScrollBody: false,
                    child: Center(
                      child: Padding(
                        padding: const EdgeInsetsDirectional.all(24.0),
                        child: Container(
                          padding: const EdgeInsetsDirectional.all(24.0),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(16),
                            border: Border.all(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.4),
                            ),
                          ),
                          child: Column(
                            mainAxisSize: MainAxisSize.min,
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              CircleAvatar(
                                radius: 36,
                                backgroundColor: colorScheme.primaryContainer
                                    .withValues(alpha: 0.35),
                                child: Icon(
                                  Icons.radar_rounded,
                                  size: 40,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(height: 16),
                              Text(
                                allSessions.isEmpty
                                    ? 'لا يوجد مناديب مسجلين حضور في الفروع اليوم'
                                    : 'لا توجد نتائج مطابقة لخيارات الفلترة الحالية',
                                style: textTheme.titleMedium?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.onSurface,
                                ),
                                textAlign: TextAlign.center,
                              ),
                              const SizedBox(height: 8),
                              Text(
                                allSessions.isEmpty
                                    ? 'عند تسجيل أي مندوب لحضوره في الفرع، سيظهر تلقائياً هنا لتتمكن من تفعيل التتبع المباشر.'
                                    : 'جرّب البحث باسم آخر أو تغيير خيارات الفلترة المحددة.',
                                style: textTheme.bodySmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                textAlign: TextAlign.center,
                              ),
                            ],
                          ),
                        ),
                      ),
                    ),
                  )
                else
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsetsDirectional.fromSTEB(
                          16.0, 4.0, 16.0, 24.0),
                      child: DelegateTrackingTable(
                        sessions: filteredSessions,
                        onSelectDelegate: (session) {
                          setState(() {
                            _selectedDelegateId = session.delegateId;
                            _isMapView = true;
                          });
                        },
                        onToggleTracking: (session, val) =>
                            _handleToggleTracking(session, val),
                        onRefreshPing: (session) async {
                          AppSnackBar.showInfo(
                            context,
                            'جاري إرسال إشارة استعلام لموقع المندوب...',
                          );
                          await _trackingService.updateLocationAndCheckGeofence(
                            delegateId: session.delegateId,
                            currentLat: session.lastLatitude ??
                                session.branchLat,
                            currentLng: session.lastLongitude ??
                                session.branchLng,
                          );
                        },
                      ),
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          );
        }

        if (!widget.showAppBar) {
          return Column(
            children: [
              _buildEmbeddedTopBar(
                context: context,
                totalCount: totalCount,
                insideCount: insideCount,
                outsideCount: outsideCount,
                allAreActive: allAreActive,
                allSessions: allSessions,
              ),
              Expanded(child: content),
            ],
          );
        }

        return content;
      },
    ),
  );
}

  Widget _buildSearchField(ColorScheme colorScheme) {
    return SizedBox(
      height: 44,
      child: TextField(
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        textAlignVertical: TextAlignVertical.center,
        style: TextStyle(
          fontSize: 13,
          color: colorScheme.onSurface,
        ),
        decoration: InputDecoration(
          isDense: true,
          contentPadding:
              const EdgeInsets.symmetric(horizontal: 12, vertical: 0),
          hintText: 'بحث باسم المندوب أو الفرع أو الهاتف...',
          hintStyle: TextStyle(
            fontSize: 12.5,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(
            Icons.search_rounded,
            size: 20,
            color: colorScheme.primary,
          ),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.close_rounded, size: 16),
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              width: 1,
            ),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(22),
            borderSide: BorderSide(
              color: colorScheme.primary,
              width: 1.5,
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildM3StatusMenu({
    required ColorScheme colorScheme,
    required int totalCount,
    required int activeTrackingCount,
    required int insideCount,
    required int outsideCount,
    required int offlineCount,
  }) {
    String currentLabel;
    IconData currentIcon;
    Color currentIconColor = colorScheme.primary;

    switch (_selectedStatusFilter) {
      case 'tracking_active':
        currentLabel = 'التتبع مفعّل ($activeTrackingCount)';
        currentIcon = Icons.radar_rounded;
        break;
      case 'inside':
        currentLabel = 'داخل النطاق ($insideCount)';
        currentIcon = Icons.check_circle_outline_rounded;
        currentIconColor = const Color(0xFF2E7D32);
        break;
      case 'outside':
        currentLabel = 'خارج النطاق ($outsideCount)';
        currentIcon = Icons.warning_amber_rounded;
        currentIconColor = const Color(0xFFEF6C00);
        break;
      case 'offline':
        currentLabel = 'غير متصل ($offlineCount)';
        currentIcon = Icons.cloud_off_rounded;
        currentIconColor = colorScheme.outline;
        break;
      case 'all':
      default:
        currentLabel = 'جميع الحالات ($totalCount)';
        currentIcon = Icons.filter_alt_outlined;
        break;
    }

    return LayoutBuilder(
      builder: (context, menuConstraints) {
        final menuWidth = menuConstraints.maxWidth;
        return SizedBox(
          height: 44,
          child: PopupMenuButton<String>(
            tooltip: 'فلترة حسب الحالة',
            offset: const Offset(0, 48),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: menuWidth,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(14),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                width: 1,
              ),
            ),
            color: colorScheme.surfaceContainerHigh,
            elevation: 3,
            onSelected: (filter) {
              setState(() => _selectedStatusFilter = filter);
            },
            itemBuilder: (context) => [
              _buildM3MenuItem(
                value: 'all',
                label: 'جميع الحالات',
                count: totalCount,
                icon: Icons.filter_alt_outlined,
                isSelected: _selectedStatusFilter == 'all',
                colorScheme: colorScheme,
              ),
              _buildM3MenuItem(
                value: 'tracking_active',
                label: 'التتبع مفعّل',
                count: activeTrackingCount,
                icon: Icons.radar_rounded,
                isSelected: _selectedStatusFilter == 'tracking_active',
                colorScheme: colorScheme,
                accentColor: colorScheme.primary,
              ),
              _buildM3MenuItem(
                value: 'inside',
                label: 'داخل النطاق',
                count: insideCount,
                icon: Icons.check_circle_outline_rounded,
                isSelected: _selectedStatusFilter == 'inside',
                colorScheme: colorScheme,
                accentColor: const Color(0xFF2E7D32),
              ),
              _buildM3MenuItem(
                value: 'outside',
                label: 'خارج النطاق',
                count: outsideCount,
                icon: Icons.warning_amber_rounded,
                isSelected: _selectedStatusFilter == 'outside',
                colorScheme: colorScheme,
                accentColor: const Color(0xFFC65102),
              ),
              _buildM3MenuItem(
                value: 'offline',
                label: 'غير متصل / لم يسجل',
                count: offlineCount,
                icon: Icons.cloud_off_rounded,
                isSelected: _selectedStatusFilter == 'offline',
                colorScheme: colorScheme,
                accentColor: colorScheme.outline,
              ),
            ],
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(currentIcon, size: 18, color: currentIconColor),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildM3BranchMenu({
    required ColorScheme colorScheme,
    required Set<String> branches,
  }) {
    final currentLabel =
        _selectedBranch == 'all' ? 'جميع الفروع' : _selectedBranch;

    return LayoutBuilder(
      builder: (context, menuConstraints) {
        final menuWidth = menuConstraints.maxWidth;
        return SizedBox(
          height: 44,
          child: PopupMenuButton<String>(
            tooltip: 'فلترة حسب الفرع',
            offset: const Offset(0, 48),
            constraints: BoxConstraints(
              minWidth: menuWidth,
              maxWidth: menuWidth,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(16),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                width: 1,
              ),
            ),
            color: colorScheme.surfaceContainerHigh,
            elevation: 3,
            onSelected: (branch) {
              setState(() => _selectedBranch = branch);
            },
            itemBuilder: (context) => branches.map((b) {
              final isSelected = _selectedBranch == b;
              return _buildM3MenuItem(
                value: b,
                label: b == 'all' ? 'جميع الفروع' : b,
                count: null,
                icon: Icons.storefront_rounded,
                isSelected: isSelected,
                colorScheme: colorScheme,
                accentColor: isSelected ? colorScheme.primary : null,
              );
            }).toList(),
            child: Container(
              padding: const EdgeInsets.symmetric(horizontal: 14),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(22),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                  width: 1,
                ),
              ),
              child: Row(
                children: [
                  Icon(
                    Icons.storefront_rounded,
                    size: 18,
                    color: colorScheme.primary,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      currentLabel,
                      style: TextStyle(
                        fontSize: 12.5,
                        fontWeight: FontWeight.w600,
                        color: colorScheme.onSurface,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  Icon(
                    Icons.expand_more_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  Widget _buildBulkActionButton({
    required ColorScheme colorScheme,
    required bool allAreActive,
    required int totalCount,
    required List<DelegateTrackingSession> allSessions,
    bool isFullWidth = false,
  }) {
    if (allAreActive) {
      return SizedBox(
        height: 44,
        width: isFullWidth ? double.infinity : null,
        child: OutlinedButton.icon(
          onPressed: _isBulkUpdating
              ? null
              : () => _handleBulkToggle(allSessions, false),
          style: OutlinedButton.styleFrom(
            foregroundColor: colorScheme.error,
            backgroundColor: colorScheme.errorContainer.withValues(alpha: 0.35),
            side: BorderSide(
              color: colorScheme.error.withValues(alpha: 0.45),
              width: 1,
            ),
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(22),
            ),
            padding: const EdgeInsets.symmetric(horizontal: 16),
          ),
          icon: _isBulkUpdating
              ? SizedBox(
                  width: 16,
                  height: 16,
                  child: CircularProgressIndicator(
                    strokeWidth: 2,
                    color: colorScheme.error,
                  ),
                )
              : const Icon(Icons.power_settings_new_rounded, size: 18),
          label: Text(
            'إيقاف التتبع للجميع ($totalCount)',
            style: const TextStyle(
              fontSize: 12.5,
              fontWeight: FontWeight.bold,
            ),
          ),
        ),
      );
    }

    return SizedBox(
      height: 44,
      width: isFullWidth ? double.infinity : null,
      child: FilledButton.tonalIcon(
        onPressed: _isBulkUpdating
            ? null
            : () => _handleBulkToggle(allSessions, true),
        style: FilledButton.styleFrom(
          foregroundColor: colorScheme.primary,
          backgroundColor: colorScheme.primaryContainer.withValues(alpha: 0.6),
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(22),
          ),
          padding: const EdgeInsets.symmetric(horizontal: 16),
        ),
        icon: _isBulkUpdating
            ? SizedBox(
                width: 16,
                height: 16,
                child: CircularProgressIndicator(
                  strokeWidth: 2,
                  color: colorScheme.primary,
                ),
              )
            : const Icon(Icons.radar_rounded, size: 18),
        label: Text(
          'تفعيل التتبع للجميع ($totalCount)',
          style: const TextStyle(
            fontSize: 12.5,
            fontWeight: FontWeight.bold,
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _buildM3MenuItem({
    required String value,
    required String label,
    required int? count,
    required IconData icon,
    required bool isSelected,
    required ColorScheme colorScheme,
    Color? accentColor,
  }) {
    final effectiveColor = accentColor ??
        (isSelected ? colorScheme.primary : colorScheme.onSurface);

    return PopupMenuItem<String>(
      value: value,
      height: 40,
      child: Row(
        children: [
          Icon(
            icon,
            size: 18,
            color: effectiveColor,
          ),
          const SizedBox(width: 10),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 13,
                fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                color: isSelected ? colorScheme.primary : colorScheme.onSurface,
              ),
            ),
          ),
          if (count != null) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
              decoration: BoxDecoration(
                color: isSelected
                    ? colorScheme.primary.withValues(alpha: 0.15)
                    : colorScheme.surfaceContainerHighest,
                borderRadius: BorderRadius.circular(10),
              ),
              child: Text(
                '$count',
                style: TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: isSelected
                      ? colorScheme.primary
                      : colorScheme.onSurfaceVariant,
                ),
              ),
            ),
            const SizedBox(width: 8),
          ],
          if (isSelected)
            Icon(
              Icons.check_rounded,
              size: 18,
              color: colorScheme.primary,
            )
          else
            const SizedBox(width: 18),
        ],
      ),
    );
  }

  Widget _buildEmbeddedTopBar({
  required BuildContext context,
  required int totalCount,
  required int insideCount,
  required int outsideCount,
  required bool allAreActive,
  required List<DelegateTrackingSession> allSessions,
}) {
  final theme = Theme.of(context);
  final colorScheme = theme.colorScheme;

  return Container(
    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
    decoration: BoxDecoration(
      color: colorScheme.surface,
      border: Border(
        bottom: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1,
        ),
      ),
    ),
    child: SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      physics: const BouncingScrollPhysics(),
      child: Row(
        textDirection: TextDirection.rtl,
        mainAxisSize: MainAxisSize.min,
        children: [
          // View Switcher (Map vs List) using standard TashilConnectedButtonGroup
          TashilConnectedButtonGroup<bool>(
            height: 38,
            selectedValue: _isMapView,
            onSelected: (val) {
              setState(() {
                if (!val) {
                  _selectedDelegateId = null;
                }
                _isMapView = val;
              });
            },
            items: [
              const TashilConnectedButtonItem<bool>(
                value: true,
                label: 'الخريطة الحية',
                icon: Icons.map_rounded,
              ),
              TashilConnectedButtonItem<bool>(
                value: false,
                label: 'قائمة تفصيلية ($totalCount)',
                icon: Icons.view_list_rounded,
              ),
            ],
          ),
          const SizedBox(width: 10),
          // Live status chips
          if (totalCount > 0) ...[
            Container(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
              decoration: BoxDecoration(
                color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Text(
                '🟢 $insideCount داخل',
                style: const TextStyle(
                  fontSize: 11,
                  fontWeight: FontWeight.bold,
                  color: Color(0xFF2E7D32),
                ),
              ),
            ),
            const SizedBox(width: 6),
            if (outsideCount > 0)
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: const Color(0xFFC65102).withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  '🟠 $outsideCount خارج',
                  style: const TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: Color(0xFFC65102),
                  ),
                ),
              ),
            const SizedBox(width: 10),
          ],
          // Refresh Button
          if (_isSyncing || _isBulkUpdating)
            const SizedBox(
              width: 20,
              height: 20,
              child: CircularProgressIndicator(strokeWidth: 2),
            )
          else
            IconButton.filledTonal(
              iconSize: 18,
              visualDensity: VisualDensity.compact,
              tooltip: 'تحديث بيانات الحاضرين',
              onPressed: _populateInitialData,
              icon: const Icon(Icons.sync_rounded),
            ),
        ],
      ),
    ),
  );
}
}
