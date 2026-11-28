import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'package:animations/animations.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
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
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/hr/domain/leave_overlap.dart';
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

/// Live count of the delegate's pending requests (the «طلباتي» tab badge).
Stream<int> pendingRequestsCount(Delegate d) => FirebaseFirestore.instance
    .collection('leave_requests')
    .where('companyUID', isEqualTo: d.companyUID)
    .where('delegateUid', isEqualTo: d.uid)
    .where('status', isEqualTo: 'pending')
    .snapshots()
    .map((s) => s.size);

class _DelegateLeavesAndRequestsScreenState
    extends State<DelegateLeavesAndRequestsScreen>
    with ExtendedFabScroll {
  String _selectedStatusFilter = 'all'; // all, pending, approved, rejected
  bool _isAnnualLeaveEnabled = false;
  int _annualLeaveQuota = 21; // الرصيد السنوي (21 يوم)
  int _currentRemainingBalance = 21;
  bool _planExpanded = false;
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

  /// Pull to refresh (C-29): re-listen and wait for the first snapshot.
  Future<void> _refresh() async {
    final done = Completer<void>();
    _listenToLeaveRequests(
      onFirst: () {
        if (!done.isCompleted) done.complete();
      },
    );
    _listenToDelegateStatus();
    await done.future.timeout(const Duration(seconds: 8), onTimeout: () {});
  }

  void _listenToLeaveRequests({VoidCallback? onFirst}) {
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
          onFirst?.call();
          onFirst = null;
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
                    style: Theme.of(context).textTheme.labelSmall
                        ?.copyWith(color: colorScheme.onSurfaceVariant),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
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
              return const Center(child: DelayedLoadingIndicator());
            }

            final docs = _leaveDocs;
            final allLeaves = docs.map((d) {
              final data = d.data();
              return {'docId': d.id, ...data};
            }).toList();

            // Dual-layer client-side security filtering (Zero leakage)
            allLeaves.removeWhere(
              (item) =>
                  (item['companyUID'] ?? '') != widget.delegate.companyUID ||
                  (item['delegateUid'] ?? '') != widget.delegate.uid,
            );

            // Pending first (what still needs an answer), then the newest
            // period first (user review 27 Nov 2026).
            int rank(Map<String, dynamic> r) =>
                r['status'] == 'pending' ? 0 : 1;
            Timestamp? when(Map<String, dynamic> r) {
              final v = r['startDate'] ?? r['createdAt'];
              return v is Timestamp ? v : null;
            }

            allLeaves.sort((a, b) {
              final byStatus = rank(a).compareTo(rank(b));
              if (byStatus != 0) return byStatus;
              final aTime = when(a);
              final bTime = when(b);
              if (aTime != null && bTime != null) return bTime.compareTo(aTime);
              return 0;
            });

            // حساب الإحصائيات
            final pendingCount = allLeaves
                .where((r) => r['status'] == 'pending')
                .length;
            final approvedCount = allLeaves
                .where((r) => r['status'] == 'approved')
                .length;
            final rejectedCount = allLeaves
                .where((r) => r['status'] == 'rejected')
                .length;

            // المقترح 5: احتساب رصيد الإجازات السنوي المستهلك والمتبقي للعام الحالي
            final currentYear = DateTime.now().year;
            // TAS-313: السنوية بس، بنفس تعريف مسير الرواتب.
            final usedLeaveDaysThisYear =
                PayrollDayRules.usedAnnualLeaveDaysInYear(
                  allLeaves,
                  currentYear,
                );
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

            return M3Refresh(
              onRefresh: _refresh,
              child: CustomScrollView(
                physics: const AlwaysScrollableScrollPhysics(),
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
                                  : AppLocalizations.of(context)!
                                        .reqEmptyFilter,
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
                            const SizedBox(height: TashilSpacing.lg),
                            FilledButton.tonalIcon(
                              key: const Key('requests_empty_new'),
                              onPressed: () =>
                                  _showCreateRequestDialog(context),
                              icon: const Icon(Symbols.add_rounded),
                              label: Text(
                                AppLocalizations.of(context)!.newRequest,
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
                        delegate: SliverChildBuilderDelegate((context, index) {
                          final req = filteredLeaves[index];
                          return _buildRequestCard(
                            req: req,
                            colorScheme: colorScheme,
                            theme: theme,
                            isArabic: isArabic,
                          );
                        }, childCount: filteredLeaves.length),
                      ),
                    ),
                ],
              ),
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
      style: Theme.of(context).textTheme.labelMedium
          ?.copyWith(color: onContainer),
    ),
  );

  // ── Probation Weekly Leaves Card (نظام الإجازات الأسبوعية فقط) ──
  /// Weekly-off plan (probation): compact by default, the details open on
  /// tap (user review 27 Nov 2026). Nothing here is counted yet, so it has
  /// no progress bar; the annual card carries one.
  Widget _buildProbationWeeklyLeavesCard({
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final tt = theme.textTheme;
    final l10n = AppLocalizations.of(context)!;
    return Card.filled(
      key: const Key('requests_plan_card'),
      margin: EdgeInsets.zero,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () => setState(() => _planExpanded = !_planExpanded),
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.lg),
          child: AnimatedSize(
            duration: MediaQuery.maybeDisableAnimationsOf(context) == true
                ? Duration.zero
                : const Duration(milliseconds: 250),
            alignment: AlignmentDirectional.topStart,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  children: [
                    _cardIcon(Symbols.event_repeat_rounded, colorScheme),
                    const SizedBox(width: TashilSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(l10n.weeklyOffPlan, style: tt.titleMedium),
                          Text(
                            l10n.daysOffPerMonth,
                            style: tt.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    AnimatedRotation(
                      turns: _planExpanded ? 0.5 : 0,
                      duration: const Duration(milliseconds: 250),
                      child: Icon(
                        Symbols.expand_more_rounded,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
                if (_planExpanded) ...[
                  const SizedBox(height: TashilSpacing.md),
                  Text(
                    l10n.weeklyPlanNote,
                    style: tt.bodySmall?.copyWith(
                      color: colorScheme.onSurfaceVariant,
                    ),
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
              ],
            ),
          ),
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

  /// Status filter: 2-5 exclusive options, so a connected ButtonGroup
  /// (C-05) across the width, each with its count (user review 27 Nov).
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
      ('pending', l10n.reqFilterPending, pendingCount),
      ('approved', l10n.statusApproved, approvedCount),
      ('rejected', l10n.statusRejected, rejectedCount),
    ];
    return Padding(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: TashilSpacing.page,
      ),
      child: ButtonGroup<String>(
        key: const Key('requests_filter'),
        variant: ButtonGroupVariant.connected,
        expand: true,
        selected: {_selectedStatusFilter},
        onSelectionChanged: (v) =>
            setState(() => _selectedStatusFilter = v.first),
        items: [
          for (final (key, label, count) in options)
            ButtonGroupItem(
              key: ValueKey('requests_filter_$key'),
              value: key,
              label: '$label ${Bidi.ltr('$count')}',
            ),
        ],
      ),
    );
  }

  /// Everything the card and the details page show about one request.
  _RequestView _viewOf(Map<String, dynamic> req) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final semantic = Theme.of(context).extension<TashilSemanticColors>();
    final locale = Localizations.localeOf(context).languageCode;
    DateTime? dt(Object? v) => v is Timestamp ? v.toDate() : null;

    final status = (req['status'] ?? 'pending').toString();
    final type = (req['type'] ?? 'annual').toString();
    final isHourly = req['isHourly'] == true;
    final hours = (req['hoursCount'] as num?)?.toDouble() ?? 0;
    final days = (req['daysCount'] as num?)?.toInt() ?? 1;
    final start = dt(req['startDate']);
    final end = dt(req['endDate']) ?? start;

    final (String typeLabel, IconData typeIcon) = switch (type) {
      'sick' => (l10n.leaveSick, Symbols.medical_services_rounded),
      'emergency' => (l10n.leaveEmergency, Symbols.emergency_home_rounded),
      'delay' => (l10n.excuseLate, Symbols.timer_rounded),
      'early_leave' => (l10n.excuseEarlyLeave, Symbols.logout_rounded),
      'absence' => (l10n.excuseAbsence, Symbols.person_off_rounded),
      'unpaid' => (l10n.leaveUnpaid, Symbols.money_off_rounded),
      _ => (l10n.leaveAnnual, Symbols.beach_access_rounded),
    };

    // «20 – 21 نوفمبر», no arrow emoji between the dates.
    String period = '';
    if (start != null) {
      final sameDay =
          end == null ||
          (end.year == start.year &&
              end.month == start.month &&
              end.day == start.day);
      if (sameDay) {
        period = DateFormat('EEEE، d MMMM', locale).format(start);
      } else if (end.month == start.month && end.year == start.year) {
        period = '${start.day} – ${DateFormat('d MMMM', locale).format(end)}';
      } else {
        period =
            '${DateFormat('d MMM', locale).format(start)} – ${DateFormat('d MMM', locale).format(end)}';
      }
    }

    // «ساعة / ساعتين / 3 ساعات», never «1.0 ساعة» (user review 27 Nov).
    // One and two read as the word alone; more is the number + plural.
    final whole = hours == hours.roundToDouble();
    final n = isHourly ? hours.round() : days;
    final h = whole ? '${hours.toInt()}' : hours.toStringAsFixed(1);
    final word = (!isHourly || whole) && (n == 1 || n == 2);
    final amount = word
        ? (isHourly ? l10n.reqHoursWord(n) : l10n.reqDaysWord(n))
        : (isHourly ? h : '$days');
    final unit = word
        ? l10n.reqDurationLabel
        : (isHourly ? l10n.reqHoursWord(n) : l10n.reqDaysWord(n));
    final (Color bg, Color fg, String label) = switch (status) {
      'approved' => (
        semantic?.successContainer ?? cs.primaryContainer,
        semantic?.onSuccessContainer ?? cs.onPrimaryContainer,
        l10n.statusApproved,
      ),
      'rejected' => (
        cs.errorContainer,
        cs.onErrorContainer,
        l10n.statusRejected,
      ),
      // Waiting for an answer: the warning pair, visible on the card.
      _ => (
        semantic?.warningContainer ?? cs.secondaryContainer,
        semantic?.onWarningContainer ?? cs.onSecondaryContainer,
        l10n.statusPending,
      ),
    };

    return _RequestView(
      docId: (req['docId'] ?? '').toString(),
      status: status,
      typeLabel: typeLabel,
      typeIcon: typeIcon,
      period: period,
      amount: amount,
      unit: unit,
      from: isHourly
          ? (req['fromTime'] ?? '').toString()
          : (start != null ? DateFormat('d MMM', locale).format(start) : ''),
      to: isHourly
          ? (req['toTime'] ?? '').toString()
          : (end != null ? DateFormat('d MMM', locale).format(end) : ''),
      reason: (req['reason'] ?? '').toString(),
      rejectReason: (req['rejectReason'] ?? '').toString(),
      resolvedByName: (req['resolvedByName'] ?? '').toString(),
      resolvedAt: dt(req['resolvedAt']),
      // TAS-42: new requests carry the Storage path; old ones only a URL.
      attachmentUrl: StorageMediaRef.pick(
        path: req['attachmentPath'],
        url: req['attachmentUrl'],
      ),
      statusBg: bg,
      statusFg: fg,
      statusLabel: label,
    );
  }

  /// The request as a SummaryCard (P-07, user review 27 Nov 2026): type and
  /// period, the amount large on the end side, the status label, from / to
  /// across the card, item actions in a ⋮ menu (C-24). A tap opens the
  /// details with a container transform (motion: OpenContainer).
  Widget _buildRequestCard({
    required Map<String, dynamic> req,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final v = _viewOf(req);
    final l10n = AppLocalizations.of(context)!;
    final menu = (v.status == 'pending' || v.attachmentUrl.isNotEmpty)
        ? MenuAnchor(
            builder: (context, controller, _) => IconButton(
              key: ValueKey('request_menu_${v.docId}'),
              icon: const Icon(Symbols.more_vert_rounded),
              tooltip: MaterialLocalizations.of(context).showMenuTooltip,
              onPressed: () =>
                  controller.isOpen ? controller.close() : controller.open(),
            ),
            menuChildren: [
              if (v.attachmentUrl.isNotEmpty)
                MenuItemButton(
                  leadingIcon: const Icon(Symbols.attachment_rounded),
                  onPressed: () => _viewAttachment(context, v.attachmentUrl),
                  child: Text(l10n.previewAttachment),
                ),
              if (v.status == 'pending')
                MenuItemButton(
                  leadingIcon: const Icon(Symbols.delete_outline_rounded),
                  onPressed: () => _cancelPendingRequest(context, v.docId),
                  child: Text(l10n.cancelRequest),
                ),
            ],
          )
        : null;

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
      child: OpenContainer<void>(
        key: ValueKey('request_card_${v.docId}'),
        closedElevation: 0,
        openElevation: 0,
        closedColor: colorScheme.surfaceContainerHighest,
        openColor: colorScheme.surface,
        middleColor: colorScheme.surface,
        closedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TashilRadius.medium),
        ),
        transitionDuration: MediaQuery.maybeDisableAnimationsOf(context) == true
            ? Duration.zero
            : const Duration(milliseconds: 400),
        closedBuilder: (context, open) =>
            _requestSummary(v, onTap: open, action: menu),
        openBuilder: (context, close) => _RequestDetailsPage(
          view: v,
          summary: _requestSummary(v),
          onPreview: v.attachmentUrl.isEmpty
              ? null
              : () => _viewAttachment(context, v.attachmentUrl),
          onCancel: v.status == 'pending'
              ? () async {
                  await _cancelPendingRequest(context, v.docId);
                  if (context.mounted) close();
                }
              : null,
        ),
      ),
    );
  }

  Widget _requestSummary(
    _RequestView v, {
    VoidCallback? onTap,
    Widget? action,
  }) {
    final l10n = AppLocalizations.of(context)!;
    return SummaryCard(
      margin: EdgeInsets.zero,
      onTap: onTap,
      action: action,
      icon: v.typeIcon,
      title: v.typeLabel,
      subtitle: v.period,
      labels: [
        SummaryLabel(
          v.statusLabel,
          container: v.statusBg,
          onContainer: v.statusFg,
        ),
      ],
      trailingValue: v.amount,
      trailingCaption: v.unit,
      facts: [
        SummaryFact(
          icon: Symbols.line_start_circle_rounded,
          label: l10n.fromField,
          value: v.from.isEmpty ? '—' : v.from,
        ),
        SummaryFact(
          icon: Symbols.line_end_circle_rounded,
          label: l10n.toField,
          value: v.to.isEmpty ? '—' : v.to,
        ),
      ],
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

      messenger.showSnackBar(SnackBar(content: Text(l10n.requestCancelled)));
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.card),
        ),
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
                        child: Text(
                          AppLocalizations.of(context)!.attachmentLoadFailed,
                        ),
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
  String _leaveTypeLabel(AppLocalizations l10n, String type) => switch (type) {
    'sick' => l10n.leaveSick,
    'emergency' => l10n.leaveEmergency,
    'delay' => l10n.excuseLate,
    'early_leave' => l10n.excuseEarlyLeave,
    'absence' => l10n.excuseAbsence,
    'unpaid' => l10n.leaveUnpaid,
    _ => l10n.leaveAnnual,
  };

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
    bool editingTo = false;

    await showTashilDialog<void>(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final theme = Theme.of(context);
          final colorScheme = theme.colorScheme;
          final textTheme = theme.textTheme;
          final semantic = theme.extension<TashilSemanticColors>();
          final isLeaveType =
              selectedType == 'annual' ||
              selectedType == 'sick' ||
              selectedType == 'emergency' ||
              selectedType == 'unpaid';
          if (selectedType == 'delay' || selectedType == 'early_leave') {
            isHourly = true;
          }
          final calculatedDays = endDate.difference(startDate).inDays + 1;
          final dirty =
              touched ||
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
            // TAS-370: the same backdate limit the rules enforce, and no
            // second request on days another live request already covers.
            if (submittedLeaveId == null) {
              final backDays = LeaveBackdate.daysFor(
                selectedType,
                isHourly: isHourly,
              );
              final first = LeaveBackdate.firstDate(
                today,
                selectedType,
                isHourly: isHourly,
              );
              if (startDate.isBefore(first)) {
                showTashilSnackBar(
                  context,
                  backDays == 0
                      ? l10n.leaveMustStartToday
                      : l10n.leaveTooOld(backDays),
                );
                return;
              }
              final conflict = LeaveOverlap.find(
                LeaveSpan(
                  id: '',
                  type: selectedType,
                  isHourly: isHourly,
                  status: 'pending',
                  start: startDate,
                  end: isHourly ? startDate : endDate,
                ),
                [
                  for (final d in _leaveDocs)
                    ?LeaveSpan.fromMap(d.id, d.data()),
                ],
              );
              if (conflict != null) {
                final fmt = DateFormat('d/M');
                showTashilSnackBar(
                  context,
                  l10n.leaveOverlapExists(
                    _leaveTypeLabel(l10n, conflict.type),
                    Bidi.ltr(fmt.format(conflict.start)),
                    Bidi.ltr(fmt.format(conflict.end)),
                  ),
                );
                return;
              }
            }
            final String? fromTimeFormatted = isHourly
                ? fromTime.format(context)
                : null;
            final String? toTimeFormatted = isHourly
                ? toTime.format(context)
                : null;

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
                  await FirebaseFirestore.instance.collection('notifications').add({
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
              color:
                  semantic?.warningContainer ?? colorScheme.tertiaryContainer,
              borderRadius: BorderRadius.circular(TashilRadius.medium),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 18,
                  color:
                      semantic?.onWarningContainer ??
                      colorScheme.onTertiaryContainer,
                ),
                const SizedBox(width: TashilSpacing.sm),
                Expanded(
                  child: Text(
                    text,
                    style: textTheme.bodySmall?.copyWith(
                      color:
                          semantic?.onWarningContainer ??
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
                      // TAS-370: a stricter type moves a too-old date back
                      // to today, so the picker never opens before its
                      // first day.
                      final first = LeaveBackdate.firstDate(
                        today,
                        val,
                        isHourly: isHourly,
                      );
                      if (startDate.isBefore(first)) {
                        startDate = DateTime(
                          today.year,
                          today.month,
                          today.day,
                        );
                        if (endDate.isBefore(startDate)) endDate = startDate;
                      }
                    });
                  },
                ),
                if (isHourly) ...[
                  const SizedBox(height: TashilSpacing.lg),
                  DateField(
                    key: const Key('newRequestDate'),
                    label: '${l10n.dateField} *',
                    value: startDate,
                    firstDate: LeaveBackdate.firstDate(
                      today,
                      selectedType,
                      isHourly: true,
                    ),
                    lastDate: today.add(const Duration(days: 60)),
                    onChanged: (d) {
                      if (d == null) return;
                      edit(() {
                        startDate = d;
                        endDate = d;
                      });
                    },
                  ),
                  // TAS-386: one time wheel at a time. Two stacked wheels
                  // covered most of the form and took the drag meant to
                  // scroll it. «من | إلى» picks which time the wheel edits.
                  const SizedBox(height: TashilSpacing.lg),
                  ButtonGroup<bool>(
                    key: const Key('newRequestTimeSide'),
                    variant: ButtonGroupVariant.connected,
                    expand: true,
                    selected: {editingTo},
                    onSelectionChanged: (v) =>
                        setDlgState(() => editingTo = v.first),
                    items: [
                      ButtonGroupItem(
                        value: false,
                        label: '${l10n.fromField} ${fromTime.format(context)}',
                      ),
                      ButtonGroupItem(
                        value: true,
                        label: '${l10n.toField} ${toTime.format(context)}',
                      ),
                    ],
                  ),
                  const SizedBox(height: TashilSpacing.sm),
                  ScrollTimePicker(
                    key: ValueKey(
                      editingTo ? 'newRequestToTime' : 'newRequestFromTime',
                    ),
                    value: editingTo ? toTime : fromTime,
                    onChanged: (t) => edit(() {
                      if (editingTo) {
                        toTime = t;
                      } else {
                        fromTime = t;
                      }
                    }),
                  ),
                ] else ...[
                  const SizedBox(height: TashilSpacing.lg),
                  DateField(
                    key: const Key('newRequestStart'),
                    label: '${l10n.fromField} *',
                    value: startDate,
                    // TAS-370: was DateTime(2024); the rules refuse older.
                    firstDate: LeaveBackdate.firstDate(
                      today,
                      selectedType,
                      isHourly: false,
                    ),
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

/// What the requests list and the details page show for one request.
class _RequestView {
  const _RequestView({
    required this.docId,
    required this.status,
    required this.typeLabel,
    required this.typeIcon,
    required this.period,
    required this.amount,
    required this.unit,
    required this.from,
    required this.to,
    required this.reason,
    required this.rejectReason,
    required this.resolvedByName,
    required this.resolvedAt,
    required this.attachmentUrl,
    required this.statusBg,
    required this.statusFg,
    required this.statusLabel,
  });
  final String docId, status, typeLabel, period, amount, unit, from, to;
  final String reason, rejectReason, resolvedByName, attachmentUrl, statusLabel;
  final IconData typeIcon;
  final DateTime? resolvedAt;
  final Color statusBg, statusFg;
}

/// Details of one request, opened from its card with a container transform.
class _RequestDetailsPage extends StatelessWidget {
  const _RequestDetailsPage({
    required this.view,
    required this.summary,
    this.onPreview,
    this.onCancel,
  });
  final _RequestView view;
  final Widget summary;
  final VoidCallback? onPreview;
  final VoidCallback? onCancel;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    Widget section(String title, String body, {Color? color}) => Padding(
      padding: const EdgeInsetsDirectional.only(top: TashilSpacing.lg),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Text(title, style: tt.titleSmall),
          const SizedBox(height: TashilSpacing.xs),
          Text(
            body,
            style: tt.bodyLarge?.copyWith(color: color ?? cs.onSurfaceVariant),
          ),
        ],
      ),
    );
    final decided = view.resolvedByName.isNotEmpty
        ? (view.resolvedAt != null
              ? '${view.resolvedByName} · ${DateFormat('d MMMM', Localizations.localeOf(context).languageCode).format(view.resolvedAt!)}'
              : view.resolvedByName)
        : '';
    return Scaffold(
      appBar: AppBar(title: Text(view.typeLabel)),
      body: ListView(
        key: const Key('request_details'),
        padding: const EdgeInsets.all(TashilSpacing.page),
        children: [
          summary,
          if (view.reason.isNotEmpty) section(l10n.reasonField, view.reason),
          if (view.status == 'rejected' && view.rejectReason.isNotEmpty)
            section(
              l10n.reqRejectReasonTitle,
              view.rejectReason,
              color: cs.error,
            ),
          if (decided.isNotEmpty) section(l10n.reqDecidedBy, decided),
          if (onPreview != null) ...[
            const SizedBox(height: TashilSpacing.lg),
            OutlinedButton.icon(
              onPressed: onPreview,
              icon: const Icon(Symbols.attachment_rounded),
              label: Text(l10n.previewAttachment),
            ),
          ],
          if (onCancel != null) ...[
            const SizedBox(height: TashilSpacing.xl),
            FilledButton.tonalIcon(
              key: const Key('request_details_cancel'),
              onPressed: onCancel,
              icon: const Icon(Symbols.delete_outline_rounded),
              label: Text(l10n.cancelRequest),
            ),
          ],
        ],
      ),
    );
  }
}
