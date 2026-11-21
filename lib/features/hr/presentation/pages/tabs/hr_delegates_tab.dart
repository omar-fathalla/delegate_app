import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:url_launcher/url_launcher.dart';

import 'package:delegate_app/core/platform/web_runtime_policy.dart';

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_home_screen.dart'
    show openAdminHomeAddDelegate;
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';

enum HRDelegatesViewMode { table, cards }

/// Web breakpoints of the «مناديب الشركة» page (MD3 Model 3).
class HRDelegatesWebBreakpoints {
  HRDelegatesWebBreakpoints._();

  /// Below this viewport width the table becomes cards.
  static const double cardsBelow = 840;

  /// Below this table width the ID/phone and name/city columns merge.
  static const double mergedColumnsBelow = 1080;
}

/// Row/card actions in the web «⋮» menu.
enum _DelegateAction { profile, attendance, leaves }

class HRDelegatesTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRDelegatesTab({super.key, required this.hrDelegate});

  /// Web primary button «إضافة مندوب».
  static const addDelegateKey = Key('hr_delegates_add_delegate');

  /// Web search bar (56 high).
  static const searchKey = Key('hr_delegates_search');

  /// Web view toggle «بطاقات/جدول».
  static const viewToggleKey = Key('hr_delegates_view_toggle');

  /// Web status filter chips (null = all).
  static Key filterKey(DelegateStatus? status) =>
      Key('hr_delegates_filter_${status?.name ?? 'all'}');

  /// Tests replace the add-delegate navigation (the form needs the full DI).
  @visibleForTesting
  static void Function(BuildContext context, Delegate supervisor)?
  debugOpenAddDelegate;

  /// Tests replace the profile navigation (the profile needs the full DI).
  @visibleForTesting
  static void Function(Delegate delegate)? debugOpenProfile;

  @override
  State<HRDelegatesTab> createState() => _HRDelegatesTabState();
}

class _HRDelegatesTabState extends State<HRDelegatesTab> {
  final TextEditingController _searchController = TextEditingController();
  final ScrollController _hScrollCtrl = ScrollController();
  final ScrollController _vScrollCtrl = ScrollController();
  DelegateStatus? _selectedStatus;
  HRDelegatesViewMode _viewMode = HRDelegatesViewMode.table;
  late AdminDelegatesBloc _delegatesBloc;

  @override
  void initState() {
    super.initState();
    _viewMode = HRDelegatesViewMode.table;
    _delegatesBloc = di.sl<AdminDelegatesBloc>();
    _loadDelegates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    _hScrollCtrl.dispose();
    _vScrollCtrl.dispose();
    _delegatesBloc.close();
    super.dispose();
  }

  void _loadDelegates() {
    AdminDelegatesBloc.clearCache();
    _delegatesBloc.add(
      LoadCompanyDelegates(
        organizationUID: widget.hrDelegate.organizationUID,
        companyUID: widget.hrDelegate.companyUID,
      ),
    );
  }

  void _callPhone(String phone) async {
    if (phone.isEmpty) return;
    final uri = Uri.parse('tel:$phone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri);
    }
  }

  void _openWhatsApp(String phone) async {
    if (phone.isEmpty) return;
    var cleanPhone = phone.replaceAll(RegExp(r'\D'), '');
    if (cleanPhone.startsWith('0')) {
      cleanPhone = '20${cleanPhone.substring(1)}';
    }
    final uri = Uri.parse('https://wa.me/$cleanPhone');
    if (await canLaunchUrl(uri)) {
      await launchUrl(uri, mode: LaunchMode.externalApplication);
    }
  }

  void _copyNationalId(String nationalId) {
    if (nationalId.isEmpty) return;
    Clipboard.setData(ClipboardData(text: nationalId));
    AppSnackBar.showSuccess(context, 'تم نسخ الرقم القومي بنجاح');
  }

  void _copyPhoneNumber(String phone) {
    if (phone.isEmpty) return;
    Clipboard.setData(ClipboardData(text: phone));
    AppSnackBar.showSuccess(context, 'تم نسخ رقم الهاتف بنجاح');
  }

