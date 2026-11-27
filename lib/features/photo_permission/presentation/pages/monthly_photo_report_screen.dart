import 'dart:async';

import 'package:animations/animations.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/services/photo_cache_manager.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/photo_permission/presentation/photo_reports_refresh.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

import '../../domain/entities/captured_photo.dart';
import '../bloc/photo_permission_bloc.dart';
import '../widgets/sync_status_banner.dart';

enum GroupMode { byDate, byBranch, byDelegate }

/// Monthly photo report (delegate «تقارير الصور» tab, supervisors, HR web).
///
/// TAS-387 (user review 27 Nov 2026), built from the playground only:
/// * one month card like attendance: arrows, the month (a menu of the months
///   that have photos), «الشهر الحالي», the numbers, the archive note;
/// * grouping is a connected ButtonGroup (C-06);
/// * each group is a section header and a 3-column grid of the photos; a
///   photo opens its page with a container transform;
/// * only a photo still on the phone carries a badge;
/// * skeletons while loading, PullToRefresh, EmptyState for empty and error.
class MonthlyPhotoReportScreen extends StatelessWidget {
  final Delegate delegate;
  final bool showAppBar;

  /// Opt-in refresh button above the report, for hosts that hide the app
  /// bar and its refresh action (the HR web shell inner page, where pull to
  /// refresh does not work with a mouse). Off by default.
  final bool showInlineRefresh;

  const MonthlyPhotoReportScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
    this.showInlineRefresh = false,
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
        showInlineRefresh: showInlineRefresh,
      );
    }

    return BlocProvider<PhotoPermissionBloc>(
      create: (_) => di.sl<PhotoPermissionBloc>(),
      child: _MonthlyPhotoReportContent(
        delegate: delegate,
        showAppBar: showAppBar,
        showInlineRefresh: showInlineRefresh,
      ),
    );
  }
}

class _MonthlyPhotoReportContent extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;
  final bool showInlineRefresh;

  const _MonthlyPhotoReportContent({
    required this.delegate,
    required this.showAppBar,
    this.showInlineRefresh = false,
  });

  @override
  State<_MonthlyPhotoReportContent> createState() =>
      _MonthlyPhotoReportContentState();
}

