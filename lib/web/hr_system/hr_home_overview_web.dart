// WEB-ONLY: «الرئيسية» tab of the HR shell (/hr/home) for company
// supervisors and HR. Data comes from HRAttendanceTab's existing,
// company-scoped loads through its viewBuilder hook; nothing here queries
// Firestore directly.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/web/hr_system/hr_home_attendance_card_web.dart';
import 'package:delegate_app/web/hr_system/hr_home_side_cards_web.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';

/// Width of the side column next to the attendance card.
const double kHrOverviewSideColumnWidth = 352;

/// Content width from which the side column sits beside the attendance card.
const double kHrOverviewTwoColumnMinWidth = 1000;

/// Content width from which the attendance card shows the full table.
const double kHrOverviewTableMinWidth = 640;

/// Everything the overview renders. Built from the attendance tab's state in
/// the app and from fake data in tests.
class HrHomeOverviewData {
  final Delegate delegate;
  final bool isLoading;
  final String? errorMessage;
  final List<HRAttendanceRecord> records;
  final List<String> chains;
  final Map<String, Branch> branchesByName;
  final int unreadNotifications;
  final bool isFreePromotion;

  const HrHomeOverviewData({
    required this.delegate,
    required this.isLoading,
    required this.errorMessage,
    required this.records,
    required this.chains,
    this.branchesByName = const {},
    this.unreadNotifications = 0,
    this.isFreePromotion = false,
  });
}

/// Actions wired to the existing screens by [HrHomeOverviewWeb].
class HrHomeOverviewActions {
  final Future<void> Function() onReload;
  final VoidCallback onOpenNotifications;
  final VoidCallback onOpenProfile;
  final VoidCallback onOpenAttendanceLog;
  final VoidCallback onOpenDelegates;
  final VoidCallback onAddDelegate;
  final VoidCallback onHowToLink;
  final ValueChanged<HRAttendanceRecord> onOpenRecord;

  const HrHomeOverviewActions({
    required this.onReload,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    required this.onOpenAttendanceLog,
    required this.onOpenDelegates,
    required this.onAddDelegate,
    required this.onHowToLink,
    required this.onOpenRecord,
  });
}

/// Shell tab: today's attendance from [HRAttendanceTab] (same queries and
/// company scope as the attendance log), the unread-notifications count, and
/// the existing add-delegate / linking-guide / detail screens.
class HrHomeOverviewWeb extends StatelessWidget {
  final Delegate delegate;
  final ValueChanged<int> onNavigateToTab;

  const HrHomeOverviewWeb({
    super.key,
    required this.delegate,
    required this.onNavigateToTab,
  });

  /// Test hook: fake data instead of the live attendance tab (it needs a
  /// live Firestore). Always null in the app.
  @visibleForTesting
  static HrHomeOverviewData Function(Delegate delegate)? debugData;

  /// Test hook: fixed clock for [debugData] (stable durations).
  @visibleForTesting
  static DateTime Function()? debugClock;

  /// Test hook: the reload the header refresh button runs for [debugData].
  @visibleForTesting
  static Future<void> Function()? debugOnReload;

  HrHomeOverviewActions _actions(
    BuildContext context, {
    required Future<void> Function() onReload,
    required DateTime month,
    required Map<String, Branch> branchesByName,
  }) => HrHomeOverviewActions(
    onReload: onReload,
    onOpenNotifications: () => context.push('/notifications', extra: delegate),
    onOpenProfile: () => context.push('/user-profile', extra: delegate),
    onOpenAttendanceLog: () => onNavigateToTab(kHrTabAttendance),
    onOpenDelegates: () => onNavigateToTab(kHrTabDelegates),
    onAddDelegate: () => openAdminHomeAddDelegate(context, delegate),
    onHowToLink: () => showAdminHomeLinkingGuide(context, delegate),
    onOpenRecord: (record) => Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HRDelegateAttendanceDetailScreen(
          delegate: record.delegate,
          initialMonth: month,
          branchesByName: branchesByName,
          hrDelegate: delegate,
        ),
      ),
    ),
  );

  @override
  Widget build(BuildContext context) {
    final fake = debugData?.call(delegate);
    if (fake != null) {
      final clock = debugClock ?? DateTime.now;
      return HrHomeOverviewView(
        data: fake,
        clock: clock,
        actions: _actions(
          context,
          onReload: () async {
            await debugOnReload?.call();
          },
          month: clock(),
          branchesByName: fake.branchesByName,
        ),
      );
    }
    return _UnreadNotifications(
      delegate: delegate,
      child: HRAttendanceTab(
        hrDelegate: delegate,
        onNavigateToTab: onNavigateToTab,
        viewBuilder: (context, view) => HrHomeOverviewView(
          data: HrHomeOverviewData(
            delegate: delegate,
            isLoading: view.isLoading,
            errorMessage: view.errorMessage,
            records: view.allRecords,
            chains: view.chains.toList()..sort(),
            branchesByName: view.branchesByName,
            unreadNotifications: _UnreadNotifications.countOf(context),
            isFreePromotion: SubscriptionCycleHelper.isFreePromotionActive(
              null,
              delegate.companyUID,
            ),
          ),
          actions: _actions(
            context,
            onReload: view.onReload ?? view.onRefresh,
            month: view.selectedDate,
            branchesByName: view.branchesByName,
          ),
        ),
      ),
    );
  }
}

