import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/services/photo_cache_manager.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../widgets/sync_status_banner.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/captured_photo.dart';

enum GroupMode {
  byDate,
  byBranch,
}

class MonthlyPhotoReportScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;

  const MonthlyPhotoReportScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  State<MonthlyPhotoReportScreen> createState() => _MonthlyPhotoReportScreenState();
}

class _MonthlyPhotoReportScreenState extends State<MonthlyPhotoReportScreen> {
  late DateTime _selectedMonth;
  GroupMode _currentGroupMode = GroupMode.byDate;

  DateTime get _now {
    try {
      return di.sl<TrustedTimeService>().now;
    } catch (_) {
      return DateTime.now();
    }
  }

  @override
  void initState() {
    super.initState();
    _selectedMonth = _now;

    final isGeneralManagerOrAdmin =
        widget.delegate.role == UserRole.admin ||
        widget.delegate.position == DelegatePosition.supervisor ||
        widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.marketing ||
        widget.delegate.role == UserRole.marketingPromotion ||
        widget.delegate.role == UserRole.branchesMarketingManager;

    if (isGeneralManagerOrAdmin) {
      _currentGroupMode = GroupMode.byBranch;
    }

    _loadPhotos();
  }

  bool get _canDeletePhoto {
    final r = widget.delegate.role;
    final pos = widget.delegate.position;
    return r != UserRole.delegate || pos == DelegatePosition.supervisor;
  }

  void _loadPhotos() {
    final isGeneralManagerOrAdmin =
        widget.delegate.role == UserRole.admin ||
        widget.delegate.position == DelegatePosition.supervisor ||
        widget.delegate.role == UserRole.organizationAdmin ||
        widget.delegate.role == UserRole.superAdmin ||
        widget.delegate.role == UserRole.marketing ||
        widget.delegate.role == UserRole.marketingPromotion ||
        widget.delegate.role == UserRole.branchesMarketingManager;

    if (isGeneralManagerOrAdmin) {
      context.read<PhotoPermissionBloc>().add(
            LoadCompanyCapturedPhotosRequested(companyUID: widget.delegate.companyUID),
          );
    } else {
      context.read<PhotoPermissionBloc>().add(
            LoadDelegateCapturedPhotosRequested(delegateUID: widget.delegate.uid),
          );
    }
  }

  Future<void> _confirmDeletePhoto(BuildContext context, CapturedPhoto photo) async {
    final bloc = context.read<PhotoPermissionBloc>();
    final confirmed = await showDialog<bool>(
      context: context,
      builder: (dialogContext) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: Row(
          children: [
            Icon(Icons.warning_amber_rounded, color: Colors.red.shade700, size: 28),
            const SizedBox(width: 8),
            const Expanded(
              child: Text(
                'تأكيد حذف الصورة',
                style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
              ),
            ),
          ],
        ),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Text(
              'هل أنت متأكد من حذف هذه الصورة المرسلة من المندوب "${photo.delegateName}" بفرع "${photo.branchName}"؟',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: Colors.red.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(8),
                border: Border.all(color: Colors.red.shade200),
              ),
              child: Row(
                children: [
                  Icon(Icons.info_outline_rounded, size: 18, color: Colors.red.shade700),
                  const SizedBox(width: 8),
                  const Expanded(
                    child: Text(
                      'سيتم حذف الصورة بشكل نهائي من قاعدة البيانات ومساحة التخزين.',
                      style: TextStyle(fontSize: 12, color: Colors.red),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(dialogContext, false),
            child: const Text('إلغاء'),
          ),
          ElevatedButton.icon(
            style: ElevatedButton.styleFrom(
              backgroundColor: Colors.red,
              foregroundColor: Colors.white,
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(10)),
            ),
            onPressed: () => Navigator.pop(dialogContext, true),
            icon: const Icon(Icons.delete_forever_rounded, size: 18),
            label: const Text('حذف نهائي'),
          ),
        ],
      ),
    );

    if (confirmed == true && mounted) {
      bloc.add(
        DeleteCapturedPhotoRequested(
          photoId: photo.uid,
          organizationUID: photo.organizationUID.isNotEmpty
              ? photo.organizationUID
              : widget.delegate.organizationUID,
          companyUID: photo.companyUID.isNotEmpty
              ? photo.companyUID
              : widget.delegate.companyUID,
          permissionId: photo.permissionId,
          photoUrl: photo.photoUrl,
        ),
      );
    }
  }