class _MonthlyPhotoReportContentState
    extends State<_MonthlyPhotoReportContent> {
  late DateTime _selectedMonth;
  GroupMode _currentGroupMode = GroupMode.byDate;
  List<CapturedPhoto> _cachedPhotos = const [];
  bool _hasLoadedPhotos = false;
  bool _reloadQueued = false;

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
    if (_isManagerView) _currentGroupMode = GroupMode.byBranch;
    _loadPhotos();
    PhotoReportsRefresh.tick.addListener(_onReportsRefreshRequested);
  }

  void _onReportsRefreshRequested() {
    if (!mounted) return;
    _reloadQueued = false;
    _loadPhotos();
  }

  @override
  void dispose() {
    PhotoReportsRefresh.tick.removeListener(_onReportsRefreshRequested);
    super.dispose();
  }

  /// Supervisors, admins, HR and marketing see the whole company's photos
  /// (TAS-354). The field delegate sees only their own, so the «active
  /// delegates» count and the «by delegate» grouping are hidden for them
  /// [UI only: the data is already their own photos].
  bool get _isManagerView =>
      widget.delegate.role == UserRole.admin ||
      widget.delegate.position == DelegatePosition.supervisor ||
      widget.delegate.role == UserRole.organizationAdmin ||
      widget.delegate.role == UserRole.superAdmin ||
      widget.delegate.role == UserRole.marketing ||
      widget.delegate.role == UserRole.marketingPromotion ||
      widget.delegate.role == UserRole.branchesMarketingManager ||
      widget.delegate.role == UserRole.hr;

  bool get _canDeletePhoto {
    final r = widget.delegate.role;
    final pos = widget.delegate.position;
    return r != UserRole.delegate || pos == DelegatePosition.supervisor;
  }

  void _loadPhotos() {
    if (_isManagerView) {
      context.read<PhotoPermissionBloc>().add(
        LoadCompanyCapturedPhotosRequested(
          companyUID: widget.delegate.companyUID,
          organizationUID: photoListOrgScope(
            widget.delegate.role,
            widget.delegate.organizationUID,
          ),
          limit: widget.delegate.companyUID.isEmpty ? 200 : null,
        ),
      );
    } else {
      context.read<PhotoPermissionBloc>().add(
        LoadDelegateCapturedPhotosRequested(delegateUID: widget.delegate.uid),
      );
    }
  }

  /// Pull to refresh: reload and wait for the answer (at most 8 s).
  Future<void> _refresh() async {
    final bloc = context.read<PhotoPermissionBloc>();
    final done = bloc.stream.firstWhere(
      (s) => s is CapturedPhotosLoaded || s is PhotoPermissionError,
    );
    _loadPhotos();
    try {
      await done.timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  /// Delete through the kit dialog (text buttons, the confirm named after
  /// its result). Returns true when the delete was sent.
  Future<bool> _confirmDeletePhoto(
    BuildContext from,
    CapturedPhoto photo,
  ) async {
    final l10n = AppLocalizations.of(context)!;
    final bloc = context.read<PhotoPermissionBloc>();
    final confirmed = await showTashilDialog<bool>(
      context: from,
      builder: (c) => AlertDialog(
        key: const Key('photo_delete_dialog'),
        icon: const Icon(Symbols.delete_forever_rounded),
        title: Text(l10n.confirmDeletePhoto),
        content: Text(
          '${l10n.deletePhotoFromConfirm(photo.delegateName, BranchDisplayCache.instance.displayName(photo.branchName))}\n\n'
          '${l10n.photoDeletePermanentNote}',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: Text(l10n.cancel),
          ),
          TextButton(
            key: const Key('photo_delete_confirm'),
            onPressed: () => Navigator.pop(c, true),
            child: Text(l10n.deletePermanently),
          ),
        ],
      ),
    );
    if (confirmed != true || !mounted) return false;
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
    return true;
  }

  bool get _isCurrentMonth {
    final now = _now;
    return _selectedMonth.year == now.year && _selectedMonth.month == now.month;
  }

  void _selectMonth(DateTime month) =>
      setState(() => _selectedMonth = DateTime(month.year, month.month));

  void _previousMonth() =>
      _selectMonth(DateTime(_selectedMonth.year, _selectedMonth.month - 1));

  void _nextMonth() {
    if (_isCurrentMonth) return;
    _selectMonth(DateTime(_selectedMonth.year, _selectedMonth.month + 1));
  }

  String _monthName(DateTime date) => DateFormat.yMMMM(
    Localizations.localeOf(context).languageCode,
  ).format(date);

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    return Scaffold(
      appBar: widget.showAppBar
          ? AppBar(
              title: Text(l10n.photoReportsTitle),
              actions: [
                IconButton(
                  icon: const Icon(Symbols.refresh_rounded),
                  tooltip: l10n.refreshPhotos,
                  onPressed: _loadPhotos,
                ),
              ],
            )
          : null,
      backgroundColor: Theme.of(context).colorScheme.surfaceContainerLowest,
      body: _withInlineRefresh(
        BlocConsumer<PhotoPermissionBloc, PhotoPermissionState>(
          listener: (context, state) {
            if (state is CapturedPhotosLoaded) {
              setState(() {
                _cachedPhotos = state.photos;
                _hasLoadedPhotos = true;
                _reloadQueued = false;
              });
            } else if (state is PhotoBatchUploadSuccess) {
              _loadPhotos();
            } else if (state is PhotoPermissionActionSuccess) {
              showTashilSnackBar(context, state.message);
              _loadPhotos();
            } else if (state is PhotoPermissionError) {
              if (_hasLoadedPhotos) showTashilSnackBar(context, state.message);
            }
          },
          builder: (context, state) {
            if (state is PhotoPermissionError && !_hasLoadedPhotos) {
              return Center(
                child: EmptyState(
                  key: const Key('photo_report_error'),
                  icon: Symbols.error_outline_rounded,
                  title: l10n.photoReportsLoadFailed,
                  message: state.message,
                  action: FilledButton.tonalIcon(
                    onPressed: _loadPhotos,
                    icon: const Icon(Symbols.refresh_rounded),
                    label: Text(l10n.retry),
                  ),
                ),
              );
            }

            // After an upload the shared bloc may move to
            // OngoingPermissionsLoaded; keep the last list and reload
            // (M31 f7dbcf37).
            final allPhotos = state is CapturedPhotosLoaded
                ? state.photos
                : _cachedPhotos;
            if (state is OngoingPermissionsLoaded && !_reloadQueued) {
              _reloadQueued = true;
              WidgetsBinding.instance.addPostFrameCallback((_) {
                if (mounted) _loadPhotos();
              });
            }
            final loading = !_hasLoadedPhotos && state is! CapturedPhotosLoaded;
            return _buildReport(allPhotos, loading: loading);
          },
        ),
      ),
    );
  }

  Widget _buildReport(List<CapturedPhoto> allPhotos, {required bool loading}) {
    final l10n = AppLocalizations.of(context)!;
    final photos = allPhotos
        .where(
          (p) =>
              p.capturedAt.year == _selectedMonth.year &&
              p.capturedAt.month == _selectedMonth.month,
        )
        .toList();
    if (photos.isNotEmpty) {
      PhotoCacheManager.precachePhotos(photos.map((p) => p.photoUrl));
    }

    return PullToRefresh(
      onRefresh: _refresh,
      child: CustomScrollView(
        key: const Key('photo_report_scroll'),
        physics: const AlwaysScrollableScrollPhysics(),
        slivers: [
          const SliverToBoxAdapter(child: SyncStatusBanner()),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              TashilSpacing.page,
              TashilSpacing.md,
              TashilSpacing.page,
              TashilSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(
              child: _buildMonthCard(allPhotos, photos, loading: loading),
            ),
          ),
          SliverPadding(
            padding: const EdgeInsetsDirectional.fromSTEB(
              TashilSpacing.page,
              TashilSpacing.xs,
              TashilSpacing.page,
              TashilSpacing.sm,
            ),
            sliver: SliverToBoxAdapter(child: _buildGroupButtons()),
          ),
          if (loading)
            _photoGridSkeleton()
          else if (photos.isEmpty)
            SliverFillRemaining(
              hasScrollBody: false,
              child: Center(
                child: EmptyState(
                  key: const Key('photo_report_empty'),
                  icon: Symbols.photo_library_rounded,
                  title: l10n.noPhotosInMonth(_monthName(_selectedMonth)),
                  message: l10n.useArrowsForMonths,
                  action: _isManagerView
                      ? null
                      : FilledButton.tonalIcon(
                          key: const Key('photo_report_capture'),
                          onPressed: () => context.push(
                            '/photo-permissions/delegate',
                            extra: widget.delegate,
                          ),
                          icon: const Icon(Symbols.photo_camera_rounded),
                          label: Text(l10n.photosCaptureAction),
                        ),
                ),
              ),
            )
          else
            ..._buildGroups(photos),
          const SliverToBoxAdapter(child: SizedBox(height: TashilSpacing.xxl)),
        ],
      ),
    );
  }

  /// The month card (same layout as the attendance month card): arrows, the
  /// month (opens a menu of months with photos), «الشهر الحالي», the
  /// numbers and the archive note.
  Widget _buildMonthCard(
    List<CapturedPhoto> allPhotos,
    List<CapturedPhoto> photos, {
    required bool loading,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;

    final monthCounts = <DateTime, int>{};
    for (final p in allPhotos) {
      final k = DateTime(p.capturedAt.year, p.capturedAt.month);
      monthCounts[k] = (monthCounts[k] ?? 0) + 1;
    }
    monthCounts.putIfAbsent(DateTime(_now.year, _now.month), () => 0);
    final months = monthCounts.keys.toList()..sort((a, b) => b.compareTo(a));

    Widget stat(IconData icon, int value, String label) => Expanded(
      child: Container(
        padding: const EdgeInsetsDirectional.symmetric(
          vertical: TashilSpacing.md,
          horizontal: TashilSpacing.sm,
        ),
        decoration: BoxDecoration(
          color: cs.surface,
          borderRadius: BorderRadius.circular(TashilRadius.medium),
        ),
        child: Column(
          children: [
            Icon(icon, size: 24, color: cs.onSurfaceVariant),
            const SizedBox(height: TashilSpacing.xs),
            SkeletonSwitcher(
              loading: loading,
              skeleton: const Padding(
                padding: EdgeInsets.symmetric(vertical: TashilSpacing.xs),
                child: Skeleton(width: 40, height: 24),
              ),
              child: Text(
                '$value',
                style: tt.headlineSmall?.copyWith(
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
            ),
            Text(
              label,
              style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
          ],
        ),
      ),
    );

    final branches = photos.map((p) => p.branchId).toSet().length;
    final delegates = photos
        .map((p) => p.delegateUID.isNotEmpty ? p.delegateUID : p.delegateName)
        .toSet()
        .length;

    return Card.filled(
      key: const Key('photo_month_card'),
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                // Symbols chevrons mirror in RTL by themselves.
                IconButton.filledTonal(
                  key: const Key('photo_month_previous'),
                  icon: const Icon(Symbols.chevron_left_rounded),
                  tooltip: l10n.previousMonth,
                  onPressed: _previousMonth,
                ),
                Expanded(
                  child: Column(
                    children: [
                      MenuAnchor(
                        builder: (context, controller, _) => TextButton.icon(
                          key: const Key('photo_month_menu'),
                          onPressed: () => controller.isOpen
                              ? controller.close()
                              : controller.open(),
                          icon: const Icon(Symbols.arrow_drop_down_rounded),
                          iconAlignment: IconAlignment.end,
                          label: Text(
                            _monthName(_selectedMonth),
                            style: tt.titleMedium?.copyWith(color: cs.primary),
                          ),
                        ),
                        menuChildren: [
                          for (final m in months)
                            MenuItemButton(
                              key: ValueKey(
                                'photo_month_${m.year}-${m.month.toString().padLeft(2, '0')}',
                              ),
                              leadingIcon: Icon(
                                m.year == _selectedMonth.year &&
                                        m.month == _selectedMonth.month
                                    ? Symbols.check_rounded
                                    : Symbols.calendar_month_rounded,
                              ),
                              trailingIcon: Text(
                                '${monthCounts[m] ?? 0}',
                                style: tt.labelLarge?.copyWith(
                                  color: cs.onSurfaceVariant,
                                ),
                              ),
                              onPressed: () => _selectMonth(m),
                              child: Text(_monthName(m)),
                            ),
                        ],
                      ),
                      if (!_isCurrentMonth)
                        TextButton.icon(
                          key: const Key('photo_month_current'),
                          onPressed: () => _selectMonth(_now),
                          icon: const Icon(Symbols.restore_rounded),
                          label: Text(l10n.currentMonth),
                        ),
                    ],
                  ),
                ),
                IconButton.filledTonal(
                  key: const Key('photo_month_next'),
                  icon: const Icon(Symbols.chevron_right_rounded),
                  tooltip: l10n.nextMonth,
                  onPressed: _isCurrentMonth ? null : _nextMonth,
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),
            Row(
              children: [
                stat(
                  Symbols.photo_library_rounded,
                  photos.length,
                  l10n.totalPhotos,
                ),
                const SizedBox(width: TashilSpacing.sm),
                stat(
                  Symbols.storefront_rounded,
                  branches,
                  l10n.branchesVisited,
                ),
                if (_isManagerView) ...[
                  const SizedBox(width: TashilSpacing.sm),
                  stat(Symbols.group_rounded, delegates, l10n.activeDelegates),
                ],
              ],
            ),
            const SizedBox(height: TashilSpacing.sm),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 16,
                  color: cs.onSurfaceVariant,
                ),
                const SizedBox(width: TashilSpacing.xs),
                Expanded(
                  child: Text(
                    l10n.photosArchiveNote,
                    style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// TAS-354 (C-06): grouping is a connected ButtonGroup. «By delegate»
  /// only for the manager view.
  Widget _buildGroupButtons() {
    final l10n = AppLocalizations.of(context)!;
    return ButtonGroup<GroupMode>(
      key: const Key('photo_group_mode'),
      variant: ButtonGroupVariant.connected,
      expand: true,
      selected: {
        !_isManagerView && _currentGroupMode == GroupMode.byDelegate
            ? GroupMode.byDate
            : _currentGroupMode,
      },
      onSelectionChanged: (v) => setState(() => _currentGroupMode = v.first),
      items: [
        ButtonGroupItem(
          value: GroupMode.byDate,
          label: l10n.byDate,
          icon: Symbols.calendar_month_rounded,
        ),
        ButtonGroupItem(
          value: GroupMode.byBranch,
          label: l10n.byBranch,
          icon: Symbols.store_rounded,
        ),
        if (_isManagerView)
          ButtonGroupItem(
            value: GroupMode.byDelegate,
            label: l10n.byDelegate,
            icon: Symbols.person_rounded,
          ),
      ],
    );
  }

  /// Each group: a section header (title + count) and a 3-column grid.
  List<Widget> _buildGroups(List<CapturedPhoto> photos) {
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).languageCode;
    final grouped = <String, List<CapturedPhoto>>{};
    final IconData icon;
    switch (_currentGroupMode) {
      case GroupMode.byDate:
        icon = Symbols.calendar_today_rounded;
        for (final p in photos) {
          grouped
              .putIfAbsent(
                DateFormat('yyyy-MM-dd').format(p.capturedAt),
                () => [],
              )
              .add(p);
        }
      case GroupMode.byBranch:
        icon = Symbols.storefront_rounded;
        for (final p in photos) {
          grouped
              .putIfAbsent(
                BranchDisplayCache.instance.displayName(p.branchName),
                () => [],
              )
              .add(p);
        }
      case GroupMode.byDelegate:
        icon = Symbols.person_rounded;
        for (final p in photos) {
          final name = p.delegateName.trim().isNotEmpty
              ? p.delegateName.trim()
              : l10n.unknownDelegate;
          grouped.putIfAbsent(name, () => []).add(p);
        }
    }
    final keys = grouped.keys.toList()
      ..sort(
        (a, b) => _currentGroupMode == GroupMode.byDate
            ? b.compareTo(a)
            : a.compareTo(b),
      );

    return [
      for (final k in keys) ...[
        SliverPadding(
          padding: const EdgeInsetsDirectional.fromSTEB(
            TashilSpacing.page,
            TashilSpacing.lg,
            TashilSpacing.page,
            TashilSpacing.sm,
          ),
          sliver: SliverToBoxAdapter(
            child: _sectionHeader(
              icon: icon,
              title: _currentGroupMode == GroupMode.byDate
                  ? DateFormat('EEEE، d MMMM', locale).format(DateTime.parse(k))
                  : k,
              count: grouped[k]!.length,
            ),
          ),
        ),
        SliverPadding(
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: TashilSpacing.page,
          ),
          sliver: SliverGrid.count(
            crossAxisCount: 3,
            mainAxisSpacing: TashilSpacing.sm,
            crossAxisSpacing: TashilSpacing.sm,
            children: [for (final p in grouped[k]!) _photoTile(p)],
          ),
        ),
      ],
    ];
  }

  Widget _sectionHeader({
    required IconData icon,
    required String title,
    required int count,
  }) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    return Row(
      children: [
        Icon(icon, size: 20, color: cs.primary),
        const SizedBox(width: TashilSpacing.sm),
        Expanded(
          child: Text(
            title,
            style: tt.titleSmall,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ),
        Text(
          AppLocalizations.of(context)!.photosCount(count),
          style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
        ),
      ],
    );
  }

  /// One photo in the grid. A photo still on the phone carries a small
  /// badge; uploaded ones carry nothing. Opens with a container transform.
  Widget _photoTile(CapturedPhoto photo) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final pending = photo.uid.startsWith('pending_');
    final shape = RoundedRectangleBorder(
      borderRadius: BorderRadius.circular(TashilRadius.medium),
    );
    return OpenContainer<bool>(
      key: ValueKey('photo_tile_${photo.uid}'),
      closedElevation: 0,
      openElevation: 0,
      closedShape: shape,
      closedColor: cs.surfaceContainerHighest,
      openColor: cs.surface,
      middleColor: cs.surface,
      transitionDuration: MediaQuery.maybeDisableAnimationsOf(context) == true
          ? Duration.zero
          : const Duration(milliseconds: 400),
      closedBuilder: (context, open) => Semantics(
        button: true,
        label:
            '${BranchDisplayCache.instance.displayName(photo.branchName)} ${DateFormat('h:mm a', Localizations.localeOf(context).languageCode).format(photo.capturedAt)}',
        child: InkWell(
          onTap: open,
          child: Stack(
            fit: StackFit.expand,
            children: [
              AppPhotoImage(
                photoUrl: photo.photoUrl,
                isThumbnail: true,
                fit: BoxFit.cover,
              ),
              if (pending)
                PositionedDirectional(
                  top: TashilSpacing.xs,
                  end: TashilSpacing.xs,
                  child: Tooltip(
                    message: l10n.pendingOnPhone,
                    child: Container(
                      key: Key('photo_pending_${photo.uid}'),
                      padding: const EdgeInsets.all(TashilSpacing.xs),
                      decoration: BoxDecoration(
                        color: cs.tertiaryContainer,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.cloud_off_rounded,
                        size: 16,
                        color: cs.onTertiaryContainer,
                      ),
                    ),
                  ),
                ),
            ],
          ),
        ),
      ),
      openBuilder: (context, close) => _PhotoDetailsPage(
        photo: photo,
        companyFallback: widget.delegate.companyName,
        onDelete: _canDeletePhoto
            ? () async {
                final sent = await _confirmDeletePhoto(context, photo);
                if (sent) close(returnValue: true);
              }
            : null,
      ),
    );
  }

  Widget _photoGridSkeleton() => SliverPadding(
    key: const Key('photo_report_skeleton'),
    padding: const EdgeInsetsDirectional.fromSTEB(
      TashilSpacing.page,
      TashilSpacing.lg,
      TashilSpacing.page,
      0,
    ),
    sliver: SliverGrid.count(
      crossAxisCount: 3,
      mainAxisSpacing: TashilSpacing.sm,
      crossAxisSpacing: TashilSpacing.sm,
      children: [
        for (var i = 0; i < 9; i++)
          const Skeleton(radius: TashilRadius.medium, height: double.infinity),
      ],
    ),
  );

  /// Adds the opt-in refresh button above [body] (HR web shell).
  Widget _withInlineRefresh(Widget body) {
    if (!widget.showInlineRefresh) return body;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: TashilSpacing.page,
            end: TashilSpacing.sm,
            top: TashilSpacing.xs,
          ),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: IconButton(
              key: const ValueKey('monthly_report_inline_refresh'),
              icon: const Icon(Symbols.refresh_rounded),
              tooltip: AppLocalizations.of(context)!.refreshAction,
              onPressed: _loadPhotos,
            ),
          ),
        ),
        Expanded(child: body),
      ],
    );
  }
}

