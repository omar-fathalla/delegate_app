import 'package:flutter/material.dart';
import '../../../../core/widgets/app_snack_bar.dart';
import '../../../profile/domain/entities/delegate.dart';
import '../../data/services/delegate_tracking_service.dart';
import '../../domain/entities/delegate_tracking_session.dart';
import '../widgets/delegate_tracking_card.dart';
import '../widgets/tracking_live_map_view.dart';
import '../widgets/tracking_stats_overview.dart';

class DelegateTrackingScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const DelegateTrackingScreen({
    super.key,
    required this.adminDelegate,
  });

  @override
  State<DelegateTrackingScreen> createState() => _DelegateTrackingScreenState();
}

class _DelegateTrackingScreenState extends State<DelegateTrackingScreen> {
  late final DelegateTrackingService _trackingService;
  final TextEditingController _searchController = TextEditingController();

  String _searchQuery = '';
  String _selectedStatusFilter = 'all'; // all, tracking_active, inside, outside, offline
  String _selectedBranch = 'all';

  bool _isSyncing = false;
  bool _isMapView = false;
  bool _isBulkUpdating = false;

  @override
  void initState() {
    super.initState();
    _trackingService = DelegateTrackingService();
    _populateInitialData();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _populateInitialData() async {
    setState(() => _isSyncing = true);
    try {
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
      backgroundColor: colorScheme.surface,
      appBar: AppBar(
        title: Text(
          'تتبع نطاق المناديب (Live Tracking)',
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
              setState(() => _isMapView = !_isMapView);
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
      ),
      body: StreamBuilder<List<DelegateTrackingSession>>(
        stream: _trackingService.streamTrackingSessions(
          companyId: companyId.isNotEmpty ? companyId : null,
          organizationId: companyId.isEmpty ? orgId : null,
        ),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final allSessions = snapshot.data ?? [];
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

          if (_isMapView) {
            return TrackingLiveMapView(
              sessions: filteredSessions,
              onToggleTracking: (session) {
                _handleToggleTracking(session, !session.isTrackingEnabled);
              },
              onRefresh: _populateInitialData,
            );
          }

          return RefreshIndicator(
            onRefresh: _populateInitialData,
            child: CustomScrollView(
              slivers: [
                // 1. Overview Header
                SliverToBoxAdapter(
                  child: TrackingStatsOverview(
                    totalCount: totalCount,
                    activeTrackingCount: activeTrackingCount,
                    insideCount: insideCount,
                    outsideCount: outsideCount,
                    offlineCount: offlineCount,
                  ),
                ),

                // 2. Bulk Actions Bar
                if (allSessions.isNotEmpty)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(
                        horizontal: 16.0,
                        vertical: 4.0,
                      ),
                      child: Row(
                        children: [
                          Expanded(
                            child: FilledButton.tonalIcon(
                              onPressed: _isBulkUpdating
                                  ? null
                                  : () => _handleBulkToggle(
                                        allSessions,
                                        !allAreActive,
                                      ),
                              icon: Icon(
                                allAreActive
                                    ? Icons.power_settings_new_rounded
                                    : Icons.radar_rounded,
                                size: 18,
                              ),
                              label: Text(
                                allAreActive
                                    ? 'إيقاف التتبع لجميع الحاضرين'
                                    : 'تفعيل التتبع لجميع الحاضرين ($totalCount)',
                                style: const TextStyle(fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                backgroundColor: allAreActive
                                    ? colorScheme.errorContainer
                                    : colorScheme.primaryContainer,
                                foregroundColor: allAreActive
                                    ? colorScheme.onErrorContainer
                                    : colorScheme.onPrimaryContainer,
                                shape: const StadiumBorder(),
                                padding: const EdgeInsetsDirectional.symmetric(vertical: 10),
                              ),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                // 3. Search & Filter Controls (M3 Dropdowns)
                SliverToBoxAdapter(
                  child: Padding(
                    padding: const EdgeInsetsDirectional.fromSTEB(16.0, 6.0, 16.0, 8.0),
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        // Search bar
                        TextField(
                          controller: _searchController,
                          decoration: InputDecoration(
                            hintText: 'بحث باسم المندوب أو الفرع أو الهاتف...',
                            prefixIcon: const Icon(Icons.search_rounded),
                            suffixIcon: _searchQuery.isNotEmpty
                                ? IconButton(
                                    icon: const Icon(Icons.clear_rounded),
                                    onPressed: () {
                                      _searchController.clear();
                                      setState(() => _searchQuery = '');
                                    },
                                  )
                                : null,
                            filled: true,
                            fillColor: colorScheme.surfaceContainerLow,
                            contentPadding: const EdgeInsetsDirectional.symmetric(
                              horizontal: 16,
                              vertical: 12,
                            ),
                            border: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
                              ),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(12),
                              borderSide: BorderSide(
                                color: colorScheme.outlineVariant
                                    .withValues(alpha: 0.5),
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
                          onChanged: (val) =>
                              setState(() => _searchQuery = val.trim()),
                        ),
                        const SizedBox(height: 8),

                        // Dropdown Filters Row
                        Row(
                          children: [
                            // Status Filter Dropdown
                            Expanded(
                              flex: branches.length > 1 ? 3 : 1,
                              child: Container(
                                height: 48,
                                padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: _selectedStatusFilter != 'all'
                                        ? colorScheme.primary
                                        : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                    width: _selectedStatusFilter != 'all' ? 1.4 : 1.0,
                                  ),
                                ),
                                child: DropdownButtonHideUnderline(
                                  child: DropdownButton<String>(
                                    value: _selectedStatusFilter,
                                    isExpanded: true,
                                    icon: Icon(
                                      Icons.keyboard_arrow_down_rounded,
                                      size: 20,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                    items: [
                                      DropdownMenuItem(
                                        value: 'all',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.filter_list_rounded,
                                              size: 18,
                                              color: colorScheme.primary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'جميع الحالات ($totalCount)',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'tracking_active',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.radar_rounded,
                                              size: 18,
                                              color: colorScheme.secondary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'التتبع مفعّل ($activeTrackingCount)',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'inside',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.check_circle_rounded,
                                              size: 18,
                                              color: colorScheme.tertiary,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'داخل الفرع ($insideCount)',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'outside',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.warning_amber_rounded,
                                              size: 18,
                                              color: colorScheme.error,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'خارج النطاق ($outsideCount)',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      DropdownMenuItem(
                                        value: 'offline',
                                        child: Row(
                                          children: [
                                            Icon(
                                              Icons.cloud_off_rounded,
                                              size: 18,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            const SizedBox(width: 8),
                                            Expanded(
                                              child: Text(
                                                'غير متصل ($offlineCount)',
                                                overflow: TextOverflow.ellipsis,
                                                style: const TextStyle(fontSize: 12.5),
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                    ],
                                    onChanged: (val) {
                                      if (val != null) {
                                        setState(() => _selectedStatusFilter = val);
                                      }
                                    },
                                  ),
                                ),
                              ),
                            ),

                            // Branch Filter Dropdown (Shown when branches exist)
                            if (branches.length > 1) ...[
                              const SizedBox(width: 8),
                              Expanded(
                                flex: 2,
                                child: Container(
                                  height: 48,
                                  padding: const EdgeInsetsDirectional.symmetric(horizontal: 10),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(12),
                                    border: Border.all(
                                      color: _selectedBranch != 'all'
                                          ? colorScheme.primary
                                          : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                      width: _selectedBranch != 'all' ? 1.4 : 1.0,
                                    ),
                                  ),
                                  child: DropdownButtonHideUnderline(
                                    child: DropdownButton<String>(
                                      value: _selectedBranch,
                                      isExpanded: true,
                                      icon: Icon(
                                        Icons.keyboard_arrow_down_rounded,
                                        size: 20,
                                        color: colorScheme.onSurfaceVariant,
                                      ),
                                      items: branches.map((b) {
                                        return DropdownMenuItem<String>(
                                          value: b,
                                          child: Row(
                                            children: [
                                              Icon(
                                                Icons.storefront_rounded,
                                                size: 16,
                                                color: colorScheme.onSurfaceVariant,
                                              ),
                                              const SizedBox(width: 6),
                                              Expanded(
                                                child: Text(
                                                  b == 'all' ? 'جميع الفروع' : b,
                                                  overflow: TextOverflow.ellipsis,
                                                  style: const TextStyle(fontSize: 12.5),
                                                ),
                                              ),
                                            ],
                                          ),
                                        );
                                      }).toList(),
                                      onChanged: (newBranch) {
                                        if (newBranch != null) {
                                          setState(() => _selectedBranch = newBranch);
                                        }
                                      },
                                    ),
                                  ),
                                ),
                              ),
                            ],
                          ],
                        ),
                      ],
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
                  SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final session = filteredSessions[index];
                        return DelegateTrackingCard(
                          session: session,
                          onToggleTracking: (val) =>
                              _handleToggleTracking(session, val),
                          onRefreshPing: () async {
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
                        );
                      },
                      childCount: filteredSessions.length,
                    ),
                  ),

                const SliverToBoxAdapter(child: SizedBox(height: 32)),
              ],
            ),
          );
        },
      ),
    );
  }
}