/// Unread count from the same NotificationBloc subscription the supervisor
/// app bar uses. Zero when the bloc is not registered (tests).
class _UnreadNotifications extends StatefulWidget {
  final Delegate delegate;
  final Widget child;

  const _UnreadNotifications({required this.delegate, required this.child});

  static int countOf(BuildContext context) {
    final scope = context
        .dependOnInheritedWidgetOfExactType<_UnreadNotificationsScope>();
    return scope?.count ?? 0;
  }

  @override
  State<_UnreadNotifications> createState() => _UnreadNotificationsState();
}

class _UnreadNotificationsState extends State<_UnreadNotifications> {
  NotificationBloc? _bloc;

  @override
  void initState() {
    super.initState();
    if (di.sl.isRegistered<NotificationBloc>()) {
      final d = widget.delegate;
      _bloc = di.sl<NotificationBloc>()
        ..add(
          SubscribeToUnreadCount(
            delegateUid: d.uid,
            organizationId: d.organizationUID,
            phoneNumber: d.phoneNumber,
            userRole: d.role.name,
            accountCreatedAt: d.createdAt,
          ),
        );
    }
  }

  @override
  void dispose() {
    _bloc?.close();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final bloc = _bloc;
    if (bloc == null) {
      return _UnreadNotificationsScope(count: 0, child: widget.child);
    }
    return BlocBuilder<NotificationBloc, NotificationState>(
      bloc: bloc,
      builder: (context, state) => _UnreadNotificationsScope(
        count: state is NotificationLoaded ? state.unreadCount : 0,
        child: widget.child,
      ),
    );
  }
}

class _UnreadNotificationsScope extends InheritedWidget {
  final int count;

  const _UnreadNotificationsScope({required this.count, required super.child});

  @override
  bool updateShouldNotify(_UnreadNotificationsScope old) => old.count != count;
}

/// The overview page (pure view; fake data in tests and goldens).
class HrHomeOverviewView extends StatefulWidget {
  final HrHomeOverviewData data;
  final HrHomeOverviewActions actions;

  /// Clock for «آخر تحديث» and the live duration of open check-ins.
  final DateTime Function() clock;

  const HrHomeOverviewView({
    super.key,
    required this.data,
    required this.actions,
    this.clock = DateTime.now,
  });

  @override
  State<HrHomeOverviewView> createState() => _HrHomeOverviewViewState();
}

class _HrHomeOverviewViewState extends State<HrHomeOverviewView> {
  final TextEditingController _search = TextEditingController();
  HrPresenceFilter _presence = HrPresenceFilter.all;
  String? _chain;
  int _page = 0;
  bool _showAllRows = false;
  Timer? _ticker;
  HrWebHeaderBridge? _headerBridge;