  void _previousMonth() {
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = _now;
    if (_selectedMonth.year >= now.year && _selectedMonth.month >= now.month) {
      return;
    }
    setState(() {
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  void _resetToCurrentMonth() {
    setState(() {
      _selectedMonth = _now;
    });
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = _now;
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;

    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: const Text(
                'تقارير الصور الشهرية',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 1,
            )
          : null,
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.green,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadPhotos();
          } else if (state is PhotoPermissionError) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: Colors.red,
                behavior: SnackBarBehavior.floating,
              ),
            );
          }
        },
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(
              child: AppLoadingIndicator(
                style: AppLoadingStyle.threeArchedCircle,
                label: 'جاري تحميل تقارير الصور...',
              ),
            );
          }

          if (state is CapturedPhotosLoaded) {
            // Filter photos for the selected month
            final filteredPhotos = state.photos.where((photo) {
              return photo.capturedAt.year == _selectedMonth.year &&
                  photo.capturedAt.month == _selectedMonth.month;
            }).toList();

            // Pre-cache all photos in the background into local persistent disk cache
            if (filteredPhotos.isNotEmpty) {
              PhotoCacheManager.precachePhotos(filteredPhotos.map((p) => p.photoUrl));
            }

            // Statistics calculation
            final totalPhotos = filteredPhotos.length;
            final uniqueBranches = filteredPhotos.map((p) => p.branchId).toSet().length;

            final today = now;
            final photosToday = filteredPhotos.where((p) =>
                p.capturedAt.year == today.year &&
                p.capturedAt.month == today.month &&
                p.capturedAt.day == today.day).length;

            return RefreshIndicator(
              onRefresh: () async {
                _loadPhotos();
              },
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
                slivers: [
                  // Sync Status Banner
                  const SliverToBoxAdapter(
                    child: SyncStatusBanner(),
                  ),

                  // Modern M3 Month Selector Navigator
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 8, 16, 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                          border: Border.all(
                            color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.surface,
                                foregroundColor: colorScheme.primary,
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(36, 36),
                              ),
                              icon: const Icon(Icons.chevron_right_rounded, size: 20),
                              onPressed: _previousMonth,
                              tooltip: 'الشهر السابق',
                            ),
                            Column(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                Text(
                                  _getMonthNameArabic(_selectedMonth),
                                  style: TextStyle(
                                    fontSize: 15,
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                                if (!isCurrentMonth) ...[
                                  const SizedBox(height: 2),
                                  InkWell(
                                    onTap: _resetToCurrentMonth,
                                    borderRadius: BorderRadius.circular(6),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                      child: Text(
                                        'الشهر الحالي ↩',
                                        style: TextStyle(
                                          fontSize: 11,
                                          fontWeight: FontWeight.bold,
                                          color: colorScheme.secondary,
                                        ),
                                      ),
                                    ),
                                  ),
                                ],
                              ],
                            ),
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.surface,
                                foregroundColor: isCurrentMonth ? colorScheme.outline : colorScheme.primary,
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(36, 36),
                              ),
                              icon: const Icon(Icons.chevron_left_rounded, size: 20),
                              onPressed: isCurrentMonth ? null : _nextMonth,
                              tooltip: 'الشهر التالي',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // M3 Summary Metrics Cards
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              title: 'إجمالي الصور',
                              value: '$totalPhotos',
                              icon: Icons.photo_library_rounded,
                              theme: theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'الفروع المزارة',
                              value: '$uniqueBranches',
                              icon: Icons.storefront_rounded,
                              theme: theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'التقاطات اليوم',
                              value: '$photosToday',
                              icon: Icons.today_rounded,
                              theme: theme,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // M3 Refined Filter Toggle (By Date vs By Branch)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildSegmentButton(
                                title: 'حسب التاريخ',
                                icon: Icons.calendar_month_rounded,
                                isSelected: _currentGroupMode == GroupMode.byDate,
                                onTap: () => setState(() => _currentGroupMode = GroupMode.byDate),
                                colorScheme: colorScheme,
                              ),
                            ),
                            Expanded(
                              child: _buildSegmentButton(
                                title: 'حسب الفرع',
                                icon: Icons.store_rounded,
                                isSelected: _currentGroupMode == GroupMode.byBranch,
                                onTap: () => setState(() => _currentGroupMode = GroupMode.byBranch),
                                colorScheme: colorScheme,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Photos list or Empty state
                  if (filteredPhotos.isEmpty)
                    SliverFillRemaining(
                      hasScrollBody: false,
                      child: _buildEmptyState(theme, colorScheme),
                    )
                  else
                    SliverPadding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                      sliver: _buildGroupedPhotosList(filteredPhotos, theme),
                    ),
                  const SliverToBoxAdapter(
                    child: SizedBox(height: 24),
                  ),
                ],
              ),
            );
          }

          if (state is PhotoPermissionError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(32.0),
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 56, color: colorScheme.error),
                    const SizedBox(height: 16),
                    Text(
                      'تعذر تحميل تقارير الصور',
                      style: theme.textTheme.titleMedium?.copyWith(fontWeight: FontWeight.bold),
                    ),
                    const SizedBox(height: 8),
                    Text(
                      state.message,
                      style: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 20),
                    FilledButton.tonalIcon(
                      onPressed: _loadPhotos,
                      icon: const Icon(Icons.refresh_rounded, size: 18),
                      label: const Text('إعادة المحاولة'),
                    ),
                  ],
                ),
              ),
            );
          }

          return const Center(child: Text('جاري تحميل التقرير...'));
        },
      ),
    );
  }

  Widget _buildSegmentButton({
    required String title,
    required IconData icon,
    required bool isSelected,
    required VoidCallback onTap,
    required ColorScheme colorScheme,
  }) {
    return GestureDetector(
      onTap: onTap,
      child: AnimatedContainer(
        duration: const Duration(milliseconds: 200),
        margin: const EdgeInsets.all(3),
        decoration: BoxDecoration(
          color: isSelected ? colorScheme.primary : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: colorScheme.primary.withValues(alpha: 0.25),
                    blurRadius: 4,
                    offset: const Offset(0, 2),
                  ),
                ]
              : null,
        ),
        child: Center(
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(
                icon,
                size: 16,
                color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 6),
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildMetricCard({
    required String title,
    required String value,
    required IconData icon,
    required ThemeData theme,
  }) {
    final colorScheme = theme.colorScheme;
    return Container(
      padding: const EdgeInsets.symmetric(vertical: 10, horizontal: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      child: Column(
        children: [
          Container(
            padding: const EdgeInsets.all(6),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(icon, color: colorScheme.primary, size: 16),
          ),
          const SizedBox(height: 6),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
              letterSpacing: -0.5,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            title,
            style: TextStyle(
              fontSize: 11,
              color: colorScheme.onSurfaceVariant,
              fontWeight: FontWeight.w500,
            ),
            textAlign: TextAlign.center,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  Widget _buildGroupedPhotosList(List<CapturedPhoto> photos, ThemeData theme) {
    if (_currentGroupMode == GroupMode.byDate) {
      final Map<String, List<CapturedPhoto>> grouped = {};
      for (var photo in photos) {
        final dateKey = DateFormat('yyyy-MM-dd').format(photo.capturedAt);
        grouped.putIfAbsent(dateKey, () => []).add(photo);
      }

      final sortedKeys = grouped.keys.toList()..sort((a, b) => b.compareTo(a));

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final key = sortedKeys[index];
            final groupPhotos = grouped[key]!;
            final displayDate = DateFormat('EEEE، d MMMM yyyy', 'ar').format(DateTime.parse(key));

            return _buildGroupSection(
              title: displayDate,
              icon: Icons.calendar_today_rounded,
              photos: groupPhotos,
              theme: theme,
            );
          },
          childCount: sortedKeys.length,
        ),
      );
    } else {
      final Map<String, List<CapturedPhoto>> grouped = {};
      for (var photo in photos) {
        grouped.putIfAbsent(photo.branchName, () => []).add(photo);
      }

      final sortedKeys = grouped.keys.toList()..sort();

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final key = sortedKeys[index];
            final groupPhotos = grouped[key]!;

            return _buildGroupSection(
              title: key,
              icon: Icons.storefront_rounded,
              photos: groupPhotos,
              theme: theme,
            );
          },
          childCount: sortedKeys.length,
        ),
      );
    }
  }

  Widget _buildGroupSection({
    required String title,
    required IconData icon,
    required List<CapturedPhoto> photos,
    required ThemeData theme,
  }) {
    final colorScheme = theme.colorScheme;

    return Container(
      margin: const EdgeInsets.only(bottom: 10),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          collapsedBackgroundColor: colorScheme.surface,
          backgroundColor: colorScheme.surfaceContainerLowest,
          tilePadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 2),
          childrenPadding: const EdgeInsets.fromLTRB(12, 0, 12, 10),
          leading: Container(
            padding: const EdgeInsets.all(7),
            decoration: BoxDecoration(
              color: colorScheme.primaryContainer.withValues(alpha: 0.5),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Icon(icon, color: colorScheme.primary, size: 18),
          ),
          title: Text(
            title,
            style: const TextStyle(
              fontSize: 14,
              fontWeight: FontWeight.bold,
            ),
          ),
          trailing: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '${photos.length} صور',
                  style: TextStyle(
                    fontSize: 11,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
              const SizedBox(width: 4),
              const Icon(Icons.expand_more_rounded, size: 20),
            ],
          ),
          children: photos.map((photo) => _buildCompactPhotoCard(context, photo, theme)).toList(),
        ),
      ),
    );
  }

  Widget _buildCompactPhotoCard(BuildContext context, CapturedPhoto photo, ThemeData theme) {
    final colorScheme = theme.colorScheme;
    final dateStr = DateFormat('yyyy-MM-dd • hh:mm a', 'ar').format(photo.capturedAt);
    final isPending = photo.uid.startsWith('pending_');

    return Container(
      margin: const EdgeInsets.only(bottom: 6),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(12),
        border: Border.all(
          color: isPending
              ? Colors.amber.shade300
              : colorScheme.outlineVariant.withValues(alpha: 0.3),
        ),
      ),
      child: Material(
        color: Colors.transparent,
        child: InkWell(
          onTap: () => _showPhotoDetails(context, photo),
          borderRadius: BorderRadius.circular(12),
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
            child: Row(
              children: [
                // Thumbnail 52x52
                AppPhotoImage(
                  photoUrl: photo.photoUrl,
                  width: 52,
                  height: 52,
                  isThumbnail: true,
                  borderRadius: BorderRadius.circular(10),
                  fit: BoxFit.cover,
                ),
                const SizedBox(width: 12),

                // Info: Branch name + Date & time + status chip
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        photo.branchName,
                        style: const TextStyle(
                          fontSize: 13.5,
                          fontWeight: FontWeight.w700,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      const SizedBox(height: 3),
                      Text(
                        dateStr,
                        style: TextStyle(
                          fontSize: 11,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.w500,
                        ),
                      ),
                      const SizedBox(height: 4),
                      Row(
                        children: [
                          if (isPending) ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.amber.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.amber.shade300, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_off_rounded, size: 10, color: Colors.amber.shade900),
                                  const SizedBox(width: 3),
                                  Text(
                                    'معلقة بالهاتف',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.amber.shade900,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Colors.green.shade50,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Colors.green.shade300, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.cloud_done_rounded, size: 10, color: Colors.green.shade700),
                                  const SizedBox(width: 3),
                                  Text(
                                    'مرفوعة بالسيرفر',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Colors.green.shade800,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (photo.comment.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Expanded(
                              child: Text(
                                '💬 ${photo.comment.trim()}',
                                style: TextStyle(
                                  fontSize: 10.5,
                                  color: colorScheme.onSurfaceVariant,
                                  fontStyle: FontStyle.italic,
                                ),
                                maxLines: 1,
                                overflow: TextOverflow.ellipsis,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],
                  ),
                ),

                // Trailing action
                Icon(
                  Icons.chevron_left_rounded,
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                  size: 20,
                ),
              ],
            ),
          ),
        ),
      ),
    );
  }

  Widget _buildEmptyState(ThemeData theme, ColorScheme colorScheme) {
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32.0),
        child: Column(
          mainAxisAlignment: MainAxisAlignment.center,
          children: [
            Container(
              padding: const EdgeInsets.all(20),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Icons.photo_library_outlined,
                size: 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد صور ملتقطة في هذا الشهر',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'صور العروض الميدانية الملتقطة خلال هذا الشهر ستظهر هنا تلقائياً.',
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  String _getMonthNameArabic(DateTime date) {
    final formatter = DateFormat('MMMM yyyy', 'ar');
    return formatter.format(date);
  }

  void _showPhotoDetails(BuildContext context, CapturedPhoto photo) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final formattedDate = DateFormat('EEEE، d MMMM yyyy - hh:mm a', 'ar').format(photo.capturedAt);

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        bool isSaving = false;
        bool saveSuccess = false;
        String? statusText;

        return StatefulBuilder(
          builder: (sheetContext, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.85,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              builder: (context, scrollController) {
                return Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surface,
                    borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      // Pull Handle
                      Center(
                        child: Container(
                          margin: const EdgeInsets.symmetric(vertical: 12),
                          width: 40,
                          height: 4,
                          decoration: BoxDecoration(
                            color: colorScheme.outlineVariant,
                            borderRadius: BorderRadius.circular(2),
                          ),
                        ),
                      ),

                      // Header title
                      Padding(
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 4),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text(
                              'تفاصيل الصورة الميدانية',
                              style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                            ),
                            Row(
                              mainAxisSize: MainAxisSize.min,
                              children: [
                                if (_canDeletePhoto)
                                  IconButton(
                                    tooltip: 'حذف الصورة نهائياً',
                                    icon: Icon(Icons.delete_outline_rounded, size: 22, color: Colors.red.shade700),
                                    onPressed: () {
                                      Navigator.pop(modalContext);
                                      _confirmDeletePhoto(context, photo);
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Icons.close_rounded, size: 20),
                                  onPressed: () => Navigator.pop(modalContext),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const Divider(height: 1),

                      Expanded(
                        child: ListView(
                          controller: scrollController,
                          padding: const EdgeInsets.all(16),
                          children: [
                            // Interactive image with zoom
                            Container(
                              height: 340,
                              decoration: BoxDecoration(
                                borderRadius: BorderRadius.circular(16),
                                border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                              ),
                              clipBehavior: Clip.antiAlias,
                              child: InteractiveViewer(
                                panEnabled: true,
                                minScale: 1.0,
                                maxScale: 4.0,
                                child: AppPhotoImage(
                                  photoUrl: photo.photoUrl,
                                  fit: BoxFit.contain,
                                ),
                              ),
                            ),
                            const SizedBox(height: 6),
                            const Center(
                              child: Text(
                                '💡 يمكنك قرص الصورة أو استخدام إصبعين لتكبير التفاصيل',
                                style: TextStyle(fontSize: 11, color: Colors.grey),
                              ),
                            ),
                            const SizedBox(height: 16),

                            // Action Buttons (Save + Delete if permitted)
                            Row(
                              children: [
                                if (_canDeletePhoto) ...[
                                  OutlinedButton.icon(
                                    onPressed: () {
                                      Navigator.pop(modalContext);
                                      _confirmDeletePhoto(context, photo);
                                    },
                                    icon: const Icon(Icons.delete_outline_rounded, color: Colors.red, size: 18),
                                    label: const Text(
                                      'حذف الصورة',
                                      style: TextStyle(color: Colors.red, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: const BorderSide(color: Colors.redAccent),
                                      padding: const EdgeInsets.symmetric(vertical: 13, horizontal: 14),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                  const SizedBox(width: 8),
                                ],
                                Expanded(
                                  child: FilledButton.icon(
                                    onPressed: isSaving
                                        ? null
                                        : () async {
                                            setSheetState(() {
                                              isSaving = true;
                                              statusText = null;
                                            });
                                            try {
                                              final success = await PhotoCacheManager.savePhotoToGallery(
                                                context,
                                                photoUrl: photo.photoUrl,
                                              );
                                              if (sheetContext.mounted) {
                                                setSheetState(() {
                                                  isSaving = false;
                                                  saveSuccess = success;
                                                  statusText = success
                                                      ? '✅ تم حفظ الصورة في ألبوم صور الهاتف بنجاح.'
                                                      : '⚠️ يرجى منح الإذن للوصول للصور من إعدادات الهاتف.';
                                                });
                                              }
                                            } catch (e) {
                                              if (sheetContext.mounted) {
                                                setSheetState(() {
                                                  isSaving = false;
                                                  saveSuccess = false;
                                                  statusText = '❌ تعذر حفظ الصورة: $e';
                                                });
                                              }
                                            }
                                          },
                                    icon: isSaving
                                        ? const SizedBox(
                                            width: 18,
                                            height: 18,
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            saveSuccess ? Icons.check_circle_rounded : Icons.download_rounded,
                                            size: 18,
                                          ),
                                    label: Text(
                                      isSaving
                                          ? 'جاري حفظ الصورة...'
                                          : saveSuccess
                                              ? 'تم الحفظ في الهاتف ✓'
                                              : 'حفظ الصورة',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: saveSuccess ? Colors.green.shade700 : null,
                                      padding: const EdgeInsets.symmetric(vertical: 13),
                                      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                                    ),
                                  ),
                                ),
                              ],
                            ),

                            // In-Modal Status Notification Banner
                            if (statusText != null) ...[
                              const SizedBox(height: 10),
                              Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
                                decoration: BoxDecoration(
                                  color: saveSuccess ? Colors.green.shade50 : Colors.amber.shade50,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: saveSuccess ? Colors.green.shade300 : Colors.amber.shade300,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      saveSuccess ? Icons.check_circle_rounded : Icons.info_outline_rounded,
                                      color: saveSuccess ? Colors.green.shade700 : Colors.amber.shade800,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        statusText!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: saveSuccess ? Colors.green.shade800 : Colors.amber.shade900,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                            const SizedBox(height: 16),

                        // Report details card
                        Container(
                          padding: const EdgeInsets.all(14),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerLow,
                            borderRadius: BorderRadius.circular(14),
                            border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.5)),
                          ),
                          child: Column(
                            crossAxisAlignment: CrossAxisAlignment.start,
                            children: [
                              _buildDetailItem(
                                icon: Icons.storefront_rounded,
                                title: 'الفرع المعتمد:',
                                value: photo.branchName,
                                theme: theme,
                              ),
                              const Divider(height: 18),
                              _buildDetailItem(
                                icon: Icons.calendar_today_rounded,
                                title: 'وقت وتاريخ الالتقاط:',
                                value: formattedDate,
                                theme: theme,
                              ),
                              const Divider(height: 18),
                              _buildDetailItem(
                                icon: Icons.person_rounded,
                                title: 'بواسطة المندوب:',
                                value: photo.delegateName,
                                theme: theme,
                              ),
                              if (photo.comment.trim().isNotEmpty) ...[
                                const Divider(height: 18),
                                _buildDetailItem(
                                  icon: Icons.comment_rounded,
                                  title: 'تعليق المندوب:',
                                  value: photo.comment,
                                  theme: theme,
                                  isComment: true,
                                ),
                              ],
                            ],
                          ),
                        ),
                      ],
                    ),
                  ),
                ],
              ),
            );
          },
        );
      },
    );
  },
);
}

  Widget _buildDetailItem({
    required IconData icon,
    required String title,
    required String value,
    required ThemeData theme,
    bool isComment = false,
  }) {
    final colorScheme = theme.colorScheme;
    return Row(
      crossAxisAlignment: isComment ? CrossAxisAlignment.start : CrossAxisAlignment.center,
      children: [
        Icon(icon, color: colorScheme.primary, size: 18),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                title,
                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
              ),
              const SizedBox(height: 2),
              Text(
                value,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.bold,
                  fontStyle: isComment ? FontStyle.italic : FontStyle.normal,
                ),
              ),
            ],
          ),
        ),
      ],
    );
  }
}
