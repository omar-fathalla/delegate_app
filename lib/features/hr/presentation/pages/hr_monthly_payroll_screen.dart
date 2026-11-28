import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/attendance/domain/missing_check_out_rule.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_table.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/hr/data/models/company_payroll_config_model.dart';
import 'package:delegate_app/features/hr/domain/services/delegate_payroll_calculator.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// كشف مسير الرواتب الشهري المربوط بساعات العمل والورديات والجزاءات والسياسات الديناميكية
class HRMonthlyPayrollScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  const HRMonthlyPayrollScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
  });

  /// Tests swap in a fake Firestore here. Null uses the real instance.
  @visibleForTesting
  static FirebaseFirestore Function()? debugFirestore;

  static FirebaseFirestore get _firestore =>
      debugFirestore?.call() ?? FirebaseFirestore.instance;

  @override
  State<HRMonthlyPayrollScreen> createState() => _HRMonthlyPayrollScreenState();
}

class _HRMonthlyPayrollScreenState extends State<HRMonthlyPayrollScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isLoading = true;
  String? _errorMessage;

  List<Delegate> _companyDelegates = [];
  List<DelegatePayrollItem> _payrollItems = [];
  late CompanyPayrollConfig _companyPayrollConfig;

  final TextEditingController _searchController = TextEditingController();
  String _searchQuery = '';

  @override
  void initState() {
    super.initState();
    _companyPayrollConfig = CompanyPayrollConfig(
      companyUID: widget.hrDelegate.companyUID,
      calculationMode: PayrollCalculationMode.monthlyWithDeductions,
      defaultDailyShiftHours: 9.0,
      defaultMonthlyBaseSalary: 3500.0,
      defaultMonthlyWorkingDays: 26,
    );
    _loadPayrollData();
  }

  /// Web shell header bridge. The top-bar refresh reloads this page through
  /// it, so the web toolbar has no refresh button of its own (TAS-119).
  HrWebHeaderBridge? _headerBridge;

  @override
  void didChangeDependencies() {
    super.didChangeDependencies();
    if (!WebRuntimePolicy.isWeb) return;
    final next = context
        .getInheritedWidgetOfExactType<HrWebHeaderBridgeScope>()
        ?.notifier;
    if (identical(next, _headerBridge)) return;
    _headerBridge?.releasePageReload(kHrTabPayroll, _loadPayrollData);
    _headerBridge = next;
    _headerBridge?.attachPageReload(kHrTabPayroll, _loadPayrollData);
  }

  @override
  void dispose() {
    _headerBridge?.releasePageReload(kHrTabPayroll, _loadPayrollData);
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPayrollData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // TAS-362: start date of the «forgotten session = zero» rule.
      await MissingCheckOutRule.ensureLoaded(HRMonthlyPayrollScreen._firestore);

      // 1. Fetch Company Payroll Configuration
      try {
        final configDoc = await HRMonthlyPayrollScreen._firestore
            .collection('company_payroll_configs')
            .doc(widget.hrDelegate.companyUID)
            .get();

        if (configDoc.exists && configDoc.data() != null) {
          _companyPayrollConfig = CompanyPayrollConfigModel.fromFirestore(configDoc);
        } else {
          _companyPayrollConfig = CompanyPayrollConfig(
            companyUID: widget.hrDelegate.companyUID,
            calculationMode: PayrollCalculationMode.monthlyWithDeductions,
            defaultDailyShiftHours: 9.0,
            defaultMonthlyBaseSalary: 3500.0,
            defaultMonthlyWorkingDays: 26,
          );
        }
      } catch (e) {
        debugPrint('Error loading company payroll config: $e');
      }

      // 2. Get Company Delegates
      final delegatesRes = await di.sl<GetCompanyDelegates>()(
        GetCompanyDelegatesParams(
          organizationUID: widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );

      delegatesRes.fold(
        (failure) => _errorMessage = failure.message,
        (page) => _companyDelegates = page.delegates,
      );

      if (_companyDelegates.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      // 3. Fetch User Wallets for base salary and individual shift overrides
      final walletsSnap = await HRMonthlyPayrollScreen._firestore
          .collection('user_wallets')
          .where('companyUID', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      final Map<String, Map<String, dynamic>> walletConfigByDelegateId = {};
      for (final doc in walletsSnap.docs) {
        if (doc.data()['companyUID'] != widget.hrDelegate.companyUID) continue;
        walletConfigByDelegateId[doc.id] = doc.data();
      }

      // 4. Penalties of the company (status and month are filtered by the
      // shared calculator, TAS-308 / TAS-366).
      final penaltiesSnap = await HRMonthlyPayrollScreen._firestore
          .collection('penalties')
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      final Map<String, List<Map<String, dynamic>>> penaltiesByDelegateId = {};
      for (final doc in penaltiesSnap.docs) {
        final data = doc.data();
        final delId = (data['targetDelegateId'] ?? '').toString();
        if (delId.isNotEmpty) {
          penaltiesByDelegateId.putIfAbsent(delId, () => []).add(data);
        }
      }

      // 5. Approved leaves of the company
      final leavesSnap = await HRMonthlyPayrollScreen._firestore
          .collection('leave_requests')
          .where('companyUID', isEqualTo: widget.hrDelegate.companyUID)
          .where('status', isEqualTo: 'approved')
          .get();

      final Map<String, List<Map<String, dynamic>>> leavesByDelegateId = {};
      for (final doc in leavesSnap.docs) {
        final data = doc.data();
        final delId = (data['delegateUid'] ?? '').toString();
        if (delId.isEmpty) continue;
        leavesByDelegateId.putIfAbsent(delId, () => []).add(data);
      }

      // 6. Attendance logs of the company
      final attendanceSnap = await HRMonthlyPayrollScreen._firestore
          .collection(kAttendanceCollection)
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      final Map<String, List<Map<String, dynamic>>> attendanceByDelegateId = {};
      for (final doc in attendanceSnap.docs) {
        final data = doc.data();
        final delId = (data['delegateId'] ?? data['userId'] ?? '').toString();
        if (delId.isEmpty) continue;
        attendanceByDelegateId.putIfAbsent(delId, () => []).add(data);
      }

      // 7. Build payroll items with the calculator the delegate's «مرتبي»
      // screen uses too (TAS-366), so both show the same net.
      final now = DateTime.now();
      final List<DelegatePayrollItem> items = [
        for (final d in _companyDelegates)
          DelegatePayrollCalculator.compute(
            delegate: d,
            config: _companyPayrollConfig,
            wallet: walletConfigByDelegateId[d.uid] ?? const {},
            attendance: attendanceByDelegateId[d.uid] ?? const [],
            leaves: leavesByDelegateId[d.uid] ?? const [],
            penalties: penaltiesByDelegateId[d.uid] ?? const [],
            month: _selectedMonth,
            now: now,
          ),
      ];

      // Sort by delegate full name
      items.sort((a, b) => a.delegate.fullName.compareTo(b.delegate.fullName));

      if (mounted) {
        setState(() {
          _payrollItems = items;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() {
          _errorMessage = 'حدث خطأ في احتساب مسير الرواتب: $e';
          _isLoading = false;
        });
      }
    }
  }

  List<DelegatePayrollItem> get _filteredPayrollItems {
    if (_searchQuery.isEmpty) return _payrollItems;
    final q = _searchQuery.toLowerCase();
    return _payrollItems.where((item) {
      final name = item.delegate.fullName.toLowerCase();
      final phone = item.delegate.phoneNumber.toLowerCase();
      return name.contains(q) || phone.contains(q);
    }).toList();
  }

  Future<void> _exportPayrollToExcel() async {
    final list = _filteredPayrollItems;
    if (list.isEmpty) return;

    try {
      final monthStr = DateFormat('yyyy-MM').format(_selectedMonth);
      final csvHeader =
          '\uFEFFاسم المندوب,رقم الهاتف,المسمى الوظيفي,أيام الحضور,أيام الإجازات المدفوعة,إجازات غير مدفوعة,أيام الغياب,ساعات العمل الفعلية,الساعات المستهدفة,الراتب الأساسي (ج.م),أجر الساعة (ج.م),الاستحقاق الفعلي (ج.م),استقطاع الغياب/العجز (ج.م),خصومات الجزاءات (ج.م),صافي الصرف المستحق (ج.م)\n';

      final csvRows = list.map((item) {
        final name = item.delegate.fullName.replaceAll(',', ' ');
        final phone = item.delegate.phoneNumber;
        final pos = item.delegate.position == DelegatePosition.supervisor ? 'مشرف' : 'مندوب / مروج';
        final attended = item.attendedDays;
        final leaves = item.approvedLeaveDays;
        final unpaidLeaves = item.unpaidLeaveDays;
        final absent = item.absentDays;
        final hours = item.formattedTotalHours;
        final targetHours = item.targetWorkHours.toStringAsFixed(1);
        final base = item.baseSalary.toStringAsFixed(2);
        final rate = item.effectiveHourlyRate.toStringAsFixed(2);
        final gross = item.grossEarned.toStringAsFixed(2);
        final absenceDed = item.absenceDeductionAmount.toStringAsFixed(2);
        final pen = item.penaltiesDeductions.toStringAsFixed(2);
        final net = item.netSalary.toStringAsFixed(2);

        return '$name,$phone,$pos,$attended,$leaves,$unpaidLeaves,$absent,$hours,$targetHours,$base,$rate,$gross,$absenceDed,$pen,$net';
      }).join('\n');

      final content = '$csvHeader$csvRows';
      final fileName = 'hr_payroll_${widget.hrDelegate.companyName}_$monthStr.csv';

      await FileDownloadHelper.downloadString(
        content: content,
        fileName: fileName,
        mimeType: 'text/csv;charset=utf-8',
        shareText: 'كشف مسير الرواتب لشركة ${widget.hrDelegate.companyName} ($monthStr)',
      );

      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تصدير كشف مسير الرواتب بنجاح'),
            backgroundColor: HrStatusColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في تصدير مسير الرواتب: $e')),
        );
      }
    }
  }

  /// نافذة ضبط سياسة وقواعد الرواتب على مستوى الشركة
  void _openCompanyPayrollPolicyDialog() {
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
        ),
        builder: (ctx) => _CompanyPayrollPolicySheet(
          config: _companyPayrollConfig,
          hrDelegate: widget.hrDelegate,
          isBottomSheet: true,
          onSave: _saveCompanyPayrollPolicy,
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.pill)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          // Size to content: capped width on web, and a max height relative
          // to the screen so short content leaves no empty area (TAS-152).
          child: ConstrainedBox(
            constraints: BoxConstraints(
              maxWidth: 560,
              maxHeight: MediaQuery.of(ctx).size.height * 0.85,
            ),
            child: _CompanyPayrollPolicySheet(
              config: _companyPayrollConfig,
              hrDelegate: widget.hrDelegate,
              isBottomSheet: false,
              onSave: _saveCompanyPayrollPolicy,
            ),
          ),
        ),
      );
    }
  }

  Future<void> _saveCompanyPayrollPolicy(CompanyPayrollConfigModel newConfig) async {
    try {
      await HRMonthlyPayrollScreen._firestore
          .collection('company_payroll_configs')
          .doc(widget.hrDelegate.companyUID)
          .set(newConfig.toMap(), SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _companyPayrollConfig = newConfig;
        });
        _loadPayrollData();

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم حفظ وتطبيق سياسة الرواتب بنجاح على كافة المناديب'),
            backgroundColor: HrStatusColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في حفظ سياسة الرواتب: $e')),
        );
      }
    }
  }

  /// نافذة تعديل راتب وساعات العمل لمندوب بعينه
  void _openDelegateSalaryDialog(DelegatePayrollItem item) {
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
        ),
        builder: (ctx) => _DelegateSalarySheet(
          item: item,
          hrDelegate: widget.hrDelegate,
          isBottomSheet: true,
          onSave: (baseSal, shiftH, customRate, selectedMode) =>
              _saveDelegateSalary(item, baseSal, shiftH, customRate, selectedMode),
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.pill)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 520, maxHeight: 720),
            child: _DelegateSalarySheet(
              item: item,
              hrDelegate: widget.hrDelegate,
              isBottomSheet: false,
              onSave: (baseSal, shiftH, customRate, selectedMode) =>
                  _saveDelegateSalary(item, baseSal, shiftH, customRate, selectedMode),
            ),
          ),
        ),
      );
    }
  }

  Future<void> _saveDelegateSalary(
    DelegatePayrollItem item,
    double baseSal,
    double shiftH,
    double? customRate,
    PayrollCalculationMode selectedMode,
  ) async {
    try {
      await HRMonthlyPayrollScreen._firestore.collection('user_wallets').doc(item.delegate.uid).set({
        'monthlyAllocation': baseSal,
        'baseSalary': baseSal,
        'dailyShiftHours': shiftH,
        'customHourlyRate': (customRate != null && customRate > 0) ? customRate : null,
        'payrollCalculationMode': selectedMode.code,
        'companyUID': widget.hrDelegate.companyUID,
        'companyName': widget.hrDelegate.companyName,
        'userName': item.delegate.fullName,
        'userPhone': item.delegate.phoneNumber,
        'updatedAt': FieldValue.serverTimestamp(),
        'updatedBy': widget.hrDelegate.fullName,
      }, SetOptions(merge: true));

      if (mounted) {
        setState(() {
          item.baseSalary = baseSal;
          item.dailyShiftHours = shiftH;
          item.customHourlyRate = (customRate != null && customRate > 0) ? customRate : null;
          item.calculationMode = selectedMode;
        });

        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(
            content: Text('تم تحديث إعدادات الراتب للمندوب ${item.delegate.fullName} بنجاح'),
            backgroundColor: HrStatusColors.of(context).success,
          ),
        );
      }
    } catch (e) {
      if (mounted) {
        ScaffoldMessenger.of(context).showSnackBar(
          SnackBar(content: Text('فشل في حفظ تعديلات الراتب: $e')),
        );
      }
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final filtered = _filteredPayrollItems;

    final totalGross = filtered.fold<double>(0.0, (acc, item) => acc + item.grossEarned);
    final totalWorkMinutes = filtered.fold<int>(0, (acc, item) => acc + item.totalWorkMinutes);
    final totalHours = totalWorkMinutes ~/ 60;
    final totalMinsRemainder = totalWorkMinutes % 60;
    final totalAbsenceDeductions = filtered.fold<double>(0.0, (acc, item) => acc + item.absenceDeductionAmount);
    final totalPenalties = filtered.fold<double>(0.0, (acc, item) => acc + item.penaltiesDeductions);
    final totalNetPayout = filtered.fold<double>(0.0, (acc, item) => acc + item.netSalary);

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
                    'مسيرات الرواتب الشهرية',
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
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(6),
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'قواعد وسياسة الرواتب للشركة',
                  onPressed: _openCompanyPayrollPolicyDialog,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(6),
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: 'تصدير مسير الرواتب إلى Excel',
                  onPressed: _exportPayrollToExcel,
                ),
                IconButton(
                  visualDensity: VisualDensity.compact,
                  constraints: const BoxConstraints(minWidth: 36, minHeight: 36),
                  padding: const EdgeInsets.all(6),
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'إعادة الاحتساب والتحديث',
                  onPressed: _loadPayrollData,
                ),
                const SizedBox(width: 4),
              ],
            )
          : null,
      body: _isLoading
          ? const Center(child: CircularProgressIndicator())
          : _errorMessage != null
              ? Center(
                  child: Text(
                    _errorMessage!,
                    style: TextStyle(color: colorScheme.error),
                  ),
                )
              : WebRuntimePolicy.isWeb
              ? _buildWebBody(context, filtered)
              : RefreshIndicator(
                  onRefresh: _loadPayrollData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
                      if (!widget.showAppBar) ...[
                        // The shell's top bar already shows the page title,
                        // so the page keeps only its actions, with labels
                        // (TAS-152).
                        Row(
                          mainAxisAlignment: MainAxisAlignment.end,
                          children: [
                            TextButton.icon(
                              icon: const Icon(Icons.tune_rounded, size: 18),
                              label: const Text('قواعد الرواتب'),
                              onPressed: _openCompanyPayrollPolicyDialog,
                            ),
                            const SizedBox(width: 8),
                            OutlinedButton.icon(
                              icon: const Icon(
                                Icons.file_download_outlined,
                                size: 18,
                              ),
                              label: const Text('تصدير Excel'),
                              onPressed: _exportPayrollToExcel,
                            ),
                            const SizedBox(width: 4),
                            IconButton(
                              icon: const Icon(Icons.refresh_rounded),
                              tooltip: 'إعادة الاحتساب والتحديث',
                              onPressed: _loadPayrollData,
                            ),
                          ],
                        ),
                        const SizedBox(height: 12),
                      ],
                      // ── 4 Top KPI Cards Side-by-Side (Including Date Selector Card) ──
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth >= 768;

                          final dateCard = _buildDateCard(colorScheme: colorScheme, theme: theme);
                          final totalCard = _buildKpiCard(
                            title: 'إجمالي الرواتب',
                            value: '${totalGross.toStringAsFixed(0)} ج.م',
                            icon: Icons.account_balance_wallet_rounded,
                            color: colorScheme.primary,
                            colorScheme: colorScheme,
                            subtitle: '$totalHours س و $totalMinsRemainder د عمل',
                          );
                          final penaltiesCard = _buildKpiCard(
                            title: 'خصومات الجزاءات',
                            value: totalPenalties > 0 ? '-${totalPenalties.toStringAsFixed(0)} ج.م' : '0 ج.م',
                            icon: Icons.gavel_rounded,
                            color: totalPenalties > 0 ? const Color(0xFFC2185B) : colorScheme.outline,
                            colorScheme: colorScheme,
                            subtitle: totalAbsenceDeductions > 0 ? 'استقطاع غياب: -${totalAbsenceDeductions.toStringAsFixed(0)} ج.م' : null,
                          );
                          final netCard = _buildKpiCard(
                            title: 'صافي المستحق للصرف',
                            value: '${totalNetPayout.toStringAsFixed(0)} ج.م',
                            icon: Icons.payments_rounded,
                            color: HrStatusColors.of(context).success,
                            colorScheme: colorScheme,
                            subtitle: 'لـ ${filtered.length} مندوب ومروج',
                          );

                          if (isDesktop) {
                            return IntrinsicHeight(
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.stretch,
                                children: [
                                  Expanded(child: dateCard),
                                  const SizedBox(width: 10),
                                  Expanded(child: totalCard),
                                  const SizedBox(width: 10),
                                  Expanded(child: penaltiesCard),
                                  const SizedBox(width: 10),
                                  Expanded(child: netCard),
                                ],
                              ),
                            );
                          } else {
                            return Column(
                              children: [
                                Row(
                                  children: [
                                    Expanded(child: dateCard),
                                    const SizedBox(width: 10),
                                    Expanded(child: totalCard),
                                  ],
                                ),
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: penaltiesCard),
                                    const SizedBox(width: 10),
                                    Expanded(child: netCard),
                                  ],
                                ),
                              ],
                            );
                          }
                        },
                      ),

                      const SizedBox(height: 14),

                      // ── Search Bar ──
                      SizedBox(
                        height: 44,
                        child: TextField(
                          controller: _searchController,
                          onChanged: (val) => setState(() => _searchQuery = val.trim()),
                          textAlignVertical: TextAlignVertical.center,
                          style: TextStyle(fontSize: HrFont.body, color: colorScheme.onSurface),
                          decoration: InputDecoration(
                            hintText: 'بحث باسم المندوب أو رقم الهاتف...',
                            hintStyle: TextStyle(
                              fontSize: HrFont.labelMedium,
                              color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                            ),
                            prefixIcon: Icon(Icons.search_rounded, size: 19, color: colorScheme.primary),
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
                              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                            ),
                            enabledBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(HrRadius.pill),
                              borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                            ),
                            focusedBorder: OutlineInputBorder(
                              borderRadius: BorderRadius.circular(HrRadius.pill),
                              borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                            ),
                          ),
                        ),
                      ),

                      const SizedBox(height: 16),

                      // ── Advanced Enterprise Payroll Table ──
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(HrRadius.card),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        clipBehavior: Clip.antiAlias,
                        child: LayoutBuilder(
                          builder: (context, constraints) {
                            const minWidth = 1150.0;
                            final width = constraints.maxWidth > minWidth ? constraints.maxWidth : minWidth;

                            return SingleChildScrollView(
                              scrollDirection: Axis.horizontal,
                              child: SizedBox(
                                width: width,
                                child: Column(
                                  children: [
                                    // Table Header
                                    Container(
                                      padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                                      color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                                      child: Row(
                                        children: const [
                                          Expanded(flex: 22, child: Text('المندوب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 10, child: Text('الحضور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 10, child: Text('الإجازات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 10, child: Text('الغياب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 14, child: Text('ساعات العمل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 13, child: Text('الأساسي / الساعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 12, child: Text('الاستحقاق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 14, child: Text('إجمالي الخصومات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          Expanded(flex: 13, child: Text('صافي الصرف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body))),
                                          SizedBox(width: 44, child: Center(child: Text('إجراء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.labelMedium)))),
                                        ],
                                      ),
                                    ),
                                    const Divider(height: 1),

                                    // Rows
                                    ListView.separated(
                                      shrinkWrap: true,
                                      physics: const NeverScrollableScrollPhysics(),
                                      itemCount: filtered.length,
                                      separatorBuilder: (_, _) => const Divider(height: 1),
                                      itemBuilder: (context, index) {
                                        final item = filtered[index];
                                        return InkWell(
                                          onTap: () => _showEmployeePayrollDetail(item),
                                          child: Container(
                                            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 10),
                                            color: index.isEven
                                                ? colorScheme.surface
                                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15),
                                            child: Row(
                                              children: [
                                                // المندوب
                                                Expanded(
                                                  flex: 22,
                                                  child: Row(
                                                    children: [
                                                      AppAvatar(
                                                        imageUrl: item.delegate.personalPhotoUrl,
                                                        fallbackText: item.delegate.fullName,
                                                        radius: 17,
                                                      ),
                                                      const SizedBox(width: 8),
                                                      Expanded(
                                                        child: Column(
                                                          crossAxisAlignment: CrossAxisAlignment.start,
                                                          children: [
                                                            Text(
                                                              item.delegate.fullName,
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            Directionality(
                                                              textDirection: TextDirection.ltr,
                                                              child: Text(
                                                                item.delegate.phoneNumber,
                                                                style: TextStyle(
                                                                  fontSize: HrFont.labelSmall,
                                                                  color: colorScheme.onSurfaceVariant,
                                                                ),
                                                              ),
                                                            ),
                                                          ],
                                                        ),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // الحضور
                                                Expanded(
                                                  flex: 10,
                                                  child: Text(
                                                    '${item.attendedDays} يوم',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: item.attendedDays > 0 ? colorScheme.onSurface : colorScheme.outline,
                                                    ),
                                                  ),
                                                ),

                                                // الإجازات
                                                Expanded(
                                                  flex: 10,
                                                  child: Text(
                                                    '${item.approvedLeaveDays} يوم',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: item.approvedLeaveDays > 0 ? colorScheme.primary : colorScheme.outline,
                                                    ),
                                                  ),
                                                ),

                                                // الغياب
                                                Expanded(
                                                  flex: 10,
                                                  child: Text(
                                                    '${item.absentDays} يوم',
                                                    style: TextStyle(
                                                      fontWeight: FontWeight.w600,
                                                      color: item.absentDays > 0 ? colorScheme.error : colorScheme.outline,
                                                    ),
                                                  ),
                                                ),

                                                // ساعات العمل
                                                Expanded(
                                                  flex: 14,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        item.formattedTotalHours,
                                                        style: const TextStyle(fontSize: HrFont.labelMedium, fontWeight: FontWeight.bold),
                                                      ),
                                                      Text(
                                                        'من ${item.targetWorkHours.toStringAsFixed(0)} س مطلوب',
                                                        style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // الأساسي / أجر الساعة
                                                Expanded(
                                                  flex: 13,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        '${item.baseSalary.toStringAsFixed(0)} ج.م',
                                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: HrFont.labelMedium),
                                                      ),
                                                      Text(
                                                        '${item.effectiveHourlyRate.toStringAsFixed(1)} ج.م/س',
                                                        style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.primary),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // الاستحقاق
                                                Expanded(
                                                  flex: 12,
                                                  child: Text(
                                                    '${item.grossEarned.toStringAsFixed(0)} ج.م',
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: HrFont.labelMedium),
                                                  ),
                                                ),

                                                // إجمالي الخصومات (غياب + جزاءات)
                                                Expanded(
                                                  flex: 14,
                                                  child: Column(
                                                    crossAxisAlignment: CrossAxisAlignment.start,
                                                    mainAxisAlignment: MainAxisAlignment.center,
                                                    children: [
                                                      Text(
                                                        item.totalDeductions > 0 ? '-${item.totalDeductions.toStringAsFixed(0)} ج.م' : '0 ج.م',
                                                        style: TextStyle(
                                                          color: item.totalDeductions > 0 ? colorScheme.error : colorScheme.outline,
                                                          fontWeight: FontWeight.bold,
                                                          fontSize: HrFont.labelMedium,
                                                        ),
                                                      ),
                                                      if (item.totalDeductions > 0)
                                                        Text(
                                                          'غياب: ${item.absenceDeductionAmount.toStringAsFixed(0)}${item.penaltiesDeductions > 0 ? ' | جزاء: ${item.penaltiesDeductions.toStringAsFixed(0)}' : ''}',
                                                          style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.error.withValues(alpha: 0.8)),
                                                        ),
                                                    ],
                                                  ),
                                                ),

                                                // صافي الصرف
                                                Expanded(
                                                  flex: 13,
                                                  child: Container(
                                                    padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
                                                    decoration: BoxDecoration(
                                                      color: HrStatusColors.of(context).success.withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(HrRadius.chip),
                                                      border: Border.all(color: HrStatusColors.of(context).success.withValues(alpha: 0.3)),
                                                    ),
                                                    child: Text(
                                                      '${item.netSalary.toStringAsFixed(0)} ج.م',
                                                      style: TextStyle(
                                                        color: HrStatusColors.of(context).success,
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: HrFont.labelMedium,
                                                      ),
                                                      textAlign: TextAlign.center,
                                                    ),
                                                  ),
                                                ),

                                                // زر الإجراءات
                                                SizedBox(
                                                  width: 44,
                                                  child: Center(
                                                    child: IconButton(
                                                      icon: const Icon(Icons.tune_rounded, size: 18),
                                                      tooltip: 'تعديل راتب وساعات المندوب',
                                                      onPressed: () => _openDelegateSalaryDialog(item),
                                                    ),
                                                  ),
                                                ),
                                              ],
                                            ),
                                          ),
                                        );
                                      },
                                    ),
                                  ],
                                ),
                              ),
                            );
                          },
                        ),
                      ),
                    ],
                  ),
                ),
    );
  }

  // ── Web layout (TAS-119) ──────────────────────────────────────────────
  // Presentation only: every number below comes from the same
  // DelegatePayrollItem getters the mobile layout and the export use.

  static final NumberFormat _webMoneyFormat = NumberFormat('#,##0', 'en');

  static String _webMoney(double value) => '${_webMoneyFormat.format(value.round())} ج.م';

  /// Table columns for the web payroll table. The last one holds the «⋮» menu.
  static const List<HrTableColumn> _webColumns = [
    HrTableColumn('المندوب', 24),
    HrTableColumn('الحضور', 9, center: true),
    HrTableColumn('الإجازات', 9, center: true),
    HrTableColumn('الغياب', 9, center: true),
    HrTableColumn('الأساسي', 12),
    HrTableColumn('الاستحقاق', 12),
    HrTableColumn('الخصومات', 12),
    HrTableColumn('الصافي', 13),
    HrTableColumn('', 7, center: true),
  ];

  void _changeMonth(DateTime month) {
    if (month == _selectedMonth) return;
    setState(() => _selectedMonth = month);
    _loadPayrollData();
  }

  Future<void> _pickMonth() async {
    final picked = await showDatePicker(
      context: context,
      initialDate: _selectedMonth,
      firstDate: DateTime(2023),
      lastDate: DateTime.now().add(const Duration(days: 365)),
      initialDatePickerMode: DatePickerMode.year,
    );
    if (picked != null) _changeMonth(DateTime(picked.year, picked.month, 1));
  }

  Widget _buildWebBody(BuildContext context, List<DelegatePayrollItem> filtered) {
    return ListView(
      key: const Key('payroll_web_body'),
      padding: const EdgeInsets.all(16),
      children: [
        _buildWebToolbar(context),
        const SizedBox(height: 16),
        _buildWebSummary(context, filtered),
        const SizedBox(height: 16),
        _buildWebTable(context, filtered),
      ],
    );
  }

  /// One row: month chip, search, rules (outlined), export (filled).
  Widget _buildWebToolbar(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final search = SizedBox(
      height: 40,
      child: TextField(
        key: const Key('payroll_web_search'),
        controller: _searchController,
        onChanged: (val) => setState(() => _searchQuery = val.trim()),
        textAlignVertical: TextAlignVertical.center,
        style: theme.textTheme.bodyMedium,
        decoration: InputDecoration(
          hintText: 'بحث باسم المندوب أو رقم الهاتف',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(color: colorScheme.onSurfaceVariant),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: colorScheme.onSurfaceVariant),
          suffixIcon: _searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  tooltip: 'مسح البحث',
                  onPressed: () {
                    _searchController.clear();
                    setState(() => _searchQuery = '');
                  },
                )
              : null,
          filled: true,
          fillColor: colorScheme.surfaceContainerHigh,
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          isDense: true,
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HrRadius.pill),
            borderSide: BorderSide.none,
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(HrRadius.pill),
            borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
          ),
        ),
      ),
    );

    final rules = OutlinedButton.icon(
      key: const Key('payroll_web_rules'),
      icon: const Icon(Icons.tune_rounded, size: 18),
      label: const Text('قواعد الرواتب'),
      onPressed: _openCompanyPayrollPolicyDialog,
    );
    final export = FilledButton.icon(
      key: const Key('payroll_web_export'),
      icon: const Icon(Icons.file_download_outlined, size: 18),
      label: const Text('تصدير Excel'),
      onPressed: _exportPayrollToExcel,
    );
    return LayoutBuilder(
      builder: (context, constraints) {
        // Narrow windows put the search on its own line.
        if (constraints.maxWidth < 760) {
          return Column(
            crossAxisAlignment: CrossAxisAlignment.stretch,
            children: [
              search,
              const SizedBox(height: 12),
              Wrap(
                spacing: 8,
                runSpacing: 8,
                crossAxisAlignment: WrapCrossAlignment.center,
                children: [_buildWebMonthChip(context), rules, export],
              ),
            ],
          );
        }
        return Row(
          children: [
            _buildWebMonthChip(context),
            const SizedBox(width: 12),
            Expanded(child: search),
            const SizedBox(width: 12),
            rules,
            const SizedBox(width: 8),
            export,
          ],
        );
      },
    );
  }

  /// Month chip: previous / month name (opens the picker) / next, plus a
  /// shortcut back to the current month.
  Widget _buildWebMonthChip(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final monthStr = DateFormat('MMMM yyyy', 'ar').format(_selectedMonth);

    return Container(
      key: const Key('payroll_web_month_chip'),
      height: 40,
      padding: const EdgeInsets.symmetric(horizontal: 4),
      decoration: BoxDecoration(
        borderRadius: BorderRadius.circular(HrRadius.button),
        border: Border.all(color: colorScheme.outline),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          IconButton(
            tooltip: 'الشهر السابق',
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: const Icon(Icons.chevron_right_rounded),
            onPressed: () => _changeMonth(DateTime(_selectedMonth.year, _selectedMonth.month - 1, 1)),
          ),
          InkWell(
            onTap: _pickMonth,
            borderRadius: BorderRadius.circular(HrRadius.chip),
            child: Padding(
              padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
              child: Row(
                mainAxisSize: MainAxisSize.min,
                children: [
                  Icon(Icons.calendar_month_rounded, size: 18, color: colorScheme.primary),
                  const SizedBox(width: 6),
                  Text(
                    monthStr,
                    style: theme.textTheme.labelLarge?.copyWith(color: colorScheme.onSurface),
                  ),
                ],
              ),
            ),
          ),
          IconButton(
            tooltip: 'الشهر التالي',
            visualDensity: VisualDensity.compact,
            iconSize: 20,
            icon: const Icon(Icons.chevron_left_rounded),
            onPressed: () => _changeMonth(DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1)),
          ),
          if (!isCurrentMonth)
            TextButton(
              style: TextButton.styleFrom(visualDensity: VisualDensity.compact),
              onPressed: () => _changeMonth(DateTime(now.year, now.month, 1)),
              child: const Text('الشهر الحالي'),
            ),
        ],
      ),
    );
  }

  /// Four month totals for the filtered list.
  Widget _buildWebSummary(BuildContext context, List<DelegatePayrollItem> filtered) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = HrStatusColors.of(context);

    final totalGross = filtered.fold<double>(0.0, (acc, item) => acc + item.grossEarned);
    final totalDeductions = filtered.fold<double>(0.0, (acc, item) => acc + item.totalDeductions);
    final totalNet = filtered.fold<double>(0.0, (acc, item) => acc + item.netSalary);

    final cards = <Widget>[
      _WebSummaryCard(
        key: const Key('payroll_summary_count'),
        title: 'عدد المناديب',
        value: '${filtered.length}',
        icon: Icons.groups_rounded,
      ),
      _WebSummaryCard(
        key: const Key('payroll_summary_gross'),
        title: 'إجمالي الاستحقاق',
        value: _webMoney(totalGross),
        icon: Icons.account_balance_wallet_rounded,
      ),
      _WebSummaryCard(
        key: const Key('payroll_summary_deductions'),
        title: 'إجمالي الخصومات',
        value: totalDeductions > 0 ? '-${_webMoney(totalDeductions)}' : _webMoney(0),
        icon: Icons.remove_circle_outline_rounded,
        valueColor: totalDeductions > 0 ? colorScheme.error : null,
      ),
      _WebSummaryCard(
        key: const Key('payroll_summary_net'),
        title: 'صافي الصرف',
        value: _webMoney(totalNet),
        icon: Icons.payments_rounded,
        background: status.successContainer,
        foreground: status.onSuccessContainer,
      ),
    ];

    return LayoutBuilder(
      builder: (context, constraints) {
        if (constraints.maxWidth < 720) {
          return Column(
            children: [
              Row(children: [Expanded(child: cards[0]), const SizedBox(width: 12), Expanded(child: cards[1])]),
              const SizedBox(height: 12),
              Row(children: [Expanded(child: cards[2]), const SizedBox(width: 12), Expanded(child: cards[3])]),
            ],
          );
        }
        return Row(
          children: [
            for (var i = 0; i < cards.length; i++) ...[
              if (i > 0) const SizedBox(width: 12),
              Expanded(child: cards[i]),
            ],
          ],
        );
      },
    );
  }

  Widget _buildWebTable(BuildContext context, List<DelegatePayrollItem> filtered) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final status = HrStatusColors.of(context);
    final muted = colorScheme.onSurfaceVariant;

    Widget days(int count, {Color? activeColor}) => Text(
          '$count يوم',
          style: hrTabularStyle(
            context,
            color: count > 0 ? (activeColor ?? colorScheme.onSurface) : muted,
          ),
        );

    Widget row(DelegatePayrollItem item) {
      final d = item.delegate;
      final position = d.position == DelegatePosition.supervisor ? 'مشرف' : 'مندوب / مروج';
      final hasDeductions = item.totalDeductions > 0;
      final deductionsText = Text(
        hasDeductions ? '-${_webMoney(item.totalDeductions)}' : _webMoney(0),
        key: Key('payroll_deductions_${d.uid}'),
        style: hrTabularStyle(context, color: hasDeductions ? colorScheme.error : muted),
      );

      return HrTableRow(
        key: Key('payroll_row_${d.uid}'),
        columns: _webColumns,
        onTap: () => _showEmployeePayrollDetail(item),
        cells: [
          // المندوب: name, then role and phone.
          Row(
            children: [
              AppAvatar(
                imageUrl: d.personalPhotoUrl,
                fallbackText: d.fullName,
                radius: 18,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      d.fullName,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodyMedium?.copyWith(fontWeight: FontWeight.w600),
                    ),
                    Row(
                      children: [
                        Text(position, style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                        if (d.phoneNumber.isNotEmpty) ...[
                          Text(' · ', style: theme.textTheme.bodySmall?.copyWith(color: muted)),
                          Flexible(
                            child: Text(
                              d.phoneNumber,
                              textDirection: TextDirection.ltr,
                              maxLines: 1,
                              overflow: TextOverflow.ellipsis,
                              style: theme.textTheme.bodySmall?.copyWith(
                                color: muted,
                                fontFeatures: const [FontFeature.tabularFigures()],
                              ),
                            ),
                          ),
                        ],
                      ],
                    ),
                  ],
                ),
              ),
            ],
          ),
          days(item.attendedDays),
          days(item.approvedLeaveDays, activeColor: colorScheme.primary),
          days(item.absentDays, activeColor: colorScheme.error),
          Text(_webMoney(item.baseSalary), style: hrTabularStyle(context)),
          Text(_webMoney(item.grossEarned), style: hrTabularStyle(context)),
          hasDeductions
              ? Tooltip(
                  message: 'غياب: ${_webMoney(item.absenceDeductionAmount)}'
                      '${item.penaltiesDeductions > 0 ? ' | جزاءات: ${_webMoney(item.penaltiesDeductions)}' : ''}',
                  child: deductionsText,
                )
              : deductionsText,
          Container(
            key: Key('payroll_net_${d.uid}'),
            padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
            decoration: BoxDecoration(
              color: status.successContainer,
              borderRadius: BorderRadius.circular(HrRadius.chip),
            ),
            child: Text(
              _webMoney(item.netSalary),
              style: hrTabularStyle(context, color: status.onSuccessContainer)
                  .copyWith(fontWeight: FontWeight.w600),
            ),
          ),
          PopupMenuButton<String>(
            key: Key('payroll_actions_${d.uid}'),
            tooltip: 'الإجراءات',
            icon: Icon(Icons.more_vert_rounded, color: muted),
            onSelected: (value) {
              if (value == 'edit') {
                _openDelegateSalaryDialog(item);
              } else if (value == 'details') {
                _showEmployeePayrollDetail(item);
              }
            },
            itemBuilder: (_) => const [
              PopupMenuItem(
                value: 'edit',
                child: ListTile(
                  leading: Icon(Icons.tune_rounded),
                  title: Text('تعديل الراتب'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
              PopupMenuItem(
                value: 'details',
                child: ListTile(
                  leading: Icon(Icons.visibility_outlined),
                  title: Text('عرض التفاصيل'),
                  contentPadding: EdgeInsets.zero,
                ),
              ),
            ],
          ),
        ],
      );
    }

    return HrTableCard(
      key: const Key('payroll_web_table'),
      minWidth: 1000,
      builder: (context, width) => Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          const HrTableHeader(columns: _webColumns, keyPrefix: 'payroll_col_'),
          if (filtered.isEmpty)
            Padding(
              padding: const EdgeInsets.all(32),
              child: Text(
                _searchQuery.isEmpty ? 'لا توجد بيانات رواتب لهذا الشهر.' : 'لا توجد نتائج مطابقة للبحث.',
                style: theme.textTheme.bodyMedium?.copyWith(color: muted),
              ),
            ),
          for (var i = 0; i < filtered.length; i++) ...[
            if (i > 0) const HrTableDivider(),
            row(filtered[i]),
          ],
        ],
      ),
    );
  }

  Widget _buildDateCard({
    required ColorScheme colorScheme,
    required ThemeData theme,
  }) {
    final now = DateTime.now();
    final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
    final monthStr = DateFormat('MMMM yyyy', 'ar').format(_selectedMonth);

    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          // Top: Icon + Title + Quick 'الحالي' badge
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(
                  Icons.calendar_month_rounded,
                  color: colorScheme.primary,
                  size: 15,
                ),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  'التاريخ / الشهر',
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              if (!isCurrentMonth)
                InkWell(
                  onTap: () {
                    setState(() {
                      _selectedMonth = DateTime(now.year, now.month, 1);
                    });
                    _loadPayrollData();
                  },
                  borderRadius: BorderRadius.circular(6),
                  child: Container(
                    padding: const EdgeInsets.symmetric(horizontal: 5, vertical: 2),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(6),
                    ),
                    child: Text(
                      'الحالي',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.primary,
                      ),
                    ),
                  ),
                ),
            ],
          ),
          const SizedBox(height: 4),

          // Bottom: Navigation Chevrons + Month name (Clickable for picker)
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              // Chevron Previous (Right in RTL)
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month - 1,
                      1,
                    );
                  });
                  _loadPayrollData();
                },
                borderRadius: BorderRadius.circular(HrRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),

              // Month Text
              Expanded(
                child: InkWell(
                  onTap: () async {
                    final picked = await showDatePicker(
                      context: context,
                      initialDate: _selectedMonth,
                      firstDate: DateTime(2023),
                      lastDate: DateTime.now().add(const Duration(days: 365)),
                      initialDatePickerMode: DatePickerMode.year,
                    );
                    if (picked != null) {
                      final newMonth = DateTime(picked.year, picked.month, 1);
                      if (newMonth != _selectedMonth) {
                        setState(() => _selectedMonth = newMonth);
                        _loadPayrollData();
                      }
                    }
                  },
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    child: Tooltip(
                      message: 'اضغط لاختيار شهر آخر',
                      child: Text(
                        monthStr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: HrFont.body,
                          fontWeight: FontWeight.w900,
                          color: colorScheme.primary,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ),
                  ),
                ),
              ),

              // Chevron Next (Left in RTL)
              InkWell(
                onTap: () {
                  setState(() {
                    _selectedMonth = DateTime(
                      _selectedMonth.year,
                      _selectedMonth.month + 1,
                      1,
                    );
                  });
                  _loadPayrollData();
                },
                borderRadius: BorderRadius.circular(HrRadius.chip),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
                    textDirection: TextDirection.ltr,
                  ),
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildKpiCard({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
    String? subtitle,
  }) {
    return Container(
      height: 84,
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(4),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 4),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            crossAxisAlignment: CrossAxisAlignment.baseline,
            textBaseline: TextBaseline.alphabetic,
            children: [
              Text(
                value,
                style: TextStyle(fontSize: HrFont.titleMedium, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.w500,
                    color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
            ],
          ),
        ],
      ),
    );
  }

  void _showEmployeePayrollDetail(DelegatePayrollItem item) {
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(HrRadius.pill)),
        ),
        builder: (ctx) => _EmployeePayrollDetailSheet(
          item: item,
          isBottomSheet: true,
          onEditSalary: () {
            Navigator.pop(ctx);
            _openDelegateSalaryDialog(item);
          },
        ),
      );
    } else {
      showDialog(
        context: context,
        builder: (ctx) => Dialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.pill)),
          backgroundColor: Theme.of(context).colorScheme.surface,
          child: ConstrainedBox(
            constraints: const BoxConstraints(maxWidth: 540, maxHeight: 780),
            child: _EmployeePayrollDetailSheet(
              item: item,
              isBottomSheet: false,
              onEditSalary: () {
                Navigator.pop(ctx);
                _openDelegateSalaryDialog(item);
              },
            ),
          ),
        ),
      );
    }
  }
}