  @override
  void initState() {
    super.initState();
    _ticker = Timer.periodic(const Duration(seconds: 30), (_) {
      if (mounted) setState(() {});
    });
    _publishHeader();
  }

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    _headerBridge = context
        .getInheritedWidgetOfExactType<HrWebHeaderBridgeScope>()
        ?.notifier;
  }

  @override
  void didUpdateWidget(HrHomeOverviewView old) {
    super.didUpdateWidget(old);
    if (_chain != null && !widget.data.chains.contains(_chain)) {
      _chain = null;
    }
    _publishHeader();
  }

  @override
  void dispose() {
    _headerBridge?.release();
    _ticker?.cancel();
    _search.dispose();
    super.dispose();
  }

  /// Hands reload and notifications to the header.
  void _publishHeader() {
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (!mounted) return;
      _headerBridge?.attach(
        unread: widget.data.unreadNotifications,
        reloadHome: widget.actions.onReload,
        openNotifications: widget.actions.onOpenNotifications,
      );
    });
  }

  void _resetPaging() {
    _page = 0;
    _showAllRows = false;
  }

  HrAttendanceCardState get _cardState {
    final d = widget.data;
    if (d.isLoading) return HrAttendanceCardState.loading;
    if (d.errorMessage != null) return HrAttendanceCardState.error;
    if (!d.records.any((r) => r.checkInTime != null)) {
      return HrAttendanceCardState.empty;
    }
    return HrAttendanceCardState.data;
  }

  @override
  Widget build(BuildContext context) {
    final window = MediaQuery.sizeOf(context).width;
    final windowClass = hrWindowClassOf(window);
    final compact = windowClass == HrWindowClass.compact;
    final padding = compact ? 16.0 : 24.0;
    final gap = compact ? 16.0 : 24.0;
    final state = _cardState;
    final enabled =
        state == HrAttendanceCardState.data ||
        state == HrAttendanceCardState.empty;
    final now = widget.clock();
    final summary = HrAttendanceSummary.compute(
      records: widget.data.records,
      branches: widget.data.branchesByName,
      presence: _presence,
      chain: _chain,
      query: _search.text,
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final content = constraints.maxWidth - padding * 2;
        final expanded = windowClass == HrWindowClass.expanded;
        final twoColumns = expanded && content >= kHrOverviewTwoColumnMinWidth;
        final showTable = expanded && content >= kHrOverviewTableMinWidth;

        final attendance = HrHomeAttendanceCard(
          state: state,
          summary: summary,
          windowClass: windowClass,
          showTable: showTable,
          errorMessage: widget.data.errorMessage,
          now: now,
          branches: widget.data.branchesByName,
          chains: widget.data.chains,
          presence: _presence,
          chain: _chain,
          search: _search,
          page: _page,
          showAllRows: _showAllRows,
          onPresenceChanged: (v) => setState(() {
            _presence = v;
            _resetPaging();
          }),
          onChainChanged: _selectChain,
          onSearchChanged: () => setState(_resetPaging),
          onPageChanged: (p) => setState(() => _page = p),
          onToggleShowAll: () => setState(() => _showAllRows = !_showAllRows),
          onOpenAbsent: () => _showAbsentList(context, summary.absent),
          onOpenAttendanceLog: widget.actions.onOpenAttendanceLog,
          onOpenDelegates: widget.actions.onOpenDelegates,
          onRetry: widget.actions.onReload,
          onOpenRecord: widget.actions.onOpenRecord,
        );
        final chains = HrHomeChainsCard(
          chains: widget.data.chains,
          selected: _chain,
          enabled: enabled,
          onSelected: _selectChain,
        );
        final feature = HrHomeFeatureCard(
          isFreePromotion: widget.data.isFreePromotion,
          onAddDelegate: widget.actions.onAddDelegate,
          onHowToLink: widget.actions.onHowToLink,
        );
        final duties = HrHomeDutiesCard(
          duties: adminHomeDuties(widget.data.delegate, isArabic: true),
        );

        final Widget body;
        if (twoColumns) {
          body = Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Expanded(child: attendance),
              SizedBox(width: gap),
              SizedBox(
                width: kHrOverviewSideColumnWidth,
                child: Column(
                  key: const ValueKey('hr_home_side_column'),
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    chains,
                    SizedBox(height: gap),
                    feature,
                    SizedBox(height: gap),
                    duties,
                  ],
                ),
              ),
            ],
          );
        } else if (expanded) {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              attendance,
              SizedBox(height: gap),
              Row(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Expanded(child: chains),
                  SizedBox(width: gap),
                  Expanded(child: feature),
                ],
              ),
              SizedBox(height: gap),
              duties,
            ],
          );
        } else {
          body = Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              attendance,
              SizedBox(height: gap),
              chains,
              SizedBox(height: gap),
              feature,
              SizedBox(height: gap),
              duties,
            ],
          );
        }

        return Scrollbar(
          child: SingleChildScrollView(
            key: const ValueKey('hr_home_overview'),
            padding: EdgeInsets.all(padding),
            child: Center(
              child: ConstrainedBox(
                constraints: const BoxConstraints(maxWidth: 1440),
                child: body,
              ),
            ),
          ),
        );
      },
    );
  }

  void _selectChain(String? chain) => setState(() {
    _chain = chain;
    _resetPaging();
  });

  void _showAbsentList(BuildContext context, List<HRAttendanceRecord> absent) {
    final list = _AbsentList(
      absent: absent,
      branches: widget.data.branchesByName,
      onOpenDelegates: widget.actions.onOpenDelegates,
    );
    if (MediaQuery.sizeOf(context).width <= 768) {
      showModalBottomSheet<void>(
        context: context,
        isScrollControlled: true,
        showDragHandle: false,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (sheetContext) => SizedBox(
          height: MediaQuery.sizeOf(sheetContext).height * 0.8,
          child: Padding(
            padding: EdgeInsets.only(
              bottom: MediaQuery.of(sheetContext).viewInsets.bottom,
            ),
            child: Column(
              children: [
                const SizedBox(height: 10),
                Container(
                  width: 38,
                  height: 4.5,
                  decoration: BoxDecoration(
                    color: Theme.of(
                      sheetContext,
                    ).colorScheme.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
                Expanded(child: list),
              ],
            ),
          ),
        ),
      );
      return;
    }
    showDialog<void>(
      context: context,
      builder: (dialogContext) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 540, maxHeight: 640),
          child: list,
        ),
      ),
    );
  }
}

