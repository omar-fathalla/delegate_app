import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/widgets/app_loading_indicator.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/services/photo_cache_manager.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import '../widgets/sync_status_banner.dart';
import '../widgets/company_name_with_code.dart';
import '../bloc/photo_permission_bloc.dart';
import '../../domain/entities/captured_photo.dart';

enum GroupMode {
  byDate,
  byBranch,
  byDelegate,
}

class MonthlyPhotoReportScreen extends StatelessWidget {
  final Delegate delegate;
  final bool showAppBar;

  const MonthlyPhotoReportScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  Widget build(BuildContext context) {
    PhotoPermissionBloc? existingBloc;
    try {
      existingBloc = context.read<PhotoPermissionBloc>();
    } catch (_) {
      existingBloc = null;
    }

    if (existingBloc != null) {
      return _MonthlyPhotoReportContent(
        delegate: delegate,
        showAppBar: showAppBar,
      );
    }

    return BlocProvider<PhotoPermissionBloc>(
      create: (_) => di.sl<PhotoPermissionBloc>(),
      child: _MonthlyPhotoReportContent(
        delegate: delegate,
        showAppBar: showAppBar,
      ),
    );
  }
}

class _MonthlyPhotoReportContent extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;

  const _MonthlyPhotoReportContent({
    required this.delegate,
    required this.showAppBar,
  });

  @override
  State<_MonthlyPhotoReportContent> createState() => _MonthlyPhotoReportContentState();
}

class _MonthlyPhotoReportContentState extends State<_MonthlyPhotoReportContent> {
  late DateTime _selectedMonth;
  GroupMode _currentGroupMode = GroupMode.byDate;
  int _slideDirection = 0; // -1 for previous (left to right), +1 for next (right to left)

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
        widget.delegate.role == UserRole.branchesMarketingManager ||
        widget.delegate.role == UserRole.hr;

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
        widget.delegate.role == UserRole.branchesMarketingManager ||
        widget.delegate.role == UserRole.hr;

