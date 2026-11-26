import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/design/widgets/date_time_fields.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/core/widgets/storage_resolved_image.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'dart:async';
import 'package:material_ui/material_ui.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_session_subscriptions.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/hr/domain/services/leave_notification_target.dart';
import 'package:delegate_app/features/hr/domain/services/payroll_day_rules.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

class DelegateLeavesAndRequestsScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;

  const DelegateLeavesAndRequestsScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  State<DelegateLeavesAndRequestsScreen> createState() =>
      _DelegateLeavesAndRequestsScreenState();
}

class _DelegateLeavesAndRequestsScreenState
    extends State<DelegateLeavesAndRequestsScreen>
    with ExtendedFabScroll {
  String _selectedStatusFilter = 'all'; // all, pending, approved, rejected
  bool _isAnnualLeaveEnabled = false;
  int _annualLeaveQuota = 21; // الرصيد السنوي (21 يوم)
  int _currentRemainingBalance = 21;
  final Set<String> _expandedDocIds = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;
  StreamSubscription<QuerySnapshot<Map<String, dynamic>>>? _leaveSub;
  List<QueryDocumentSnapshot<Map<String, dynamic>>> _leaveDocs = const [];
  bool _leaveLoaded = false;

  @override
  void initState() {
    super.initState();
    _isAnnualLeaveEnabled = widget.delegate.isAnnualLeaveEnabled;
    _annualLeaveQuota = widget.delegate.annualLeaveQuota > 0
        ? widget.delegate.annualLeaveQuota
        : 21;
    _listenToDelegateStatus();
    _listenToLeaveRequests();
  }

  String get _userSubKey => 'leaves.users.${widget.delegate.uid}';
  String get _leaveSubKey => 'leaves.leave_requests.${widget.delegate.uid}';

  void _listenToDelegateStatus() {
    _userSub?.cancel();
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.delegate.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            if (data.containsKey('isAnnualLeaveEnabled')) {
              _isAnnualLeaveEnabled = data['isAnnualLeaveEnabled'] == true;
            }
            if (data['annualLeaveQuota'] is num) {
              _annualLeaveQuota = (data['annualLeaveQuota'] as num).toInt();
            }
          });
        }
      }
    });
    FirestoreSessionSubscriptions.instance.register(_userSubKey, _userSub!);
  }

  void _listenToLeaveRequests() {
    _leaveSub?.cancel();
    _leaveSub = FirebaseFirestore.instance
        .collection('leave_requests')
        .where('companyUID', isEqualTo: widget.delegate.companyUID)
        .where('delegateUid', isEqualTo: widget.delegate.uid)
        .snapshots()
        .listen((snap) {
      if (!mounted) return;
      setState(() {
        _leaveDocs = snap.docs;
        _leaveLoaded = true;
      });
    });
    FirestoreSessionSubscriptions.instance.register(_leaveSubKey, _leaveSub!);
  }

  @override
  void dispose() {
    // Best-effort; AuthBloc also cancelAll() before signOut.
    _userSub?.cancel();
    _leaveSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  Text(
                    AppLocalizations.of(context)!.reqTitle,
                    style: Theme.of(context).textTheme.titleMedium,
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.delegate.companyName.isNotEmpty
                        ? widget.delegate.companyName
                        : widget.delegate.organizationName,
                    style: Theme.of(context).textTheme.labelSmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Symbols.refresh_rounded),
                  tooltip: AppLocalizations.of(context)!.refreshAction,
                  onPressed: () {
                    _listenToLeaveRequests();
                    _listenToDelegateStatus();
                  },
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      // TAS-353 (C-04): shrinks to an icon while the list scrolls down.
      floatingActionButton: M3ExtendedFab(
        key: const Key('newRequestFab'),
        onPressed: () => _showCreateRequestDialog(context),
        icon: Symbols.add_rounded,
        label: AppLocalizations.of(context)!.newRequest,
        extended: fabExtended,
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: onFabScroll,
        child: Builder(
        builder: (context) {
          if (!_leaveLoaded) {
            return const Center(child: M3DelayedLoading());
          }

          final docs = _leaveDocs;
          final allLeaves = docs.map((d) {
            final data = d.data();
            return {
              'docId': d.id,
              ...data,
            };
          }).toList();

          // Dual-layer client-side security filtering (Zero leakage)
          allLeaves.removeWhere(
            (item) =>
                (item['companyUID'] ?? '') != widget.delegate.companyUID ||
                (item['delegateUid'] ?? '') != widget.delegate.uid,
          );

          // ترتيب زمني تنازلي من الأحدث للأقدم
          allLeaves.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });

          // حساب الإحصائيات
          final pendingCount =
              allLeaves.where((r) => r['status'] == 'pending').length;
          final approvedCount =
              allLeaves.where((r) => r['status'] == 'approved').length;
          final rejectedCount =
              allLeaves.where((r) => r['status'] == 'rejected').length;

          // المقترح 5: احتساب رصيد الإجازات السنوي المستهلك والمتبقي للعام الحالي
          final currentYear = DateTime.now().year;
          // TAS-313: السنوية بس، بنفس تعريف مسير الرواتب.
          final usedLeaveDaysThisYear =
              PayrollDayRules.usedAnnualLeaveDaysInYear(allLeaves, currentYear);
          final remainingBalance = (_annualLeaveQuota - usedLeaveDaysThisYear)
              .clamp(0, _annualLeaveQuota);
          _currentRemainingBalance = remainingBalance;

          // فلترة القائمة حسب التبويب
          final filteredLeaves = allLeaves.where((req) {
            final status = (req['status'] ?? 'pending').toString();
            if (_selectedStatusFilter != 'all' &&
                status != _selectedStatusFilter) {
              return false;
            }
            return true;
          }).toList();

          return CustomScrollView(
            slivers: [
              // ── 1. Leave Balance & KPI Summary Cards ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // كارت رصيد الإجازات السنوي أو كارت فترة التجربة (الإجازات الأسبوعية فقط)
                      if (_isAnnualLeaveEnabled)
                        _buildAnnualBalanceCard(
                          usedDays: usedLeaveDaysThisYear,
                          remainingDays: remainingBalance,
                          totalQuota: _annualLeaveQuota,
                          colorScheme: colorScheme,
                        )
                      else
                        _buildProbationWeeklyLeavesCard(
                          colorScheme: colorScheme,
                          theme: theme,
                          isArabic: isArabic,
                        ),
                    ],
                  ),
                ),
              ),

              // ── 2. Filter Button Group (مجموعة أزرار متصلة بدون سكرول) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsetsDirectional.symmetric(
                    vertical: TashilSpacing.xs,
                  ),
                  child: _buildFilterButtonGroup(
                    totalCount: allLeaves.length,
                    pendingCount: pendingCount,
                    approvedCount: approvedCount,
                    rejectedCount: rejectedCount,
                    colorScheme: colorScheme,
                  ),
                ),
              ),

              // ── 3. List of Requests ──
              if (filteredLeaves.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Symbols.event_busy_rounded,
                          size: 56,
                          color: colorScheme.onSurfaceVariant,
                        ),
                        const SizedBox(height: TashilSpacing.lg),
                        Text(
                          _selectedStatusFilter == 'all'
                              ? AppLocalizations.of(context)!.reqEmptyAll
                              : AppLocalizations.of(context)!.reqEmptyFilter,
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          AppLocalizations.of(context)!.reqEmptyHint,
                          style: theme.textTheme.bodyMedium?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsetsDirectional.fromSTEB(
                    TashilSpacing.page,
                    TashilSpacing.xs,
                    TashilSpacing.page,
                    96,
                  ),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final req = filteredLeaves[index];
                        return _buildRequestCard(
                          req: req,
                          colorScheme: colorScheme,
                          theme: theme,
                          isArabic: isArabic,
                        );
                      },
                      childCount: filteredLeaves.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
      ),
    );
  }

  // ── Annual Balance Card ──
  // TAS-353: Card.filled, the card icon on primary + onPrimary, text from
  // the textTheme. A low balance is a warning label, never an error colour.
  Widget _buildAnnualBalanceCard({
    required int usedDays,
    required int remainingDays,
    required int totalQuota,
    required ColorScheme colorScheme,
  }) {
    final progress = (usedDays / totalQuota).clamp(0.0, 1.0);
    final tt = Theme.of(context).textTheme;
    final semantic = Theme.of(context).extension<TashilSemanticColors>();
    final low = remainingDays <= 3;
    final l10n = AppLocalizations.of(context)!;

    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _cardIcon(Symbols.account_balance_wallet_rounded, colorScheme),
                const SizedBox(width: TashilSpacing.md),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(l10n.annualLeaveBalance, style: tt.titleSmall),
                      Text(
                        l10n.forYear(DateTime.now().year),
                        style: tt.bodySmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                ),
                _label(
                  l10n.remainingDays(remainingDays),
                  low
                      ? (semantic?.warningContainer ??
                            colorScheme.tertiaryContainer)
                      : colorScheme.secondaryContainer,
                  low
                      ? (semantic?.onWarningContainer ??
                            colorScheme.onTertiaryContainer)
                      : colorScheme.onSecondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),
            LinearProgressIndicator(value: progress),
            const SizedBox(height: TashilSpacing.sm),
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Text(
                  l10n.usedDays(usedDays),
                  style: tt.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
                Text(
                  l10n.totalQuotaDays(totalQuota),
                  style: tt.labelMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// Icon on a card (TAS-384 rule): primary circle, onPrimary icon.
  Widget _cardIcon(IconData icon, ColorScheme colorScheme) => Container(
    padding: const EdgeInsets.all(TashilSpacing.sm),
    decoration: BoxDecoration(
      color: colorScheme.primary,
      shape: BoxShape.circle,
    ),
    child: Icon(icon, size: 20, color: colorScheme.onPrimary),
  );

  /// Compact read-only label: a container role with its on colour.
  Widget _label(String text, Color container, Color onContainer) => Container(
    padding: const EdgeInsetsDirectional.symmetric(
      horizontal: TashilSpacing.sm,
      vertical: TashilSpacing.xs / 2,
    ),
    decoration: BoxDecoration(
      color: container,
      borderRadius: BorderRadius.circular(TashilRadius.small),
    ),
    child: Text(
      text,
      style: Theme.of(context).textTheme.labelMedium?.copyWith(
        color: onContainer,
      ),
    ),
  );

  // ── Probation Weekly Leaves Card (نظام الإجازات الأسبوعية فقط) ──
  Widget _buildProbationWeeklyLeavesCard({
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final tt = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Card.filled(
      margin: EdgeInsets.zero,
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                _cardIcon(Symbols.event_repeat_rounded, colorScheme),
                const SizedBox(width: TashilSpacing.md),
                Expanded(
                  child: Text(l10n.weeklyOffPlan, style: tt.titleSmall),
                ),
                _label(
                  l10n.daysOffPerMonth,
                  colorScheme.secondaryContainer,
                  colorScheme.onSecondaryContainer,
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),
            Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 16,
                  color: colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: TashilSpacing.sm),
                Expanded(
                  child: Text(
                    l10n.weeklyPlanNote,
                    style: tt.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),
            Row(
              children: [
                Expanded(
                  child: _buildLeaveFeaturePill(
                    icon: Symbols.calendar_today_rounded,
                    label: l10n.weeklyDayOff,
                    sublabel: l10n.oneDayEvery7,
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: TashilSpacing.sm),
                Expanded(
                  child: _buildLeaveFeaturePill(
                    icon: Symbols.schedule_rounded,
                    label: l10n.hourlyPermission,
                    sublabel: l10n.availableLabel,
                    colorScheme: colorScheme,
                  ),
                ),
                const SizedBox(width: TashilSpacing.sm),
                Expanded(
                  child: _buildLeaveFeaturePill(
                    icon: Symbols.lock_clock_rounded,
                    label: l10n.annualBalance21,
                    sublabel: l10n.onceActivated,
                    colorScheme: colorScheme,
                    isMuted: true,
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }

  Widget _buildLeaveFeaturePill({
    required IconData icon,
    required String label,
    required String sublabel,
    required ColorScheme colorScheme,
    bool isMuted = false,
  }) {
    final tt = Theme.of(context).textTheme;
    final fg = isMuted ? colorScheme.onSurfaceVariant : colorScheme.onSurface;
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: TashilSpacing.sm,
        vertical: TashilSpacing.sm,
      ),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(TashilRadius.medium),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 18,
            color: isMuted ? colorScheme.onSurfaceVariant : colorScheme.primary,
          ),
          const SizedBox(height: TashilSpacing.xs),
          Text(
            label,
            style: tt.labelMedium?.copyWith(color: fg),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: tt.labelSmall?.copyWith(color: colorScheme.onSurfaceVariant),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  /// TAS-353 (C-06): the status filter is one row of single-select
  /// FilterChips «label · count» (the separate KPI row with the same
  /// numbers is gone).
  Widget _buildFilterButtonGroup({
    required int totalCount,
    required int pendingCount,
    required int approvedCount,
    required int rejectedCount,
    required ColorScheme colorScheme,
  }) {
    final l10n = AppLocalizations.of(context)!;
    final options = [
      ('all', l10n.filterAll, totalCount),
      ('pending', l10n.statusPendingReview, pendingCount),
      ('approved', l10n.statusApprovedPl, approvedCount),
      ('rejected', l10n.statusRejectedPl, rejectedCount),
    ];
    return SingleChildScrollView(
      scrollDirection: Axis.horizontal,
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: TashilSpacing.page,
      ),
      child: Row(
        children: [
          for (final (key, label, count) in options) ...[
            if (key != 'all') const SizedBox(width: TashilSpacing.sm),
            FilterChip(
              key: ValueKey('requests_filter_$key'),
              selected: _selectedStatusFilter == key,
              label: Text('$label · $count'),
              onSelected: (_) =>
                  setState(() => _selectedStatusFilter = key),
            ),
          ],
        ],
      ),
    );
  }

  Widget _buildRequestCard({
    required Map<String, dynamic> req,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final docId = (req['docId'] ?? '').toString();
    final isExpanded = _expandedDocIds.contains(docId);

    final status = (req['status'] ?? 'pending').toString();
    final type = (req['type'] ?? 'annual').toString();
    final isHourly = req['isHourly'] == true;
    final hoursCount = (req['hoursCount'] as num?)?.toDouble() ?? 0;
    final daysCount = (req['daysCount'] as num?)?.toInt() ?? 1;
    final reason = (req['reason'] ?? '').toString();
    final rejectReason = (req['rejectReason'] ?? '').toString();
    // TAS-42: new requests carry the Storage path; old ones only a URL.
    final attachmentUrl = StorageMediaRef.pick(
      path: req['attachmentPath'],
      url: req['attachmentUrl'],
    );
    final resolvedByName = (req['resolvedByName'] ?? '').toString();
    final resolvedAt = req['resolvedAt'] is Timestamp
        ? (req['resolvedAt'] as Timestamp).toDate()
        : null;

    // Formatting dates
    String periodStr = '';
    if (isHourly) {
      final start = req['startDate'] is Timestamp
          ? (req['startDate'] as Timestamp).toDate()
          : DateTime.now();
      final dateStr = DateFormat('yyyy/MM/dd').format(start);
      final fromTime = (req['fromTime'] ?? '').toString();
      final toTime = (req['toTime'] ?? '').toString();
      if (fromTime.isNotEmpty && toTime.isNotEmpty) {
        periodStr = '$dateStr • ($fromTime - $toTime)';
      } else {
        periodStr = AppLocalizations.of(context)!.dateWithHours(dateStr, hoursCount);
      }
    } else {
      final start = req['startDate'] is Timestamp
          ? (req['startDate'] as Timestamp).toDate()
          : null;
      final end = req['endDate'] is Timestamp
          ? (req['endDate'] as Timestamp).toDate()
          : null;
      if (start != null && end != null) {
        final fStart = DateFormat('yyyy/MM/dd').format(start);
        final fEnd = DateFormat('yyyy/MM/dd').format(end);
        periodStr = fStart == fEnd ? fStart : '$fStart ⬅️ $fEnd';
      }
    }

    // Type definition
    String typeLabel;
    IconData typeIcon;
    switch (type) {
      case 'sick':
        typeLabel = AppLocalizations.of(context)!.leaveSick;
        typeIcon = Symbols.medical_services_rounded;
        break;
      case 'emergency':
        typeLabel = AppLocalizations.of(context)!.leaveEmergency;
        typeIcon = Symbols.warning_amber_rounded;
        break;
      case 'delay':
        typeLabel = AppLocalizations.of(context)!.excuseLate;
        typeIcon = Symbols.timer_rounded;
        break;
      case 'early_leave':
        typeLabel = AppLocalizations.of(context)!.excuseEarlyLeave;
        typeIcon = Symbols.logout_rounded;
        break;
      case 'absence':
        typeLabel = AppLocalizations.of(context)!.excuseAbsence;
        typeIcon = Symbols.person_off_rounded;
        break;
      case 'unpaid':
        typeLabel = AppLocalizations.of(context)!.leaveUnpaid;
        typeIcon = Symbols.money_off_rounded;
        break;
      default:
        typeLabel = AppLocalizations.of(context)!.leaveAnnual;
        typeIcon = Symbols.beach_access_rounded;
        break;
    }

    // TAS-353: status is a compact label (container role + on colour);
    // rejected is the only error, pending is neutral, approved is success.
    final semantic = Theme.of(context).extension<TashilSemanticColors>();
    final l10n = AppLocalizations.of(context)!;
    final tt = theme.textTheme;
    final (Color statusBg, Color statusFg, String statusLabel) =
        switch (status) {
      'approved' => (
        semantic?.successContainer ?? colorScheme.primaryContainer,
        semantic?.onSuccessContainer ?? colorScheme.onPrimaryContainer,
        l10n.statusApproved,
      ),
      'rejected' => (
        colorScheme.errorContainer,
        colorScheme.onErrorContainer,
        l10n.statusRejected,
      ),
      _ => (
        colorScheme.surfaceContainerHighest,
        colorScheme.onSurfaceVariant,
        l10n.statusPending,
      ),
    };

    final durationText = isHourly
        ? l10n.hoursCount(hoursCount)
        : l10n.daysCount(daysCount);

    return Card.filled(
      key: ValueKey('request_card_$docId'),
      margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedDocIds.remove(docId);
            } else {
              _expandedDocIds.add(docId);
            }
          });
        },
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.md),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  _cardIcon(typeIcon, colorScheme),
                  const SizedBox(width: TashilSpacing.md),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          '$typeLabel · $durationText',
                          style: tt.titleSmall,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                        const SizedBox(height: TashilSpacing.xs / 2),
                        Text(
                          periodStr,
                          style: tt.bodySmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                          ),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ],
                    ),
                  ),
                  const SizedBox(width: TashilSpacing.sm),
                  _label(statusLabel, statusBg, statusFg),
                  AnimatedRotation(
                    turns: isExpanded ? 0.5 : 0.0,
                    duration: AppMotionDurations.short4,
                    child: Icon(
                      Symbols.expand_more_rounded,
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
              ),
              if (isExpanded) ...[
                const Divider(height: TashilSpacing.xl),
                if (reason.isNotEmpty)
                  Text(
                    l10n.reasonLabel(reason),
                    style: tt.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                if (status == 'rejected' && rejectReason.isNotEmpty) ...[
                  const SizedBox(height: TashilSpacing.sm),
                  Text(
                    l10n.rejectReasonLabel(rejectReason),
                    style: tt.bodyMedium?.copyWith(color: colorScheme.error),
                  ),
                ],
                if (status == 'approved' && resolvedByName.isNotEmpty) ...[
                  const SizedBox(height: TashilSpacing.sm),
                  Text(
                    resolvedAt != null
                        ? '${l10n.approvedBy(resolvedByName)} (${DateFormat('yyyy/MM/dd').format(resolvedAt)})'
                        : l10n.approvedBy(resolvedByName),
                    style: tt.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                ],
                if (attachmentUrl.isNotEmpty || status == 'pending') ...[
                  const SizedBox(height: TashilSpacing.sm),
                  Row(
                    children: [
                      if (attachmentUrl.isNotEmpty)
                        OutlinedButton.icon(
                          icon: const Icon(Symbols.attachment_rounded),
                          label: Text(l10n.previewAttachment),
                          onPressed: () =>
                              _viewAttachment(context, attachmentUrl),
                        ),
                      const Spacer(),
                      if (status == 'pending')
                        TextButton.icon(
                          icon: const Icon(Symbols.delete_outline_rounded),
                          label: Text(l10n.cancelRequest),
                          onPressed: () =>
                              _cancelPendingRequest(context, req['docId']),
                        ),
                    ],
                  ),
                ],
              ],
            ],
          ),
        ),
      ),
    );
  }

  // ── إلغاء الطلب المعلق ──
  Future<void> _cancelPendingRequest(BuildContext context, String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    final l10n = AppLocalizations.of(context)!;
    // TAS-353 (C-27): kit dialog, text buttons, confirm last.
    final confirm = await showTashilDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: Text(l10n.cancelRequest),
        content: Text(l10n.cancelRequestConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: Text(l10n.keepRequest),
          ),
          TextButton(
            onPressed: () => Navigator.pop(ctx, true),
            child: Text(l10n.yesCancel),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('leave_requests')
          .doc(docId)
          .delete();

      messenger.showSnackBar(
        SnackBar(content: Text(l10n.requestCancelled)),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text(l10n.cancelRequestFailed(e))),
      );
    }
  }

  // ── معاينة المرفق بدقة عالية ──
  void _viewAttachment(BuildContext context, String url) {
    showTashilDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.card)),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Padding(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  Text(
                    AppLocalizations.of(context)!.requestAttachment,
                    style: Theme.of(context).textTheme.titleMedium,
                  ),
                  IconButton(
                    tooltip: MaterialLocalizations.of(ctx).closeButtonTooltip,
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(HrRadius.card),
                bottomRight: Radius.circular(HrRadius.card),
              ),
              child: InteractiveViewer(
                maxScale: 4.0,
                child: StorageResolvedImage(
                  pathOrUrl: url,
                  builder: (_, resolved) => Image.network(
                    resolved,
                  fit: BoxFit.contain,
                  loadingBuilder: (_, child, progress) {
                    if (progress == null) return child;
                    return const SizedBox(
                      height: 240,
                      child: Center(child: CircularProgressIndicator()),
                    );
                  },
                  errorBuilder: (_, _, _) => SizedBox(
                    height: 160,
                    child: Center(
                      child: Text(AppLocalizations.of(context)!.attachmentLoadFailed),
                    ),
                  ),
                ),
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── تسجيل إجازة / عذر جديد ──
  // TAS-353 (C-27): a FormDialog (full screen on compact, basic dialog from
  // 600dp). ✕ is the only way out and asks before dropping edits; the save
  // action is named after its result. Fields are outlined: DateField (C-14)
  // and the inline ScrollTimePicker (C-15). The submit logic is unchanged.
  Future<void> _showCreateRequestDialog(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final messenger = ScaffoldMessenger.of(context);

    String selectedType = _isAnnualLeaveEnabled ? 'annual' : 'delay';
    final initialType = selectedType;
    final today = DateTime.now();
    DateTime startDate = DateTime(today.year, today.month, today.day);
    DateTime endDate = startDate;

    bool isHourly = !_isAnnualLeaveEnabled;
    const double hoursCount = 2.0;
    TimeOfDay fromTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay toTime = const TimeOfDay(hour: 11, minute: 0);

    final reasonCtrl = TextEditingController();
    XFile? pickedAttachment;
    bool isSubmitting = false;
    String? submittedLeaveId;
    bool touched = false;

    await showTashilDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final textTheme = theme.textTheme;
          final semantic = theme.extension<TashilSemanticColors>();
          final isLeaveType = selectedType == 'annual' ||
              selectedType == 'sick' ||
              selectedType == 'emergency' ||
              selectedType == 'unpaid';
          if (selectedType == 'delay' || selectedType == 'early_leave') {
            isHourly = true;
          }
          final calculatedDays = endDate.difference(startDate).inDays + 1;
          final dirty = touched ||
              selectedType != initialType ||
              reasonCtrl.text.trim().isNotEmpty ||
              pickedAttachment != null;

          void edit(VoidCallback change) => setDlgState(() {
                touched = true;
                change();
              });

          Future<void> submit() async {
            final reason = reasonCtrl.text.trim();
            if (reason.isEmpty) {
              showTashilSnackBar(context, l10n.enterLeaveReason);
              return;
            }
            if (!_isAnnualLeaveEnabled && selectedType == 'annual') {
              showTashilSnackBar(context, l10n.annualNotActive);
              return;
            }
            final String? fromTimeFormatted =
                isHourly ? fromTime.format(context) : null;
            final String? toTimeFormatted =
                isHourly ? toTime.format(context) : null;

            setDlgState(() => isSubmitting = true);
            try {
              String? attachmentPath;
              String? attachmentUrl;
              // Upload the attachment (skipped on retry once the leave exists).
              if (submittedLeaveId == null && pickedAttachment != null) {
                final bytes = await pickedAttachment!.readAsBytes();
                final fileName =
                    '${DateTime.now().millisecondsSinceEpoch}_${pickedAttachment!.name}';
                final storageRef = FirebaseStorage.instance.ref().child(
                      'leave_attachments/${widget.delegate.companyUID}/${widget.delegate.uid}/$fileName',
                    );
                final metadata = SettableMetadata(
                  contentType: 'image/jpeg',
                  customMetadata: {
                    'companyUID': widget.delegate.companyUID,
                    'delegateUid': widget.delegate.uid,
                  },
                );
                final uploadTask = await storageRef.putData(bytes, metadata);
                // TAS-42: store the path; the URL only for old app versions.
                attachmentPath = uploadTask.ref.fullPath;
                attachmentUrl = await LegacyStorageUrls.urlFor(uploadTask.ref);
              }

              if (submittedLeaveId == null) {
                final docRef = FirebaseFirestore.instance
                    .collection('leave_requests')
                    .doc();
                final int finalDays = isHourly
                    ? 0
                    : (endDate.difference(startDate).inDays + 1);
                await docRef.set({
                  'id': docRef.id,
                  'delegateUid': widget.delegate.uid,
                  'delegateName': widget.delegate.fullName,
                  'delegatePhone': widget.delegate.phoneNumber,
                  'companyUID': widget.delegate.companyUID,
                  'organizationUID': widget.delegate.organizationUID,
                  'type': selectedType,
                  'isHourly': isHourly,
                  'hoursCount': isHourly ? hoursCount : null,
                  'fromTime': fromTimeFormatted,
                  'toTime': toTimeFormatted,
                  'startDate': Timestamp.fromDate(startDate),
                  'endDate': Timestamp.fromDate(endDate),
                  'daysCount': finalDays,
                  'reason': reason,
                  'attachmentUrl': attachmentUrl,
                  'attachmentPath': ?attachmentPath,
                  'status': 'pending',
                  'createdAt': FieldValue.serverTimestamp(),
                  'resolvedAt': null,
                  'resolvedBy': null,
                  'resolvedByName': null,
                  'rejectReason': null,
                });
                submittedLeaveId = docRef.id;
              }

              // Notify the supervisor; a refused notification never fails
              // the request itself.
              String notifTitle;
              switch (selectedType) {
                case 'delay':
                  notifTitle = 'عذر تأخير جديد قيد المراجعة';
                  break;
                case 'sick':
                  notifTitle = 'طلب إجازة مرضية جديدة';
                  break;
                default:
                  notifTitle = 'طلب إجازة جديد قيد المراجعة';
                  break;
              }
              try {
                final notifUid = leaveNotificationDelegateUid(
                  supervisorUid: widget.delegate.supervisorUid,
                  companyUID: widget.delegate.companyUID,
                );
                if (notifUid != null) {
                  await FirebaseFirestore.instance
                      .collection('notifications')
                      .add({
                    'delegateUid': notifUid,
                    'companyUID': widget.delegate.companyUID,
                    'organizationUID': widget.delegate.organizationUID,
                    'title': notifTitle,
                    'body':
                        'قدم المندوب ${widget.delegate.fullName} طلباً جديداً يحتاج إلى مراجعتك واعتمادك.',
                    'type': 'leave_request_submitted',
                    'targetRole': 'supervisor',
                    'isRead': false,
                    'createdAt': FieldValue.serverTimestamp(),
                    'createdBy': widget.delegate.uid,
                    'senderName': widget.delegate.fullName,
                  });
                }
              } catch (_) {}

              if (ctx.mounted) Navigator.pop(ctx);
              if (messenger.mounted) {
                messenger.removeCurrentSnackBar();
                messenger.showSnackBar(
                  SnackBar(content: Text(l10n.requestSent)),
                );
              }
            } catch (e) {
              setDlgState(() => isSubmitting = false);
              if (context.mounted) {
                showTashilSnackBar(context, l10n.sendRequestFailed(e));
              }
            }
          }

          Widget sectionLabel(String text) => Padding(
                padding: const EdgeInsetsDirectional.only(
                  top: TashilSpacing.lg,
                  bottom: TashilSpacing.sm,
                ),
                child: Text(
                  text,
                  style: textTheme.titleSmall?.copyWith(
                    color: colorScheme.onSurface,
                  ),
                ),
              );

          Widget note(String text) => Container(
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: semantic?.warningContainer ??
                      colorScheme.tertiaryContainer,
                  borderRadius: BorderRadius.circular(TashilRadius.medium),
                ),
                child: Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Icon(
                      Symbols.info_rounded,
                      size: 18,
                      color: semantic?.onWarningContainer ??
                          colorScheme.onTertiaryContainer,
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                    Expanded(
                      child: Text(
                        text,
                        style: textTheme.bodySmall?.copyWith(
                          color: semantic?.onWarningContainer ??
                              colorScheme.onTertiaryContainer,
                        ),
                      ),
                    ),
                  ],
                ),
              );

          return FormDialog(
            title: l10n.newRequest,
            saveLabel: l10n.sendRequestAction,
            onSave: isSubmitting ? () {} : submit,
            saving: isSubmitting,
            dirty: dirty && !isSubmitting,
            child: Column(
              key: const Key('newRequestForm'),
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                if (!_isAnnualLeaveEnabled) note(l10n.weeklyPlanAvailableInfo),
                const SizedBox(height: TashilSpacing.sm),
                DropdownMenu<String>(
                  key: const Key('newRequestType'),
                  initialSelection: selectedType,
                  expandedInsets: EdgeInsets.zero,
                  requestFocusOnTap: false,
                  label: Text('${l10n.requestType} *'),
                  dropdownMenuEntries: [
                    DropdownMenuEntry(
                      value: 'annual',
                      enabled: _isAnnualLeaveEnabled,
                      label: _isAnnualLeaveEnabled
                          ? l10n.annualLeaveFromBalance
                          : l10n.annualLeaveUnavailable,
                    ),
                    DropdownMenuEntry(value: 'sick', label: l10n.leaveSick),
                    DropdownMenuEntry(
                      value: 'emergency',
                      label: l10n.leaveEmergency,
                    ),
                    DropdownMenuEntry(value: 'unpaid', label: l10n.leaveUnpaid),
                    DropdownMenuEntry(
                      value: 'delay',
                      label: l10n.lateArrivalHourly,
                    ),
                    DropdownMenuEntry(
                      value: 'early_leave',
                      label: l10n.earlyLeaveHourly,
                    ),
                    DropdownMenuEntry(
                      value: 'absence',
                      label: l10n.excusedAbsenceFullDay,
                    ),
                  ],
                  onSelected: (val) {
                    if (val == null) return;
                    edit(() {
                      selectedType = val;
                      isHourly = (val == 'delay' || val == 'early_leave');
                    });
                  },
                ),
                if (isHourly) ...[
                  const SizedBox(height: TashilSpacing.lg),
                  DateField(
                    key: const Key('newRequestDate'),
                    label: '${l10n.dateField} *',
                    value: startDate,
                    firstDate: today.subtract(const Duration(days: 30)),
                    lastDate: today.add(const Duration(days: 60)),
                    onChanged: (d) {
                      if (d == null) return;
                      edit(() {
                        startDate = d;
                        endDate = d;
                      });
                    },
                  ),
                  sectionLabel(l10n.fromField),
                  ScrollTimePicker(
                    key: const Key('newRequestFromTime'),
                    value: fromTime,
                    onChanged: (t) => edit(() => fromTime = t),
                  ),
                  sectionLabel(l10n.toField),
                  ScrollTimePicker(
                    key: const Key('newRequestToTime'),
                    value: toTime,
                    onChanged: (t) => edit(() => toTime = t),
                  ),
                ] else ...[
                  const SizedBox(height: TashilSpacing.lg),
                  DateField(
                    key: const Key('newRequestStart'),
                    label: '${l10n.fromField} *',
                    value: startDate,
                    firstDate: DateTime(2024),
                    lastDate: DateTime(2030),
                    onChanged: (d) {
                      if (d == null) return;
                      edit(() {
                        startDate = d;
                        if (endDate.isBefore(startDate)) endDate = startDate;
                      });
                    },
                  ),
                  const SizedBox(height: TashilSpacing.lg),
                  DateField(
                    key: const Key('newRequestEnd'),
                    label: '${l10n.toField} *',
                    value: endDate,
                    firstDate: startDate,
                    lastDate: DateTime(2030),
                    onChanged: (d) {
                      if (d == null) return;
                      edit(() => endDate = d);
                    },
                  ),
                  const SizedBox(height: TashilSpacing.sm),
                  Text(
                    l10n.durationLabel(l10n.daysCount(calculatedDays)),
                    style: textTheme.bodyMedium?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
                  ),
                  if (isLeaveType &&
                      calculatedDays > _currentRemainingBalance) ...[
                    const SizedBox(height: TashilSpacing.sm),
                    note(
                      l10n.daysExceedBalance(
                        calculatedDays,
                        _currentRemainingBalance,
                      ),
                    ),
                  ],
                ],
                const SizedBox(height: TashilSpacing.lg),
                TextField(
                  key: const Key('newRequestReason'),
                  controller: reasonCtrl,
                  maxLines: 3,
                  minLines: 2,
                  onChanged: (_) => setDlgState(() {}),
                  decoration: InputDecoration(
                    labelText: '${l10n.reasonField} *',
                    hintText: l10n.reasonHint,
                    border: const OutlineInputBorder(),
                  ),
                ),
                sectionLabel(l10n.attachmentOptional),
                if (pickedAttachment != null)
                  InputChip(
                    avatar: const Icon(Symbols.image_rounded),
                    label: Text(
                      pickedAttachment!.name,
                      overflow: TextOverflow.ellipsis,
                    ),
                    onDeleted: () => edit(() => pickedAttachment = null),
                  )
                else
                  Row(
                    children: [
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final img = await ImagePicker().pickImage(
                              source: ImageSource.camera,
                              imageQuality: 80,
                            );
                            if (img != null) {
                              edit(() => pickedAttachment = img);
                            }
                          },
                          icon: const Icon(Symbols.photo_camera_rounded),
                          label: Text(l10n.cameraLabel),
                        ),
                      ),
                      const SizedBox(width: TashilSpacing.sm),
                      Expanded(
                        child: OutlinedButton.icon(
                          onPressed: () async {
                            final img = await ImagePicker().pickImage(
                              source: ImageSource.gallery,
                              imageQuality: 80,
                            );
                            if (img != null) {
                              edit(() => pickedAttachment = img);
                            }
                          },
                          icon: const Icon(Symbols.photo_library_rounded),
                          label: Text(l10n.galleryLabel),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
          );
        },
      ),
    );
  }
}
