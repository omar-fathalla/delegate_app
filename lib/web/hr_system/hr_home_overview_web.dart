// WEB-ONLY: «الرئيسية» tab of the HR shell (/hr/home) for company
// supervisors and HR. Data comes from HRAttendanceTab's existing,
// company-scoped loads through its viewBuilder hook; nothing here queries
// Firestore directly.
import 'dart:async';

import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/foundation.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/utils/subscription_cycle_helper.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/features/admin/data/company_chains.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_add_chains_sheet.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/web/hr_system/hr_home_attendance_card_web.dart';
import 'package:delegate_app/web/hr_system/hr_home_side_cards_web.dart';
import 'package:delegate_app/web/hr_system/hr_notifications_side_sheet.dart';
import 'package:delegate_app/web/hr_system/hr_overlay_scrollbar.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

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

  /// Chain names with a pending company «طلب ضم سلسلة».
  final List<String> pendingChainRequests;

  const HrHomeOverviewData({
    required this.delegate,
    required this.isLoading,
    required this.errorMessage,
    required this.records,
    required this.chains,
    this.branchesByName = const {},
    this.unreadNotifications = 0,
    this.isFreePromotion = false,
    this.pendingChainRequests = const [],
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

  /// «إضافة سلسلة» in the chains card. Null hides it.
  final VoidCallback? onAddChain;

  /// «عرض الكل» under the pending chain requests.
  final VoidCallback? onOpenChainRequests;

  const HrHomeOverviewActions({
    required this.onReload,
    required this.onOpenNotifications,
    required this.onOpenProfile,
    required this.onOpenAttendanceLog,
    required this.onOpenDelegates,
    required this.onAddDelegate,
    required this.onHowToLink,
    required this.onOpenRecord,
    this.onAddChain,
    this.onOpenChainRequests,
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
    onOpenNotifications: () {
      if (!WebRuntimePolicy.isWeb) {
        context.push('/notifications', extra: delegate);
        return;
      }
      showHrNotificationsSideSheet(context, delegate: delegate);
    },
    onOpenProfile: () => context.push('/user-profile', extra: delegate),
    onOpenAttendanceLog: () => onNavigateToTab(kHrTabAttendance),
    onOpenDelegates: () => onNavigateToTab(kHrTabDelegates),
    onAddDelegate: () => openAdminHomeAddDelegate(context, delegate),
    onAddChain: () => _addChain(context),
    onOpenChainRequests: () => onNavigateToTab(kHrTabSubscriptions),
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

  /// Company-level «طلب ضم سلسلة» from the home chains card (TAS-117).
  Future<void> _addChain(BuildContext context) async {
    final names = await HrAddChainsSheet.show(context, supervisor: delegate);
    if (!context.mounted || names == null || names.isEmpty) return;
    _PendingChainRequests.reload(context);
    AppSnackBar.showSuccess(
      context,
      'تم إرسال طلب ضم ${names.length} سلسلة للشركة. بعد الموافقة تظهر فروعها لكل المناديب النشطين المدفوع اشتراكهم.',
    );
  }

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
    return _PendingChainRequests(
      delegate: delegate,
      child: _UnreadNotifications(
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
              pendingChainRequests: _PendingChainRequests.namesOf(context),
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
      ),
    );
  }
}

/// Pending company «طلب ضم سلسلة» names for the chains card. One query when
/// the page opens and again after a new request is sent.
class _PendingChainRequests extends StatefulWidget {
  final Delegate delegate;
  final Widget child;

  const _PendingChainRequests({required this.delegate, required this.child});

  static List<String> namesOf(BuildContext context) =>
      context
          .dependOnInheritedWidgetOfExactType<_PendingChainRequestsScope>()
          ?.names ??
      const [];

  static void reload(BuildContext context) => context
      .getInheritedWidgetOfExactType<_PendingChainRequestsScope>()
      ?.reload();

  @override
  State<_PendingChainRequests> createState() => _PendingChainRequestsState();
}

class _PendingChainRequestsState extends State<_PendingChainRequests> {
  List<String> _names = const [];

  @override
  void initState() {
    super.initState();
    // Warm the chain catalog so «إضافة سلسلة» opens at once.
    try {
      HrAddChainsSheet.prefetch(widget.delegate);
    } catch (_) {
      // No Firebase app (tests): the sheet loads on open instead.
    }
    _load();
  }

  Future<void> _load() async {
    try {
      final rows = await fetchPendingCompanyChainRequests(
        firestore: FirebaseFirestore.instance,
        companyUID: widget.delegate.companyUID,
      );
      if (!mounted) return;
      setState(() {
        _names = [
          for (final r in rows)
            if (r.organizationName.trim().isNotEmpty) r.organizationName.trim(),
        ];
      });
    } catch (_) {
      // The card just hides the section; the sheet still shows pending chains.
    }
  }

  @override
  Widget build(BuildContext context) => _PendingChainRequestsScope(
    names: _names,
    reload: _load,
    child: widget.child,
  );
}

class _PendingChainRequestsScope extends InheritedWidget {
  final List<String> names;
  final VoidCallback reload;

  const _PendingChainRequestsScope({
    required this.names,
    required this.reload,
    required super.child,
  });

  @override
  bool updateShouldNotify(_PendingChainRequestsScope old) =>
      !listEquals(old.names, names);
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
  final ScrollController _scroll = ScrollController();
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
    _scroll.dispose();
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
          onAddChain: widget.actions.onAddChain,
          pendingRequests: widget.data.pendingChainRequests,
          onOpenRequests: widget.actions.onOpenChainRequests,
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

        return HrOverlayScrollbar(
          controller: _scroll,
          child: SingleChildScrollView(
            controller: _scroll,
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
          borderRadius: BorderRadius.vertical(
            top: Radius.circular(HrRadius.pill),
          ),
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
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.pill),
        ),
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
                    fontSize: HrFont.titleMedium,
                    fontWeight: FontWeight.w600,
                  ),
                ),
                subtitle: Text(
                  [
                    if (r.delegate.delegatePublicId.trim().isNotEmpty)
                      r.delegate.delegatePublicId.trim(),
                    if (chain.isNotEmpty) chain,
                  ].join(' · '),
                  style: TextStyle(
                    fontSize: HrFont.body,
                    color: cs.onSurfaceVariant,
                  ),
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
              borderRadius: BorderRadius.circular(HrRadius.pill),
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