    if (isGeneralManagerOrAdmin) {
      context.read<PhotoPermissionBloc>().add(
            LoadCompanyCapturedPhotosRequested(
              companyUID: widget.delegate.companyUID,
              limit: widget.delegate.companyUID.isEmpty ? 200 : null,
            ),
          );
    } else {
      context.read<PhotoPermissionBloc>().add(
            LoadDelegateCapturedPhotosRequested(delegateUID: widget.delegate.uid),
          );
    }
  }

  Future<void> _confirmDeletePhoto(CapturedPhoto photo) async {
    final bloc = context.read<PhotoPermissionBloc>();
    final colorScheme = Theme.of(context).colorScheme;
    final isDesktop = MediaQuery.sizeOf(context).width > 768;

    Widget buildConfirmContent(BuildContext modalContext) {
      return Padding(
        padding: EdgeInsets.fromLTRB(
          20,
          isDesktop ? 20 : 12,
          20,
          24 + MediaQuery.viewInsetsOf(modalContext).bottom,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (!isDesktop) ...[
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
              const SizedBox(height: 16),
            ],
            Row(
              children: [
                Icon(Symbols.warning_amber_rounded, color: colorScheme.error, size: 28),
                const SizedBox(width: 8),
                const Expanded(
                  child: Text(
                    'تأكيد حذف الصورة',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),
            Text(
              'هل أنت متأكد من حذف هذه الصورة المرسلة من "${photo.delegateName}" بفرع "${BranchDisplayCache.instance.displayName(photo.branchName)}"؟',
              style: const TextStyle(fontSize: 14),
            ),
            const SizedBox(height: 12),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.error.withValues(alpha: 0.1),
                borderRadius: BorderRadius.circular(12),
                border: Border.all(color: colorScheme.error.withValues(alpha: 0.3)),
              ),
              child: Row(
                children: [
                  Icon(Symbols.info_rounded, size: 18, color: colorScheme.error),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      'سيتم حذف الصورة بشكل نهائي من قاعدة البيانات ومساحة التخزين.',
                      style: TextStyle(fontSize: 12, color: colorScheme.error),
                    ),
                  ),
                ],
              ),
            ),
            const SizedBox(height: 20),
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainer,
                borderRadius: BorderRadius.circular(24),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  Expanded(
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: () => Navigator.pop(modalContext, false),
                        child: Center(
                          child: Text(
                            'إلغاء',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.8),
                  ),
                  Expanded(
                    child: Material(
                      color: colorScheme.error.withValues(alpha: 0.12),
                      child: InkWell(
                        onTap: () => Navigator.pop(modalContext, true),
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(Symbols.delete_forever_rounded, size: 18, color: colorScheme.error),
                              const SizedBox(width: 6),
                              Flexible(
                                child: Text(
                                  'حذف نهائي',
                                  overflow: TextOverflow.ellipsis,
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: 14,
                                    color: colorScheme.error,
                                  ),
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
      );
    }

    if (!mounted) return;
    final bool? confirmed;
    if (isDesktop) {
      confirmed = await showDialog<bool>(
        context: context,
        builder: (dialogContext) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520),
            child: buildConfirmContent(dialogContext),
          ),
        ),
      );
    } else {
      confirmed = await showM3ModalBottomSheet<bool>(
        context: context,
        isScrollControlled: true,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => buildConfirmContent(sheetContext),
      );
    }

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
      _slideDirection = -1;
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month - 1);
    });
  }

  void _nextMonth() {
    final now = _now;
    if (_selectedMonth.year >= now.year && _selectedMonth.month >= now.month) {
      return;
    }
    setState(() {
      _slideDirection = 1;
      _selectedMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1);
    });
  }

  void _selectMonth(DateTime month) {
    setState(() {
      _slideDirection = month.isAfter(_selectedMonth) ? 1 : -1;
      _selectedMonth = DateTime(month.year, month.month);
    });
  }

  void _resetToCurrentMonth() {
    final now = _now;
    setState(() {
      _slideDirection = 1;
      _selectedMonth = DateTime(now.year, now.month);
    });
  }

  void _showMonthPickerSheet(BuildContext context, List<CapturedPhoto> allPhotos) {
    final colorScheme = Theme.of(context).colorScheme;
    final now = _now;

    // Aggregate all historical months from allPhotos
    final Map<String, int> monthCounts = {};
    for (var photo in allPhotos) {
      final key = '${photo.capturedAt.year}-${photo.capturedAt.month.toString().padLeft(2, '0')}';
      monthCounts[key] = (monthCounts[key] ?? 0) + 1;
    }

    // Ensure current month is represented
    final currentKey = '${now.year}-${now.month.toString().padLeft(2, '0')}';
    monthCounts.putIfAbsent(currentKey, () => 0);

    final sortedKeys = monthCounts.keys.toList()..sort((a, b) => b.compareTo(a));

    showModalBottomSheet(
      context: context,
      sheetAnimationStyle: m3SheetAnimation,
      backgroundColor: Colors.transparent,
      builder: (sheetContext) {
        return Container(
          padding: const EdgeInsets.fromLTRB(16, 12, 16, 24),
          decoration: BoxDecoration(
            color: colorScheme.surface,
            borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              Center(
                child: Container(
                  width: 40,
                  height: 4,
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant,
                    borderRadius: BorderRadius.circular(2),
                  ),
                ),
              ),
              const SizedBox(height: 14),
              Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Row(
                    children: [
                      Icon(Symbols.calendar_month_rounded, color: colorScheme.primary, size: 22),
                      const SizedBox(width: 8),
                      const Text(
                        'أرشيف الشهور المسجلة',
                        style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                    ],
                  ),
                  IconButton(
                    icon: const Icon(Symbols.close_rounded, size: 20),
                    onPressed: () => Navigator.pop(sheetContext),
                  ),
                ],
              ),
              const SizedBox(height: 10),
              Flexible(
                child: ListView.builder(
                  shrinkWrap: true,
                  itemCount: sortedKeys.length,
                  itemBuilder: (context, index) {
                    final key = sortedKeys[index];
                    final parts = key.split('-');
                    final year = int.parse(parts[0]);
                    final month = int.parse(parts[1]);
                    final date = DateTime(year, month);
                    final isSelected = _selectedMonth.year == year && _selectedMonth.month == month;
                    final isCurrent = now.year == year && now.month == month;
                    final count = monthCounts[key] ?? 0;

                    return Padding(
                      padding: const EdgeInsets.only(bottom: 8),
                      child: Material(
                        color: isSelected
                            ? colorScheme.primaryContainer.withValues(alpha: 0.5)
                            : colorScheme.surfaceContainer,
                        clipBehavior: Clip.antiAlias,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(12),
                          side: BorderSide(
                            color: isSelected
                                ? colorScheme.primary
                                : colorScheme.outlineVariant.withValues(alpha: 0.4),
                          ),
                        ),
                        child: ListTile(
                        onTap: () {
                          Navigator.pop(sheetContext);
                          _selectMonth(date);
                        },
                        leading: Icon(
                          isSelected ? Symbols.check_circle_rounded : Symbols.folder_rounded,
                          color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                        ),
                        title: Text(
                          _getMonthNameArabic(date),
                          style: TextStyle(
                            fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                            color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                          ),
                        ),
                        subtitle: isCurrent
                            ? Text(
                                'الشهر الحالي',
                                style: TextStyle(
                                  fontSize: 11,
                                  color: colorScheme.secondary,
                                  fontWeight: FontWeight.bold,
                                ),
                              )
                            : null,
                        trailing: Container(
                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                          decoration: BoxDecoration(
                            color: count > 0
                                ? colorScheme.primary.withValues(alpha: 0.12)
                                : colorScheme.surfaceContainerHigh,
                            borderRadius: BorderRadius.circular(8),
                          ),
                          child: Text(
                            '$count صورة',
                            style: TextStyle(
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                              color: count > 0 ? colorScheme.primary : colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  );
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
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
                'الأرشيف الشهري لصور الشركة',
                style: TextStyle(
                  fontSize: 17,
                  fontWeight: FontWeight.bold,
                  letterSpacing: -0.2,
                ),
              ),
              centerTitle: true,
              elevation: 0,
              scrolledUnderElevation: 1,
              actions: [
                IconButton(
                  icon: const Icon(Symbols.refresh_rounded),
                  tooltip: 'تحديث الصور',
                  onPressed: _loadPhotos,
                ),
              ],
            )
          : null,
      backgroundColor: colorScheme.surfaceContainerLowest,
      body: BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
        listener: (context, state) {
          if (state is PhotoPermissionActionSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(
                content: Text(state.message),
                backgroundColor: colorScheme.primary,
                behavior: SnackBarBehavior.floating,
              ),
            );
            _loadPhotos();
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
        builder: (context, state) {
          if (state is PhotoPermissionLoading) {
            return const Center(
              child: AppLoadingIndicator(
                style: AppLoadingStyle.threeArchedCircle,
                label: 'جاري تحميل أرشيف الصور...',
              ),
            );
          }

          if (state is CapturedPhotosLoaded) {
            final allPhotos = state.photos;

            // Filter photos for the selected month
            final filteredPhotos = allPhotos.where((photo) {
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
            final uniqueDelegates = filteredPhotos.map((p) => p.delegateUID.isNotEmpty ? p.delegateUID : p.delegateName).toSet().length;

            // Extract historical months that have photos
            final Map<String, int> availableMonthsMap = {};
            for (var p in allPhotos) {
              final k = '${p.capturedAt.year}-${p.capturedAt.month.toString().padLeft(2, '0')}';
              availableMonthsMap[k] = (availableMonthsMap[k] ?? 0) + 1;
            }
            final sortedAvailableKeys = availableMonthsMap.keys.toList()..sort((a, b) => b.compareTo(a));

            return M3Refresh(
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

                  // Company Identity Header
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 10, 16, 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer,
                          borderRadius: BorderRadius.circular(14),
                        ),
                        child: Row(
                          children: [
                            Container(
                              padding: const EdgeInsets.all(8),
                              decoration: BoxDecoration(
                                color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Icon(
                                Symbols.business_rounded,
                                color: colorScheme.primary,
                                size: 20,
                              ),
                            ),
                            const SizedBox(width: 12),
                            Expanded(
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  CompanyNameWithCode(
                                    organizationUID: widget.delegate.organizationUID,
                                    companyUID: widget.delegate.companyUID,
                                    companyName: widget.delegate.companyName,
                                    companyCode: null,
                                    style: TextStyle(
                                      fontSize: 14,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onSurface,
                                    ),
                                  ),
                                  const SizedBox(height: 2),
                                  Text(
                                    'جميع الصور محفوظة ومؤرشفة للشركة ومستقلة عن حسابات المناديب',
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Animated Month Navigator Bar
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 4, 16, 6),
                      child: Container(
                        padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer.withValues(alpha: 0.6),
                          borderRadius: BorderRadius.circular(16),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            // Previous Month Button (Unlimited historical cycling)
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.surface,
                                foregroundColor: colorScheme.primary,
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(38, 38),
                              ),
                              icon: const Icon(
                                Symbols.chevron_right_rounded,
                                size: 22,
                                textDirection: TextDirection.ltr,
                              ),
                              onPressed: _previousMonth,
                              tooltip: 'الشهر السابق (أرشيف)',
                            ),

                            // Animated Month Title + Picker trigger
                            InkWell(
                              onTap: () => _showMonthPickerSheet(context, allPhotos),
                              borderRadius: BorderRadius.circular(12),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
                                child: Column(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AnimatedSwitcher(
                                      duration: AppMotionDurations.medium2,
                                      transitionBuilder: (child, animation) {
                                        final offsetAnimation = Tween<Offset>(
                                          begin: Offset(_slideDirection * 0.4, 0.0),
                                          end: Offset.zero,
                                        ).animate(CurvedAnimation(
                                          parent: animation,
                                          curve: AppMotionCurves.emphasizedDecelerate,
                                        ));
                                        return FadeTransition(
                                          opacity: animation,
                                          child: SlideTransition(
                                            position: offsetAnimation,
                                            child: child,
                                          ),
                                        );
                                      },
                                      child: KeyedSubtree(
                                        key: ValueKey('${_selectedMonth.year}-${_selectedMonth.month}'),
                                        child: Row(
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
                                            const SizedBox(width: 4),
                                            Icon(
                                              Symbols.arrow_drop_down_rounded,
                                              color: colorScheme.primary,
                                              size: 20,
                                            ),
                                          ],
                                        ),
                                      ),
                                    ),
                                    if (!isCurrentMonth) ...[
                                      const SizedBox(height: 2),
                                      InkWell(
                                        onTap: _resetToCurrentMonth,
                                        borderRadius: BorderRadius.circular(6),
                                        child: Padding(
                                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Symbols.restore_rounded,
                                                size: 13,
                                                color: colorScheme.secondary,
                                              ),
                                              const SizedBox(width: 4),
                                              Text(
                                                'العودة للشهر الحالي',
                                                style: TextStyle(
                                                  fontSize: 11,
                                                  fontWeight: FontWeight.bold,
                                                  color: colorScheme.secondary,
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
                            ),

                            // Next Month Button
                            IconButton.filledTonal(
                              style: IconButton.styleFrom(
                                backgroundColor: colorScheme.surface,
                                foregroundColor: isCurrentMonth ? colorScheme.outline : colorScheme.primary,
                                padding: const EdgeInsets.all(8),
                                minimumSize: const Size(38, 38),
                              ),
                              icon: const Icon(
                                Symbols.chevron_left_rounded,
                                size: 22,
                                textDirection: TextDirection.ltr,
                              ),
                              onPressed: isCurrentMonth ? null : _nextMonth,
                              tooltip: 'الشهر التالي',
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Quick Historical Months Chips (if more than 1 month has data)
                  if (sortedAvailableKeys.isNotEmpty)
                    SliverToBoxAdapter(
                      child: Container(
                        height: 38,
                        margin: const EdgeInsets.only(top: 2, bottom: 6),
                        child: ListView.builder(
                          scrollDirection: Axis.horizontal,
                          padding: const EdgeInsets.symmetric(horizontal: 16),
                          itemCount: sortedAvailableKeys.length,
                          itemBuilder: (context, index) {
                            final k = sortedAvailableKeys[index];
                            final parts = k.split('-');
                            final y = int.parse(parts[0]);
                            final m = int.parse(parts[1]);
                            final chipDate = DateTime(y, m);
                            final isSelected = _selectedMonth.year == y && _selectedMonth.month == m;
                            final count = availableMonthsMap[k] ?? 0;

                            return Padding(
                              padding: const EdgeInsets.only(left: 8),
                              child: ChoiceChip(
                                label: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(_getMonthNameArabic(chipDate)),
                                    const SizedBox(width: 4),
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 1),
                                      decoration: BoxDecoration(
                                        color: isSelected
                                            ? colorScheme.onPrimary.withValues(alpha: 0.2)
                                            : colorScheme.primary.withValues(alpha: 0.1),
                                        borderRadius: BorderRadius.circular(6),
                                      ),
                                      child: Text(
                                        '$count',
                                        style: TextStyle(
                                          fontSize: 10,
                                          fontWeight: FontWeight.bold,
                                          color: isSelected ? colorScheme.onPrimary : colorScheme.primary,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                                selected: isSelected,
                                selectedColor: colorScheme.primary,
                                labelStyle: TextStyle(
                                  fontSize: 11.5,
                                  fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                                  color: isSelected ? colorScheme.onPrimary : colorScheme.onSurface,
                                ),
                                onSelected: (selected) {
                                  if (selected) {
                                    _selectMonth(chipDate);
                                  }
                                },
                              ),
                            );
                          },
                        ),
                      ),
                    ),

                  // Summary Metrics Cards (Photos, Branches, Delegates)
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                      child: Row(
                        children: [
                          Expanded(
                            child: _buildMetricCard(
                              title: 'إجمالي الصور',
                              value: '$totalPhotos',
                              icon: Symbols.photo_library_rounded,
                              theme: theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'الفروع المزارة',
                              value: '$uniqueBranches',
                              icon: Symbols.storefront_rounded,
                              theme: theme,
                            ),
                          ),
                          const SizedBox(width: 8),
                          Expanded(
                            child: _buildMetricCard(
                              title: 'المناديب النشطين',
                              value: '$uniqueDelegates',
                              icon: Symbols.group_rounded,
                              theme: theme,
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),

                  // 3 Grouping Segment Modes: By Date / By Branch / By Delegate
                  SliverToBoxAdapter(
                    child: Padding(
                      padding: const EdgeInsets.fromLTRB(16, 6, 16, 8),
                      child: Container(
                        height: 42,
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainer.withValues(alpha: 0.5),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: Row(
                          children: [
                            Expanded(
                              child: _buildSegmentButton(
                                title: 'حسب التاريخ',
                                icon: Symbols.calendar_month_rounded,
                                isSelected: _currentGroupMode == GroupMode.byDate,
                                onTap: () => setState(() => _currentGroupMode = GroupMode.byDate),
                                colorScheme: colorScheme,
                              ),
                            ),
                            Expanded(
                              child: _buildSegmentButton(
                                title: 'حسب الفرع',
                                icon: Symbols.store_rounded,
                                isSelected: _currentGroupMode == GroupMode.byBranch,
                                onTap: () => setState(() => _currentGroupMode = GroupMode.byBranch),
                                colorScheme: colorScheme,
                              ),
                            ),
                            Expanded(
                              child: _buildSegmentButton(
                                title: 'حسب المندوب',
                                icon: Symbols.person_rounded,
                                isSelected: _currentGroupMode == GroupMode.byDelegate,
                                onTap: () => setState(() => _currentGroupMode = GroupMode.byDelegate),
                                colorScheme: colorScheme,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),

                  // Photos list or Empty state with smooth animated transition
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
                    Icon(Symbols.error_outline_rounded, size: 56, color: colorScheme.error),
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
                      icon: const Icon(Symbols.refresh_rounded, size: 18),
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
          color: isSelected ? colorScheme.secondaryContainer : Colors.transparent,
          borderRadius: BorderRadius.circular(10),
          boxShadow: isSelected
              ? [
                  BoxShadow(
                    color: Colors.transparent,
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
                size: 15,
                color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 4),
              Text(
                title,
                style: TextStyle(
                  fontSize: 11.5,
                  fontWeight: isSelected ? FontWeight.bold : FontWeight.w500,
                  color: isSelected ? colorScheme.onSecondaryContainer : colorScheme.onSurfaceVariant,
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
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(14),
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
              icon: Symbols.calendar_today_rounded,
              photos: groupPhotos,
              theme: theme,
            );
          },
          childCount: sortedKeys.length,
        ),
      );
    } else if (_currentGroupMode == GroupMode.byBranch) {
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
              icon: Symbols.storefront_rounded,
              photos: groupPhotos,
              theme: theme,
            );
          },
          childCount: sortedKeys.length,
        ),
      );
    } else {
      // GroupMode.byDelegate
      final Map<String, List<CapturedPhoto>> grouped = {};
      for (var photo in photos) {
        final delName = photo.delegateName.trim().isNotEmpty ? photo.delegateName.trim() : 'مندوب غير محدد';
        grouped.putIfAbsent(delName, () => []).add(photo);
      }

      final sortedKeys = grouped.keys.toList()..sort();

      return SliverList(
        delegate: SliverChildBuilderDelegate(
          (context, index) {
            final key = sortedKeys[index];
            final groupPhotos = grouped[key]!;

            return _buildGroupSection(
              title: key,
              icon: Symbols.person_rounded,
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
        color: colorScheme.surfaceContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      clipBehavior: Clip.antiAlias,
      child: Theme(
        data: theme.copyWith(dividerColor: Colors.transparent),
        child: ExpansionTile(
          initiallyExpanded: false,
          collapsedBackgroundColor: colorScheme.surfaceContainer,
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
                  color: colorScheme.surfaceContainerHigh,
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
              const Icon(Symbols.expand_more_rounded, size: 20),
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
              ? Theme.of(context).colorScheme.tertiary
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
                // Thumbnail 54x54
                AppPhotoImage(
                  photoUrl: photo.photoUrl,
                  width: 54,
                  height: 54,
                  isThumbnail: true,
                  borderRadius: BorderRadius.circular(10),
                  fit: BoxFit.cover,
                ),
                const SizedBox(width: 12),

                // Info
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        children: [
                          Expanded(
                            child: Text(
                              _currentGroupMode == GroupMode.byDelegate
                                  ? BranchDisplayCache.instance.displayName(photo.branchName)
                                  : photo.delegateName.isNotEmpty
                                      ? photo.delegateName
                                      : BranchDisplayCache.instance.displayName(photo.branchName),
                              style: const TextStyle(
                                fontSize: 13.5,
                                fontWeight: FontWeight.w700,
                              ),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                            ),
                          ),
                          if (_currentGroupMode == GroupMode.byDelegate) ...[
                            Text(
                              photo.delegateName,
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.primary,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          ],
                        ],
                      ),
                      const SizedBox(height: 3),
                      Text(
                        _currentGroupMode == GroupMode.byDate
                            ? '${BranchDisplayCache.instance.displayName(photo.branchName)} • $dateStr'
                            : dateStr,
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
                                color: Theme.of(context).colorScheme.tertiaryContainer,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Theme.of(context).colorScheme.tertiary, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.cloud_off_rounded, size: 10, color: Theme.of(context).colorScheme.onTertiaryContainer),
                                  const SizedBox(width: 3),
                                  Text(
                                    'معلقة بالهاتف',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 1.5),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.primaryContainer,
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: Theme.of(context).colorScheme.primary, width: 0.8),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Symbols.cloud_done_rounded, size: 10, color: Theme.of(context).colorScheme.onPrimaryContainer),
                                  const SizedBox(width: 3),
                                  Text(
                                    'مرفوعة بالسيرفر',
                                    style: TextStyle(
                                      fontSize: 9.5,
                                      fontWeight: FontWeight.bold,
                                      color: Theme.of(context).colorScheme.onPrimaryContainer,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],
                          if (photo.comment.trim().isNotEmpty) ...[
                            const SizedBox(width: 6),
                            Icon(Symbols.comment_rounded, size: 12, color: colorScheme.onSurfaceVariant),
                            const SizedBox(width: 4),
                            Expanded(
                              child: Text(
                                photo.comment.trim(),
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
                  Symbols.chevron_right_rounded,
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
                color: colorScheme.surfaceContainer.withValues(alpha: 0.5),
                shape: BoxShape.circle,
              ),
              child: Icon(
                Symbols.photo_library_rounded,
                size: 56,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              'لا توجد صور ملتقطة في ${_getMonthNameArabic(_selectedMonth)}',
              style: TextStyle(
                fontSize: 15,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
            const SizedBox(height: 6),
            Text(
              'يمكنك التنقل بين الشهور السابقة باستخدام الأسهم بالأعلى لتصفح الأرشيف الكامل للشركة.',
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
      sheetAnimationStyle: m3SheetAnimation,
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
              builder: (scrollContext, scrollController) {
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
                                    icon: Icon(Symbols.delete_outline_rounded, size: 22, color: Colors.red.shade700),
                                    onPressed: () {
                                      Navigator.pop(modalContext);
                                      _confirmDeletePhoto(photo);
                                    },
                                  ),
                                IconButton(
                                  icon: const Icon(Symbols.close_rounded, size: 20),
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
                            Center(
                              child: Text(
                                'يمكنك قرص الصورة أو استخدام إصبعين لتكبير التفاصيل',
                                style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
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
                                      _confirmDeletePhoto(photo);
                                    },
                                    icon: Icon(Symbols.delete_rounded, color: colorScheme.error, size: 18),
                                    label: Text(
                                      'حذف الصورة',
                                      style: TextStyle(color: colorScheme.error, fontWeight: FontWeight.bold, fontSize: 13),
                                    ),
                                    style: OutlinedButton.styleFrom(
                                      side: BorderSide(color: colorScheme.error),
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
                                                      ? 'تم حفظ الصورة في ألبوم صور الهاتف بنجاح.'
                                                      : 'يرجى منح الإذن للوصول للصور من إعدادات الهاتف.';
                                                });
                                              }
                                            } catch (e) {
                                              if (sheetContext.mounted) {
                                                setSheetState(() {
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
                                            child: CircularProgressIndicator(
                                              strokeWidth: 2,
                                              color: Colors.white,
                                            ),
                                          )
                                        : Icon(
                                            saveSuccess ? Symbols.check_circle_rounded : Symbols.download_rounded,
                                            size: 18,
                                          ),
                                    label: Text(
                                      isSaving
                                          ? 'جاري حفظ الصورة...'
                                          : saveSuccess
                                              ? 'تم الحفظ في الهاتف'
                                              : 'حفظ الصورة',
                                      style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                                    ),
                                    style: FilledButton.styleFrom(
                                      backgroundColor: saveSuccess ? colorScheme.primary : null,
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
                                  color: saveSuccess ? Theme.of(context).colorScheme.primaryContainer : Theme.of(context).colorScheme.tertiaryContainer,
                                  borderRadius: BorderRadius.circular(12),
                                  border: Border.all(
                                    color: saveSuccess ? Theme.of(context).colorScheme.primary : Theme.of(context).colorScheme.tertiary,
                                  ),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      saveSuccess ? Symbols.check_circle_rounded : Symbols.info_rounded,
                                      color: saveSuccess ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onTertiaryContainer,
                                      size: 18,
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Text(
                                        statusText!,
                                        style: TextStyle(
                                          fontSize: 12,
                                          fontWeight: FontWeight.bold,
                                          color: saveSuccess ? Theme.of(context).colorScheme.onPrimaryContainer : Theme.of(context).colorScheme.onTertiaryContainer,
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
                                color: colorScheme.surfaceContainer,
                                borderRadius: BorderRadius.circular(14),
                              ),
                              child: Column(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  _buildDetailItem(
                                    icon: Symbols.business_rounded,
                                    title: 'الشركة التابعة:',
                                    value: photo.companyName.isNotEmpty
                                        ? photo.companyName
                                        : widget.delegate.companyName,
                                    theme: theme,
                                  ),
                                  const Divider(height: 18),
                                  _buildDetailItem(
                                    icon: Symbols.storefront_rounded,
                                    title: 'الفرع المعتمد:',
                                    value: photo.branchName,
                                    theme: theme,
                                  ),
                                  const Divider(height: 18),
                                  _buildDetailItem(
                                    icon: Symbols.calendar_today_rounded,
                                    title: 'وقت وتاريخ الالتقاط:',
                                    value: formattedDate,
                                    theme: theme,
                                  ),
                                  const Divider(height: 18),
                                  _buildDetailItem(
                                    icon: Symbols.person_rounded,
                                    title: 'بواسطة المندوب:',
                                    value: photo.delegateName,
                                    theme: theme,
                                  ),
                                  if (photo.comment.trim().isNotEmpty) ...[
                                    const Divider(height: 18),
                                    _buildDetailItem(
                                      icon: Symbols.comment_rounded,
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
