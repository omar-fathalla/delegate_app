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
import 'package:delegate_app/features/hr/presentation/pages/hr_delegate_attendance_detail_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_add_chains_sheet.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/profile/presentation/pages/profile_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;

enum HRDelegatesViewMode { table, cards }

/// Web breakpoints of the «مناديب الشركة» page (MD3 Model 3).
class HRDelegatesWebBreakpoints {
  HRDelegatesWebBreakpoints._();

  /// Below this viewport width the table becomes cards.
  static const double cardsBelow = 840;

  /// Below this table width the ID/phone and name/city columns merge.
  static const double mergedColumnsBelow = 1080;
}

class HRDelegatesTab extends StatefulWidget {
  final Delegate hrDelegate;

  const HRDelegatesTab({super.key, required this.hrDelegate});

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
    // Warm the chain catalog so «إضافة سلاسل للشركة» opens at once.
    if (WebRuntimePolicy.isWeb) HrAddChainsSheet.prefetch(widget.hrDelegate);
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

  /// Web: company-level «إضافة سلاسل للشركة» («طلب ضم سلسلة»). Replaces
  /// the per-delegate action: approved chains reach every active, paid
  /// delegate of the company automatically.
  Future<void> _openAddCompanyChains() async {
    final names = await HrAddChainsSheet.show(
      context,
      supervisor: widget.hrDelegate,
    );
    if (!mounted || names == null || names.isEmpty) return;
    AppSnackBar.showSuccess(
      context,
      'تم إرسال طلب ضم ${names.length} سلسلة للشركة. بعد الموافقة تظهر فروعها لكل المناديب النشطين المدفوع اشتراكهم.',
    );
  }

  static const addCompanyChainsKey = Key('hr_add_company_chains');

  /// Chains the delegate is on, from the loaded delegate (primary chain
  /// plus allOrganizationNames). No extra reads.
  int _chainCount(Delegate delegate) {
    final names = <String>{
      for (final n in [delegate.organizationName, ...delegate.allOrganizationNames])
        if (n.trim().isNotEmpty) n.trim().toLowerCase(),
    };
    if (names.isEmpty && delegate.organizationUID.trim().isNotEmpty) return 1;
    return names.length;
  }

  /// Web filter segments: room around each label, selected one included.
  static const EdgeInsets _webSegmentPadding = EdgeInsets.symmetric(horizontal: 18);

  /// Small circular icon action. Neutral grey by default; [accent] gives the
  /// purple «إضافة سلاسل» look with a tighter circle. 48dp tap target.
  Widget _webIconAction({
    Key? key,
    required String tooltip,
    required IconData icon,
    required VoidCallback? onPressed,
    required ColorScheme colorScheme,
    bool accent = false,
  }) {
    final size = accent ? 30.0 : 34.0;
    return Tooltip(
      message: tooltip,
      child: IconButton(
        key: key,
        onPressed: onPressed,
        icon: Icon(icon),
        iconSize: accent ? 18 : 19,
        style: IconButton.styleFrom(
          fixedSize: Size(size, size),
          minimumSize: Size(size, size),
          padding: EdgeInsets.zero,
          tapTargetSize: MaterialTapTargetSize.padded,
          shape: const CircleBorder(),
          backgroundColor: accent
              ? colorScheme.primary.withValues(alpha: 0.12)
              : colorScheme.surfaceContainerHighest,
          foregroundColor: accent ? colorScheme.primary : colorScheme.onSurfaceVariant,
          disabledBackgroundColor: colorScheme.onSurface.withValues(alpha: 0.06),
          disabledForegroundColor: colorScheme.onSurface.withValues(alpha: 0.32),
        ),
      ),
    );
  }

