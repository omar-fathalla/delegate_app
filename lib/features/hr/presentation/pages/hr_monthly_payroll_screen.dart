import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/hr/data/models/company_payroll_config_model.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// عنصر مسير الراتب للمندوب متوافق مع كافة أنماط وقواعد الاحتساب
class _DelegatePayrollItem {
  final Delegate delegate;
  int attendedDays;
  int approvedLeaveDays;
  int absentDays;
  int totalWorkMinutes;

  // إعدادات الراتب والوردية
  double baseSalary;
  double dailyShiftHours;
  double? customHourlyRate;
  PayrollCalculationMode calculationMode;
  int monthTargetWorkingDays;

  // الجزاءات
  double penaltiesDeductions;
  List<Map<String, dynamic>> appliedPenalties;

  _DelegatePayrollItem({
    required this.delegate,
    this.attendedDays = 0,
    this.approvedLeaveDays = 0,
    this.absentDays = 0,
    this.totalWorkMinutes = 0,
    this.baseSalary = 3500.0,
    this.dailyShiftHours = 9.0,
    this.customHourlyRate,
    this.calculationMode = PayrollCalculationMode.monthlyWithDeductions,
    this.monthTargetWorkingDays = 26,
    this.penaltiesDeductions = 0.0,
    List<Map<String, dynamic>>? appliedPenalties,
  }) : appliedPenalties = appliedPenalties ?? [];

  /// ساعات العمل الفعلية المنجزة
  double get actualWorkHours => totalWorkMinutes / 60.0;

  /// إجمالي الساعات المستهدفة للوردية في الشهر
  double get targetWorkHours => monthTargetWorkingDays * dailyShiftHours;

  /// أجر الساعة الفعلي المعتمد
  double get effectiveHourlyRate {
    if (customHourlyRate != null && customHourlyRate! > 0) {
      return customHourlyRate!;
    }
    if (targetWorkHours > 0) {
      return baseSalary / targetWorkHours;
    }
    return baseSalary / (26 * 9.0);
  }

  /// أجر اليوم الفعلي المعتمد
  double get effectiveDailyRate => effectiveHourlyRate * dailyShiftHours;

  /// استحقاق ساعات العمل الفعلية
  double get earnedWorkAmount => actualWorkHours * effectiveHourlyRate;

  /// إجمالي ساعات الإجازات المعتمدة
  double get leaveHours => approvedLeaveDays * dailyShiftHours;

  /// استحقاق الإجازات المعتمدة (مدفوعة الأجر)
  double get earnedLeaveAmount => approvedLeaveDays * effectiveDailyRate;

  /// ساعات النقص أو العجز عن الساعات المستهدفة
  double get shortfallHours {
    final workedAndLeave = actualWorkHours + leaveHours;
    final shortfall = targetWorkHours - workedAndLeave;
    return shortfall > 0 ? shortfall : 0.0;
  }

  /// قيمة استقطاع الغياب ونقص الساعات
  double get absenceDeductionAmount {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      // في نمط الساعات يتقاضى فقط ما أنجزه ولا يوجد استقطاع غياب إضافي
      return 0.0;
    }
    final deduction = shortfallHours * effectiveHourlyRate;
    return deduction > baseSalary ? baseSalary : deduction;
  }

  /// إجمالي الاستحقاق قبل الخصومات (Gross)
  double get grossEarned {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      return earnedWorkAmount + earnedLeaveAmount;
    }
    return baseSalary;
  }

  /// إجمالي الخصومات (غياب + جزاءات)
  double get totalDeductions => absenceDeductionAmount + penaltiesDeductions;

  /// صافي المستحق الفعلي للصرف (Net Payout)
  double get netSalary {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      final net = (grossEarned - penaltiesDeductions);
      return net > 0 ? net : 0.0;
    } else {
      final net = (baseSalary - absenceDeductionAmount - penaltiesDeductions);
      return net > 0 ? net : 0.0;
    }
  }

  String get formattedTotalHours {
    final h = totalWorkMinutes ~/ 60;
    final m = totalWorkMinutes % 60;
    return '$h س و $m د';
  }
}

/// كشف مسير الرواتب الشهري المربوط بساعات العمل والورديات والجزاءات والسياسات الديناميكية
class HRMonthlyPayrollScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  const HRMonthlyPayrollScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
  });

  @override
  State<HRMonthlyPayrollScreen> createState() => _HRMonthlyPayrollScreenState();
}

class _HRMonthlyPayrollScreenState extends State<HRMonthlyPayrollScreen> {
  DateTime _selectedMonth = DateTime(DateTime.now().year, DateTime.now().month, 1);
  bool _isLoading = true;
  String? _errorMessage;

