import 'package:delegate_app/core/storage/storage_media.dart';
import 'package:delegate_app/core/widgets/storage_resolved_image.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/features/hr/data/hr_leave_settings_writer.dart';
import 'package:delegate_app/features/hr/domain/leave_overlap.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';

/// Max height of the web create-dialog dropdown menus. Keeps the open menu
/// inside the dialog; longer lists scroll (TAS-151).
const double kHrLeaveDialogMenuHeight = 240;

/// شاشة تقديم ومراجعة واعتماد طلبات الإجازات ومبررات الغياب (HR Leaves & Excuses)
class HRLeavesAndExcusesScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  /// Optional list-detail hook (web-only desktop shell). When null (mobile),
  /// tapping a request expands it inline exactly as before.
  final ValueChanged<HRLeaveSelection>? onSelectLeave;
  final String? selectedLeaveKey;

  /// Firestore used for the requests list stream. Null means
  /// [FirebaseFirestore.instance]; tests pass a fake.
  final FirebaseFirestore? firestore;

  const HRLeavesAndExcusesScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
    this.onSelectLeave,
    this.selectedLeaveKey,
    this.firestore,
  });

  @override
  State<HRLeavesAndExcusesScreen> createState() =>
      _HRLeavesAndExcusesScreenState();
}