/// Absent delegates of the day (opened from the third stat).
class _AbsentList extends StatelessWidget {
  final List<HRAttendanceRecord> absent;
  final Map<String, Branch> branches;
  final VoidCallback onOpenDelegates;

  const _AbsentList({
    required this.absent,
    required this.branches,
    required this.onOpenDelegates,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      key: const ValueKey('hr_home_absent_list'),
      mainAxisSize: MainAxisSize.min,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 8),
          child: HrCardTitle(
            icon: Icons.person_off_outlined,
            text: 'الغايبين النهاردة (${absent.length})',
          ),
        ),
        Flexible(
          child: ListView.separated(
            shrinkWrap: true,
            padding: const EdgeInsets.symmetric(horizontal: 12),
            itemCount: absent.length,
            separatorBuilder: (_, _) => Divider(
              height: 1,
              indent: 64,
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
            itemBuilder: (context, i) {
              final r = absent[i];
              final chain = hrRecordChain(r, branches);
              return ListTile(
                minTileHeight: 56,
                leading: chain.isEmpty
                    ? null
                    : HrChainAvatar(chain: chain, size: 32),
                title: Text(
                  r.delegate.fullName,
                  style: const TextStyle(
                    fontSize: 15,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    if (r.delegate.delegatePublicId.trim().isNotEmpty)
                      r.delegate.delegatePublicId.trim(),
                    if (chain.isNotEmpty) chain,
                  ].join(' · '),
                  style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
                ),
              );
            },
          ),
        ),
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 8, 24, 20),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              borderRadius: BorderRadius.circular(24),
              border: Border.all(color: cs.outlineVariant),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                Expanded(
                  child: TextButton(
                    key: const ValueKey('hr_home_absent_close'),
                    onPressed: () => Navigator.of(context).pop(),
                    style: TextButton.styleFrom(
                      shape: const RoundedRectangleBorder(),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('إغلاق'),
                  ),
                ),
                VerticalDivider(width: 1, color: cs.outlineVariant),
                Expanded(
                  child: TextButton(
                    onPressed: () {
                      Navigator.of(context).pop();
                      onOpenDelegates();
                    },
                    style: TextButton.styleFrom(
                      shape: const RoundedRectangleBorder(),
                      minimumSize: const Size.fromHeight(48),
                    ),
                    child: const Text('عرض المناديب'),
                  ),
                ),
              ],
            ),
          ),
        ),
      ],
    );
  }
}