/// ورقة ضبط سياسة وقواعد الرواتب للشركة بنمط M3 مع مجموعة الأزرار المترابطة
class _CompanyPayrollPolicySheet extends StatefulWidget {
  final CompanyPayrollConfig config;
  final Delegate hrDelegate;
  final bool isBottomSheet;
  final Future<void> Function(CompanyPayrollConfigModel newConfig) onSave;

  const _CompanyPayrollPolicySheet({
    required this.config,
    required this.hrDelegate,
    required this.isBottomSheet,
    required this.onSave,
  });

  @override
  State<_CompanyPayrollPolicySheet> createState() =>
      _CompanyPayrollPolicySheetState();
}

class _CompanyPayrollPolicySheetState
    extends State<_CompanyPayrollPolicySheet> {
  late PayrollCalculationMode _selectedMode;
  late TextEditingController _shiftHoursCtrl;
  late TextEditingController _baseSalaryCtrl;
  late TextEditingController _workingDaysCtrl;
  late TextEditingController _customHourlyRateCtrl;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _selectedMode = widget.config.calculationMode;
    _shiftHoursCtrl = TextEditingController(
      text: widget.config.defaultDailyShiftHours.toStringAsFixed(0),
    );
    _baseSalaryCtrl = TextEditingController(
      text: widget.config.defaultMonthlyBaseSalary.toStringAsFixed(0),
    );
    _workingDaysCtrl = TextEditingController(
      text: widget.config.defaultMonthlyWorkingDays.toString(),
    );
    _customHourlyRateCtrl = TextEditingController(
      text: widget.config.defaultHourlyRate != null &&
              widget.config.defaultHourlyRate! > 0
          ? widget.config.defaultHourlyRate!.toStringAsFixed(1)
          : '',
    );
  }

  @override
  void dispose() {
    _shiftHoursCtrl.dispose();
    _baseSalaryCtrl.dispose();
    _workingDaysCtrl.dispose();
    _customHourlyRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final double shiftH = double.tryParse(_shiftHoursCtrl.text.trim()) ?? 9.0;
    final double baseSal = double.tryParse(_baseSalaryCtrl.text.trim()) ?? 3500.0;
    final int workD = int.tryParse(_workingDaysCtrl.text.trim()) ?? 26;
    final double? customRate = double.tryParse(_customHourlyRateCtrl.text.trim());

    final newConfig = CompanyPayrollConfigModel(
      companyUID: widget.hrDelegate.companyUID,
      calculationMode: _selectedMode,
      defaultDailyShiftHours: shiftH,
      defaultMonthlyBaseSalary: baseSal,
      defaultMonthlyWorkingDays: workD,
      defaultHourlyRate: (customRate != null && customRate > 0) ? customRate : null,
      updatedAt: DateTime.now(),
      updatedBy: widget.hrDelegate.fullName,
    );

    await widget.onSave(newConfig);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    final double shiftH = double.tryParse(_shiftHoursCtrl.text.trim()) ?? 9.0;
    final double baseSal = double.tryParse(_baseSalaryCtrl.text.trim()) ?? 3500.0;
    final int workD = int.tryParse(_workingDaysCtrl.text.trim()) ?? 26;
    final double? customRate = double.tryParse(_customHourlyRateCtrl.text.trim());

    final double derivedRate =
        (workD * shiftH) > 0 ? baseSal / (workD * shiftH) : 0.0;
    final double activeRate =
        (customRate != null && customRate > 0) ? customRate : derivedRate;
    final double activeDailyRate = activeRate * shiftH;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Drag Handle Pill on Mobile Bottom Sheet
        if (widget.isBottomSheet)
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

        // 2. Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(
                  Icons.tune_rounded,
                  color: colorScheme.primary,
                  size: 22,
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text(
                      'قواعد وسياسة الرواتب',
                      style: TextStyle(fontSize: HrFont.titleMedium, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'ضبط معايير الورديات واحتساب الساعات للشركة',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 3. Scrollable Body. The bottom sheet has a fixed height, so the body
        // fills it; the dialog has only a max height, so the body takes just
        // the space its content needs and scrolls past that (TAS-152).
        Flexible(
          fit: widget.isBottomSheet ? FlexFit.tight : FlexFit.loose,
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // نمط الاحتساب
                const Text(
                  'طريقة احتساب مسير الرواتب:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(HrRadius.card)),
                        onTap: () => setState(() =>
                            _selectedMode = PayrollCalculationMode.monthlyWithDeductions),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedMode ==
                                        PayrollCalculationMode.monthlyWithDeductions
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: _selectedMode ==
                                        PayrollCalculationMode.monthlyWithDeductions
                                    ? colorScheme.primary
                                    : colorScheme.outline,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'راتب شهري أساسي مع استقطاع الغياب ونقص الساعات',
                                      style: TextStyle(
                                        fontSize: HrFont.body,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'يُحدد راتب أساسي ثابت، ويُخصم منه ما يعادل ساعات الغياب أو العجز عن ساعات الوردية المحددة لكل موظف',
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
                      ),
                      const Divider(height: 1),
                      InkWell(
                        borderRadius: const BorderRadius.vertical(
                            bottom: Radius.circular(HrRadius.card)),
                        onTap: () => setState(() =>
                            _selectedMode = PayrollCalculationMode.hourlyRate),
                        child: Padding(
                          padding: const EdgeInsets.symmetric(
                            horizontal: 14,
                            vertical: 12,
                          ),
                          child: Row(
                            children: [
                              Icon(
                                _selectedMode == PayrollCalculationMode.hourlyRate
                                    ? Icons.radio_button_checked_rounded
                                    : Icons.radio_button_unchecked_rounded,
                                color: _selectedMode ==
                                        PayrollCalculationMode.hourlyRate
                                    ? colorScheme.primary
                                    : colorScheme.outline,
                                size: 20,
                              ),
                              const SizedBox(width: 12),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    const Text(
                                      'احتساب بالساعات المنجزة (ساعات العمل × أجر الساعة)',
                                      style: TextStyle(
                                        fontSize: HrFont.body,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'يتقاضى المندوب أجراً مباشراً عن كل ساعة عمل منجزة + الإجازات الرسمية المعتمدة',
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
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 16),

                // ساعات الوردية والراتب الأساسي وأيام الشهر
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _shiftHoursCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'ساعات الوردية اليومية',
                          suffixText: 'ساعات',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _workingDaysCtrl,
                        keyboardType: TextInputType.number,
                        inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'أيام العمل الرسمية بالشهر',
                          suffixText: 'أيام',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),

                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _baseSalaryCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'الراتب الأساسي الافتراضي',
                          suffixText: 'ج.م',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _customHourlyRateCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'أجر الساعة المخصص (اختياري)',
                          hintText: derivedRate.toStringAsFixed(1),
                          suffixText: 'ج.م/س',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 16),

                // بطاقة المعاينة المباشرة للحساب
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.primary.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(
                      color: colorScheme.primary.withValues(alpha: 0.2),
                    ),
                  ),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'أجر الساعة الفعلي المعتمد:',
                            style: TextStyle(
                              fontSize: HrFont.labelMedium,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${activeRate.toStringAsFixed(2)} ج.م / ساعة',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: HrFont.body,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          Text(
                            'أجر الوردية الكاملة (${shiftH.toStringAsFixed(0)} ساعات):',
                            style: const TextStyle(fontSize: HrFont.labelMedium),
                          ),
                          Text(
                            '${activeDailyRate.toStringAsFixed(2)} ج.م / يوم',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: HrFont.body,
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 6),
                      Row(
                        mainAxisAlignment: MainAxisAlignment.spaceBetween,
                        children: [
                          const Text(
                            'الساعات المستهدفة للشهر:',
                            style: TextStyle(fontSize: HrFont.labelMedium),
                          ),
                          Text(
                            '${(workD * shiftH).toStringAsFixed(0)} ساعة عمل',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: HrFont.labelMedium,
                            ),
                          ),
                        ],
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4. Pinned Connected Action Button Group
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(HrRadius.pill),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // Cancel (إلغاء)
                Expanded(
                  flex: 1,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSaving ? null : () => Navigator.pop(context),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'إلغاء',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1.2,
                  height: 28,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // Save (حفظ)
                Expanded(
                  flex: 1,
                  child: Material(
                    color: colorScheme.primary,
                    child: InkWell(
                      onTap: _isSaving ? null : _handleSave,
                      child: Center(
                        child: _isSaving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: colorScheme.onPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'حفظ',
                                    style: TextStyle(
                                      fontSize: HrFont.body,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimary,
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
        ),
      ],
    );

    if (widget.isBottomSheet) {
      final double sheetHeight = mediaQuery.size.height * 0.85;
      return SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// ورقة تعديل راتب وساعات المندوب بنمط M3 مع مجموعة الأزرار المترابطة
class _DelegateSalarySheet extends StatefulWidget {
  final DelegatePayrollItem item;
  final Delegate hrDelegate;
  final bool isBottomSheet;
  final Future<void> Function(
    double baseSal,
    double shiftH,
    double? customRate,
    PayrollCalculationMode selectedMode,
  ) onSave;

  const _DelegateSalarySheet({
    required this.item,
    required this.hrDelegate,
    required this.isBottomSheet,
    required this.onSave,
  });

  @override
  State<_DelegateSalarySheet> createState() => _DelegateSalarySheetState();
}

class _DelegateSalarySheetState extends State<_DelegateSalarySheet> {
  late TextEditingController _baseSalaryCtrl;
  late TextEditingController _shiftHoursCtrl;
  late TextEditingController _customRateCtrl;
  late PayrollCalculationMode _selectedMode;
  bool _isSaving = false;

  @override
  void initState() {
    super.initState();
    _baseSalaryCtrl = TextEditingController(
      text: widget.item.baseSalary.toStringAsFixed(0),
    );
    _shiftHoursCtrl = TextEditingController(
      text: widget.item.dailyShiftHours.toStringAsFixed(0),
    );
    _customRateCtrl = TextEditingController(
      text: widget.item.customHourlyRate != null &&
              widget.item.customHourlyRate! > 0
          ? widget.item.customHourlyRate!.toStringAsFixed(1)
          : '',
    );
    _selectedMode = widget.item.calculationMode;
  }

  @override
  void dispose() {
    _baseSalaryCtrl.dispose();
    _shiftHoursCtrl.dispose();
    _customRateCtrl.dispose();
    super.dispose();
  }

  Future<void> _handleSave() async {
    setState(() => _isSaving = true);
    final double baseSal =
        double.tryParse(_baseSalaryCtrl.text.trim()) ?? widget.item.baseSalary;
    final double shiftH =
        double.tryParse(_shiftHoursCtrl.text.trim()) ?? widget.item.dailyShiftHours;
    final double? customRate = double.tryParse(_customRateCtrl.text.trim());

    await widget.onSave(baseSal, shiftH, customRate, _selectedMode);
    if (mounted) {
      Navigator.pop(context);
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    final double baseSal =
        double.tryParse(_baseSalaryCtrl.text.trim()) ?? widget.item.baseSalary;
    final double shiftH =
        double.tryParse(_shiftHoursCtrl.text.trim()) ?? widget.item.dailyShiftHours;
    final double? customRate = double.tryParse(_customRateCtrl.text.trim());

    final targetH = widget.item.monthTargetWorkingDays * shiftH;
    final double derivedRate = targetH > 0 ? baseSal / targetH : 0.0;
    final double activeRate =
        (customRate != null && customRate > 0) ? customRate : derivedRate;

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Drag Handle Pill on Mobile Bottom Sheet
        if (widget.isBottomSheet)
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

        // 2. Header
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              AppAvatar(
                imageUrl: widget.item.delegate.personalPhotoUrl,
                fallbackText: widget.item.delegate.fullName,
                radius: 20,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Text(
                      widget.item.delegate.fullName,
                      style: const TextStyle(
                        fontSize: HrFont.titleMedium,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'تعديل معايير الراتب وساعات الوردية الخاصة بالمندوب',
                      style: TextStyle(
                        fontSize: HrFont.labelSmall,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              IconButton(
                icon: const Icon(Icons.close_rounded),
                tooltip: 'إغلاق',
                onPressed: () => Navigator.pop(context),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 3. Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                TextField(
                  controller: _baseSalaryCtrl,
                  keyboardType:
                      const TextInputType.numberWithOptions(decimal: true),
                  inputFormatters: [
                    FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                  ],
                  onChanged: (_) => setState(() {}),
                  decoration: InputDecoration(
                    labelText: 'الراتب الأساسي للمندوب',
                    suffixText: 'ج.م',
                    filled: true,
                    fillColor: colorScheme.surface,
                    border: OutlineInputBorder(
                      borderRadius: BorderRadius.circular(HrRadius.card),
                    ),
                  ),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextField(
                        controller: _shiftHoursCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'ساعات الوردية اليومية',
                          suffixText: 'ساعات',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                      ),
                    ),
                    const SizedBox(width: 12),
                    Expanded(
                      child: TextField(
                        controller: _customRateCtrl,
                        keyboardType:
                            const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [
                          FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*')),
                        ],
                        onChanged: (_) => setState(() {}),
                        decoration: InputDecoration(
                          labelText: 'أجر الساعة المخصص',
                          hintText: derivedRate.toStringAsFixed(1),
                          suffixText: 'ج.م/س',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(HrRadius.card),
                          ),
                        ),
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // نمط الاحتساب
                const Text(
                  'نمط الاحتساب الخاص بهذا المندوب:',
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.labelMedium),
                ),
                const SizedBox(height: 6),
                Wrap(
                  spacing: 8,
                  children: [
                    ChoiceChip(
                      label: const Text('شهري مع استقطاع'),
                      selected: _selectedMode ==
                          PayrollCalculationMode.monthlyWithDeductions,
                      onSelected: (sel) {
                        if (sel) {
                          setState(() => _selectedMode =
                              PayrollCalculationMode.monthlyWithDeductions);
                        }
                      },
                    ),
                    ChoiceChip(
                      label: const Text('بالساعات المنجزة'),
                      selected:
                          _selectedMode == PayrollCalculationMode.hourlyRate,
                      onSelected: (sel) {
                        if (sel) {
                          setState(() => _selectedMode =
                              PayrollCalculationMode.hourlyRate);
                        }
                      },
                    ),
                  ],
                ),
                const SizedBox(height: 14),

                // معاينة
                Container(
                  padding: const EdgeInsets.all(12),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'أجر الساعة الناتج:',
                        style: TextStyle(fontSize: HrFont.labelMedium),
                      ),
                      Text(
                        '${activeRate.toStringAsFixed(2)} ج.م/ساعة',
                        style: TextStyle(
                          color: colorScheme.primary,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                    ],
                  ),
                ),
              ],
            ),
          ),
        ),

        // 4. Pinned Connected Action Button Group
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(HrRadius.pill),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // Cancel (إلغاء)
                Expanded(
                  flex: 1,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: _isSaving ? null : () => Navigator.pop(context),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'إلغاء',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1.2,
                  height: 28,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // Save (حفظ)
                Expanded(
                  flex: 1,
                  child: Material(
                    color: colorScheme.primary,
                    child: InkWell(
                      onTap: _isSaving ? null : _handleSave,
                      child: Center(
                        child: _isSaving
                            ? SizedBox(
                                width: 20,
                                height: 20,
                                child: CircularProgressIndicator(
                                  strokeWidth: 2,
                                  color: colorScheme.onPrimary,
                                ),
                              )
                            : Row(
                                mainAxisAlignment: MainAxisAlignment.center,
                                children: [
                                  Icon(
                                    Icons.check_rounded,
                                    size: 18,
                                    color: colorScheme.onPrimary,
                                  ),
                                  const SizedBox(width: 6),
                                  Text(
                                    'حفظ',
                                    style: TextStyle(
                                      fontSize: HrFont.body,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.onPrimary,
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
        ),
      ],
    );

    if (widget.isBottomSheet) {
      final double sheetHeight = mediaQuery.size.height * 0.75;
      return SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// ورقة تفاصيل مسير راتب المندوب بنمط M3 فخم ومنسق بالكامل مع بطاقات وأيقونات جوجل
class _EmployeePayrollDetailSheet extends StatelessWidget {
  final DelegatePayrollItem item;
  final bool isBottomSheet;
  final VoidCallback onEditSalary;

  const _EmployeePayrollDetailSheet({
    required this.item,
    required this.isBottomSheet,
    required this.onEditSalary,
  });

  Widget _buildSectionCard({
    required BuildContext context,
    required String title,
    required IconData icon,
    required Color iconColor,
    required List<Widget> children,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      margin: const EdgeInsets.only(bottom: 12),
      padding: const EdgeInsets.all(14),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: iconColor.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: HrFont.body,
                  color: colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 10),
          ...children,
        ],
      ),
    );
  }

  Widget _buildDetailRow({
    required BuildContext context,
    required IconData icon,
    required String label,
    required String value,
    Color? valueColor,
    bool isBold = false,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(vertical: 4),
      child: Row(
        children: [
          Icon(icon, size: 16, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8)),
          const SizedBox(width: 8),
          Text(
            label,
            style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: HrFont.labelMedium,
              fontWeight: isBold ? FontWeight.bold : FontWeight.w600,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final mediaQuery = MediaQuery.of(context);

    final content = Column(
      mainAxisSize: MainAxisSize.min,
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        // 1. Top Drag Handle Pill on Mobile Bottom Sheet
        if (isBottomSheet)
          Center(
            child: Container(
              width: 38,
              height: 4.5,
              margin: const EdgeInsets.only(top: 10, bottom: 6),
              decoration: BoxDecoration(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
          ),

        // 2. Header (صورة المندوب والاسم ورقم الهاتف مع زر X بخلفية دائرية أنيقة)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 10),
          child: Row(
            children: [
              AppAvatar(
                imageUrl: item.delegate.personalPhotoUrl,
                fallbackText: item.delegate.fullName,
                radius: 24,
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      item.delegate.fullName,
                      style: const TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: HrFont.titleMedium,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Row(
                      children: [
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(6),
                          ),
                          child: Text(
                            item.delegate.position == DelegatePosition.supervisor
                                ? 'مشرف ميداني'
                                : 'مندوب / مروج',
                            style: TextStyle(
                              fontSize: HrFont.labelSmall,
                              fontWeight: FontWeight.w600,
                              color: colorScheme.primary,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            item.delegate.phoneNumber,
                            style: TextStyle(
                              color: colorScheme.onSurfaceVariant,
                              fontSize: HrFont.labelMedium,
                            ),
                          ),
                        ),
                      ],
                    ),
                  ],
                ),
              ),
              // زر الإغلاق X داخل خلفية دائرية أنيقة مع إطار
              Container(
                width: 36,
                height: 36,
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest,
                  shape: BoxShape.circle,
                  border: Border.all(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                    width: 1,
                  ),
                ),
                child: IconButton(
                  padding: EdgeInsets.zero,
                  icon: Icon(Icons.close_rounded, size: 20, color: colorScheme.onSurfaceVariant),
                  tooltip: 'غلق',
                  onPressed: () => Navigator.pop(context),
                ),
              ),
            ],
          ),
        ),
        const Divider(height: 1),

        // 3. Scrollable Body
        Expanded(
          child: SingleChildScrollView(
            padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // ── البطاقة الأولى: قاعدة الاحتساب وساعات الوردية ──
                _buildSectionCard(
                  context: context,
                  title: 'قاعدة الاحتساب وساعات الوردية',
                  icon: Icons.tune_rounded,
                  iconColor: colorScheme.primary,
                  children: [
                    _buildDetailRow(
                      context: context,
                      icon: Icons.rule_rounded,
                      label: 'طريقة الاحتساب:',
                      value: item.calculationMode.label,
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.schedule_rounded,
                      label: 'ساعات الوردية اليومية:',
                      value: '${item.dailyShiftHours.toStringAsFixed(0)} ساعات / يوم',
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.payments_outlined,
                      label: 'الراتب الأساسي الشهري:',
                      value: '${item.baseSalary.toStringAsFixed(0)} ج.م',
                      valueColor: colorScheme.primary,
                      isBold: true,
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.timelapse_rounded,
                      label: 'أجر الساعة المعتمد:',
                      value: '${item.effectiveHourlyRate.toStringAsFixed(2)} ج.م / ساعة',
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.calendar_today_rounded,
                      label: 'أجر يوم العمل الكامل:',
                      value: '${item.effectiveDailyRate.toStringAsFixed(1)} ج.م / يوم',
                      valueColor: colorScheme.primary,
                      isBold: true,
                    ),
                  ],
                ),

                // ── البطاقة الثانية: تفاصيل الحضور وساعات العمل ──
                _buildSectionCard(
                  context: context,
                  title: 'تفاصيل الحضور وساعات العمل للشهر',
                  icon: Icons.event_note_rounded,
                  iconColor: const Color(0xFF1976D2),
                  children: [
                    _buildDetailRow(
                      context: context,
                      icon: Icons.calendar_month_rounded,
                      label: 'أيام العمل المنقضية للشهر:',
                      value: '${item.elapsedWorkingDays} يوم',
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.check_circle_outline_rounded,
                      label: 'أيام الحضور الفعلي:',
                      value: '${item.attendedDays} يوم',
                      valueColor: HrStatusColors.of(context).success,
                      isBold: true,
                    ),
                    if (item.approvedLeaveDays > 0)
                      _buildDetailRow(
                        context: context,
                        icon: Icons.beach_access_rounded,
                        label: 'إجازات معتمدة (مدفوعة):',
                        value: '${item.approvedLeaveDays} يوم (${item.earnedLeaveAmount.toStringAsFixed(0)} ج.م)',
                        valueColor: colorScheme.primary,
                      ),
                    if (item.unpaidLeaveDays > 0)
                      _buildDetailRow(
                        context: context,
                        icon: Icons.event_busy_rounded,
                        label: 'إجازات غير مدفوعة (مرضية / طارئة / بدون أجر):',
                        value: '${item.unpaidLeaveDays} يوم',
                        valueColor: colorScheme.error,
                      ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.cancel_outlined,
                      label: 'أيام الغياب:',
                      value: '${item.absentDays} يوم',
                      valueColor: item.absentDays > 0 ? colorScheme.error : null,
                      isBold: item.absentDays > 0,
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.fact_check_rounded,
                      label: 'الأيام المستحقة للصرف:',
                      value: '${item.payableDays} يوم (${(item.payableDays * item.effectiveDailyRate).toStringAsFixed(0)} ج.م)',
                      valueColor: HrStatusColors.of(context).success,
                      isBold: true,
                    ),
                    _buildDetailRow(
                      context: context,
                      icon: Icons.hourglass_bottom_rounded,
                      label: 'إجمالي ساعات العمل الفعلية:',
                      value: '${item.formattedTotalHours} (${item.earnedWorkAmount.toStringAsFixed(0)} ج.م)',
                    ),
                    if (item.deductibleDays > 0 &&
                        item.calculationMode == PayrollCalculationMode.monthlyWithDeductions) ...[
                      const SizedBox(height: 6),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 8),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(HrRadius.chip),
                          border: Border.all(
                            color: colorScheme.error.withValues(alpha: 0.25),
                          ),
                        ),
                        child: Row(
                          children: [
                            Icon(Icons.remove_circle_outline_rounded, size: 16, color: colorScheme.error),
                            const SizedBox(width: 8),
                            Expanded(
                              child: Text(
                                'استقطاع أيام الغياب${item.unpaidLeaveDays > 0 ? ' والإجازات غير المدفوعة' : ''} (${item.deductibleDays} يوم × ${item.effectiveDailyRate.toStringAsFixed(1)} ج.م): -${item.absenceDeductionAmount.toStringAsFixed(0)} ج.م',
                                style: TextStyle(
                                  color: colorScheme.error,
                                  fontSize: HrFont.labelSmall,
                                  fontWeight: FontWeight.bold,
                                ),
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                ),

                // ── البطاقة الثالثة: الجزاءات والخصومات المطبقة ──
                _buildSectionCard(
                  context: context,
                  title: 'الجزاءات والخصومات (${item.appliedPenalties.length})',
                  icon: Icons.gavel_rounded,
                  iconColor: item.appliedPenalties.isNotEmpty ? colorScheme.error : colorScheme.outline,
                  children: [
                    if (item.appliedPenalties.isEmpty)
                      Row(
                        children: [
                          Icon(Icons.verified_rounded, size: 18, color: HrStatusColors.of(context).success),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'لا توجد أي جزاءات مسجلة على المندوب في هذا الشهر',
                              style: TextStyle(
                                fontSize: HrFont.labelMedium,
                                color: HrStatusColors.of(context).success,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ),
                        ],
                      )
                    else
                      ...item.appliedPenalties.map(
                        (p) => _buildDetailRow(
                          context: context,
                          icon: Icons.remove_circle_rounded,
                          label: p['title']?.toString() ?? 'مخالفة جزاء',
                          value: '-${p['fineAmount'] ?? 0} ج.م',
                          valueColor: colorScheme.error,
                          isBold: true,
                        ),
                      ),
                  ],
                ),

                const SizedBox(height: 4),

                // ── البطاقة الرابعة: بطاقة صافي المستحق للصرف المميزة في الأسفل ──
                Container(
                  padding: const EdgeInsets.all(16),
                  decoration: BoxDecoration(
                    color: HrStatusColors.of(context).success.withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(HrRadius.card),
                    border: Border.all(
                      color: HrStatusColors.of(context).success.withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: HrStatusColors.of(context).success.withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(HrRadius.card),
                        ),
                        child: Icon(
                          Icons.payments_rounded,
                          color: HrStatusColors.of(context).success,
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Text(
                              'صافي المستحق للصرف',
                              style: TextStyle(
                                fontSize: HrFont.labelMedium,
                                fontWeight: FontWeight.bold,
                                color: HrStatusColors.of(context).success,
                              ),
                            ),
                            Text(
                              'مستحق عن ${item.payableDays} يوم عمل (بعد الخصومات والجزاءات)',
                              style: TextStyle(
                                fontSize: HrFont.labelSmall,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${item.netSalary.toStringAsFixed(0)} ج.م',
                        style: TextStyle(
                          fontSize: HrFont.titleLarge,
                          fontWeight: FontWeight.w900,
                          color: HrStatusColors.of(context).success,
                        ),
                      ),
                    ],
                  ),
                ),
                const SizedBox(height: 8),
              ],
            ),
          ),
        ),

        // 4. Pinned Connected Action Button Group (غلق | تعديل)
        Padding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          child: Container(
            height: 48,
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHigh,
              borderRadius: BorderRadius.circular(HrRadius.pill),
              border: Border.all(
                color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                width: 1.2,
              ),
            ),
            clipBehavior: Clip.antiAlias,
            child: Row(
              children: [
                // زر غلق
                Expanded(
                  flex: 1,
                  child: Material(
                    color: Colors.transparent,
                    child: InkWell(
                      onTap: () => Navigator.pop(context),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.close_rounded,
                              size: 18,
                              color: colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'غلق',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ),
                  ),
                ),

                // Vertical Divider
                Container(
                  width: 1.2,
                  height: 28,
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                ),

                // زر تعديل
                Expanded(
                  flex: 1,
                  child: Material(
                    color: colorScheme.primary,
                    child: InkWell(
                      onTap: onEditSalary,
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(
                              Icons.tune_rounded,
                              size: 18,
                              color: colorScheme.onPrimary,
                            ),
                            const SizedBox(width: 6),
                            Text(
                              'تعديل',
                              style: TextStyle(
                                fontSize: HrFont.body,
                                fontWeight: FontWeight.bold,
                                color: colorScheme.onPrimary,
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
        ),
      ],
    );

    if (isBottomSheet) {
      final double sheetHeight = mediaQuery.size.height * 0.85;
      return SizedBox(
        height: sheetHeight,
        child: Padding(
          padding: EdgeInsets.only(bottom: mediaQuery.viewInsets.bottom),
          child: content,
        ),
      );
    }

    return content;
  }
}

/// Web summary card (TAS-119): title in labelLarge, value in headlineSmall
/// with tabular figures. [background] / [foreground] tint the whole card
/// (used for the net payout card).
class _WebSummaryCard extends StatelessWidget {
  const _WebSummaryCard({
    super.key,
    required this.title,
    required this.value,
    required this.icon,
    this.valueColor,
    this.background,
    this.foreground,
  });

  final String title;
  final String value;
  final IconData icon;
  final Color? valueColor;
  final Color? background;
  final Color? foreground;

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final labelColor = foreground ?? colorScheme.onSurfaceVariant;

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: background ?? colorScheme.surface,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: background == null ? Border.all(color: colorScheme.outlineVariant) : null,
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: 20, color: labelColor),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  title,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: theme.textTheme.labelLarge?.copyWith(color: labelColor),
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.w600,
              color: valueColor ?? foreground ?? colorScheme.onSurface,
              fontFeatures: const [FontFeature.tabularFigures()],
            ),
          ),
        ],
      ),
    );
  }
}