  /// Web actions (MD3 Model 3): «أسبوعية»/«سنوية» and «سجل الحضور»
  /// (neutral grey). Chains are added for the whole company from the page
  /// button «إضافة سلاسل للشركة», not per delegate.
  List<Widget> _buildWebActions(Delegate delegate, ColorScheme colorScheme) {
    return [
      _webIconAction(
        key: Key('hr_delegate_leaves_${delegate.uid}'),
        tooltip: delegate.isAnnualLeaveEnabled
            ? 'سنوية: الإجازات السنوية مفعّلة (${delegate.annualLeaveQuota} يوم) - اضغط للتعديل'
            : 'أسبوعية: الإجازات السنوية غير مفعّلة - اضغط للتفعيل',
        icon: delegate.isAnnualLeaveEnabled
            ? Symbols.beach_access_rounded
            : Symbols.event_repeat_rounded,
        onPressed: () => _showAnnualLeaveManagementDialog(delegate),
        colorScheme: colorScheme,
      ),
      _webIconAction(
        key: Key('hr_delegate_attendance_${delegate.uid}'),
        tooltip: 'سجل الحضور والانصراف',
        icon: Symbols.fact_check_rounded,
        onPressed: () => _openAttendance(delegate),
        colorScheme: colorScheme,
      ),
    ];
  }