/// One photo, opened from the grid with a container transform: the photo
/// (pinch to zoom), save in the app bar (small indicator while saving), delete
/// in the ⋮ menu when allowed, and the details as label-over-value rows.
class _PhotoDetailsPage extends StatefulWidget {
  const _PhotoDetailsPage({
    required this.photo,
    required this.companyFallback,
    this.onDelete,
  });

  final CapturedPhoto photo;
  final String companyFallback;
  final Future<void> Function()? onDelete;

  @override
  State<_PhotoDetailsPage> createState() => _PhotoDetailsPageState();
}

class _PhotoDetailsPageState extends State<_PhotoDetailsPage> {
  bool _saving = false;

  Future<void> _save() async {
    final l10n = AppLocalizations.of(context)!;
    setState(() => _saving = true);
    String message;
    try {
      final ok = await PhotoCacheManager.savePhotoToGallery(
        context,
        photoUrl: widget.photo.photoUrl,
      );
      message = ok ? l10n.photoSavedToGallery : l10n.grantPhotosPermission;
    } catch (e) {
      message = l10n.photoSaveFailed(e);
    }
    if (!mounted) return;
    setState(() => _saving = false);
    showTashilSnackBar(context, message);
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final photo = widget.photo;
    final locale = Localizations.localeOf(context).languageCode;

    Widget detail(IconData icon, String label, String value) => Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        vertical: TashilSpacing.sm,
      ),
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: TashilSpacing.md),
          Expanded(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Text(
                  label,
                  style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
                ),
                Text(value, style: tt.bodyLarge),
              ],
            ),
          ),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.photoDetails),
        actions: [
          IconButton(
            key: const Key('photo_details_save'),
            tooltip: l10n.savePhoto,
            onPressed: _saving ? null : _save,
            icon: _saving
                ? const SizedBox.square(
                    dimension: 20,
                    child: CircularProgressIndicator(strokeWidth: 2.5),
                  )
                : const Icon(Symbols.download_rounded),
          ),
          if (widget.onDelete != null)
            MenuAnchor(
              builder: (context, controller, _) => IconButton(
                key: const Key('photo_details_menu'),
                icon: const Icon(Symbols.more_vert_rounded),
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  key: const Key('photo_details_delete'),
                  leadingIcon: const Icon(Symbols.delete_outline_rounded),
                  onPressed: widget.onDelete,
                  child: Text(l10n.deletePhoto),
                ),
              ],
            ),
        ],
      ),
      body: ListView(
        key: const Key('photo_details'),
        padding: const EdgeInsets.all(TashilSpacing.page),
        children: [
          ClipRRect(
            borderRadius: BorderRadius.circular(TashilRadius.large),
            child: ColoredBox(
              color: cs.surfaceContainerHighest,
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: InteractiveViewer(
                  minScale: 1,
                  maxScale: 4,
                  child: AppPhotoImage(
                    photoUrl: photo.photoUrl,
                    fit: BoxFit.contain,
                  ),
                ),
              ),
            ),
          ),
          const SizedBox(height: TashilSpacing.xs),
          Text(
            l10n.pinchToZoom,
            textAlign: TextAlign.center,
            style: tt.labelMedium?.copyWith(color: cs.onSurfaceVariant),
          ),
          const SizedBox(height: TashilSpacing.md),
          detail(
            Symbols.storefront_rounded,
            l10n.branchField,
            BranchDisplayCache.instance.displayName(photo.branchName),
          ),
          detail(
            Symbols.calendar_today_rounded,
            l10n.capturedAtField,
            DateFormat(
              'EEEE، d MMMM • h:mm a',
              locale,
            ).format(photo.capturedAt),
          ),
          detail(
            Symbols.person_rounded,
            l10n.delegateField,
            photo.delegateName,
          ),
          detail(
            Symbols.business_rounded,
            l10n.companyLabel,
            photo.companyName.isNotEmpty
                ? photo.companyName
                : widget.companyFallback,
          ),
          if (photo.comment.trim().isNotEmpty)
            detail(
              Symbols.comment_rounded,
              l10n.delegateCommentField,
              photo.comment.trim(),
            ),
        ],
      ),
    );
  }
}