  void _openProfile(Delegate delegate, {int initialTabIndex = 0}) {
    final hook = HRDelegatesTab.debugOpenProfile;
    if (hook != null) return hook(delegate);
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => BlocProvider(
          create: (_) => di.sl<ProfileBloc>(),
          child: ProfileScreen(
            delegate: delegate,
            showBackButton: true,
            initialTabIndex: initialTabIndex,
          ),
        ),
      ),
    );
  }

  /// Chain names the delegate is on, from the loaded delegate (primary chain
  /// plus allOrganizationNames), case-insensitively unique. No extra reads.
  List<String> _chainNames(Delegate delegate) {
    final seen = <String>{};
    return [
      for (final n in [
        delegate.organizationName,
        ...delegate.allOrganizationNames,
      ])
        if (n.trim().isNotEmpty && seen.add(n.trim().toLowerCase())) n.trim(),
    ];
  }

  int _chainCount(Delegate delegate) {
    final names = _chainNames(delegate);
    if (names.isEmpty && delegate.organizationUID.trim().isNotEmpty) return 1;
    return names.length;
  }

  /// Web chains cell: plain text (icon + count), not a button. The chain
  /// names show on hover.
  Widget _buildWebChains(Delegate delegate, ColorScheme colorScheme) {
    final count = _chainCount(delegate);
    final names = _chainNames(delegate);
    return Tooltip(
      message: names.isEmpty
          ? 'مرتبط بـ $count سلسلة'
          : 'السلاسل: ${names.join('، ')}',
      child: Row(
        key: Key('hr_delegate_chains_${delegate.uid}'),
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Symbols.storefront_rounded,
            size: 16,
            color: colorScheme.onSurfaceVariant,
          ),
          const SizedBox(width: 4),
          Text('$count', style: hrTabularStyle(context)),
        ],
      ),
    );
  }

  /// Web row/card actions (TAS-115, TAS-144): one «⋮» menu with labels.
  Widget _buildWebActionsMenu(Delegate delegate) {
    PopupMenuItem<_DelegateAction> item(
      _DelegateAction action,
      IconData icon,
      String label,
    ) => PopupMenuItem<_DelegateAction>(
      key: Key('hr_delegate_menu_${action.name}'),
      value: action,
      child: Row(
        children: [
          Icon(icon, size: 20),
          const SizedBox(width: 12),
          Text(label, style: const TextStyle(fontSize: HrFont.body)),
        ],
      ),
    );

    return PopupMenuButton<_DelegateAction>(
      key: Key('hr_delegate_actions_${delegate.uid}'),
      tooltip: 'إجراءات المندوب',
      icon: const Icon(Icons.more_vert_rounded),
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
      ),
      onSelected: (action) {
        switch (action) {
          case _DelegateAction.profile:
            _openProfile(delegate);
          case _DelegateAction.attendance:
            _openAttendance(delegate);
          case _DelegateAction.leaves:
            _showAnnualLeaveManagementDialog(delegate);
        }
      },
      itemBuilder: (_) => [
        item(_DelegateAction.profile, Icons.person_rounded, 'عرض الملف'),
        item(
          _DelegateAction.attendance,
          Symbols.fact_check_rounded,
          'سجل الحضور والانصراف',
        ),
        item(
          _DelegateAction.leaves,
          delegate.isAnnualLeaveEnabled
              ? Symbols.beach_access_rounded
              : Symbols.event_repeat_rounded,
          delegate.isAnnualLeaveEnabled
              ? 'نظام الإجازات: سنوية'
              : 'نظام الإجازات: أسبوعية',
        ),
      ],
    );
  }

  void _openAddDelegate() {
    final open = HRDelegatesTab.debugOpenAddDelegate ?? openAdminHomeAddDelegate;
    open(context, widget.hrDelegate);
  }

  void _openAttendance(Delegate delegate) {
    openHrDelegateAttendanceDetail(
      context,
      delegate: delegate,
      hrDelegate: widget.hrDelegate,
    );
  }

  /// Leave dialog notes: never below 12 on the web (TAS-144); mobile keeps
  /// M3 labelSmall.
  static double get _dialogNoteSize =>
      WebRuntimePolicy.isWeb ? HrFont.labelMedium : HrFont.labelSmall;

  Future<void> _showAnnualLeaveManagementDialog(Delegate delegate) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    bool isEnabled = delegate.isAnnualLeaveEnabled;
    int quota = delegate.annualLeaveQuota > 0 ? delegate.annualLeaveQuota : 21;
    bool isSaving = false;

    await showDialog(
      context: context,
      barrierDismissible: !isSaving,
      builder: (ctx) => StatefulBuilder(
        builder: (dialogContext, setDialogState) {
          return AlertDialog(
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(HrRadius.button),
            ),
            titlePadding: const EdgeInsets.fromLTRB(20, 20, 20, 12),
            contentPadding: const EdgeInsets.symmetric(horizontal: 20),
            actionsPadding: const EdgeInsets.fromLTRB(20, 12, 20, 16),
            title: Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(8),
                  decoration: BoxDecoration(
                    color: isEnabled
                        ? HrStatusColors.of(
                            context,
                          ).success.withValues(alpha: 0.12)
                        : Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(HrRadius.chip),
                  ),
                  child: Icon(
                    isEnabled
                        ? Icons.beach_access_rounded
                        : Icons.event_repeat_rounded,
                    color: isEnabled
                        ? HrStatusColors.of(context).success
                        : HrStatusColors.of(context).warning,
                    size: 22,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      const Text(
                        'إدارة نظام الإجازات',
                        style: TextStyle(
                          fontSize: HrFont.titleMedium,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        delegate.fullName,
                        style: TextStyle(
                          fontSize: HrFont.labelMedium,
                          color: colorScheme.onSurfaceVariant,
                          fontWeight: FontWeight.normal,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            content: SingleChildScrollView(
              child: SizedBox(
                width: 440,
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const SizedBox(height: 8),
                    // كارت توضيحي لحالة المندوب
                    Container(
                      padding: const EdgeInsets.all(12),
                      decoration: BoxDecoration(
                        color: isEnabled
                            ? HrStatusColors.of(
                                context,
                              ).success.withValues(alpha: 0.08)
                            : HrStatusColors.of(context).warning.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(HrRadius.card),
                        border: Border.all(
                          color: isEnabled
                              ? HrStatusColors.of(
                                  context,
                                ).success.withValues(alpha: 0.25)
                              : HrStatusColors.of(context).warning.withValues(alpha: 0.35),
                        ),
                      ),
                      child: Row(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Icon(
                            isEnabled
                                ? Icons.check_circle_outline_rounded
                                : Icons.info_outline_rounded,
                            size: 20,
                            color: isEnabled
                                ? HrStatusColors.of(context).success
                                : HrStatusColors.of(context).warning,
                          ),
                          const SizedBox(width: 10),
                          Expanded(
                            child: Column(
                              crossAxisAlignment: CrossAxisAlignment.start,
                              children: [
                                Text(
                                  isEnabled
                                      ? 'مفعّل له رصيد الإجازات السنوية ($quota يوم)'
                                      : 'نظام الإجازات الأسبوعية فقط',
                                  style: TextStyle(
                                    fontWeight: FontWeight.bold,
                                    fontSize: HrFont.body,
                                    color: isEnabled
                                        ? HrStatusColors.of(context).success
                                        : HrStatusColors.of(context).warning,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isEnabled
                                      ? 'المندوب مثبت ويحق له التقديم على إجازات اعتيادية تُخصم من رصيده السنوي.'
                                      : 'المندوب جديد أو في فترة اختبار؛ يحصل على الإجازات الأسبوعية الاعتيادية فقط (يوم أسبوعياً بمعدل 4 أيام شهرياً). لا يظهر له رصيد الـ 21 يوماً السنوي.',
                                  key: const Key('hr_leave_dialog_note'),
                                  style: TextStyle(
                                    fontSize: _dialogNoteSize,
                                    color: colorScheme.onSurfaceVariant,
                                    height: 1.4,
                                  ),
                                ),
                              ],
                            ),
                          ),
                        ],
                      ),
                    ),
                    const SizedBox(height: 16),

                    // مفتاح التفعيل M3 SwitchListTile
                    // A Material (not a decorated Container) so the tile's
                    // ink and background paint on it.
                    Material(
                      color: colorScheme.surfaceContainerHigh.withValues(
                        alpha: 0.5,
                      ),
                      clipBehavior: Clip.antiAlias,
                      shape: RoundedRectangleBorder(
                        borderRadius: BorderRadius.circular(HrRadius.card),
                        side: BorderSide(
                          color: colorScheme.outlineVariant.withValues(
                            alpha: 0.4,
                          ),
                        ),
                      ),
                      child: SwitchListTile.adaptive(
                        value: isEnabled,
                        contentPadding: const EdgeInsets.symmetric(
                          horizontal: 14,
                          vertical: 4,
                        ),
                        activeTrackColor: colorScheme.primary,
                        activeThumbColor: colorScheme.onPrimary,
                        title: const Text(
                          'تفعيل الإجازات السنوية',
                          style: TextStyle(
                            fontWeight: FontWeight.bold,
                            fontSize: HrFont.body,
                          ),
                        ),
                        subtitle: Text(
                          isEnabled
                              ? 'إتاحة رصيد الإجازات السنوي والتقديم الاعتيادي'
                              : 'اقتصار المندوب على الإجازات الأسبوعية فقط',
                          style: TextStyle(
                            fontSize: _dialogNoteSize,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                        onChanged: (val) {
                          setDialogState(() => isEnabled = val);
                        },
                      ),
                    ),

                    if (isEnabled) ...[
                      const SizedBox(height: 14),
                      Text(
                        'إجمالي رصيد الإجازات السنوية (أيام):',
                        style: TextStyle(
                          fontSize: HrFont.labelMedium,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: 6),
                      TextFormField(
                        initialValue: quota.toString(),
                        keyboardType: TextInputType.number,
                        decoration: InputDecoration(
                          hintText: '21',
                          suffixText: 'يوم',
                          contentPadding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 10,
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                        onChanged: (val) {
                          final parsed = int.tryParse(val.trim());
                          if (parsed != null && parsed >= 0) {
                            quota = parsed;
                          }
                        },
                      ),
                    ],
                  ],
                ),
              ),
            ),
            actions: [
              TextButton(
                onPressed: isSaving ? null : () => Navigator.pop(dialogContext),
                child: const Text('إلغاء'),
              ),
              FilledButton.icon(
                icon: isSaving
                    ? const SizedBox(
                        width: 16,
                        height: 16,
                        child: CircularProgressIndicator(
                          strokeWidth: 2,
                          color: Colors.white,
                        ),
                      )
                    : const Icon(Icons.check_rounded, size: 18),
                label: Text(isSaving ? 'جارٍ الحفظ...' : 'حفظ التغييرات'),
                onPressed: isSaving
                    ? null
                    : () async {
                        setDialogState(() => isSaving = true);
                        try {
                          final updatePayload = {
                            'isAnnualLeaveEnabled': isEnabled,
                            'annualLeaveQuota': quota,
                            'updatedAt': FieldValue.serverTimestamp(),
                          };

                          // 1. Update in company delegates subcollection if scoped
                          final orgUid = delegate.organizationUID.isNotEmpty
                              ? delegate.organizationUID
                              : widget.hrDelegate.organizationUID;
                          final compUid = delegate.companyUID.isNotEmpty
                              ? delegate.companyUID
                              : widget.hrDelegate.companyUID;
                          if (orgUid.isNotEmpty && compUid.isNotEmpty) {
                            await FirebaseFirestore.instance
                                .collection('organizations')
                                .doc(orgUid)
                                .collection('companies')
                                .doc(compUid)
                                .collection('delegates')
                                .doc(delegate.uid)
                                // update(): never create a stub doc.
                                .update(updatePayload);
                          }

                          // 2. Safely update in users collection if document exists
                          final userRef = FirebaseFirestore.instance
                              .collection('users')
                              .doc(delegate.uid);
                          final userDoc = await userRef.get();
                          if (userDoc.exists) {
                            await userRef.set(
                              updatePayload,
                              SetOptions(merge: true),
                            );
                          }

                          if (dialogContext.mounted) {
                            Navigator.pop(dialogContext);
                          }
                          if (mounted) {
                            AppSnackBar.showSuccess(
                              context,
                              isEnabled
                                  ? 'تم تفعيل رصيد الإجازات السنوية للمندوب ($quota يوم)'
                                  : 'تم ضبط المندوب على نظام الإجازات الأسبوعية فقط',
                            );
                            _loadDelegates();
                          }
                        } catch (e) {
                          setDialogState(() => isSaving = false);
                          if (mounted) {
                            AppSnackBar.showError(
                              context,
                              'حدث خطأ أثناء حفظ الإعدادات: $e',
                            );
                          }
                        }
                      },
              ),
            ],
          );
        },
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    return BlocProvider.value(
      value: _delegatesBloc,
      child: Column(
        children: [
          // ── Search & Filter Toolbar ──
          Container(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            decoration: BoxDecoration(
              color: colorScheme.surface,
              boxShadow: [
                BoxShadow(
                  color: colorScheme.shadow.withValues(alpha: 0.03),
                  blurRadius: 8,
                  offset: const Offset(0, 3),
                ),
              ],
            ),
            child: BlocBuilder<AdminDelegatesBloc, AdminDelegatesState>(
              builder: (context, state) {
                int total = 0;
                int activeCount = 0;
                int suspendedCount = 0;
                if (state is AdminDelegatesLoaded) {
                  total = state.delegates.length;
                  activeCount = state.delegates
                      .where((d) => d.status == DelegateStatus.active)
                      .length;
                  suspendedCount = state.delegates
                      .where((d) => d.status == DelegateStatus.suspended)
                      .length;
                }

                if (WebRuntimePolicy.isWeb) {
                  return _buildWebToolbar(
                    total: total,
                    activeCount: activeCount,
                    suspendedCount: suspendedCount,
                    colorScheme: colorScheme,
                  );
                }

                final searchBar = SearchBar(
                  controller: _searchController,
                  hintText: 'بحث بالاسم، رقم الهاتف، أو الرقم القومي...',
                  elevation: const WidgetStatePropertyAll(0),
                  constraints: const BoxConstraints(
                    minHeight: 44,
                    maxHeight: 44,
                  ),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HrRadius.pill),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(
                          alpha: 0.35,
                        ),
                      ),
                    ),
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh,
                  ),
                  leading: Icon(
                    Icons.search_rounded,
                    size: 19,
                    color: colorScheme.primary,
                  ),
                  trailing: _searchController.text.isNotEmpty
                      ? [
                          IconButton(
                            icon: const Icon(Icons.clear_rounded, size: 18),
                            onPressed: () {
                              _searchController.clear();
                              setState(() {});
                            },
                          ),
                        ]
                      : null,
                  padding: const WidgetStatePropertyAll(
                    EdgeInsets.symmetric(horizontal: 14),
                  ),
                  onChanged: (_) => setState(() {}),
                );

                final statusButtonGroup =
                    TashilConnectedButtonGroup<DelegateStatus?>(
                      height: 44,
                      selectedValue: _selectedStatus,
                      items: [
                        TashilConnectedButtonItem<DelegateStatus?>(
                          value: null,
                          label: total > 0
                              ? 'جميع المناديب ($total)'
                              : 'جميع المناديب',
                          icon: Icons.people_alt_rounded,
                        ),
                        TashilConnectedButtonItem<DelegateStatus?>(
                          value: DelegateStatus.active,
                          label: activeCount > 0 ? 'نشط ($activeCount)' : 'نشط',
                          icon: Icons.check_circle_outline_rounded,
                          activeColor: HrStatusColors.of(context).success,
                        ),
                        TashilConnectedButtonItem<DelegateStatus?>(
                          value: DelegateStatus.suspended,
                          label: suspendedCount > 0
                              ? 'متوقف ($suspendedCount)'
                              : 'متوقف',
                          icon: Icons.pause_circle_outline_rounded,
                          activeColor: HrStatusColors.of(context).danger,
                        ),
                      ],
                      onSelected: (val) {
                        setState(() => _selectedStatus = val);
                      },
                    );

                final viewModeButtonGroup =
                    TashilConnectedButtonGroup<HRDelegatesViewMode>(
                      height: 44,
                      selectedValue: _viewMode,
                      items: const [
                        TashilConnectedButtonItem<HRDelegatesViewMode>(
                          value: HRDelegatesViewMode.table,
                          label: 'جدول',
                          icon: Icons.table_chart_rounded,
                        ),
                        TashilConnectedButtonItem<HRDelegatesViewMode>(
                          value: HRDelegatesViewMode.cards,
                          label: 'بطاقات',
                          icon: Icons.grid_view_rounded,
                        ),
                      ],
                      onSelected: (val) {
                        setState(() => _viewMode = val);
                      },
                    );

                final refreshButton = IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(HrRadius.pill),
                    ),
                    minimumSize: const Size(44, 44),
                    maximumSize: const Size(44, 44),
                  ),
                  tooltip: 'تحديث القائمة',
                  onPressed: _loadDelegates,
                  icon: const Icon(Icons.sync_rounded, size: 20),
                );

                return LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktopWide = constraints.maxWidth >= 960;

                    if (isDesktopWide) {
                      return Row(
                        children: [
                          Expanded(child: searchBar),
                          const SizedBox(width: 10),
                          statusButtonGroup,
                          const SizedBox(width: 10),
                          viewModeButtonGroup,
                          const SizedBox(width: 10),
                          refreshButton,
                        ],
                      );
                    }

                    return Column(
                      children: [
                        Row(
                          children: [
                            Expanded(
                              child: SingleChildScrollView(
                                scrollDirection: Axis.horizontal,
                                child: statusButtonGroup,
                              ),
                            ),
                            const SizedBox(width: 8),
                            refreshButton,
                          ],
                        ),
                        const SizedBox(height: 10),
                        Row(
                          children: [
                            Expanded(child: searchBar),
                            const SizedBox(width: 8),
                            viewModeButtonGroup,
                          ],
                        ),
                      ],
                    );
                  },
                );
              },
            ),
          ),

          // ── Delegates List / Table ──
          Expanded(
            child: BlocBuilder<AdminDelegatesBloc, AdminDelegatesState>(
              builder: (context, state) {
                if (state is AdminDelegatesLoading) {
                  return const Center(child: CircularProgressIndicator());
                } else if (state is AdminDelegatesError) {
                  return Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.message,
                          style: TextStyle(color: colorScheme.error),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: _loadDelegates,
                          child: const Text('إعادة المحاولة'),
                        ),
                      ],
                    ),
                  );
                } else if (state is AdminDelegatesLoaded) {
                  final query = _searchController.text.trim().toLowerCase();
                  final filtered = state.delegates.where((d) {
                    if (query.isNotEmpty) {
                      final matchesName = d.fullName.toLowerCase().contains(
                        query,
                      );
                      final matchesPhone = d.phoneNumber.contains(query);
                      final matchesNat = d.nationalityID.contains(query);
                      if (!matchesName && !matchesPhone && !matchesNat) {
                        return false;
                      }
                    }
                    if (_selectedStatus != null &&
                        d.status != _selectedStatus) {
                      return false;
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty && WebRuntimePolicy.isWeb) {
                    return _buildWebEmpty(
                      hasDelegates: state.delegates.isNotEmpty,
                    );
                  }
                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 56,
                            color: colorScheme.onSurfaceVariant.withValues(
                              alpha: 0.5,
                            ),
                          ),
                          const SizedBox(height: 12),
                          Text(
                            'لا يوجد مناديب مسجلين يطابقون شروط البحث',
                            style: theme.textTheme.bodyMedium?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    );
                  }

                  return RefreshIndicator(
                    onRefresh: () async => _loadDelegates(),
                    child: _buildDelegatesBody(filtered, theme, colorScheme),
                  );
                }

                return const SizedBox.shrink();
              },
            ),
          ),
        ],
      ),
    );
  }

  /// Web toolbar (TAS-116, TAS-144) in two rows: search (56) and status
  /// filter chips, then the view toggle, refresh and «إضافة مندوب».
  Widget _buildWebToolbar({
    required int total,
    required int activeCount,
    required int suspendedCount,
    required ColorScheme colorScheme,
  }) {
    final textTheme = Theme.of(context).textTheme;
    final forcedCards =
        MediaQuery.sizeOf(context).width < HRDelegatesWebBreakpoints.cardsBelow;

    final searchBar = SearchBar(
      key: HRDelegatesTab.searchKey,
      controller: _searchController,
      hintText: 'بحث بالاسم أو رقم الهاتف أو الرقم القومي',
      elevation: const WidgetStatePropertyAll(0),
      constraints: const BoxConstraints(minHeight: 56, maxHeight: 56),
      shape: WidgetStatePropertyAll(
        RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.pill),
        ),
      ),
      backgroundColor: WidgetStatePropertyAll(
        colorScheme.surfaceContainerHigh,
      ),
      textStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(fontSize: HrFont.titleMedium),
      ),
      hintStyle: WidgetStatePropertyAll(
        textTheme.bodyLarge?.copyWith(
          fontSize: HrFont.titleMedium,
          color: colorScheme.onSurfaceVariant,
        ),
      ),
      leading: Icon(Icons.search_rounded, color: colorScheme.onSurfaceVariant),
      trailing: _searchController.text.isNotEmpty
          ? [
              IconButton(
                tooltip: 'مسح البحث',
                icon: const Icon(Icons.clear_rounded),
                onPressed: () {
                  _searchController.clear();
                  setState(() {});
                },
              ),
            ]
          : null,
      padding: const WidgetStatePropertyAll(
        EdgeInsets.symmetric(horizontal: 16),
      ),
      onChanged: (_) => setState(() {}),
    );

    Widget chip(DelegateStatus? status, String label, int count) {
      return FilterChip(
        key: HRDelegatesTab.filterKey(status),
        label: Text(count > 0 ? '$label ($count)' : label),
        labelStyle: textTheme.labelLarge?.copyWith(fontSize: HrFont.body),
        selected: _selectedStatus == status,
        showCheckmark: true,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.chip),
        ),
        onSelected: (_) => setState(() => _selectedStatus = status),
      );
    }

    final filters = Wrap(
      spacing: 8,
      runSpacing: 8,
      children: [
        chip(null, 'الكل', total),
        chip(DelegateStatus.active, 'نشط', activeCount),
        chip(DelegateStatus.suspended, 'متوقف', suspendedCount),
      ],
    );

    final viewToggle = SegmentedButton<HRDelegatesViewMode>(
      key: HRDelegatesTab.viewToggleKey,
      showSelectedIcon: false,
      segments: const [
        ButtonSegment(
          value: HRDelegatesViewMode.cards,
          label: Text('بطاقات'),
          icon: Icon(Icons.grid_view_rounded),
        ),
        ButtonSegment(
          value: HRDelegatesViewMode.table,
          label: Text('جدول'),
          icon: Icon(Icons.table_rows_rounded),
        ),
      ],
      selected: {_viewMode},
      onSelectionChanged: (s) => setState(() => _viewMode = s.first),
    );

    final addButton = FilledButton.icon(
      key: HRDelegatesTab.addDelegateKey,
      onPressed: _openAddDelegate,
      icon: const Icon(Icons.person_add_alt_1_rounded),
      label: const Text('إضافة مندوب'),
      style: FilledButton.styleFrom(
        minimumSize: const Size(48, 48),
        padding: const EdgeInsets.symmetric(horizontal: 20),
        textStyle: textTheme.labelLarge?.copyWith(
          fontSize: HrFont.body,
          fontWeight: FontWeight.w700,
        ),
      ),
    );

    return LayoutBuilder(
      builder: (context, constraints) {
        final wide = constraints.maxWidth >= 900;
        return Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (wide)
              Row(
                children: [
                  Expanded(child: searchBar),
                  const SizedBox(width: 16),
                  filters,
                ],
              )
            else ...[
              searchBar,
              const SizedBox(height: 12),
              Align(alignment: AlignmentDirectional.centerStart, child: filters),
            ],
            const SizedBox(height: 12),
            Row(
              children: [
                // Below the cards breakpoint the page always shows cards.
                if (!forcedCards) ...[viewToggle, const SizedBox(width: 8)],
                IconButton(
                  key: const Key('hr_delegates_refresh'),
                  tooltip: 'تحديث القائمة',
                  onPressed: _loadDelegates,
                  icon: const Icon(Icons.refresh_rounded),
                ),
                const Spacer(),
                addButton,
              ],
            ),
          ],
        );
      },
    );
  }

  /// Web empty result: nothing matches, or no delegates yet.
  Widget _buildWebEmpty({required bool hasDelegates}) {
    if (!hasDelegates) {
      return HrEmptyState(
        key: const Key('hr_delegates_empty'),
        icon: Icons.group_off_rounded,
        title: 'لا يوجد مناديب',
        message: 'سيظهر المناديب هنا عند إضافتهم.',
        action: FilledButton.icon(
          onPressed: _openAddDelegate,
          icon: const Icon(Icons.person_add_alt_1_rounded),
          label: const Text('إضافة مندوب'),
        ),
      );
    }
    return HrEmptyState(
      key: const Key('hr_delegates_no_match'),
      icon: Icons.person_search_rounded,
      title: 'لا توجد نتائج',
      message: 'لا يوجد مناديب يطابقون البحث أو الفلتر الحالي.',
      action: TextButton(
        onPressed: () {
          _searchController.clear();
          setState(() => _selectedStatus = null);
        },
        child: const Text('مسح البحث والفلتر'),
      ),
    );
  }

  Widget _buildDelegatesBody(
    List<Delegate> delegates,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (WebRuntimePolicy.isWeb) {
      final narrow =
          MediaQuery.sizeOf(context).width <
          HRDelegatesWebBreakpoints.cardsBelow;
      if (narrow || _viewMode == HRDelegatesViewMode.cards) {
        return _buildWebCardsGrid(delegates);
      }
      return _buildWebDelegatesTable(delegates, theme, colorScheme);
    }
    return _viewMode == HRDelegatesViewMode.table
        ? _buildDelegatesTable(delegates, theme, colorScheme)
        : _buildCardsGrid(delegates, theme, colorScheme);
  }

  /// Web table columns (MD3 Model 3). Header and cells use the same list,
  /// the same cell padding and the same alignment, so they always line up.
  List<HrTableColumn> _webColumns(bool merged) => merged
      ? const [
          HrTableColumn('المندوب / المروج', 3),
          HrTableColumn('الرقم القومي / الهاتف', 3),
          HrTableColumn('السلاسل', 2, center: true),
          HrTableColumn('الحالة', 2, center: true),
          HrTableColumn('الإجراءات', 2, center: true),
        ]
      : const [
          HrTableColumn('#', 1, center: true),
          HrTableColumn('المندوب / المروج', 4),
          HrTableColumn('الرقم القومي', 3),
          HrTableColumn('رقم الهاتف', 3),
          HrTableColumn('المدينة', 3),
          HrTableColumn('السلاسل', 2, center: true),
          HrTableColumn('الحالة', 2, center: true),
          HrTableColumn('الإجراءات', 2, center: true),
        ];

  /// Web table (MD3 Model 3): a row tap opens the delegate's profile, the
  /// actions sit in a «⋮» menu, and the ID/phone and name/city columns
  /// merge on narrower tables.
  Widget _buildWebDelegatesTable(
    List<Delegate> delegates,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: HrTableCard(
        horizontalController: _hScrollCtrl,
        builder: (context, width) {
          final merged = width < HRDelegatesWebBreakpoints.mergedColumnsBelow;
          final cols = _webColumns(merged);
          return Column(
            children: [
              HrTableHeader(columns: cols, keyPrefix: 'hr_delegates_header_'),
              Expanded(
                child: ListView.separated(
                  controller: _vScrollCtrl,
                  physics: const AlwaysScrollableScrollPhysics(),
                  itemCount: delegates.length,
                  separatorBuilder: (_, _) => const HrTableDivider(),
                  itemBuilder: (context, index) => _buildWebRow(
                    delegates[index],
                    index,
                    cols: cols,
                    merged: merged,
                    theme: theme,
                    colorScheme: colorScheme,
                  ),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  Widget _buildWebRow(
    Delegate delegate,
    int index, {
    required List<HrTableColumn> cols,
    required bool merged,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final city = delegate.city.isNotEmpty
        ? delegate.city
        : (delegate.companyName.isNotEmpty ? delegate.companyName : '—');

    final mono = hrTabularStyle(context);
    final nameStyle = theme.textTheme.bodyMedium?.copyWith(
      fontWeight: FontWeight.bold,
      color: colorScheme.onSurface,
    );

    Widget plain(String value, {TextStyle? style}) => SelectableText(
      value.isNotEmpty ? value : '—',
      style: style ?? mono,
      maxLines: 1,
    );

    final name = Row(
      children: [
        AppAvatar(
          imageUrl: delegate.personalPhotoUrl,
          fallbackText: delegate.fullName,
          radius: 16,
        ),
        const SizedBox(width: 10),
        Expanded(
          child: merged
              ? Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      delegate.fullName,
                      style: nameStyle,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                    Text(
                      city,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: HrFont.labelSmall,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : Text(
                  delegate.fullName,
                  style: nameStyle,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
        ),
      ],
    );

    final chains = _buildWebChains(delegate, colorScheme);
    final status = _webStatusChip(delegate);
    final actions = _buildWebActionsMenu(delegate);

    final cells = merged
        ? <Widget>[
            name,
            Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                plain(delegate.nationalityID),
                plain(
                  delegate.phoneNumber,
                  style: mono.copyWith(color: colorScheme.onSurfaceVariant),
                ),
              ],
            ),
            chains,
            status,
            actions,
          ]
        : <Widget>[
            Text(
              '${index + 1}',
              style: TextStyle(
                fontWeight: FontWeight.w600,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
            name,
            plain(delegate.nationalityID),
            plain(delegate.phoneNumber),
            Text(
              city,
              style: theme.textTheme.bodySmall?.copyWith(
                color: colorScheme.onSurface,
                fontWeight: FontWeight.w500,
              ),
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
            ),
            chains,
            status,
            actions,
          ];

    return HrTableRow(
      key: Key('hr_delegate_row_${delegate.uid}'),
      columns: cols,
      cells: cells,
      onTap: () => _openProfile(delegate),
    );
  }

  Widget _webStatusChip(Delegate delegate) {
    final isActive = delegate.status == DelegateStatus.active;
    return HrStatusChip(
      label: isActive ? 'نشط' : 'متوقف',
      tone: isActive ? HrStatusTone.success : HrStatusTone.neutral,
      icon: isActive ? Icons.check_circle_rounded : Icons.pause_circle_rounded,
    );
  }

  /// Web cards (TAS-144): compact cards with the essentials only, laid out
  /// in rows so each card takes its natural height (no empty areas, no
  /// clipped chips).
  Widget _buildWebCardsGrid(List<Delegate> delegates) {
    const gap = 12.0;
    const minCardWidth = 320.0;
    return LayoutBuilder(
      builder: (context, constraints) {
        final inner = constraints.maxWidth - 32;
        final columns = ((inner + gap) / (minCardWidth + gap)).floor().clamp(
          1,
          4,
        );
        final rows = (delegates.length / columns).ceil();
        return ListView.separated(
          key: const Key('hr_delegates_cards'),
          controller: _vScrollCtrl,
          physics: const AlwaysScrollableScrollPhysics(),
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: rows,
          separatorBuilder: (_, _) => const SizedBox(height: gap),
          itemBuilder: (context, row) => Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              for (var c = 0; c < columns; c++) ...[
                if (c > 0) const SizedBox(width: gap),
                Expanded(
                  child: row * columns + c < delegates.length
                      ? _buildWebDelegateCard(delegates[row * columns + c])
                      : const SizedBox.shrink(),
                ),
              ],
            ],
          ),
        );
      },
    );
  }

  Widget _buildWebDelegateCard(Delegate delegate) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final city = delegate.city.isNotEmpty
        ? delegate.city
        : (delegate.companyName.isNotEmpty ? delegate.companyName : '—');
    final annual = delegate.isAnnualLeaveEnabled;

    return Card(
      key: Key('hr_delegate_card_${delegate.uid}'),
      margin: EdgeInsets.zero,
      elevation: 0,
      color: colorScheme.surface,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: colorScheme.outlineVariant),
      ),
      child: InkWell(
        onTap: () => _openProfile(delegate),
        child: Padding(
          padding: const EdgeInsetsDirectional.fromSTEB(16, 12, 4, 14),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Row(
                children: [
                  AppAvatar(
                    imageUrl: delegate.personalPhotoUrl,
                    fallbackText: delegate.fullName,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      mainAxisSize: MainAxisSize.min,
                      children: [
                        Text(
                          delegate.fullName,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.titleSmall?.copyWith(
                            fontSize: HrFont.body,
                            fontWeight: FontWeight.w700,
                            color: colorScheme.onSurface,
                          ),
                        ),
                        Text(
                          city,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: theme.textTheme.bodySmall?.copyWith(
                            fontSize: HrFont.labelMedium,
                            color: colorScheme.onSurfaceVariant,
                          ),
                        ),
                      ],
                    ),
                  ),
                  _buildWebActionsMenu(delegate),
                ],
              ),
              const SizedBox(height: 12),
              Padding(
                padding: const EdgeInsetsDirectional.only(end: 12),
                child: Wrap(
                  spacing: 8,
                  runSpacing: 8,
                  crossAxisAlignment: WrapCrossAlignment.center,
                  children: [
                    _webStatusChip(delegate),
                    HrStatusChip(
                      key: Key('hr_delegate_leave_${delegate.uid}'),
                      label: annual
                          ? 'سنوية (${delegate.annualLeaveQuota} يوم)'
                          : 'أسبوعية فقط',
                      tone: annual ? HrStatusTone.success : HrStatusTone.info,
                      icon: annual
                          ? Icons.beach_access_rounded
                          : Icons.event_repeat_rounded,
                    ),
                    _buildWebChains(delegate, colorScheme),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  /// جدول بيانات المناديب الاحترافي (العرض الافتراضي المطلوب)
  Widget _buildDelegatesTable(
    List<Delegate> delegates,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    const minWidth = 1200.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(HrRadius.card),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
          boxShadow: [
            BoxShadow(
              color: colorScheme.shadow.withValues(alpha: 0.03),
              blurRadius: 12,
              offset: const Offset(0, 4),
            ),
          ],
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final availableWidth = constraints.maxWidth;
            final contentWidth = availableWidth > minWidth
                ? availableWidth
                : minWidth;
            final isScrollable = contentWidth > availableWidth;

            return Scrollbar(
              controller: _hScrollCtrl,
              thumbVisibility: isScrollable,
              trackVisibility: isScrollable,
              interactive: isScrollable,
              thickness: 10.0,
              radius: const Radius.circular(HrRadius.chip),
              notificationPredicate: (notification) =>
                  notification.depth == 0 &&
                  notification.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _hScrollCtrl,
                scrollDirection: Axis.horizontal,
                physics: const AlwaysScrollableScrollPhysics(),
                child: SizedBox(
                  width: contentWidth,
                  child: Column(
                    children: [
                      // ── Table Header (Fixed at top) ──
                      Container(
                        height: 52,
                        padding: const EdgeInsets.symmetric(horizontal: 16),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(
                            alpha: 0.45,
                          ),
                          border: Border(
                            bottom: BorderSide(
                              color: colorScheme.outlineVariant.withValues(
                                alpha: 0.6,
                              ),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildHeaderCell(
                              '#',
                              flex: 4,
                              theme: theme,
                              colorScheme: colorScheme,
                              isCenter: true,
                            ),
                            _buildHeaderCell(
                              'المندوب / المروج',
                              flex: 20,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            _buildHeaderCell(
                              'الرقم القومي',
                              flex: 15,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            _buildHeaderCell(
                              'رقم الهاتف',
                              flex: 14,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            _buildHeaderCell(
                              'المدينة / المحافظة',
                              flex: 13,
                              theme: theme,
                              colorScheme: colorScheme,
                            ),
                            _buildHeaderCell(
                              'الحالة',
                              flex: 10,
                              theme: theme,
                              colorScheme: colorScheme,
                              isCenter: true,
                            ),
                            _buildHeaderCell(
                              'الإجراءات والملف',
                              flex: 34,
                              theme: theme,
                              colorScheme: colorScheme,
                              isCenter: true,
                            ),
                          ],
                        ),
                      ),

                      // ── Table Rows (Recycled Virtual ListView) ──
                      Expanded(
                        child: ListView.separated(
                          controller: _vScrollCtrl,
                          physics: const AlwaysScrollableScrollPhysics(),
                          itemCount: delegates.length,
                          separatorBuilder: (context, index) => Divider(
                            height: 1,
                            thickness: 1,
                            color: colorScheme.outlineVariant.withValues(
                              alpha: 0.22,
                            ),
                          ),
                          itemBuilder: (context, index) {
                            final delegate = delegates[index];
                            final isActive =
                                delegate.status == DelegateStatus.active;
                            final statusColor = isActive
                                ? HrStatusColors.of(context).success
                                : HrStatusColors.of(context).danger;
                            final statusText = isActive ? 'نشط' : 'متوقف';

                            final posName =
                                delegate.position == DelegatePosition.supervisor
                                ? 'مشرف'
                                : 'مندوب / مروج';

                            return InkWell(
                              onTap: () => _openProfile(delegate),
                              hoverColor: colorScheme.primaryContainer
                                  .withValues(alpha: 0.12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(
                                  horizontal: 16,
                                  vertical: 12,
                                ),
                                color: index.isEven
                                    ? colorScheme.surface
                                    : colorScheme.surfaceContainerHighest
                                          .withValues(alpha: 0.18),
                                child: Row(
                                  children: [
                                    // # Index
                                    Expanded(
                                      flex: 4,
                                      child: Center(
                                        child: Text(
                                          '${index + 1}',
                                          style: TextStyle(
                                            fontWeight: FontWeight.w600,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Delegate Info (Avatar + Name + Role)
                                    Expanded(
                                      flex: 20,
                                      child: Row(
                                        children: [
                                          AppAvatar(
                                            imageUrl: delegate.personalPhotoUrl,
                                            fallbackText: delegate.fullName,
                                            radius: 20,
                                          ),
                                          const SizedBox(width: 10),
                                          Expanded(
                                            child: Column(
                                              crossAxisAlignment:
                                                  CrossAxisAlignment.start,
                                              mainAxisAlignment:
                                                  MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  delegate.fullName,
                                                  style: theme
                                                      .textTheme
                                                      .bodyMedium
                                                      ?.copyWith(
                                                        fontWeight:
                                                            FontWeight.bold,
                                                        color: colorScheme
                                                            .onSurface,
                                                      ),
                                                  maxLines: 1,
                                                  overflow:
                                                      TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  posName,
                                                  style: theme
                                                      .textTheme
                                                      .bodySmall
                                                      ?.copyWith(
                                                        color:
                                                            colorScheme.primary,
                                                        fontWeight:
                                                            FontWeight.w600,
                                                        fontSize:
                                                            HrFont.labelSmall,
                                                      ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // National ID
                                    Expanded(
                                      flex: 15,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.badge_outlined,
                                            size: 15,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: SelectableText(
                                              delegate.nationalityID.isNotEmpty
                                                  ? delegate.nationalityID
                                                  : '—',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        colorScheme.onSurface,
                                                    letterSpacing: 0.5,
                                                  ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ),
                                          if (delegate.nationalityID.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                                size: 14,
                                              ),
                                              tooltip: 'نسخ الرقم القومي',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 24,
                                                minHeight: 24,
                                              ),
                                              onPressed: () => _copyNationalId(
                                                delegate.nationalityID,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    // Phone Number
                                    Expanded(
                                      flex: 14,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.phone_iphone_rounded,
                                            size: 15,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                          const SizedBox(width: 6),
                                          Expanded(
                                            child: SelectableText(
                                              delegate.phoneNumber.isNotEmpty
                                                  ? delegate.phoneNumber
                                                  : '—',
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    fontFamily: 'monospace',
                                                    fontWeight: FontWeight.w600,
                                                    color:
                                                        colorScheme.onSurface,
                                                    letterSpacing: 0.3,
                                                  ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ),
                                          if (delegate.phoneNumber.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(
                                                Icons.copy_rounded,
                                                size: 14,
                                              ),
                                              tooltip: 'نسخ رقم الهاتف',
                                              visualDensity:
                                                  VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(
                                                minWidth: 24,
                                                minHeight: 24,
                                              ),
                                              onPressed: () => _copyPhoneNumber(
                                                delegate.phoneNumber,
                                              ),
                                            ),
                                        ],
                                      ),
                                    ),

                                    // City / Location
                                    Expanded(
                                      flex: 13,
                                      child: Row(
                                        children: [
                                          Icon(
                                            Icons.location_on_outlined,
                                            size: 15,
                                            color: colorScheme.onSurfaceVariant
                                                .withValues(alpha: 0.8),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              delegate.city.isNotEmpty
                                                  ? delegate.city
                                                  : (delegate
                                                            .companyName
                                                            .isNotEmpty
                                                        ? delegate.companyName
                                                        : '—'),
                                              style: theme.textTheme.bodySmall
                                                  ?.copyWith(
                                                    color:
                                                        colorScheme.onSurface,
                                                    fontWeight: FontWeight.w500,
                                                  ),
                                              maxLines: 1,
                                              overflow: TextOverflow.ellipsis,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),

                                    // Status Badge
                                    Expanded(
                                      flex: 10,
                                      child: Center(
                                        child: Container(
                                          padding: const EdgeInsets.symmetric(
                                            horizontal: 10,
                                            vertical: 4,
                                          ),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(
                                              alpha: 0.12,
                                            ),
                                            borderRadius: BorderRadius.circular(
                                              HrRadius.button,
                                            ),
                                            border: Border.all(
                                              color: statusColor.withValues(
                                                alpha: 0.3,
                                              ),
                                            ),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(
                                                Icons.circle,
                                                size: 7,
                                                color: statusColor,
                                              ),
                                              const SizedBox(width: 5),
                                              Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: HrFont.labelSmall,
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                      ),
                                    ),

                                    // Actions (Call + WhatsApp + Leaves + Attendance + Profile)
                                    Expanded(
                                      flex: 34,
                                      child: Center(
                                        child: _buildTableActionsButtonGroup(
                                          delegate,
                                          colorScheme,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                      const SizedBox(height: 10),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildHeaderCell(
    String title, {
    required int flex,
    required ThemeData theme,
    required ColorScheme colorScheme,
    bool isCenter = false,
  }) {
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 6),
        child: Text(
          title,
          textAlign: isCenter ? TextAlign.center : TextAlign.start,
          style: theme.textTheme.labelMedium?.copyWith(
            color: colorScheme.onSurfaceVariant,
            fontWeight: FontWeight.bold,
            letterSpacing: 0.2,
            fontSize: HrFont.labelMedium,
          ),
        ),
      ),
    );
  }

  /// عرض شبكة البطاقات (كخيار تبديل إضافي)
  Widget _buildCardsGrid(
    List<Delegate> filtered,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth > 750) {
          return GridView.builder(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 550,
              mainAxisExtent: WebRuntimePolicy.isWeb ? 190 : 175,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              return _buildDelegateCard(filtered[index], theme, colorScheme);
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _buildDelegateCard(filtered[index], theme, colorScheme);
          },
        );
      },
    );
  }

  Widget _buildDelegateCard(
    Delegate delegate,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    final isActive = delegate.status == DelegateStatus.active;
    final statusColor = isActive
        ? HrStatusColors.of(context).success
        : HrStatusColors.of(context).danger;
    final statusText = isActive ? 'نشط' : 'متوقف';

    final posName = delegate.position == DelegatePosition.supervisor
        ? 'مشرف'
        : 'مندوب / مروج';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          children: [
            Row(
              crossAxisAlignment: CrossAxisAlignment.center,
              children: [
                AppAvatar(
                  imageUrl: delegate.personalPhotoUrl,
                  fallbackText: delegate.fullName,
                  radius: 24,
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        delegate.fullName,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        posName,
                        style: theme.textTheme.bodySmall?.copyWith(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.w600,
                        ),
                      ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 7,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: delegate.isAnnualLeaveEnabled
                              ? HrStatusColors.of(
                                  context,
                                ).success.withValues(alpha: 0.1)
                              : Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: delegate.isAnnualLeaveEnabled
                                ? HrStatusColors.of(
                                    context,
                                  ).success.withValues(alpha: 0.25)
                                : Colors.amber.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              delegate.isAnnualLeaveEnabled
                                  ? Icons.beach_access_rounded
                                  : Icons.event_repeat_rounded,
                              size: 10,
                              color: delegate.isAnnualLeaveEnabled
                                  ? HrStatusColors.of(context).success
                                  : HrStatusColors.of(context).warning,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              delegate.isAnnualLeaveEnabled
                                  ? 'سنوي (${delegate.annualLeaveQuota} يوم)'
                                  : 'أسبوعي فقط (تجربة)',
                              style: TextStyle(
                                fontSize: HrFont.labelSmall,
                                fontWeight: FontWeight.bold,
                                color: delegate.isAnnualLeaveEnabled
                                    ? HrStatusColors.of(context).success
                                    : HrStatusColors.of(context).warning,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (delegate.nationalityID.isNotEmpty)
                        Row(
                          children: [
                            Icon(
                              Icons.badge_outlined,
                              size: 14,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              delegate.nationalityID,
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                    ],
                  ),
                ),
                // Status Badge
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(HrRadius.button),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(Icons.circle, size: 8, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusText,
                        style: TextStyle(
                          color: statusColor,
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),

            const SizedBox(height: 10),
            const Divider(height: 1),
            const SizedBox(height: 8),

            // Actions Row
            Row(
              children: [
                const Spacer(),
                _buildTableActionsButtonGroup(delegate, colorScheme),
              ],
            ),
          ],
        ),
      ),
    );
  }

  /// أزرار الإجراءات والتواصل والملف كـ Button Group موحدة وفق M3
  Widget _buildTableActionsButtonGroup(
    Delegate delegate,
    ColorScheme colorScheme,
  ) {
    final hasPhone = delegate.phoneNumber.trim().isNotEmpty;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
          width: 1,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          // زر الاتصال الهاتفي (Google Icon)
          if (hasPhone) ...[
            Material(
              color: Colors.transparent,
              child: Tooltip(
                message: 'اتصال هاتفي (${delegate.phoneNumber})',
                child: InkWell(
                  onTap: () => _callPhone(delegate.phoneNumber),
                  hoverColor: colorScheme.primary.withValues(alpha: 0.12),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: Center(
                      child: Icon(
                        Icons.phone_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
            // زر الواتساب (Google Icon)
            Material(
              color: Colors.transparent,
              child: Tooltip(
                message: 'مراسلة عبر واتساب (${delegate.phoneNumber})',
                child: InkWell(
                  onTap: () => _openWhatsApp(delegate.phoneNumber),
                  hoverColor: const Color(0xFF25D366).withValues(alpha: 0.15),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    child: const Center(
                      child: Icon(
                        Icons.chat_bubble_rounded,
                        size: 14,
                        color: Color(0xFF1EBE5D),
                      ),
                    ),
                  ),
                ),
              ),
            ),
            Container(
              width: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.45),
            ),
          ],
          // زر إدارة الإجازات السنوية والأسبوعية
          Material(
            color: Colors.transparent,
            child: Tooltip(
              message: delegate.isAnnualLeaveEnabled
                  ? 'الإجازات السنوية: مفعّلة (${delegate.annualLeaveQuota} يوم) - اضغط للتعديل'
                  : 'الإجازات السنوية: غير مفعّلة (أسبوعية فقط) - اضغط للتفعيل',
              child: InkWell(
                onTap: () => _showAnnualLeaveManagementDialog(delegate),
                hoverColor:
                    (delegate.isAnnualLeaveEnabled
                            ? HrStatusColors.of(context).success
                            : HrStatusColors.of(context).warning)
                        .withValues(alpha: 0.1),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 8),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        delegate.isAnnualLeaveEnabled
                            ? Icons.beach_access_rounded
                            : Icons.event_repeat_rounded,
                        size: 14,
                        color: delegate.isAnnualLeaveEnabled
                            ? HrStatusColors.of(context).success
                            : HrStatusColors.of(context).warning,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        delegate.isAnnualLeaveEnabled ? 'سنوية' : 'أسبوعية',
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.bold,
                          color: delegate.isAnnualLeaveEnabled
                              ? HrStatusColors.of(context).success
                              : HrStatusColors.of(context).warning,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          Container(
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          // زر سجل الحضور
          Material(
            color: Colors.transparent,
            child: Tooltip(
              message: 'سجل الحضور والانصراف',
              child: InkWell(
                onTap: () => _openAttendance(delegate),
                hoverColor: colorScheme.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.how_to_reg_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'سجل الحضور',
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
                        ),
                      ),
                    ],
                  ),
                ),
              ),
            ),
          ),
          // فاصل دقيق بين الزرين
          Container(
            width: 1,
            color: colorScheme.outlineVariant.withValues(alpha: 0.45),
          ),
          // زر الملف الشخصي والبيانات الورقية
          Material(
            color: Colors.transparent,
            child: Tooltip(
              message: 'الملف والوثائق الرسمية',
              child: InkWell(
                onTap: () => _openProfile(delegate),
                hoverColor: colorScheme.primary.withValues(alpha: 0.08),
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 9),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.folder_shared_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'الملف',
                        style: TextStyle(
                          fontSize: HrFont.labelSmall,
                          fontWeight: FontWeight.w600,
                          color: colorScheme.onSurface,
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
    );
  }
}