  void _openAttendance(Delegate delegate) {
    Navigator.push(
      context,
      MaterialPageRoute(
        builder: (_) => HRDelegateAttendanceDetailScreen(
          delegate: delegate,
          hrDelegate: widget.hrDelegate,
        ),
      ),
    );
  }

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
              borderRadius: BorderRadius.circular(20),
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
                        ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
                        : Colors.amber.withValues(alpha: 0.15),
                    borderRadius: BorderRadius.circular(10),
                  ),
                  child: Icon(
                    isEnabled
                        ? Icons.beach_access_rounded
                        : Icons.event_repeat_rounded,
                    color: isEnabled
                        ? const Color(0xFF2E7D32)
                        : Colors.amber.shade900,
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
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      Text(
                        delegate.fullName,
                        style: TextStyle(
                          fontSize: 12,
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
                            ? const Color(0xFF2E7D32).withValues(alpha: 0.08)
                            : Colors.amber.withValues(alpha: 0.1),
                        borderRadius: BorderRadius.circular(12),
                        border: Border.all(
                          color: isEnabled
                              ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
                              : Colors.amber.withValues(alpha: 0.35),
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
                                ? const Color(0xFF2E7D32)
                                : Colors.amber.shade900,
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
                                    fontSize: 13,
                                    color: isEnabled
                                        ? const Color(0xFF2E7D32)
                                        : Colors.amber.shade900,
                                  ),
                                ),
                                const SizedBox(height: 4),
                                Text(
                                  isEnabled
                                      ? 'المندوب مثبت ويحق له التقديم على إجازات اعتيادية تُخصم من رصيده السنوي.'
                                      : 'المندوب جديد أو في فترة اختبار؛ يحصل على الإجازات الأسبوعية الاعتيادية فقط (يوم أسبوعياً بمعدل 4 أيام شهرياً). لا يظهر له رصيد الـ 21 يوماً السنوي.',
                                  style: TextStyle(
                                    fontSize: 11.5,
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
                    Container(
                      decoration: BoxDecoration(
                        color: colorScheme.surfaceContainerHigh.withValues(alpha: 0.5),
                        borderRadius: BorderRadius.circular(14),
                        border: Border.all(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.4),
                        ),
                      ),
                      child: SwitchListTile.adaptive(
                        value: isEnabled,
                        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 4),
                        activeTrackColor: colorScheme.primary,
                        activeThumbColor: colorScheme.onPrimary,
                        title: const Text(
                          'تفعيل الإجازات السنوية',
                          style: TextStyle(fontWeight: FontWeight.bold, fontSize: 14),
                        ),
                        subtitle: Text(
                          isEnabled
                              ? 'إتاحة رصيد الإجازات السنوي والتقديم الاعتيادي'
                              : 'اقتصار المندوب على الإجازات الأسبوعية فقط',
                          style: TextStyle(
                            fontSize: 11.5,
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
                          fontSize: 12.5,
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
                            borderRadius: BorderRadius.circular(12),
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
                                .set(updatePayload, SetOptions(merge: true));
                          }

                          // 2. Safely update in users collection if document exists
                          final userRef = FirebaseFirestore.instance
                              .collection('users')
                              .doc(delegate.uid);
                          final userDoc = await userRef.get();
                          if (userDoc.exists) {
                            await userRef.set(updatePayload, SetOptions(merge: true));
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

                final searchBar = SearchBar(
                  controller: _searchController,
                  hintText: 'بحث بالاسم، رقم الهاتف، أو الرقم القومي...',
                  elevation: const WidgetStatePropertyAll(0),
                  constraints: const BoxConstraints(minHeight: 44, maxHeight: 44),
                  shape: WidgetStatePropertyAll(
                    RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
                      side: BorderSide(
                        color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      ),
                    ),
                  ),
                  backgroundColor: WidgetStatePropertyAll(
                    colorScheme.surfaceContainerHigh,
                  ),
                  leading: Icon(Icons.search_rounded, size: 19, color: colorScheme.primary),
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

                final statusButtonGroup = TashilConnectedButtonGroup<DelegateStatus?>(
                  height: 44,
                  itemPadding: WebRuntimePolicy.isWeb ? _webSegmentPadding : null,
                  selectedValue: _selectedStatus,
                  items: [
                    TashilConnectedButtonItem<DelegateStatus?>(
                      value: null,
                      label: total > 0 ? 'جميع المناديب ($total)' : 'جميع المناديب',
                      icon: Icons.people_alt_rounded,
                    ),
                    TashilConnectedButtonItem<DelegateStatus?>(
                      value: DelegateStatus.active,
                      label: activeCount > 0 ? 'نشط ($activeCount)' : 'نشط',
                      icon: Icons.check_circle_outline_rounded,
                      activeColor: const Color(0xFF2E7D32),
                    ),
                    TashilConnectedButtonItem<DelegateStatus?>(
                      value: DelegateStatus.suspended,
                      label: suspendedCount > 0 ? 'متوقف ($suspendedCount)' : 'متوقف',
                      icon: Icons.pause_circle_outline_rounded,
                      activeColor: const Color(0xFFC62828),
                    ),
                  ],
                  onSelected: (val) {
                    setState(() => _selectedStatus = val);
                  },
                );

                final viewModeButtonGroup = TashilConnectedButtonGroup<HRDelegatesViewMode>(
                  height: 44,
                  itemPadding: WebRuntimePolicy.isWeb ? _webSegmentPadding : null,
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

                final addCompanyChainsButton = WebRuntimePolicy.isWeb
                    ? FilledButton.icon(
                        key: addCompanyChainsKey,
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(0, 44),
                          padding: const EdgeInsets.symmetric(horizontal: 18),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(22),
                          ),
                        ),
                        onPressed: _openAddCompanyChains,
                        icon: const Icon(Symbols.add_business_rounded, size: 20),
                        label: const Text(
                          'إضافة سلاسل للشركة',
                          style: TextStyle(fontWeight: FontWeight.w700),
                        ),
                      )
                    : null;

                final refreshButton = IconButton.filledTonal(
                  style: IconButton.styleFrom(
                    shape: RoundedRectangleBorder(
                      borderRadius: BorderRadius.circular(22),
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
                    final isDesktopWide = constraints.maxWidth >=
                        (WebRuntimePolicy.isWeb ? 900 : 960);

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
                          if (addCompanyChainsButton != null) ...[
                            const SizedBox(width: 10),
                            addCompanyChainsButton,
                          ],
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
                            if (addCompanyChainsButton != null) ...[
                              const SizedBox(width: 8),
                              addCompanyChainsButton,
                            ],
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
                        Text(state.message, style: TextStyle(color: colorScheme.error)),
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
                      final matchesName = d.fullName.toLowerCase().contains(query);
                      final matchesPhone = d.phoneNumber.contains(query);
                      final matchesNat = d.nationalityID.contains(query);
                      if (!matchesName && !matchesPhone && !matchesNat) {
                        return false;
                      }
                    }
                    if (_selectedStatus != null && d.status != _selectedStatus) {
                      return false;
                    }
                    return true;
                  }).toList();

                  if (filtered.isEmpty) {
                    return Center(
                      child: Column(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          Icon(
                            Icons.people_outline_rounded,
                            size: 56,
                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.5),
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

  Widget _buildDelegatesBody(
    List<Delegate> delegates,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    if (WebRuntimePolicy.isWeb) {
      final narrow = MediaQuery.sizeOf(context).width <
          HRDelegatesWebBreakpoints.cardsBelow;
      if (narrow || _viewMode == HRDelegatesViewMode.cards) {
        return _buildCardsGrid(delegates, theme, colorScheme);
      }
      return _buildWebDelegatesTable(delegates, theme, colorScheme);
    }
    return _viewMode == HRDelegatesViewMode.table
        ? _buildDelegatesTable(delegates, theme, colorScheme)
        : _buildCardsGrid(delegates, theme, colorScheme);
  }

  /// Web table columns (MD3 Model 3). Header and cells use the same list,
  /// the same cell padding and the same alignment, so they always line up.
  List<_WebCol> _webColumns(bool merged) => merged
      ? const [
          _WebCol('المندوب / المروج', 3),
          _WebCol('الرقم القومي / الهاتف', 3),
          _WebCol('السلاسل', 2, center: true),
          _WebCol('الحالة', 2, center: true),
          _WebCol('الإجراءات', 2, center: true),
        ]
      : const [
          _WebCol('#', 1, center: true),
          _WebCol('المندوب / المروج', 4),
          _WebCol('الرقم القومي', 3),
          _WebCol('رقم الهاتف', 3),
          _WebCol('المدينة', 3),
          _WebCol('السلاسل', 2, center: true),
          _WebCol('الحالة', 2, center: true),
          _WebCol('الإجراءات', 3, center: true),
        ];

  static const double _webCellPadding = 8;

  Widget _webCell(_WebCol col, Widget child) => Expanded(
        flex: col.flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: _webCellPadding),
          child: Align(
            alignment: col.center
                ? Alignment.center
                : AlignmentDirectional.centerStart,
            child: child,
          ),
        ),
      );

  /// Web table (MD3 Model 3): no row tap, icon actions, and the ID/phone
  /// and name/city columns merge on narrower tables.
  Widget _buildWebDelegatesTable(
    List<Delegate> delegates,
    ThemeData theme,
    ColorScheme colorScheme,
  ) {
    const minWidth = 860.0;

    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      child: Container(
        decoration: BoxDecoration(
          color: colorScheme.surface,
          borderRadius: BorderRadius.circular(16),
          border: Border.all(
            color: colorScheme.outlineVariant.withValues(alpha: 0.6),
          ),
        ),
        clipBehavior: Clip.antiAlias,
        child: LayoutBuilder(
          builder: (context, constraints) {
            final available = constraints.maxWidth;
            final width = available > minWidth ? available : minWidth;
            final merged = width < HRDelegatesWebBreakpoints.mergedColumnsBelow;
            final scrollable = width > available;
            final cols = _webColumns(merged);

            final table = SizedBox(
              width: width,
              child: Column(
                children: [
                  Container(
                    height: 44,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                    decoration: BoxDecoration(
                      color: colorScheme.surfaceContainerLow,
                      border: Border(
                        bottom: BorderSide(
                          color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                        ),
                      ),
                    ),
                    child: Row(
                      children: [
                        for (final c in cols)
                          _webCell(
                            c,
                            Text(
                              c.title,
                              key: Key('hr_delegates_header_${c.title}'),
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.labelMedium?.copyWith(
                                color: colorScheme.onSurfaceVariant,
                                fontWeight: FontWeight.bold,
                                fontSize: 12.5,
                              ),
                            ),
                          ),
                      ],
                    ),
                  ),
                  Expanded(
                    child: ListView.separated(
                      controller: _vScrollCtrl,
                      physics: const AlwaysScrollableScrollPhysics(),
                      itemCount: delegates.length,
                      separatorBuilder: (_, _) => Divider(
                        height: 1,
                        thickness: 1,
                        color: colorScheme.outlineVariant.withValues(alpha: 0.3),
                      ),
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
              ),
            );

            if (!scrollable) return table;
            return Scrollbar(
              controller: _hScrollCtrl,
              thumbVisibility: true,
              notificationPredicate: (n) =>
                  n.depth == 0 && n.metrics.axis == Axis.horizontal,
              child: SingleChildScrollView(
                controller: _hScrollCtrl,
                scrollDirection: Axis.horizontal,
                child: table,
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildWebRow(
    Delegate delegate,
    int index, {
    required List<_WebCol> cols,
    required bool merged,
    required ThemeData theme,
    required ColorScheme colorScheme,
  }) {
    final isActive = delegate.status == DelegateStatus.active;
    final statusColor =
        isActive ? const Color(0xFF2E7D32) : colorScheme.onSurfaceVariant;
    final statusBg = isActive
        ? const Color(0xFF2E7D32).withValues(alpha: 0.12)
        : colorScheme.surfaceContainerHighest;
    final city = delegate.city.isNotEmpty
        ? delegate.city
        : (delegate.companyName.isNotEmpty ? delegate.companyName : '—');

    final mono = theme.textTheme.bodySmall?.copyWith(
      fontWeight: FontWeight.w600,
      color: colorScheme.onSurface,
      letterSpacing: 0.3,
    );
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
                    Text(delegate.fullName, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
                    Text(
                      city,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: colorScheme.onSurfaceVariant,
                        fontSize: 11.5,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ],
                )
              : Text(delegate.fullName, style: nameStyle, maxLines: 1, overflow: TextOverflow.ellipsis),
        ),
      ],
    );

    final chainCount = _chainCount(delegate);
    final chains = Tooltip(
      message: 'مرتبط بـ $chainCount سلسلة',
      child: Container(
        key: Key('hr_delegate_chains_${delegate.uid}'),
        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 3),
        decoration: BoxDecoration(
          border: Border.all(color: colorScheme.outlineVariant),
          borderRadius: BorderRadius.circular(8),
        ),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Symbols.storefront_rounded, size: 15, color: colorScheme.onSurfaceVariant),
            const SizedBox(width: 4),
            Text(
              '$chainCount',
              style: TextStyle(
                fontSize: 12.5,
                fontWeight: FontWeight.w700,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
      ),
    );

    final status = Container(
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
      decoration: BoxDecoration(
        color: statusBg,
        borderRadius: BorderRadius.circular(8),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(Icons.circle, size: 7, color: statusColor),
          const SizedBox(width: 5),
          Text(
            isActive ? 'نشط' : 'متوقف',
            style: TextStyle(
              color: statusColor,
              fontSize: 12,
              fontWeight: FontWeight.w600,
            ),
          ),
        ],
      ),
    );

    final actions = Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        for (final (i, w) in _buildWebActions(delegate, colorScheme).indexed) ...[
          if (i > 0) const SizedBox(width: 2),
          w,
        ],
      ],
    );

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
                  style: mono?.copyWith(color: colorScheme.onSurfaceVariant),
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

    return Container(
      key: Key('hr_delegate_row_${delegate.uid}'),
      padding: const EdgeInsets.symmetric(horizontal: 8),
      constraints: const BoxConstraints(minHeight: 52),
      child: Row(
        children: [
          for (var i = 0; i < cols.length; i++) _webCell(cols[i], cells[i]),
        ],
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
          borderRadius: BorderRadius.circular(16),
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
            final contentWidth =
                availableWidth > minWidth ? availableWidth : minWidth;
            final isScrollable = contentWidth > availableWidth;

            return Scrollbar(
              controller: _hScrollCtrl,
              thumbVisibility: isScrollable,
              trackVisibility: isScrollable,
              interactive: isScrollable,
              thickness: 10.0,
              radius: const Radius.circular(8),
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
                          color: colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.45),
                          border: Border(
                            bottom: BorderSide(
                              color: colorScheme.outlineVariant
                                  .withValues(alpha: 0.6),
                              width: 1.5,
                            ),
                          ),
                        ),
                        child: Row(
                          children: [
                            _buildHeaderCell('#', flex: 4, theme: theme, colorScheme: colorScheme, isCenter: true),
                            _buildHeaderCell('المندوب / المروج', flex: 20, theme: theme, colorScheme: colorScheme),
                            _buildHeaderCell('الرقم القومي', flex: 15, theme: theme, colorScheme: colorScheme),
                            _buildHeaderCell('رقم الهاتف', flex: 14, theme: theme, colorScheme: colorScheme),
                            _buildHeaderCell('المدينة / المحافظة', flex: 13, theme: theme, colorScheme: colorScheme),
                            _buildHeaderCell('الحالة', flex: 10, theme: theme, colorScheme: colorScheme, isCenter: true),
                            _buildHeaderCell('الإجراءات والملف', flex: 34, theme: theme, colorScheme: colorScheme, isCenter: true),
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
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.22),
                          ),
                          itemBuilder: (context, index) {
                            final delegate = delegates[index];
                            final isActive = delegate.status == DelegateStatus.active;
                            final statusColor =
                                isActive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
                            final statusText = isActive ? 'نشط' : 'متوقف';

                            final posName = delegate.position == DelegatePosition.supervisor
                                ? 'مشرف'
                                : 'مندوب / مروج';

                            return InkWell(
                              onTap: () => _openProfile(delegate),
                              hoverColor: colorScheme.primaryContainer.withValues(alpha: 0.12),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                color: index.isEven
                                    ? colorScheme.surface
                                    : colorScheme.surfaceContainerHighest.withValues(alpha: 0.18),
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
                                              crossAxisAlignment: CrossAxisAlignment.start,
                                              mainAxisAlignment: MainAxisAlignment.center,
                                              children: [
                                                Text(
                                                  delegate.fullName,
                                                  style: theme.textTheme.bodyMedium?.copyWith(
                                                    fontWeight: FontWeight.bold,
                                                    color: colorScheme.onSurface,
                                                  ),
                                                  maxLines: 1,
                                                  overflow: TextOverflow.ellipsis,
                                                ),
                                                const SizedBox(height: 2),
                                                Text(
                                                  posName,
                                                  style: theme.textTheme.bodySmall?.copyWith(
                                                    color: colorScheme.primary,
                                                    fontWeight: FontWeight.w600,
                                                    fontSize: 11,
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
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                                letterSpacing: 0.5,
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ),
                                          if (delegate.nationalityID.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.copy_rounded, size: 14),
                                              tooltip: 'نسخ الرقم القومي',
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                              onPressed: () => _copyNationalId(delegate.nationalityID),
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
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontFamily: 'monospace',
                                                fontWeight: FontWeight.w600,
                                                color: colorScheme.onSurface,
                                                letterSpacing: 0.3,
                                              ),
                                              textAlign: TextAlign.start,
                                            ),
                                          ),
                                          if (delegate.phoneNumber.isNotEmpty)
                                            IconButton(
                                              icon: const Icon(Icons.copy_rounded, size: 14),
                                              tooltip: 'نسخ رقم الهاتف',
                                              visualDensity: VisualDensity.compact,
                                              padding: EdgeInsets.zero,
                                              constraints: const BoxConstraints(minWidth: 24, minHeight: 24),
                                              onPressed: () => _copyPhoneNumber(delegate.phoneNumber),
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
                                            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                                          ),
                                          const SizedBox(width: 5),
                                          Expanded(
                                            child: Text(
                                              delegate.city.isNotEmpty
                                                  ? delegate.city
                                                  : (delegate.companyName.isNotEmpty
                                                      ? delegate.companyName
                                                      : '—'),
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                color: colorScheme.onSurface,
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
                                          padding:
                                              const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: statusColor.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(20),
                                            border:
                                                Border.all(color: statusColor.withValues(alpha: 0.3)),
                                          ),
                                          child: Row(
                                            mainAxisSize: MainAxisSize.min,
                                            children: [
                                              Icon(Icons.circle, size: 7, color: statusColor),
                                              const SizedBox(width: 5),
                                              Text(
                                                statusText,
                                                style: TextStyle(
                                                  color: statusColor,
                                                  fontSize: 11,
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
                                        child: _buildTableActionsButtonGroup(delegate, colorScheme),
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
            fontSize: 12.5,
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
            padding: const EdgeInsets.symmetric(
              horizontal: 16,
              vertical: 12,
            ),
            gridDelegate: SliverGridDelegateWithMaxCrossAxisExtent(
              maxCrossAxisExtent: 550,
              mainAxisExtent: WebRuntimePolicy.isWeb ? 190 : 175,
              crossAxisSpacing: 12,
              mainAxisSpacing: 12,
            ),
            itemCount: filtered.length,
            itemBuilder: (context, index) {
              return _buildDelegateCard(
                filtered[index],
                theme,
                colorScheme,
              );
            },
          );
        }

        return ListView.separated(
          padding: const EdgeInsets.symmetric(
            horizontal: 16,
            vertical: 12,
          ),
          itemCount: filtered.length,
          separatorBuilder: (_, _) => const SizedBox(height: 10),
          itemBuilder: (context, index) {
            return _buildDelegateCard(
              filtered[index],
              theme,
              colorScheme,
            );
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
    final statusColor =
        isActive ? const Color(0xFF2E7D32) : const Color(0xFFC62828);
    final statusText = isActive ? 'نشط' : 'متوقف';

    final posName = delegate.position == DelegatePosition.supervisor
        ? 'مشرف'
        : 'مندوب / مروج';

    return Card(
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
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
                      // Web: the type is the same for everyone, so it's hidden.
                      if (!WebRuntimePolicy.isWeb)
                        Text(
                          posName,
                          style: theme.textTheme.bodySmall?.copyWith(
                            color: colorScheme.primary,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                      const SizedBox(height: 3),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2),
                        decoration: BoxDecoration(
                          color: delegate.isAnnualLeaveEnabled
                              ? const Color(0xFF2E7D32).withValues(alpha: 0.1)
                              : Colors.amber.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(6),
                          border: Border.all(
                            color: delegate.isAnnualLeaveEnabled
                                ? const Color(0xFF2E7D32).withValues(alpha: 0.25)
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
                                  ? const Color(0xFF2E7D32)
                                  : Colors.amber.shade900,
                            ),
                            const SizedBox(width: 4),
                            Text(
                              delegate.isAnnualLeaveEnabled
                                  ? 'سنوي (${delegate.annualLeaveQuota} يوم)'
                                  : 'أسبوعي فقط (تجربة)',
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: delegate.isAnnualLeaveEnabled
                                    ? const Color(0xFF2E7D32)
                                    : Colors.amber.shade900,
                              ),
                            ),
                          ],
                        ),
                      ),
                      if (delegate.nationalityID.isNotEmpty)
                        Row(
                          children: [
                            Icon(Icons.badge_outlined,
                                size: 14, color: colorScheme.onSurfaceVariant),
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
                  padding:
                      const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.12),
                    borderRadius: BorderRadius.circular(20),
                    border: Border.all(color: statusColor.withValues(alpha: 0.3)),
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
                          fontSize: 11,
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
            if (WebRuntimePolicy.isWeb)
              Align(
                alignment: AlignmentDirectional.centerEnd,
                child: Wrap(
                  spacing: 4,
                  runSpacing: 4,
                  alignment: WrapAlignment.end,
                  children: _buildWebActions(delegate, colorScheme),
                ),
              )
            else
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
  Widget _buildTableActionsButtonGroup(Delegate delegate, ColorScheme colorScheme) {
    final hasPhone = delegate.phoneNumber.trim().isNotEmpty;

    return Container(
      height: 32,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(16),
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
                hoverColor: (delegate.isAnnualLeaveEnabled
                        ? const Color(0xFF2E7D32)
                        : Colors.amber.shade800)
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
                            ? const Color(0xFF2E7D32)
                            : Colors.amber.shade800,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        delegate.isAnnualLeaveEnabled ? 'سنوية' : 'أسبوعية',
                        style: TextStyle(
                          fontSize: 11,
                          fontWeight: FontWeight.bold,
                          color: delegate.isAnnualLeaveEnabled
                              ? const Color(0xFF2E7D32)
                              : Colors.amber.shade800,
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
                onTap: () {
                  Navigator.push(
                    context,
                    MaterialPageRoute(
                      builder: (_) => HRDelegateAttendanceDetailScreen(
                        delegate: delegate,
                        hrDelegate: widget.hrDelegate,
                      ),
                    ),
                  );
                },
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
                          fontSize: 11,
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
                          fontSize: 11,
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

/// One web table column: same flex, padding and alignment for the header
/// and every cell.
class _WebCol {
  const _WebCol(this.title, this.flex, {this.center = false});
  final String title;
  final int flex;
  final bool center;
}