  List<Delegate> _companyDelegates = [];
  List<_DelegatePayrollItem> _payrollItems = [];
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

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadPayrollData() async {
    setState(() {
      _isLoading = true;
      _errorMessage = null;
    });

    try {
      // 1. Fetch Company Payroll Configuration
      try {
        final configDoc = await FirebaseFirestore.instance
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
        (delegates) => _companyDelegates = delegates,
      );

      if (_companyDelegates.isEmpty) {
        if (mounted) setState(() => _isLoading = false);
        return;
      }

      final monthStart = DateTime(_selectedMonth.year, _selectedMonth.month, 1, 0, 0, 0);
      final nextMonth = DateTime(_selectedMonth.year, _selectedMonth.month + 1, 1);
      final monthEnd = nextMonth.subtract(const Duration(seconds: 1));

      // 3. Fetch User Wallets for base salary and individual shift overrides
      final walletsSnap = await FirebaseFirestore.instance
          .collection('user_wallets')
          .where('companyUID', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      final Map<String, Map<String, dynamic>> walletConfigByDelegateId = {};
      for (final doc in walletsSnap.docs) {
        walletConfigByDelegateId[doc.id] = doc.data();
      }

      // 4. Fetch Penalties approved in this month
      final penaltiesSnap = await FirebaseFirestore.instance
          .collection('penalties')
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      final Map<String, List<Map<String, dynamic>>> penaltiesByDelegateId = {};
      for (final doc in penaltiesSnap.docs) {
        final data = doc.data();
        final status = (data['status'] ?? '').toString();
        if (status.contains('approved') || status == 'applied') {
          final ts = data['createdAt'];
          if (ts is Timestamp) {
            final pDate = ts.toDate();
            if (pDate.isBefore(monthStart) || pDate.isAfter(monthEnd)) {
              continue;
            }
          }
          final delId = (data['targetDelegateId'] ?? '').toString();
          if (delId.isNotEmpty) {
            penaltiesByDelegateId.putIfAbsent(delId, () => []).add(data);
          }
        }
      }

      // 5. Fetch Approved Leaves in this month
      final leavesSnap = await FirebaseFirestore.instance
          .collection('leave_requests')
          .where('companyUID', isEqualTo: widget.hrDelegate.companyUID)
          .where('status', isEqualTo: 'approved')
          .get();

      final Map<String, int> leaveDaysByDelegateId = {};
      for (final doc in leavesSnap.docs) {
        final data = doc.data();
        final sTs = data['startDate'];
        if (sTs is Timestamp) {
          final sDate = sTs.toDate();
          if (sDate.isBefore(monthStart) || sDate.isAfter(monthEnd)) continue;
        }
        final delId = (data['delegateUid'] ?? '').toString();
        final days = (data['daysCount'] as num?)?.toInt() ?? 1;
        if (delId.isNotEmpty) {
          leaveDaysByDelegateId[delId] = (leaveDaysByDelegateId[delId] ?? 0) + days;
        }
      }

      // 6. Fetch Attendance logs for the month
      final attendanceSnap = await FirebaseFirestore.instance
          .collection(kAttendanceCollection)
          .where('companyId', isEqualTo: widget.hrDelegate.companyUID)
          .get();

      final Map<String, Map<String, List<Map<String, dynamic>>>> attendanceByDelegateAndDay = {};
      for (final doc in attendanceSnap.docs) {
        final data = doc.data();
        final ts = data['timestamp'];
        if (ts is Timestamp) {
          final date = ts.toDate();
          if (date.isBefore(monthStart) || date.isAfter(monthEnd)) continue;
          final delId = (data['delegateId'] ?? data['userId'] ?? '').toString();
          if (delId.isEmpty) continue;

          final dateKey = DateFormat('yyyy-MM-dd').format(date);
          attendanceByDelegateAndDay
              .putIfAbsent(delId, () => {})
              .putIfAbsent(dateKey, () => [])
              .add(data);
        }
      }

      // 7. Build Payroll Items
      final now = DateTime.now();
      final isCurrentMonth = _selectedMonth.year == now.year && _selectedMonth.month == now.month;
      final activeDaysInMonth = isCurrentMonth ? now.day : nextMonth.subtract(const Duration(days: 1)).day;

      final List<_DelegatePayrollItem> items = [];

      for (final d in _companyDelegates) {
        final daysMap = attendanceByDelegateAndDay[d.uid] ?? {};
        int attendedDaysCount = 0;
        int totalMins = 0;

        for (final logs in daysMap.values) {
          DateTime? inTime;
          DateTime? outTime;
          for (final log in logs) {
            final type = log['type']?.toString();
            final ts = log['timestamp'];
            DateTime? t;
            if (ts is Timestamp) t = ts.toDate();

            if (type == 'check_in') {
              if (inTime == null || (t != null && t.isBefore(inTime))) inTime = t;
            } else if (type == 'check_out') {
              if (outTime == null || (t != null && t.isAfter(outTime))) outTime = t;
            }
          }

          if (inTime != null) {
            attendedDaysCount++;
            if (outTime != null) {
              final diff = outTime.difference(inTime).inMinutes;
              if (diff > 0) totalMins += diff;
            } else {
              // قاعدة الـ 9 ساعات: إغلاق تلقائي واحتساب 9 ساعات عمل كاملة (540 دقيقة)
              final isPastDay = inTime.isBefore(DateTime(now.year, now.month, now.day));
              final isElapsed9Hours = now.difference(inTime) >= const Duration(hours: 9);
              if (isPastDay || isElapsed9Hours) {
                totalMins += (9 * 60);
              }
            }
          }
        }

        final leaveDays = leaveDaysByDelegateId[d.uid] ?? 0;
        final absent = (activeDaysInMonth - attendedDaysCount - leaveDays).clamp(0, activeDaysInMonth);

        // Configuration resolution (Custom Wallet Override vs Company Policy)
        final walletData = walletConfigByDelegateId[d.uid] ?? {};
        final alloc = (walletData['monthlyAllocation'] as num?)?.toDouble() ?? 0.0;
        final base = (walletData['baseSalary'] as num?)?.toDouble() ?? 0.0;
        final delegateBaseSalary = alloc > 0
            ? alloc
            : (base > 0 ? base : _companyPayrollConfig.defaultMonthlyBaseSalary);

        final delegateShiftHours = (walletData['dailyShiftHours'] as num?)?.toDouble() ??
            _companyPayrollConfig.defaultDailyShiftHours;

        final customRate = (walletData['customHourlyRate'] as num?)?.toDouble();

        final modeCode = walletData['payrollCalculationMode']?.toString();
        final delegateMode = modeCode != null
            ? PayrollCalculationModeExt.fromCode(modeCode)
            : _companyPayrollConfig.calculationMode;

        // Penalties sum
        final delegatePenalties = penaltiesByDelegateId[d.uid] ?? [];
        double totalPenalties = 0.0;
        for (final p in delegatePenalties) {
          totalPenalties += (p['fineAmount'] as num?)?.toDouble() ?? 0.0;
        }

        items.add(
          _DelegatePayrollItem(
            delegate: d,
            attendedDays: attendedDaysCount,
            approvedLeaveDays: leaveDays,
            absentDays: absent,
            totalWorkMinutes: totalMins,
            baseSalary: delegateBaseSalary,
            dailyShiftHours: delegateShiftHours,
            customHourlyRate: customRate,
            calculationMode: delegateMode,
            monthTargetWorkingDays: _companyPayrollConfig.defaultMonthlyWorkingDays,
            penaltiesDeductions: totalPenalties,
            appliedPenalties: delegatePenalties,
          ),
        );
      }

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

  List<_DelegatePayrollItem> get _filteredPayrollItems {
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
          '\uFEFFاسم المندوب,رقم الهاتف,المسمى الوظيفي,أيام الحضور,أيام الإجازات,أيام الغياب,ساعات العمل الفعلية,الساعات المستهدفة,الراتب الأساسي (ج.م),أجر الساعة (ج.م),الاستحقاق الفعلي (ج.م),استقطاع الغياب/العجز (ج.م),خصومات الجزاءات (ج.م),صافي الصرف المستحق (ج.م)\n';

      final csvRows = list.map((item) {
        final name = item.delegate.fullName.replaceAll(',', ' ');
        final phone = item.delegate.phoneNumber;
        final pos = item.delegate.position == DelegatePosition.supervisor ? 'مشرف' : 'مندوب / مروج';
        final attended = item.attendedDays;
        final leaves = item.approvedLeaveDays;
        final absent = item.absentDays;
        final hours = item.formattedTotalHours;
        final targetHours = item.targetWorkHours.toStringAsFixed(1);
        final base = item.baseSalary.toStringAsFixed(2);
        final rate = item.effectiveHourlyRate.toStringAsFixed(2);
        final gross = item.grossEarned.toStringAsFixed(2);
        final absenceDed = item.absenceDeductionAmount.toStringAsFixed(2);
        final pen = item.penaltiesDeductions.toStringAsFixed(2);
        final net = item.netSalary.toStringAsFixed(2);

        return '$name,$phone,$pos,$attended,$leaves,$absent,$hours,$targetHours,$base,$rate,$gross,$absenceDed,$pen,$net';
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
          const SnackBar(
            content: Text('تم تصدير كشف مسير الرواتب بنجاح'),
            backgroundColor: Color(0xFF2E7D32),
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
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    var selectedMode = _companyPayrollConfig.calculationMode;
    final shiftHoursCtrl = TextEditingController(
      text: _companyPayrollConfig.defaultDailyShiftHours.toStringAsFixed(0),
    );
    final baseSalaryCtrl = TextEditingController(
      text: _companyPayrollConfig.defaultMonthlyBaseSalary.toStringAsFixed(0),
    );
    final workingDaysCtrl = TextEditingController(
      text: _companyPayrollConfig.defaultMonthlyWorkingDays.toString(),
    );
    final customHourlyRateCtrl = TextEditingController(
      text: _companyPayrollConfig.defaultHourlyRate != null && _companyPayrollConfig.defaultHourlyRate! > 0
          ? _companyPayrollConfig.defaultHourlyRate!.toStringAsFixed(1)
          : '',
    );

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final double shiftH = double.tryParse(shiftHoursCtrl.text.trim()) ?? 9.0;
            final double baseSal = double.tryParse(baseSalaryCtrl.text.trim()) ?? 3500.0;
            final int workD = int.tryParse(workingDaysCtrl.text.trim()) ?? 26;
            final double? customRate = double.tryParse(customHourlyRateCtrl.text.trim());

            final double derivedRate = (workD * shiftH) > 0 ? baseSal / (workD * shiftH) : 0.0;
            final double activeRate = (customRate != null && customRate > 0) ? customRate : derivedRate;
            final double activeDailyRate = activeRate * shiftH;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  Container(
                    padding: const EdgeInsets.all(8),
                    decoration: BoxDecoration(
                      color: colorScheme.primary.withValues(alpha: 0.12),
                      borderRadius: BorderRadius.circular(10),
                    ),
                    child: Icon(Icons.tune_rounded, color: colorScheme.primary, size: 22),
                  ),
                  const SizedBox(width: 12),
                  const Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text('قواعد وسياسة الرواتب', style: TextStyle(fontSize: 17, fontWeight: FontWeight.bold)),
                        Text('ضبط معايير الورديات واحتساب الساعات للشركة', style: TextStyle(fontSize: 12, color: Colors.grey)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 520,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // نمط الاحتساب
                      const Text(
                        'طريقة احتساب مسير الرواتب:',
                        style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                      ),
                      const SizedBox(height: 8),
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerLow,
                          borderRadius: BorderRadius.circular(14),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        child: Column(
                          children: [
                            InkWell(
                              borderRadius: const BorderRadius.vertical(top: Radius.circular(14)),
                              onTap: () => setDialogState(() => selectedMode = PayrollCalculationMode.monthlyWithDeductions),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      selectedMode == PayrollCalculationMode.monthlyWithDeductions
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: selectedMode == PayrollCalculationMode.monthlyWithDeductions
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
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'يُحدد راتب أساسي ثابت، ويُخصم منه ما يعادل ساعات الغياب أو العجز عن وردية الـ 9 ساعات',
                                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
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
                              borderRadius: const BorderRadius.vertical(bottom: Radius.circular(14)),
                              onTap: () => setDialogState(() => selectedMode = PayrollCalculationMode.hourlyRate),
                              child: Padding(
                                padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
                                child: Row(
                                  children: [
                                    Icon(
                                      selectedMode == PayrollCalculationMode.hourlyRate
                                          ? Icons.radio_button_checked_rounded
                                          : Icons.radio_button_unchecked_rounded,
                                      color: selectedMode == PayrollCalculationMode.hourlyRate
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
                                            style: TextStyle(fontSize: 13, fontWeight: FontWeight.w600),
                                          ),
                                          const SizedBox(height: 2),
                                          Text(
                                            'يتقاضى المندوب أجراً مباشراً عن كل ساعة عمل منجزة + الإجازات الرسمية المعتمدة',
                                            style: TextStyle(fontSize: 11, color: colorScheme.onSurfaceVariant),
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
                              controller: shiftHoursCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'ساعات الوردية اليومية',
                                suffixText: 'ساعات',
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: workingDaysCtrl,
                              keyboardType: TextInputType.number,
                              inputFormatters: [FilteringTextInputFormatter.digitsOnly],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'أيام العمل الرسمية بالشهر',
                                suffixText: 'أيام',
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                              controller: baseSalaryCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'الراتب الأساسي الافتراضي',
                                suffixText: 'ج.م',
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: customHourlyRateCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'أجر الساعة المخصص (اختياري)',
                                hintText: derivedRate.toStringAsFixed(1),
                                suffixText: 'ج.م/س',
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
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
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.primary.withValues(alpha: 0.2)),
                        ),
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('أجر الساعة الفعلي المعتمد:', style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold)),
                                Text('${activeRate.toStringAsFixed(2)} ج.م / ساعة', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                Text('أجر الوردية الكاملة (${shiftH.toStringAsFixed(0)} ساعات):', style: const TextStyle(fontSize: 12)),
                                Text('${activeDailyRate.toStringAsFixed(2)} ج.م / يوم', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13)),
                              ],
                            ),
                            const SizedBox(height: 6),
                            Row(
                              mainAxisAlignment: MainAxisAlignment.spaceBetween,
                              children: [
                                const Text('الساعات المستهدفة للشهر:', style: TextStyle(fontSize: 12)),
                                Text('${(workD * shiftH).toStringAsFixed(0)} ساعة عمل', style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                              ],
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('حفظ وتطبيق السياسة'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    final newConfig = CompanyPayrollConfigModel(
                      companyUID: widget.hrDelegate.companyUID,
                      calculationMode: selectedMode,
                      defaultDailyShiftHours: shiftH,
                      defaultMonthlyBaseSalary: baseSal,
                      defaultMonthlyWorkingDays: workD,
                      defaultHourlyRate: (customRate != null && customRate > 0) ? customRate : null,
                      updatedAt: DateTime.now(),
                      updatedBy: widget.hrDelegate.fullName,
                    );

                    try {
                      await FirebaseFirestore.instance
                          .collection('company_payroll_configs')
                          .doc(widget.hrDelegate.companyUID)
                          .set(newConfig.toMap(), SetOptions(merge: true));

                      setState(() {
                        _companyPayrollConfig = newConfig;
                      });
                      _loadPayrollData();

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          const SnackBar(
                            content: Text('تم حفظ وتطبيق سياسة الرواتب بنجاح على كافة المناديب'),
                            backgroundColor: Color(0xFF2E7D32),
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
                  },
                ),
              ],
            );
          },
        );
      },
    );
  }

  /// نافذة تعديل راتب وساعات العمل لمندوب بعينه
  void _openDelegateSalaryDialog(_DelegatePayrollItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    final baseSalaryCtrl = TextEditingController(text: item.baseSalary.toStringAsFixed(0));
    final shiftHoursCtrl = TextEditingController(text: item.dailyShiftHours.toStringAsFixed(0));
    final customRateCtrl = TextEditingController(
      text: item.customHourlyRate != null && item.customHourlyRate! > 0
          ? item.customHourlyRate!.toStringAsFixed(1)
          : '',
    );
    var selectedMode = item.calculationMode;

    showDialog(
      context: context,
      builder: (ctx) {
        return StatefulBuilder(
          builder: (dialogCtx, setDialogState) {
            final double baseSal = double.tryParse(baseSalaryCtrl.text.trim()) ?? item.baseSalary;
            final double shiftH = double.tryParse(shiftHoursCtrl.text.trim()) ?? item.dailyShiftHours;
            final double? customRate = double.tryParse(customRateCtrl.text.trim());

            final targetH = item.monthTargetWorkingDays * shiftH;
            final double derivedRate = targetH > 0 ? baseSal / targetH : 0.0;
            final double activeRate = (customRate != null && customRate > 0) ? customRate : derivedRate;

            return AlertDialog(
              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(20)),
              title: Row(
                children: [
                  AppAvatar(
                    imageUrl: item.delegate.personalPhotoUrl,
                    fallbackText: item.delegate.fullName,
                    radius: 20,
                  ),
                  const SizedBox(width: 12),
                  Expanded(
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(item.delegate.fullName, style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold)),
                        Text('تعديل معايير الراتب وساعات الوردية الخاصة بالمندوب', style: TextStyle(fontSize: 11.5, color: colorScheme.onSurfaceVariant)),
                      ],
                    ),
                  ),
                ],
              ),
              content: SizedBox(
                width: 440,
                child: SingleChildScrollView(
                  child: Column(
                    mainAxisSize: MainAxisSize.min,
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      TextField(
                        controller: baseSalaryCtrl,
                        keyboardType: const TextInputType.numberWithOptions(decimal: true),
                        inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                        onChanged: (_) => setDialogState(() {}),
                        decoration: InputDecoration(
                          labelText: 'الراتب الأساسي للمندوب',
                          suffixText: 'ج.م',
                          filled: true,
                          fillColor: colorScheme.surface,
                          border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                        ),
                      ),
                      const SizedBox(height: 12),
                      Row(
                        children: [
                          Expanded(
                            child: TextField(
                              controller: shiftHoursCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'ساعات الوردية اليومية',
                                suffixText: 'ساعات',
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                          const SizedBox(width: 12),
                          Expanded(
                            child: TextField(
                              controller: customRateCtrl,
                              keyboardType: const TextInputType.numberWithOptions(decimal: true),
                              inputFormatters: [FilteringTextInputFormatter.allow(RegExp(r'^\d*\.?\d*'))],
                              onChanged: (_) => setDialogState(() {}),
                              decoration: InputDecoration(
                                labelText: 'أجر الساعة المخصص',
                                hintText: derivedRate.toStringAsFixed(1),
                                suffixText: 'ج.م/س',
                                filled: true,
                                fillColor: colorScheme.surface,
                                border: OutlineInputBorder(borderRadius: BorderRadius.circular(12)),
                              ),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),

                      // خيار نمط الاحتساب
                      const Text('نمط الاحتساب الخاص بهذا المندوب:', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)),
                      const SizedBox(height: 6),
                      Wrap(
                        spacing: 8,
                        children: [
                          ChoiceChip(
                            label: const Text('شهري مع استقطاع'),
                            selected: selectedMode == PayrollCalculationMode.monthlyWithDeductions,
                            onSelected: (sel) {
                              if (sel) setDialogState(() => selectedMode = PayrollCalculationMode.monthlyWithDeductions);
                            },
                          ),
                          ChoiceChip(
                            label: const Text('بالساعات المنجزة'),
                            selected: selectedMode == PayrollCalculationMode.hourlyRate,
                            onSelected: (sel) {
                              if (sel) setDialogState(() => selectedMode = PayrollCalculationMode.hourlyRate);
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
                          borderRadius: BorderRadius.circular(12),
                          border: Border.all(color: colorScheme.outlineVariant.withValues(alpha: 0.6)),
                        ),
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.spaceBetween,
                          children: [
                            const Text('أجر الساعة الناتج:', style: TextStyle(fontSize: 12)),
                            Text('${activeRate.toStringAsFixed(2)} ج.م/ساعة', style: TextStyle(color: colorScheme.primary, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ],
                  ),
                ),
              ),
              actions: [
                TextButton(
                  onPressed: () => Navigator.pop(ctx),
                  child: const Text('إلغاء'),
                ),
                FilledButton.icon(
                  icon: const Icon(Icons.check_rounded, size: 18),
                  label: const Text('حفظ التعديل'),
                  onPressed: () async {
                    Navigator.pop(ctx);
                    try {
                      await FirebaseFirestore.instance.collection('user_wallets').doc(item.delegate.uid).set({
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

                      setState(() {
                        item.baseSalary = baseSal;
                        item.dailyShiftHours = shiftH;
                        item.customHourlyRate = (customRate != null && customRate > 0) ? customRate : null;
                        item.calculationMode = selectedMode;
                      });

                      if (mounted) {
                        ScaffoldMessenger.of(context).showSnackBar(
                          SnackBar(
                            content: Text('تم تحديث إعدادات الراتب للمندوب ${item.delegate.fullName} بنجاح'),
                            backgroundColor: const Color(0xFF2E7D32),
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
                  },
                ),
              ],
            );
          },
        );
      },
    );
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
              title: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  const Text(
                    'مسيرات الرواتب الشهرية',
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
                  ),
                  Text(
                    widget.hrDelegate.companyName,
                    style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
              actions: [
                IconButton(
                  icon: const Icon(Icons.tune_rounded),
                  tooltip: 'قواعد وسياسة الرواتب للشركة',
                  onPressed: _openCompanyPayrollPolicyDialog,
                ),
                IconButton(
                  icon: const Icon(Icons.file_download_outlined),
                  tooltip: 'تصدير مسير الرواتب إلى Excel',
                  onPressed: _exportPayrollToExcel,
                ),
                IconButton(
                  icon: const Icon(Icons.refresh_rounded),
                  tooltip: 'إعادة الاحتساب والتحديث',
                  onPressed: _loadPayrollData,
                ),
                const SizedBox(width: 8),
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
              : RefreshIndicator(
                  onRefresh: _loadPayrollData,
                  child: ListView(
                    padding: const EdgeInsets.all(16),
                    children: [
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
                            color: const Color(0xFF2E7D32),
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

                      // ── Single-Row Unified Desktop Toolbar ──
                      LayoutBuilder(
                        builder: (context, constraints) {
                          final isDesktop = constraints.maxWidth >= 768;

                          final searchWidget = SizedBox(
                            height: 44,
                            child: TextField(
                              controller: _searchController,
                              onChanged: (val) => setState(() => _searchQuery = val.trim()),
                              textAlignVertical: TextAlignVertical.center,
                              style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                              decoration: InputDecoration(
                                hintText: 'بحث باسم المندوب أو رقم الهاتف...',
                                hintStyle: TextStyle(
                                  fontSize: 12,
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
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                                ),
                                enabledBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                                ),
                                focusedBorder: OutlineInputBorder(
                                  borderRadius: BorderRadius.circular(22),
                                  borderSide: BorderSide(color: colorScheme.primary, width: 1.5),
                                ),
                              ),
                            ),
                          );

                          final policyBtn = OutlinedButton.icon(
                            style: OutlinedButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                              backgroundColor: colorScheme.surfaceContainerHigh,
                            ),
                            icon: Icon(Icons.tune_rounded, size: 18, color: colorScheme.primary),
                            label: Text(
                              'قواعد وسياسة الرواتب',
                              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5, color: colorScheme.primary),
                            ),
                            onPressed: _openCompanyPayrollPolicyDialog,
                          );

                          final exportBtn = FilledButton.tonalIcon(
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(0, 44),
                              padding: const EdgeInsets.symmetric(horizontal: 14),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              backgroundColor: colorScheme.surfaceContainerHigh,
                              foregroundColor: colorScheme.primary,
                              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                            ),
                            icon: const Icon(Icons.arrow_downward_rounded, size: 18),
                            label: const Text('Excel', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12.5)),
                            onPressed: _exportPayrollToExcel,
                          );

                          final refreshBtn = IconButton.filledTonal(
                            style: IconButton.styleFrom(
                              minimumSize: const Size(44, 44),
                              shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(22)),
                              backgroundColor: colorScheme.surfaceContainerHigh,
                              side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
                            ),
                            icon: const Icon(Icons.refresh_rounded, size: 20),
                            tooltip: 'تحديث الحسابات',
                            onPressed: _loadPayrollData,
                          );

                          if (isDesktop) {
                            return Row(
                              children: [
                                Expanded(child: searchWidget),
                                const SizedBox(width: 10),
                                policyBtn,
                                const SizedBox(width: 8),
                                exportBtn,
                                const SizedBox(width: 8),
                                refreshBtn,
                              ],
                            );
                          } else {
                            return Column(
                              children: [
                                searchWidget,
                                const SizedBox(height: 10),
                                Row(
                                  children: [
                                    Expanded(child: policyBtn),
                                    const SizedBox(width: 8),
                                    Expanded(child: exportBtn),
                                    const SizedBox(width: 8),
                                    refreshBtn,
                                  ],
                                ),
                              ],
                            );
                          }
                        },
                      ),

                      const SizedBox(height: 16),

                      // ── Advanced Enterprise Payroll Table ──
                      Container(
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(16),
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
                                          Expanded(flex: 22, child: Text('المندوب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 10, child: Text('الحضور', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 10, child: Text('الإجازات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 10, child: Text('الغياب', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 14, child: Text('ساعات العمل', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 13, child: Text('الأساسي / الساعة', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 12, child: Text('الاستحقاق', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 14, child: Text('إجمالي الخصومات', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          Expanded(flex: 13, child: Text('صافي الصرف', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13))),
                                          SizedBox(width: 44, child: Center(child: Text('إجراء', style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12)))),
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
                                                              style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                                                              overflow: TextOverflow.ellipsis,
                                                            ),
                                                            Directionality(
                                                              textDirection: TextDirection.ltr,
                                                              child: Text(
                                                                item.delegate.phoneNumber,
                                                                style: TextStyle(
                                                                  fontSize: 11,
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
                                                        style: const TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                                                      ),
                                                      Text(
                                                        'من ${item.targetWorkHours.toStringAsFixed(0)} س مطلوب',
                                                        style: TextStyle(fontSize: 10.5, color: colorScheme.onSurfaceVariant),
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
                                                        style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
                                                      ),
                                                      Text(
                                                        '${item.effectiveHourlyRate.toStringAsFixed(1)} ج.م/س',
                                                        style: TextStyle(fontSize: 10.5, color: colorScheme.primary),
                                                      ),
                                                    ],
                                                  ),
                                                ),

                                                // الاستحقاق
                                                Expanded(
                                                  flex: 12,
                                                  child: Text(
                                                    '${item.grossEarned.toStringAsFixed(0)} ج.م',
                                                    style: const TextStyle(fontWeight: FontWeight.w600, fontSize: 12.5),
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
                                                          fontSize: 12.5,
                                                        ),
                                                      ),
                                                      if (item.totalDeductions > 0)
                                                        Text(
                                                          'غياب: ${item.absenceDeductionAmount.toStringAsFixed(0)}${item.penaltiesDeductions > 0 ? ' | جزاء: ${item.penaltiesDeductions.toStringAsFixed(0)}' : ''}',
                                                          style: TextStyle(fontSize: 10, color: colorScheme.error.withValues(alpha: 0.8)),
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
                                                      color: const Color(0xFF2E7D32).withValues(alpha: 0.12),
                                                      borderRadius: BorderRadius.circular(8),
                                                      border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                                                    ),
                                                    child: Text(
                                                      '${item.netSalary.toStringAsFixed(0)} ج.م',
                                                      style: const TextStyle(
                                                        color: Color(0xFF2E7D32),
                                                        fontWeight: FontWeight.bold,
                                                        fontSize: 12.5,
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
        borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(8),
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
                    fontSize: 11.5,
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
                        fontSize: 9.5,
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
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_right_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
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
                  borderRadius: BorderRadius.circular(8),
                  child: Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 2, vertical: 1),
                    child: Tooltip(
                      message: 'اضغط لاختيار شهر آخر',
                      child: Text(
                        monthStr,
                        textAlign: TextAlign.center,
                        style: TextStyle(
                          fontSize: 13.5,
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
                borderRadius: BorderRadius.circular(8),
                child: Padding(
                  padding: const EdgeInsets.all(2),
                  child: Icon(
                    Icons.chevron_left_rounded,
                    size: 20,
                    color: colorScheme.onSurfaceVariant,
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
        borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, color: color, size: 15),
              ),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 11.5,
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
                style: TextStyle(fontSize: 15.5, fontWeight: FontWeight.bold, color: color),
                overflow: TextOverflow.ellipsis,
              ),
              if (subtitle != null)
                Text(
                  subtitle,
                  style: TextStyle(
                    fontSize: 9.5,
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

  void _showEmployeePayrollDetail(_DelegatePayrollItem item) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(24)),
      ),
      builder: (ctx) {
        return Padding(
          padding: EdgeInsets.only(
            left: 20,
            right: 20,
            top: 20,
            bottom: MediaQuery.of(ctx).viewInsets.bottom + 20,
          ),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              // Header
              Row(
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
                        Text(item.delegate.fullName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: 16)),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(item.delegate.phoneNumber, style: TextStyle(color: colorScheme.onSurfaceVariant, fontSize: 12)),
                        ),
                      ],
                    ),
                  ),
                  Container(
                    padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 6),
                    decoration: BoxDecoration(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.14),
                      borderRadius: BorderRadius.circular(10),
                      border: Border.all(color: const Color(0xFF2E7D32).withValues(alpha: 0.3)),
                    ),
                    child: Text(
                      'الصافي: ${item.netSalary.toStringAsFixed(0)} ج.م',
                      style: const TextStyle(color: Color(0xFF2E7D32), fontWeight: FontWeight.bold, fontSize: 14),
                    ),
                  ),
                ],
              ),
              const SizedBox(height: 16),
              const Divider(),
              const SizedBox(height: 10),

              // القاعدة المطبقة
              Text(
                'قاعدة الاحتساب وساعات الوردية:',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text('• طريقة الاحتساب: ${item.calculationMode.label}'),
              Text('• ساعات الوردية اليومية: ${item.dailyShiftHours.toStringAsFixed(0)} ساعات/يوم'),
              Text('• أجر الساعة المعتمد: ${item.effectiveHourlyRate.toStringAsFixed(2)} ج.م / ساعة (اليوم: ${item.effectiveDailyRate.toStringAsFixed(1)} ج.م)'),
              const SizedBox(height: 12),

              // تفاصيل الحضور
              Text(
                'تفاصيل الحضور وساعات العمل للشهر:',
                style: TextStyle(fontWeight: FontWeight.bold, color: colorScheme.primary, fontSize: 13),
              ),
              const SizedBox(height: 6),
              Text('• أيام الحضور الفعلي: ${item.attendedDays} يوم'),
              Text('• أيام الإجازات المعتمدة: ${item.approvedLeaveDays} يوم (استحقاقها: ${item.earnedLeaveAmount.toStringAsFixed(0)} ج.م)'),
              Text('• أيام الغياب: ${item.absentDays} يوم'),
              Text('• إجمالي ساعات العمل الفعلية: ${item.formattedTotalHours} (استحقاقها: ${item.earnedWorkAmount.toStringAsFixed(0)} ج.م)'),
              if (item.shortfallHours > 0 && item.calculationMode == PayrollCalculationMode.monthlyWithDeductions)
                Text('• عجز ساعات العمل عن المستهدف: ${item.shortfallHours.toStringAsFixed(1)} ساعة (-${item.absenceDeductionAmount.toStringAsFixed(0)} ج.م)',
                    style: const TextStyle(color: Colors.red, fontWeight: FontWeight.w600)),
              const SizedBox(height: 12),

              // الجزاءات والخصومات
              Text(
                'الجزاءات والخصومات المطبقة (${item.appliedPenalties.length}):',
                style: const TextStyle(fontWeight: FontWeight.bold, color: Colors.red, fontSize: 13),
              ),
              const SizedBox(height: 6),
              if (item.appliedPenalties.isEmpty)
                const Text('لا توجد أي جزاءات مسجلة على المندوب في هذا الشهر 👍')
              else
                ...item.appliedPenalties.map((p) => Text('• ${p['title'] ?? 'مخالفة'}: -${p['fineAmount'] ?? 0} ج.م')),

              const SizedBox(height: 18),

              // زر تعديل الراتب للمندوب
              SizedBox(
                width: double.infinity,
                child: OutlinedButton.icon(
                  icon: const Icon(Icons.tune_rounded, size: 18),
                  label: const Text('تعديل معايير الراتب وساعات هذا المندوب'),
                  onPressed: () {
                    Navigator.pop(ctx);
                    _openDelegateSalaryDialog(item);
                  },
                ),
              ),
            ],
          ),
        );
      },
    );
  }
}