class _HRLeavesAndExcusesScreenState extends State<HRLeavesAndExcusesScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedStatusFilter = 'pending'; // 'pending', 'approved', 'rejected', 'all'
  String _searchQuery = '';
  List<Delegate> _companyDelegates = [];
  final Set<String> _expandedLeaveDocIds = {};

  @override
  void initState() {
    super.initState();
    _loadCompanyDelegates();
  }

  /// Web shell bridge, so the top-bar refresh reloads this tab (TAS-183).
  HrWebHeaderBridge? _headerBridge;

  /// Shell tab only: a page with its own AppBar is not inside the shell.
  bool get _hrWebShellTab => WebRuntimePolicy.isWeb && !widget.showAppBar;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!_hrWebShellTab) return;
    final next = context
        .getInheritedWidgetOfExactType<HrWebHeaderBridgeScope>()
        ?.notifier;
    if (identical(next, _headerBridge)) return;
    _headerBridge?.releasePageReload(kHrTabLeaves, _reloadFromShell);
    _headerBridge = next;
    _headerBridge?.attachPageReload(kHrTabLeaves, _reloadFromShell);
  }

  @override
  void dispose() {
    _headerBridge?.releasePageReload(kHrTabLeaves, _reloadFromShell);
    _searchController.dispose();
    super.dispose();
  }

  /// Top-bar refresh: re-subscribes the requests stream (it is built in
  /// [build]) and reloads the company delegates used by the dialogs.
  Future<void> _reloadFromShell() async {
    if (!mounted) return;
    setState(() {});
    await _loadCompanyDelegates();
  }

  Future<void> _loadCompanyDelegates() async {
    try {
      final res = await di.sl<GetCompanyDelegates>()(
        GetCompanyDelegatesParams(
          organizationUID: widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );
      res.fold((_) {}, (page) {
        if (mounted) setState(() => _companyDelegates = page.delegates);
      });
    } catch (_) {}
  }

  Future<void> _openDelegatesLeaveManager() async {
    if (_companyDelegates.isEmpty) {
      await _loadCompanyDelegates();
    }
    if (!mounted) return;

    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
      ),
      builder: (sheetContext) {
        return StatefulBuilder(
          builder: (ctx, setSheetState) {
            return DraggableScrollableSheet(
              initialChildSize: 0.75,
              minChildSize: 0.5,
              maxChildSize: 0.95,
              expand: false,
              builder: (_, scrollController) {
                return Column(
                  children: [
                    // Drag Handle
                    Container(
                      margin: const EdgeInsets.only(top: 12, bottom: 8),
                      width: 40,
                      height: 4,
                      decoration: BoxDecoration(
                        color: colorScheme.outlineVariant,
                        borderRadius: BorderRadius.circular(2),
                      ),
                    ),
                    // Header
                    Padding(
                      padding: const EdgeInsets.fromLTRB(20, 8, 20, 16),
                      child: Row(
                        children: [
                          Container(
                            padding: const EdgeInsets.all(8),
                            decoration: BoxDecoration(
                              color: colorScheme.primary.withValues(alpha: 0.12),
                              borderRadius: BorderRadius.circular(HrRadius.card),
                            ),
                            child: Icon(
                              Icons.beach_access_rounded,
                              color: colorScheme.primary,
                              size: 22,
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                const Text(
                                  'إدارة رصيد الإجازات السنوية للمناديب',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: HrFont.titleMedium,
                                  ),
                                ),
                                Text(
                                  'تفعيل أو إيقاف رصيد الإجازات السنوية (21 يوم) للمناديب الجدد وفترة التجربة',
                                  style: TextStyle(
                                    fontSize: HrFont.labelSmall,
                                    color: colorScheme.onSurfaceVariant,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const Divider(height: 1),
                    Expanded(
                      child: _companyDelegates.isEmpty
                          ? const Center(child: Text('لا يوجد مناديب مسجلين في الشركة'))
                          : ListView.separated(
                              controller: scrollController,
                              padding: const EdgeInsets.all(16),
                              itemCount: _companyDelegates.length,
                              separatorBuilder: (_, _) => const SizedBox(height: 8),
                              itemBuilder: (context, index) {
                                final del = _companyDelegates[index];
                                final isEnabled = del.isAnnualLeaveEnabled;

                                return Container(
                                  padding: const EdgeInsets.all(12),
                                  decoration: BoxDecoration(
                                    color: colorScheme.surfaceContainerLow,
                                    borderRadius: BorderRadius.circular(HrRadius.card),
                                    border: Border.all(
                                      color: isEnabled
                                          ? HrStatusColors.of(context).success.withValues(alpha: 0.3)
                                          : colorScheme.outlineVariant.withValues(alpha: 0.4),
                                    ),
                                  ),
                                  child: Row(
                                    children: [
                                      AppAvatar(
                                        imageUrl: del.personalPhotoUrl,
                                        fallbackText: del.fullName,
                                        radius: 20,
                                      ),
                                      const SizedBox(width: 12),
                                      Expanded(
                                        child: Column(
                                          crossAxisAlignment: CrossAxisAlignment.start,
                                          children: [
                                            Text(
                                              del.fullName,
                                              style: const TextStyle(
                                                fontWeight: FontWeight.bold,
                                                fontSize: HrFont.body,
                                              ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                            const SizedBox(height: 2),
                                            Text(
                                              isEnabled
                                                  ? 'رصيد سنوي مفعّل (${del.annualLeaveQuota} يوم)'
                                                  : 'إجازات أسبوعية فقط (فترة تجربة)',
                                              style: TextStyle(
                                                fontSize: HrFont.labelSmall,
                                                fontWeight: FontWeight.w600,
                                                color: isEnabled
                                                    ? HrStatusColors.of(context).success
                                                    : HrStatusColors.of(context).warning,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ),
                                      Switch.adaptive(
                                        value: isEnabled,
                                        activeTrackColor: colorScheme.primary,
                                        activeThumbColor: colorScheme.onPrimary,
                                        onChanged: (val) async {
                                          final messenger = ScaffoldMessenger.of(context);
                                          final updatedDel = del is DelegateModel
                                              ? del.copyWith(isAnnualLeaveEnabled: val)
                                              : Delegate(
                                                  uid: del.uid,
                                                  firstName: del.firstName,
                                                  middleName: del.middleName,
                                                  lastName: del.lastName,
                                                  fullName: del.fullName,
                                                  nationalityID: del.nationalityID,
                                                  motherName: del.motherName,
                                                  city: del.city,
                                                  phoneNumber: del.phoneNumber,
                                                  gender: del.gender,
                                                  position: del.position,
                                                  birthDate: del.birthDate,
                                                  organizationUID: del.organizationUID,
                                                  organizationName: del.organizationName,
                                                  companyUID: del.companyUID,
                                                  companyName: del.companyName,
                                                  status: del.status,
                                                  delegatePublicId: del.delegatePublicId,
                                                  allReceiptCodes: del.allReceiptCodes,
                                                  createdAt: del.createdAt,
                                                  createdBy: del.createdBy,
                                                  hasPendingUpdate: del.hasPendingUpdate,
                                                  isDeductedFromCompany: del.isDeductedFromCompany,
                                                  isPrinted: del.isPrinted,
                                                  isProfileComplete: del.isProfileComplete,
                                                  numberOfDocuments: del.numberOfDocuments,
                                                  paymentAmount: del.paymentAmount,
                                                  version: del.version,
                                                  documents: del.documents,
                                                  isAnnualLeaveEnabled: val,
                                                  annualLeaveQuota: del.annualLeaveQuota,
                                                );

                                          setSheetState(() {
                                            _companyDelegates[index] = updatedDel;
                                          });
                                          setState(() {});

                                          try {
                                            final payload = {
                                              'isAnnualLeaveEnabled': val,
                                              'annualLeaveQuota': del.annualLeaveQuota > 0 ? del.annualLeaveQuota : 21,
                                              'updatedAt': FieldValue.serverTimestamp(),
                                            };

                                            final orgUid = del.organizationUID.isNotEmpty
                                                ? del.organizationUID
                                                : widget.hrDelegate.organizationUID;
                                            final compUid = del.companyUID.isNotEmpty
                                                ? del.companyUID
                                                : widget.hrDelegate.companyUID;

                                            // TAS-74: delegate doc required, users copy best effort.
                                            await saveDelegateLeaveSettings(
                                              firestore: FirebaseFirestore.instance,
                                              organizationUID: orgUid,
                                              companyUID: compUid,
                                              delegateUid: del.uid,
                                              payload: payload,
                                            );
                                          } catch (e) {
                                            messenger.showSnackBar(
                                              SnackBar(content: Text('فشل حفظ التعديل: $e')),
                                            );
                                          }
                                        },
                                      ),
                                    ],
                                  ),
                                );
                              },
                            ),
                    ),
                  ],
                );
              },
            );
          },
        );
      },
    );
  }

  /// Width from which the toolbar is a single row (see the toolbar below).
  static const double _toolbarRowMinWidth = 850;

  /// «إدارة الأرصدة» when the page has no AppBar (shell tab, TAS-183).
  ///
  /// [inToolbar]: the wide web toolbar row, styled like its other controls.
  /// Otherwise a compact button for the action row above the toolbar.
  Widget _leaveManagerButton({required bool inToolbar}) {
    const label = Text('إدارة الأرصدة');
    const icon = Icon(Icons.beach_access_rounded, size: 18);
    final button = inToolbar
        ? OutlinedButton.icon(
            key: const ValueKey('hr_leaves_manage_balances'),
            style: OutlinedButton.styleFrom(
              minimumSize: const Size(0, 44),
              padding: const EdgeInsets.symmetric(horizontal: 16),
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(HrRadius.pill),
              ),
            ),
            onPressed: _openDelegatesLeaveManager,
            icon: icon,
            label: label,
          )
        : TextButton.icon(
            key: const ValueKey('hr_leaves_manage_balances'),
            onPressed: _openDelegatesLeaveManager,
            icon: icon,
            label: label,
          );
    return Tooltip(
      message: 'إدارة إجازات وأرصدة المناديب',
      child: button,
    );
  }

  /// Action row above the toolbar when the page has no AppBar: mobile tab and
  /// narrow web. Wide web shows the button in the toolbar row instead.
  Widget _leaveManagerActionRow() {
    return LayoutBuilder(
      builder: (context, constraints) {
        // Same width test as the toolbar (it has 16 padding on each side).
        final toolbarRow = constraints.maxWidth - 32 >= _toolbarRowMinWidth;
        if (WebRuntimePolicy.isWeb && toolbarRow) {
          return const SizedBox.shrink();
        }
        return Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 0, 8, 0),
          child: Align(
            alignment: AlignmentDirectional.centerEnd,
            child: _leaveManagerButton(inToolbar: false),
          ),
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final web = WebRuntimePolicy.isWeb;

    Query<Map<String, dynamic>> query =
        (widget.firestore ?? FirebaseFirestore.instance)
        .collection('leave_requests')
        .where('companyUID', isEqualTo: widget.hrDelegate.companyUID);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
              titleSpacing: 0,
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text(
                    'الإجازات',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: HrFont.body,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.hrDelegate.companyName,
                    style: TextStyle(
                      fontSize: HrFont.labelSmall,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
        actions: [
          IconButton(
            icon: const Icon(Icons.beach_access_rounded),
            tooltip: 'إدارة إجازات وأرصدة المناديب',
            onPressed: _openDelegatesLeaveManager,
          ),
          // The list is a live stream; web relies on the shell refresh.
          if (!WebRuntimePolicy.isWeb)
            IconButton(
              icon: const Icon(Icons.refresh_rounded),
              tooltip: 'تحديث',
              onPressed: () => setState(() {}),
            ),
          const SizedBox(width: 8),
        ],
      )
          : null,
      // Web uses the toolbar button instead of a FAB (TAS-151).
      floatingActionButton: web
          ? null
          : FloatingActionButton.extended(
              heroTag: 'hr_leaves_create_fab',
              onPressed: _showCreateLeaveDialog,
              icon: const Icon(Icons.add_task_rounded),
              label: const Text('تسجيل'),
            ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: CircularProgressIndicator());
          }

          final docs = snapshot.data?.docs ?? [];
          final allLeaves = docs.map((d) {
            final data = d.data();
            return {
              'docId': d.id,
              ...data,
            };
          }).toList();

          allLeaves.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });

          final pendingCount =
              allLeaves.where((r) => r['status'] == 'pending').length;
          final approvedCount =
              allLeaves.where((r) => r['status'] == 'approved').length;
          final rejectedCount =
              allLeaves.where((r) => r['status'] == 'rejected').length;

          final filteredLeaves = allLeaves.where((req) {
            final status = (req['status'] ?? 'pending').toString();
            if (_selectedStatusFilter != 'all' &&
                status != _selectedStatusFilter) {
              return false;
            }

            if (_searchQuery.isNotEmpty) {
              final q = _searchQuery.toLowerCase();
              final name = (req['delegateName'] ?? '').toString().toLowerCase();
              final phone =
                  (req['delegatePhone'] ?? '').toString().toLowerCase();
              final reason = (req['reason'] ?? '').toString().toLowerCase();
              if (!name.contains(q) &&
                  !phone.contains(q) &&
                  !reason.contains(q)) {
                return false;
              }
            }

            return true;
          }).toList();

          return Column(
            children: [
              // ── 1. Top KPI Summary Cards ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isWide = constraints.maxWidth >= 768;
                    final kpis = [
                      _buildKpiCard(
                        title: 'إجمالي الطلبات',
                        value: '${allLeaves.length}',
                        subtitle: 'طلبات مسجلة',
                        icon: Icons.event_note_rounded,
                        color: colorScheme.primary,
                        colorScheme: colorScheme,
                      ),
                      _buildKpiCard(
                        title: 'قيد المراجعة',
                        value: '$pendingCount',
                        subtitle: 'تحتاج إجراء من الإدارة',
                        icon: Icons.hourglass_top_rounded,
                        color: pendingCount > 0 ? HrStatusColors.of(context).warning : colorScheme.outline,
                        colorScheme: colorScheme,
                      ),
                      _buildKpiCard(
                        title: 'الإجازات المعتمدة',
                        value: '$approvedCount',
                        subtitle: 'إجازات مقبولة',
                        icon: Icons.check_circle_rounded,
                        color: HrStatusColors.of(context).success,
                        colorScheme: colorScheme,
                      ),
                      _buildKpiCard(
                        title: 'الطلبات المرفوضة',
                        value: '$rejectedCount',
                        subtitle: 'تم رفض الإجازة',
                        icon: Icons.cancel_outlined,
                        color: rejectedCount > 0 ? HrStatusColors.of(context).danger : colorScheme.outline,
                        colorScheme: colorScheme,
                      ),
                    ];

                    if (isWide) {
                      return IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: kpis.map((k) => Expanded(child: Padding(
                            padding: const EdgeInsets.symmetric(horizontal: 4),
                            child: k,
                          ))).toList(),
                        ),
                      );
                    }

                    // Web list-detail pane only (onSelectLeave set): 2-column grid.
                    if (widget.onSelectLeave != null) {
                      return GridView.count(
                        crossAxisCount: 2,
                        shrinkWrap: true,
                        physics: const NeverScrollableScrollPhysics(),
                        mainAxisSpacing: 8,
                        crossAxisSpacing: 8,
                        childAspectRatio: (constraints.maxWidth - 8) / 2 / 116,
                        children: kpis,
                      );
                    }

                    return SizedBox(
                      height: 116,
                      child: ListView.separated(
                        scrollDirection: Axis.horizontal,
                        itemCount: kpis.length,
                        separatorBuilder: (_, _) => const SizedBox(width: 8),
                        itemBuilder: (_, i) => SizedBox(width: 190, child: kpis[i]),
                      ),
                    );
                  },
                ),
              ),

              if (!widget.showAppBar) _leaveManagerActionRow(),

              // ── 2. Unified Single-Row Toolbar ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop =
                        constraints.maxWidth >= _toolbarRowMinWidth;

                    final searchWidget = SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(fontSize: HrFont.body, color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'بحث باسم المندوب أو رقم الهاتف أو العذر...',
                          hintStyle: TextStyle(
                            fontSize: HrFont.labelMedium,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                          ),
                          prefixIcon: Icon(
                            Icons.search_rounded,
                            size: 19,
                            color: colorScheme.primary,
                          ),
                          suffixIcon: _searchQuery.isNotEmpty
                              ? IconButton(
                                  icon: const Icon(Icons.clear_rounded, size: 16),
                                  onPressed: () {
                                    _searchController.clear();
                                    setState(() => _searchQuery = '');
                                  },
                                )
                              : null,
                          filled: true,
                          fillColor: colorScheme.surfaceContainerHigh,
                          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
                          isDense: true,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.pill),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.pill),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.pill),
                            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                          ),
                        ),
                      ),
                    );

                    final statusButtonGroup = TashilConnectedButtonGroup<String>(
                      height: 44.0,
                      isScrollable: true,
                      selectedValue: _selectedStatusFilter,
                      onSelected: (val) {
                        setState(() => _selectedStatusFilter = val);
                      },
                      items: [
                        TashilConnectedButtonItem<String>(
                          value: 'pending',
                          label: 'قيد المراجعة ($pendingCount)',
                          icon: Icons.hourglass_top_rounded,
                          activeColor: pendingCount > 0
                              ? HrStatusColors.of(context).warning
                              : colorScheme.primary,
                          activeForegroundColor: Colors.white,
                        ),
                        TashilConnectedButtonItem<String>(
                          value: 'approved',
                          label: 'المعتمدة ($approvedCount)',
                          icon: Icons.check_circle_rounded,
                          activeColor: HrStatusColors.of(context).success,
                          activeForegroundColor: Colors.white,
                        ),
                        TashilConnectedButtonItem<String>(
                          value: 'rejected',
                          label: 'المرفوضة ($rejectedCount)',
                          icon: Icons.cancel_outlined,
                          activeColor: colorScheme.outline,
                          activeForegroundColor: Colors.white,
                        ),
                        TashilConnectedButtonItem<String>(
                          value: 'all',
                          label: 'الكل (${allLeaves.length})',
                          icon: Icons.list_alt_rounded,
                        ),
                      ],
                    );

                    // Web: primary action lives in the toolbar (TAS-151).
                    final createButton = FilledButton.icon(
                      key: const ValueKey('hr_leaves_create_button'),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(0, 44),
                        padding: const EdgeInsets.symmetric(horizontal: 18),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(HrRadius.pill),
                        ),
                      ),
                      onPressed: _showCreateLeaveDialog,
                      icon: const Icon(Icons.add_task_rounded, size: 18),
                      label: const Text('تسجيل إجازة'),
                    );

                    final searchRow = web
                        ? Row(
                            children: [
                              Expanded(child: searchWidget),
                              const SizedBox(width: 12),
                              createButton,
                            ],
                          )
                        : searchWidget;

                    if (isDesktop) {
                      return Row(
                        children: [
                          Expanded(child: searchWidget),
                          const SizedBox(width: 12),
                          statusButtonGroup,
                          if (web && !widget.showAppBar) ...[
                            const SizedBox(width: 12),
                            _leaveManagerButton(inToolbar: true),
                          ],
                          if (web) ...[
                            const SizedBox(width: 12),
                            createButton,
                          ],
                        ],
                      );
                    }

                    // Web list-detail pane only (onSelectLeave set): wrap the tabs.
                    if (widget.onSelectLeave != null) {
                      final tabs = <(String, String, IconData)>[
                        ('pending', 'قيد المراجعة ($pendingCount)', Icons.hourglass_top_rounded),
                        ('approved', 'المعتمدة ($approvedCount)', Icons.check_circle_rounded),
                        ('rejected', 'المرفوضة ($rejectedCount)', Icons.cancel_outlined),
                        ('all', 'الكل (${allLeaves.length})', Icons.list_alt_rounded),
                      ];
                      return Column(
                        crossAxisAlignment: CrossAxisAlignment.stretch,
                        children: [
                          searchRow,
                          const SizedBox(height: 10),
                          Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: [
                              for (final t in tabs)
                                ChoiceChip(
                                  key: ValueKey('leave_tab_${t.$1}'),
                                  avatar: Icon(t.$3, size: 18),
                                  showCheckmark: false,
                                  label: Text(t.$2),
                                  selected: _selectedStatusFilter == t.$1,
                                  onSelected: (_) =>
                                      setState(() => _selectedStatusFilter = t.$1),
                                ),
                            ],
                          ),
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchRow,
                        const SizedBox(height: 10),
                        SingleChildScrollView(
                          scrollDirection: Axis.horizontal,
                          child: statusButtonGroup,
                        ),
                      ],
                    );
                  },
                ),
              ),
              const Divider(height: 1),
              Expanded(
                child: filteredLeaves.isEmpty
                    ? Center(
                        child: Column(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.event_busy_rounded,
                              size: 56,
                              color: colorScheme.outline.withValues(alpha: 0.5),
                            ),
                            const SizedBox(height: 12),
                            Text(
                              _searchQuery.isNotEmpty
                                  ? 'لا توجد نتائج مطابقة لبحثك'
                                  : 'لا توجد طلبات إجازات في هذا التبويب',
                              style: theme.textTheme.titleMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      )
                    : ListView.builder(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 12,
                        ),
                        itemCount: filteredLeaves.length,
                        itemBuilder: (context, index) {
                          final leave = filteredLeaves[index];
                          return _buildLeaveCard(
                            context,
                            leave,
                            theme,
                            colorScheme,
                          );
                        },
                      ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildLeaveCard(
    BuildContext context,
    Map<String, dynamic> leave,
    ThemeData theme,
    ColorScheme colorScheme, {
    bool forceExpanded = false,
    bool hideActions = false,
  }) {
    final docId = (leave['docId'] ?? '').toString();
    final itemKey = docId.isNotEmpty
        ? docId
        : '${leave['delegateUID']}_${leave['createdAt']}';
    final isExpanded =
        forceExpanded || _expandedLeaveDocIds.contains(itemKey);

    final status = (leave['status'] ?? 'pending').toString();
    final name = (leave['delegateName'] ?? 'مندوب').toString();
    final phone = (leave['delegatePhone'] ?? '').toString();
    final type = (leave['type'] ?? 'annual').toString();
    final reason = (leave['reason'] ?? '').toString();
    final rejectReason = (leave['rejectReason'] ?? '').toString();
    final daysCount = (leave['daysCount'] as num?)?.toInt() ?? 1;
    final isHourly = leave['isHourly'] == true;
    final hoursCount = (leave['hoursCount'] as num?)?.toDouble() ?? 0;
    // TAS-42: new requests carry the Storage path; old ones only a URL.
    final attachmentUrl = StorageMediaRef.pick(
      path: leave['attachmentPath'],
      url: leave['attachmentUrl'],
    );
    final fromTime = (leave['fromTime'] ?? '').toString();
    final toTime = (leave['toTime'] ?? '').toString();

    DateTime? startDate;
    if (leave['startDate'] is Timestamp) {
      startDate = (leave['startDate'] as Timestamp).toDate();
    }
    DateTime? endDate;
    if (leave['endDate'] is Timestamp) {
      endDate = (leave['endDate'] as Timestamp).toDate();
    }

    String dateRangeStr;
    if (isHourly) {
      final dStr = startDate != null
          ? DateFormat('yyyy-MM-dd').format(startDate)
          : '-';
      if (fromTime.isNotEmpty && toTime.isNotEmpty) {
        dateRangeStr = '$dStr ($fromTime إلى $toTime)';
      } else {
        dateRangeStr = '$dStr ($hoursCount ساعة)';
      }
    } else {
      dateRangeStr = (startDate != null && endDate != null)
          ? '${DateFormat('yyyy-MM-dd').format(startDate)} إلى ${DateFormat('yyyy-MM-dd').format(endDate)}'
          : (startDate != null
              ? DateFormat('yyyy-MM-dd').format(startDate)
              : '-');
    }

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (status == 'approved') {
      statusColor = HrStatusColors.of(context).success;
      statusLabel = 'معتمد';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      statusColor = colorScheme.error;
      statusLabel = 'مرفوض';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = HrStatusColors.of(context).warning;
      statusLabel = 'قيد المراجعة';
      statusIcon = Icons.hourglass_top_rounded;
    }

    String typeLabel;
    IconData typeIcon;
    switch (type) {
      case 'sick':
        typeLabel = 'إجازة مرضية';
        typeIcon = Icons.medical_services_outlined;
        break;
      case 'emergency':
        typeLabel = 'إجازة عارضة';
        typeIcon = Icons.flash_on_rounded;
        break;
      case 'delay':
        typeLabel = 'عذر تأخير';
        typeIcon = Icons.timer_outlined;
        break;
      case 'early_leave':
        typeLabel = 'إذن انصراف مبكر';
        typeIcon = Icons.logout_rounded;
        break;
      case 'absence':
        typeLabel = 'عذر غياب';
        typeIcon = Icons.person_off_outlined;
        break;
      case 'unpaid':
        typeLabel = 'إجازة بدون أجر';
        typeIcon = Icons.money_off_rounded;
        break;
      default:
        typeLabel = 'إجازة اعتيادية';
        typeIcon = Icons.beach_access_rounded;
        break;
    }

    final durationText = isHourly ? '$hoursCount ساعة' : '$daysCount يوم';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: status == 'pending'
              ? statusColor.withValues(alpha: 0.35)
              : colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: status == 'pending' ? 1.2 : 1.0,
        ),
      ),
      color: !forceExpanded && widget.selectedLeaveKey == itemKey
          ? colorScheme.secondaryContainer
          : colorScheme.surface,
      child: InkWell(
        borderRadius: BorderRadius.circular(HrRadius.card),
        onTap: () {
          final onSelect = widget.onSelectLeave;
          if (onSelect != null && !forceExpanded) {
            onSelect(HRLeaveSelection(
              key: itemKey,
              delegateName: name,
              isPending: status == 'pending',
              approve: () => _approveLeave(leave),
              reject: () => _rejectLeave(leave),
              buildDetail: (ctx) => _buildLeaveCard(
                ctx,
                leave,
                Theme.of(ctx),
                Theme.of(ctx).colorScheme,
                forceExpanded: true,
                hideActions: true,
              ),
            ));
            return;
          }
          setState(() {
            if (_expandedLeaveDocIds.contains(itemKey)) {
              _expandedLeaveDocIds.remove(itemKey);
            } else {
              _expandedLeaveDocIds.add(itemKey);
            }
          });
        },
        child: AnimatedSize(
          duration: AppMotionDurations.short3,
          curve: AppMotionCurves.standard,
          alignment: Alignment.topCenter,
          child: Padding(
            padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 11),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Always Visible Compact Content
                Row(
                  children: [
                    AppAvatar(
                      fallbackText: name,
                      radius: 19,
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Flexible(
                                child: Text(
                                  name,
                                  style: theme.textTheme.titleSmall?.copyWith(
                                    fontWeight: FontWeight.bold,
                                    fontSize: HrFont.body,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              if (phone.isNotEmpty) ...[
                                const SizedBox(width: 6),
                                Directionality(
                                  textDirection: TextDirection.ltr,
                                  child: Text(
                                    phone,
                                    style: theme.textTheme.bodySmall?.copyWith(
                                      color: colorScheme.onSurfaceVariant,
                                      fontSize: HrFont.labelSmall,
                                    ),
                                  ),
                                ),
                              ],
                            ],
                          ),
                          const SizedBox(height: 3),
                          // Compact leave type, period and duration
                          Row(
                            children: [
                              Icon(
                                typeIcon,
                                size: 12,
                                color: colorScheme.primary,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                typeLabel,
                                style: TextStyle(
                                  fontSize: HrFont.labelSmall,
                                  fontWeight: FontWeight.bold,
                                  color: colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Text(
                                '•',
                                style: TextStyle(
                                  fontSize: HrFont.labelSmall,
                                  color: colorScheme.outline,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Expanded(
                                child: Text(
                                  dateRangeStr,
                                  style: TextStyle(
                                    fontSize: HrFont.labelSmall,
                                    color: colorScheme.onSurfaceVariant,
                                    fontWeight: FontWeight.w500,
                                  ),
                                  maxLines: 1,
                                  overflow: TextOverflow.ellipsis,
                                ),
                              ),
                              const SizedBox(width: 6),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 6,
                                  vertical: 1.5,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerHighest
                                      .withValues(alpha: 0.6),
                                  borderRadius: BorderRadius.circular(6),
                                  border: Border.all(
                                    color: colorScheme.outlineVariant
                                        .withValues(alpha: 0.4),
                                  ),
                                ),
                                child: Text(
                                  durationText,
                                  style: const TextStyle(
                                    fontSize: HrFont.labelSmall,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(width: 8),
                    // Trailing: Status Badge + Expand/Collapse Indicator
                    Column(
                      crossAxisAlignment: CrossAxisAlignment.end,
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 8,
                            vertical: 3,
                          ),
                          decoration: BoxDecoration(
                            color: statusColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(HrRadius.chip),
                            border: Border.all(
                              color: statusColor.withValues(alpha: 0.3),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(statusIcon, size: 11, color: statusColor),
                              const SizedBox(width: 4),
                              Text(
                                statusLabel,
                                style: TextStyle(
                                  color: statusColor,
                                  fontSize: HrFont.labelSmall,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ],
                          ),
                        ),
                        const SizedBox(height: 3),
                        Icon(
                          isExpanded
                              ? Icons.keyboard_arrow_up_rounded
                              : Icons.keyboard_arrow_down_rounded,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                      ],
                    ),
                  ],
                ),

                // Expanded Section: Details, Reason, Attachments, Actions
                if (isExpanded) ...[
                  const SizedBox(height: 8),
                  const Divider(height: 1),
                  const SizedBox(height: 8),

                  // Reason
                  if (reason.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHighest
                            .withValues(alpha: 0.2),
                        borderRadius: BorderRadius.circular(HrRadius.chip),
                      ),
                      child: Text(
                        'السبب: $reason',
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Reject Reason (if rejected)
                  if (rejectReason.isNotEmpty) ...[
                    Container(
                      width: double.infinity,
                      padding: const EdgeInsets.symmetric(
                        horizontal: 10,
                        vertical: 6,
                      ),
                      decoration: BoxDecoration(
                        color: colorScheme.errorContainer.withValues(alpha: 0.25),
                        borderRadius: BorderRadius.circular(HrRadius.chip),
                        border: Border.all(
                          color: colorScheme.error.withValues(alpha: 0.3),
                        ),
                      ),
                      child: Text(
                        'سبب الرفض: $rejectReason',
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          color: colorScheme.error,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Attachment Button
                  if (attachmentUrl.isNotEmpty) ...[
                    Align(
                      alignment: AlignmentDirectional.centerStart,
                      child: OutlinedButton.icon(
                        style: OutlinedButton.styleFrom(
                          visualDensity: VisualDensity.compact,
                          padding: const EdgeInsets.symmetric(
                            horizontal: 10,
                            vertical: 4,
                          ),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(HrRadius.chip),
                          ),
                        ),
                        icon: const Icon(Icons.attachment_rounded, size: 15),
                        label: const Text(
                          'معاينة المرفق (تقرير / مستند)',
                          style: TextStyle(fontSize: HrFont.labelSmall),
                        ),
                        onPressed: () => _viewAttachment(context, attachmentUrl),
                      ),
                    ),
                    const SizedBox(height: 6),
                  ],

                  // Pending Actions (Approve / Reject)
                  if (status == 'pending' && !hideActions) ...[
                    const SizedBox(height: 4),
                    Row(
                      children: [
                        Expanded(
                          child: OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              foregroundColor: colorScheme.error,
                              side: BorderSide(
                                color: colorScheme.error.withValues(alpha: 0.5),
                              ),
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                              ),
                            ),
                            onPressed: () => _rejectLeave(leave),
                            icon: const Icon(Icons.close_rounded, size: 16),
                            label: const Text(
                              'رفض',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: HrFont.labelMedium,
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          flex: 2,
                          child: FilledButton.icon(
                            style: FilledButton.styleFrom(
                              backgroundColor: HrStatusColors.of(context).success,
                              foregroundColor: Colors.white,
                              padding: const EdgeInsets.symmetric(vertical: 8),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                              ),
                            ),
                            onPressed: () => _approveLeave(leave),
                            icon: const Icon(Icons.check_circle_rounded, size: 16),
                            label: const Text(
                              'اعتماد الإجازة',
                              style: TextStyle(
                                fontWeight: FontWeight.bold,
                                fontSize: HrFont.labelMedium,
                              ),
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }

  /// Web-only dropdown for the create dialog (TAS-151). The menu matches the
  /// field width and has a capped height, so it stays inside the dialog.
  Widget _dialogWebDropdown<T>({
    required Key key,
    required T? initialSelection,
    required List<DropdownMenuEntry<T>> entries,
    required ValueChanged<T?> onSelected,
    required TextStyle textStyle,
    required ColorScheme colorScheme,
  }) {
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(HrRadius.chip),
      borderSide: BorderSide(
        color: colorScheme.outlineVariant.withValues(alpha: 0.6),
      ),
    );
    return DropdownMenu<T>(
      key: key,
      initialSelection: initialSelection,
      expandedInsets: EdgeInsets.zero,
      requestFocusOnTap: false,
      menuHeight: kHrLeaveDialogMenuHeight,
      textStyle: textStyle,
      dropdownMenuEntries: entries,
      onSelected: onSelected,
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        contentPadding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
        border: border,
        enabledBorder: border,
      ),
    );
  }

  Future<void> _showCreateLeaveDialog() async {
    if (_companyDelegates.isEmpty) {
      await _loadCompanyDelegates();
    }

    Delegate? selectedDelegate =
        _companyDelegates.isNotEmpty ? _companyDelegates.first : null;
    String selectedType = 'annual';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();
    final reasonCtrl = TextEditingController();

    if (!mounted) return;

    await showDialog(
      context: context,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final days = endDate.difference(startDate).inDays + 1;
          final colorScheme = Theme.of(context).colorScheme;
          // Web uses the M3 type scale (never below 12); mobile keeps its
          // original sizes (TAS-151).
          final web = WebRuntimePolicy.isWeb;
          final textTheme = Theme.of(context).textTheme;
          final fieldLabelStyle = web
              ? textTheme.labelLarge!.copyWith(
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                )
              : TextStyle(
                  fontSize: HrFont.labelMedium,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurface,
                );
          final fieldTextStyle = web
              ? textTheme.bodyMedium!.copyWith(
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                )
              : TextStyle(
                  fontSize: HrFont.labelMedium,
                  color: colorScheme.onSurface,
                  fontWeight: FontWeight.w500,
                );
          final captionStyle = web
              ? textTheme.labelMedium!
              : const TextStyle(fontSize: HrFont.labelSmall);
          final valueStyle = web
              ? textTheme.bodyMedium!.copyWith(fontWeight: FontWeight.bold)
              : const TextStyle(
                  fontSize: HrFont.labelMedium,
                  fontWeight: FontWeight.bold,
                );
          final buttonTextStyle = web
              ? textTheme.labelLarge!
              : const TextStyle(fontSize: HrFont.labelMedium);

          return Dialog(
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HrRadius.button),
              side: BorderSide(
                color: colorScheme.outlineVariant.withValues(alpha: 0.5),
              ),
            ),
            insetPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 24),
            clipBehavior: Clip.antiAlias,
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 440),
              child: Column(
                mainAxisSize: MainAxisSize.min,
                crossAxisAlignment: CrossAxisAlignment.stretch,
                children: [
                  // Dialog Header
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 14, 16, 12),
                    child: Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.all(7),
                          decoration: BoxDecoration(
                            color: colorScheme.primary.withValues(alpha: 0.12),
                            borderRadius: BorderRadius.circular(HrRadius.chip),
                          ),
                          child: Icon(
                            Icons.edit_calendar_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'تسجيل إجازة / عذر غياب جديد',
                            style: TextStyle(
                              fontSize: HrFont.titleMedium,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(HrRadius.button),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Icons.close_rounded,
                              size: 20,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ),
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),

                  // Dialog Body
                  Flexible(
                    child: SingleChildScrollView(
                      padding: const EdgeInsets.fromLTRB(16, 14, 16, 14),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Text(
                            'المندوب:',
                            style: fieldLabelStyle,
                          ),
                          const SizedBox(height: 6),
                          if (web)
                            _dialogWebDropdown<Delegate>(
                              key: const ValueKey('hr_leave_delegate_menu'),
                              initialSelection: selectedDelegate,
                              entries: [
                                for (final d in _companyDelegates)
                                  DropdownMenuEntry(value: d, label: d.fullName),
                              ],
                              onSelected: (val) =>
                                  setDlgState(() => selectedDelegate = val),
                              textStyle: fieldTextStyle,
                              colorScheme: colorScheme,
                            )
                          else
                          DropdownButtonFormField<Delegate>(
                            initialValue: selectedDelegate,
                            isExpanded: true,
                            style: fieldTextStyle,
                            items: _companyDelegates
                                .map((d) => DropdownMenuItem(
                                      value: d,
                                      child: Text(d.fullName),
                                    ))
                                .toList(),
                            onChanged: (val) => setDlgState(() => selectedDelegate = val),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'نوع الطلب:',
                            style: fieldLabelStyle,
                          ),
                          const SizedBox(height: 6),
                          if (web)
                            _dialogWebDropdown<String>(
                              key: const ValueKey('hr_leave_type_menu'),
                              initialSelection: selectedType,
                              entries: const [
                                DropdownMenuEntry(
                                    value: 'annual', label: 'إجازة اعتيادية'),
                                DropdownMenuEntry(
                                    value: 'sick', label: 'إجازة مرضية'),
                                DropdownMenuEntry(
                                    value: 'emergency', label: 'إجازة عارضة'),
                                DropdownMenuEntry(
                                    value: 'unpaid', label: 'إجازة بدون أجر'),
                                DropdownMenuEntry(
                                    value: 'delay', label: 'عذر تأخير'),
                                DropdownMenuEntry(
                                    value: 'absence', label: 'عذر غياب'),
                              ],
                              onSelected: (val) =>
                                  setDlgState(() => selectedType = val ?? 'annual'),
                              textStyle: fieldTextStyle,
                              colorScheme: colorScheme,
                            )
                          else
                          DropdownButtonFormField<String>(
                            initialValue: selectedType,
                            isExpanded: true,
                            style: fieldTextStyle,
                            items: const [
                              DropdownMenuItem(
                                  value: 'annual', child: Text('إجازة اعتيادية')),
                              DropdownMenuItem(
                                  value: 'sick', child: Text('إجازة مرضية')),
                              DropdownMenuItem(
                                  value: 'emergency', child: Text('إجازة عارضة')),
                              DropdownMenuItem(
                                  value: 'unpaid', child: Text('إجازة بدون أجر')),
                              DropdownMenuItem(
                                  value: 'delay', child: Text('عذر تأخير')),
                              DropdownMenuItem(
                                  value: 'absence', child: Text('عذر غياب')),
                            ],
                            onChanged: (val) =>
                                setDlgState(() => selectedType = val ?? 'annual'),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                          ),
                          const SizedBox(height: 12),
                          // Connected Date Range Button Group
                          Row(
                            children: [
                              Text(
                                'الفترة بالأيام:',
                                style: fieldLabelStyle,
                              ),
                              const Spacer(),
                              Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 8,
                                  vertical: 2,
                                ),
                                decoration: BoxDecoration(
                                  color: colorScheme.primary.withValues(alpha: 0.1),
                                  borderRadius: BorderRadius.circular(6),
                                ),
                                child: Text(
                                  'المدة: $days ${days == 1 ? 'يوم' : 'أيام'}',
                                  style: captionStyle.copyWith(
                                    fontWeight: FontWeight.bold,
                                    color: colorScheme.primary,
                                  ),
                                ),
                              ),
                            ],
                          ),
                          const SizedBox(height: 6),
                          Container(
                            decoration: BoxDecoration(
                              color: colorScheme.surfaceContainerLow,
                              borderRadius: BorderRadius.circular(HrRadius.chip),
                              border: Border.all(
                                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                              ),
                            ),
                            child: Row(
                              children: [
                                // من تاريخ
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: startDate,
                                        firstDate: DateTime(2024),
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDlgState(() {
                                          startDate = picked;
                                          if (endDate.isBefore(startDate)) {
                                            endDate = startDate;
                                          }
                                        });
                                      }
                                    },
                                    borderRadius: const BorderRadius.horizontal(
                                      right: Radius.circular(9),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.calendar_today_rounded,
                                            size: 15,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'من تاريخ',
                                                  style: captionStyle.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  DateFormat('dd-MM-yyyy').format(startDate),
                                                  style: valueStyle,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                                Container(
                                  width: 1,
                                  height: 28,
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                                // إلى تاريخ
                                Expanded(
                                  child: InkWell(
                                    onTap: () async {
                                      final picked = await showDatePicker(
                                        context: context,
                                        initialDate: endDate,
                                        firstDate: startDate,
                                        lastDate: DateTime(2030),
                                      );
                                      if (picked != null) {
                                        setDlgState(() => endDate = picked);
                                      }
                                    },
                                    borderRadius: const BorderRadius.horizontal(
                                      left: Radius.circular(9),
                                    ),
                                    child: Padding(
                                      padding: const EdgeInsets.symmetric(
                                        horizontal: 10,
                                        vertical: 8,
                                      ),
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.event_available_rounded,
                                            size: 15,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 8),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisSize: MainAxisSize.min,
                                              children: [
                                                Text(
                                                  'إلى تاريخ',
                                                  style: captionStyle.copyWith(
                                                    fontWeight: FontWeight.w600,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                ),
                                                const SizedBox(height: 1),
                                                Text(
                                                  DateFormat('dd-MM-yyyy').format(endDate),
                                                  style: valueStyle,
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ),
                              ],
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'سبب الطلب:',
                            style: fieldLabelStyle,
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: reasonCtrl,
                            style: web
                                ? textTheme.bodyMedium
                                : const TextStyle(fontSize: HrFont.labelMedium),
                            decoration: InputDecoration(
                              hintText: 'اكتب السبب باختصار...',
                              hintStyle: captionStyle.copyWith(
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(HrRadius.chip),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            maxLines: 2,
                          ),
                        ],
                      ),
                    ),
                  ),

                  // Footer: Buttons Group
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Row(
                      children: [
                        // إلغاء
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(HrRadius.chip),
                                ),
                                side: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.7),
                                ),
                                foregroundColor: colorScheme.onSurfaceVariant,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () => Navigator.pop(ctx),
                              icon: const Icon(Icons.close_rounded, size: 16),
                              label: Text(
                                'إلغاء',
                                style: buttonTextStyle.copyWith(
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // حفظ واعتماد
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(HrRadius.chip),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: () async {
                                if (selectedDelegate == null) return;
                                final messenger = ScaffoldMessenger.of(context);
                                final successColor = HrStatusColors.of(context).success;
                                final days = endDate.difference(startDate).inDays + 1;
                                final mayRecord = await _leaveOverlapGate(
                                  delegateUid: selectedDelegate!.uid,
                                  candidate: LeaveSpan(
                                    id: '',
                                    type: selectedType,
                                    isHourly: false,
                                    status: 'approved',
                                    start: DateTime(startDate.year, startDate.month, startDate.day),
                                    end: DateTime(endDate.year, endDate.month, endDate.day),
                                  ),
                                );
                                if (!mayRecord) return;
                                final docRef = FirebaseFirestore.instance
                                    .collection('leave_requests')
                                    .doc();

                                await docRef.set({
                                  'id': docRef.id,
                                  'delegateUid': selectedDelegate!.uid,
                                  'delegateName': selectedDelegate!.fullName,
                                  'delegatePhone': selectedDelegate!.phoneNumber,
                                  'companyUID': widget.hrDelegate.companyUID,
                                  'organizationUID': widget.hrDelegate.organizationUID,
                                  'type': selectedType,
                                  'startDate': Timestamp.fromDate(startDate),
                                  'endDate': Timestamp.fromDate(endDate),
                                  'daysCount': days,
                                  'reason': reasonCtrl.text.trim(),
                                  'status': 'approved', // Created by HR is approved directly
                                  'createdAt': FieldValue.serverTimestamp(),
                                  'resolvedAt': FieldValue.serverTimestamp(),
                                  'resolvedBy': widget.hrDelegate.uid,
                                  'resolvedByName': widget.hrDelegate.fullName,
                                });

                                if (ctx.mounted) Navigator.pop(ctx);
                                if (mounted) {
                                  messenger.showSnackBar(
                                    SnackBar(
                                      content: Text('تم تسجيل واعتماد الإجازة بنجاح'),
                                      backgroundColor: successColor,
                                    ),
                                  );
                                }
                              },
                              icon: const Icon(Icons.check_rounded, size: 16),
                              label: Text(
                                'حفظ واعتماد',
                                style: buttonTextStyle.copyWith(
                                  fontWeight: FontWeight.bold,
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
        },
      ),
    );
  }

  static String _hrLeaveTypeLabel(String type) => switch (type) {
    'sick' => 'إجازة مرضية',
    'emergency' => 'إجازة عارضة',
    'delay' => 'عذر تأخير',
    'early_leave' => 'إذن انصراف مبكر',
    'absence' => 'عذر غياب',
    'unpaid' => 'إجازة بدون أجر',
    _ => 'إجازة اعتيادية',
  };

  /// TAS-370 (user decision 2026-11-27): before HR approves or records a
  /// leave, look for another live leave of the same delegate on the same
  /// days. An approved one blocks (payroll would count the days twice); a
  /// pending one only warns. Returns true when HR may go on.
  Future<bool> _leaveOverlapGate({
    required String delegateUid,
    required LeaveSpan candidate,
  }) async {
    final List<LeaveSpan> existing;
    try {
      existing = await LeaveOverlap.loadForDelegate(
        widget.firestore ?? FirebaseFirestore.instance,
        companyUID: widget.hrDelegate.companyUID,
        delegateUid: delegateUid,
      );
    } catch (_) {
      // A failed read never blocks HR; the decision stays theirs.
      return true;
    }
    final conflict = LeaveOverlap.find(candidate, existing);
    if (conflict == null || !mounted) return true;
    final fmt = DateFormat('yyyy-MM-dd');
    final from = Bidi.ltr(fmt.format(conflict.start));
    final to = Bidi.ltr(fmt.format(conflict.end));
    final label = _hrLeaveTypeLabel(conflict.type);
    if (conflict.isApproved) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text(
            'لا يمكن الاعتماد: توجد $label معتمدة لنفس المندوب من $from إلى $to.',
          ),
        ),
      );
      return false;
    }
    final go = await showTashilDialog<bool>(
      context: context,
      builder: (c) => AlertDialog(
        title: const Text('يوجد طلب آخر على نفس الأيام'),
        content: Text(
          'يوجد طلب $label قيد المراجعة لنفس المندوب من $from إلى $to. '
          'هل تريد الاعتماد على أي حال؟',
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(c, false),
            child: const Text('رجوع'),
          ),
          TextButton(
            key: const Key('leaveOverlapApproveAnyway'),
            onPressed: () => Navigator.pop(c, true),
            child: const Text('اعتماد'),
          ),
        ],
      ),
    );
    return go ?? false;
  }

  Future<void> _approveLeave(Map<String, dynamic> leave) async {
    final docId = leave['docId']?.toString() ?? '';
    final delegateUid = leave['delegateUid']?.toString() ?? '';
    final delegateName = leave['delegateName']?.toString() ?? '';

    final candidate = LeaveSpan.fromMap(docId, leave);
    if (candidate != null &&
        !await _leaveOverlapGate(
          delegateUid: delegateUid,
          candidate: candidate,
        )) {
      return;
    }

    try {
      await FirebaseFirestore.instance
          .collection('leave_requests')
          .doc(docId)
          .update({
        'status': 'approved',
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': widget.hrDelegate.uid,
        'resolvedByName': widget.hrDelegate.fullName,
      });

      // إرسال إشعار للمندوب
      await FirebaseFirestore.instance.collection('notifications').add({
        'delegateUid': delegateUid,
        'companyUID': widget.hrDelegate.companyUID,
        'organizationUID': widget.hrDelegate.organizationUID,
        'title': 'تمت الموافقة على طلب الإجازة / العذر',
        'body': 'تم اعتماد طلبك من قِبل إدارة الشركة (${widget.hrDelegate.companyName}).',
        'type': 'leave_approved',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.hrDelegate.uid,
        'senderName': widget.hrDelegate.fullName,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم اعتماد طلب الإجازة لـ "$delegateName" بنجاح'),
            backgroundColor: HrStatusColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في اعتماد الإجازة: $e')),
        );
      }
    }
  }

  Future<void> _rejectLeave(Map<String, dynamic> leave) async {
    final docId = leave['docId']?.toString() ?? '';
    final delegateUid = leave['delegateUid']?.toString() ?? '';
    final delegateName = leave['delegateName']?.toString() ?? '';
    final reasonCtrl = TextEditingController();

    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('رفض طلب الإجازة / العذر'),
        content: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Text('هل أنت متأكد من رفض طلب "$delegateName"؟'),
            const SizedBox(height: 10),
            TextField(
              controller: reasonCtrl,
              decoration: const InputDecoration(
                labelText: 'سبب الرفض',
                border: OutlineInputBorder(),
              ),
            ),
          ],
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('تأكيد الرفض'),
          ),
        ],
      ),
    );

    if (confirm != true || !mounted) return;

    try {
      await FirebaseFirestore.instance
          .collection('leave_requests')
          .doc(docId)
          .update({
        'status': 'rejected',
        'rejectReason': reasonCtrl.text.trim(),
        'resolvedAt': FieldValue.serverTimestamp(),
        'resolvedBy': widget.hrDelegate.uid,
        'resolvedByName': widget.hrDelegate.fullName,
      });

      await FirebaseFirestore.instance.collection('notifications').add({
        'delegateUid': delegateUid,
        'companyUID': widget.hrDelegate.companyUID,
        'organizationUID': widget.hrDelegate.organizationUID,
        'title': 'تم رفض طلب الإجازة / العذر',
        'body': 'تم رفض طلبك: ${reasonCtrl.text.trim()}',
        'type': 'leave_rejected',
        'isRead': false,
        'createdAt': FieldValue.serverTimestamp(),
        'createdBy': widget.hrDelegate.uid,
        'senderName': widget.hrDelegate.fullName,
      });

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('تم رفض طلب إجازة "$delegateName"')),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في رفض الطلب: $e')),
        );
      }
    }
  }

  // ── معاينة المرفق بدقة عالية ──
  void _viewAttachment(BuildContext context, String url) {
    showDialog(
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
                  const Text(
                    'مرفق الطلب',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.titleMedium),
                  ),
                  IconButton(
                    icon: const Icon(Icons.close_rounded),
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
                  errorBuilder: (_, _, _) => const SizedBox(
                    height: 160,
                    child: Center(
                      child: Text('فشل في تحميل صورة المرفق'),
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

  Widget _buildKpiCard({
    required String title,
    required String value,
    required String subtitle,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: HrFont.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 6),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: HrFont.titleMedium,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: HrFont.labelSmall,
              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }
}


/// A request selected in the desktop list-detail layout. [approve]/[reject]
/// call the screen's existing actions unchanged.
class HRLeaveSelection {
  final String key;
  final String delegateName;
  final bool isPending;
  final Future<void> Function() approve;
  final Future<void> Function() reject;
  final WidgetBuilder buildDetail;

  const HRLeaveSelection({
    required this.key,
    required this.delegateName,
    required this.isPending,
    required this.approve,
    required this.reject,
    required this.buildDetail,
  });
}

/// Public detail pane for one leave/excuse request: header with approve
/// (filled) / reject (outlined), then the request's full details.
class HRLeaveDetailView extends StatelessWidget {
  final HRLeaveSelection selection;
  final VoidCallback? onActionDone;

  const HRLeaveDetailView({
    super.key,
    required this.selection,
    this.onActionDone,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Padding(
          padding: const EdgeInsets.fromLTRB(24, 20, 24, 12),
          child: Row(
            children: [
              Expanded(
                child: Text(
                  selection.delegateName,
                  style: Theme.of(context).textTheme.titleLarge?.copyWith(
                        color: cs.onSurface,
                        fontWeight: FontWeight.bold,
                      ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (selection.isPending) ...[
                OutlinedButton.icon(
                  onPressed: () async {
                    await selection.reject();
                    onActionDone?.call();
                  },
                  icon: const Icon(Symbols.close_rounded),
                  label: const Text('رفض'),
                ),
                const SizedBox(width: 8),
                FilledButton.icon(
                  onPressed: () async {
                    await selection.approve();
                    onActionDone?.call();
                  },
                  icon: const Icon(Symbols.check_circle_rounded),
                  label: const Text('اعتماد الإجازة'),
                ),
              ],
            ],
          ),
        ),
        const Divider(height: 1),
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.all(24),
            child: selection.buildDetail(context),
          ),
        ),
      ],
    );
  }
}
