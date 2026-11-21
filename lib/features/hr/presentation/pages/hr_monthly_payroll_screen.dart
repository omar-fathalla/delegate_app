import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:flutter/services.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/hr/data/models/company_payroll_config_model.dart';
import 'package:delegate_app/features/hr/domain/services/payroll_day_rules.dart';
import 'package:delegate_app/features/hr/domain/entities/company_payroll_config.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// عنصر مسير الراتب للمندوب متوافق مع كافة أنماط وقواعد الاحتساب
class _DelegatePayrollItem {
  final Delegate delegate;
  int attendedDays;
  int approvedLeaveDays;

  /// إجازات معتمدة غير مدفوعة (مرضية / طارئة / بدون أجر) — تُخصم كالغياب
  int unpaidLeaveDays;
  int absentDays;
  int elapsedWorkingDays;
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
    this.unpaidLeaveDays = 0,
    this.absentDays = 0,
    this.elapsedWorkingDays = 0,
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

  /// عدد الأيام المستحقة للصرف (أيام الحضور الفعلي + الإجازات الرسمية المعتمدة)
  int get payableDays {
    final days = attendedDays + approvedLeaveDays;
    return days > elapsedWorkingDays ? elapsedWorkingDays : days;
  }

  /// ساعات النقص الناتجة عن أيام الغياب الفعلية
  double get shortfallHours => deductibleDays * dailyShiftHours;

  /// الأيام المخصومة = الغياب + الإجازات غير المدفوعة
  int get deductibleDays => absentDays + unpaidLeaveDays;

  /// قيمة استقطاع أيام الغياب الفعلية (عدد أيام الغياب × أجر اليوم المعتمد)
  double get absenceDeductionAmount {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      // في نمط الساعات يتقاضى فقط ما أنجزه بالساعة ولا يوجد استقطاع غياب إضافي
      return 0.0;
    }
    // استقطاع الغياب = عدد أيام الغياب الفعلية × أجر اليوم
    final deduction = deductibleDays * effectiveDailyRate;
    return deduction > grossEarned ? grossEarned : deduction;
  }

  /// إجمالي الاستحقاق للفترة المنقضية قبل الخصومات (Gross)
  double get grossEarned {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      return earnedWorkAmount + earnedLeaveAmount;
    }
    // في النمط الشهري: استحقاق الفترة المنقضية = أيام العمل المنقضية × أجر اليوم المعتمد
    final earned = elapsedWorkingDays * effectiveDailyRate;
    return earned > baseSalary ? baseSalary : earned;
  }

  /// إجمالي الخصومات (غياب + جزاءات)
  double get totalDeductions => absenceDeductionAmount + penaltiesDeductions;

  /// صافي المستحق الفعلي للصرف (Net Payout)
  /// = (أيام الفترة - أيام الغياب) × أجر اليوم - الجزاءات
  /// = الأيام المستحقة الفعلية × أجر اليوم - الجزاءات
  double get netSalary {
    if (calculationMode == PayrollCalculationMode.hourlyRate) {
      final net = (grossEarned - penaltiesDeductions);
      return net > 0 ? net : 0.0;
    } else {
      // صافي الصرف هو أجر الأيام المستحقة الفعلية ناقص الجزاءات
      final earnedDaysAmount = payableDays * effectiveDailyRate;
      final net = (earnedDaysAmount - penaltiesDeductions);
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
        (page) => _companyDelegates = page.delegates,
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
        if (doc.data()['companyUID'] != widget.hrDelegate.companyUID) continue;
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

      // السنوية تُدفع في حدود الرصيد؛ المرضية/الطارئة/بدون أجر غير مدفوعة؛ التأخير/الانصراف المبكر لا تُحتسب
      final Map<String, int> unpaidLeaveDaysByDelegateId = {};
      final Map<String, int> annualDaysThisMonth = {};
      final Map<String, int> annualDaysEarlierThisYear = {};
      final yearStart = DateTime(monthStart.year);
      for (final doc in leavesSnap.docs) {
        final data = doc.data();
        final delId = (data['delegateUid'] ?? '').toString();
        if (delId.isEmpty) continue;
        final days = (data['daysCount'] as num?)?.toInt() ?? 1;
        final sTs = data['startDate'];
        final sDate = sTs is Timestamp ? sTs.toDate() : null;
        final inMonth = sDate == null || !(sDate.isBefore(monthStart) || sDate.isAfter(monthEnd));
        final category = PayrollDayRules.categorize(data);
        if (category == PayrollLeaveCategory.notALeaveDay) continue;
        if (category == PayrollLeaveCategory.annual) {
          if (inMonth) {
            annualDaysThisMonth[delId] = (annualDaysThisMonth[delId] ?? 0) + days;
          } else if (!sDate.isBefore(yearStart) && sDate.isBefore(monthStart)) {
            annualDaysEarlierThisYear[delId] = (annualDaysEarlierThisYear[delId] ?? 0) + days;
          }
          continue;
        }
        if (!inMonth) continue;
        unpaidLeaveDaysByDelegateId[delId] = (unpaidLeaveDaysByDelegateId[delId] ?? 0) + days;
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
      final isFutureMonth = _selectedMonth.isAfter(DateTime(now.year, now.month));

      // حساب عدد أيام العمل الفعلية المعتمدة حتى تاريخ التقييم (باستثناء أيام الجمعة كعطلات رسمية)
      int elapsedWorkingDays = 0;
      if (!isFutureMonth) {
        final int lastDayToEvaluate = isCurrentMonth
            ? now.day
            : nextMonth.subtract(const Duration(days: 1)).day;

        for (int day = 1; day <= lastDayToEvaluate; day++) {
          final dt = DateTime(_selectedMonth.year, _selectedMonth.month, day);
          // الجمعة عطلة أسبوعية رسمية لا تحتسب يوم عمل مطلوب للغياب
          if (dt.weekday != DateTime.friday) {
            elapsedWorkingDays++;
          }
        }
        if (elapsedWorkingDays > _companyPayrollConfig.defaultMonthlyWorkingDays) {
          elapsedWorkingDays = _companyPayrollConfig.defaultMonthlyWorkingDays;
        }
      }

      final List<_DelegatePayrollItem> items = [];

      for (final d in _companyDelegates) {
        final daysMap = attendanceByDelegateAndDay[d.uid] ?? {};
        int attendedDaysCount = 0;
        int totalMins = 0;
        final walletData = walletConfigByDelegateId[d.uid] ?? {};
        final delegateShiftHours = (walletData['dailyShiftHours'] as num?)?.toDouble() ??
            _companyPayrollConfig.defaultDailyShiftHours;

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
            // الأقل من (الفعلي، الوردية المحددة) — بدون أوفر تايم، واليوم المغلق تلقائياً = الوردية
            totalMins += PayrollDayRules.paidMinutesForDay(
              checkIn: inTime,
              checkOut: outTime,
              now: now,
              shiftHours: delegateShiftHours,
            );
          }
        }

        final paidAnnualDays = PayrollDayRules.paidAnnualLeaveDays(
          annualLeaveEnabled: d.isAnnualLeaveEnabled,
          annualQuota: d.annualLeaveQuota,
          usedEarlierThisYear: annualDaysEarlierThisYear[d.uid] ?? 0,
          requestedThisMonth: annualDaysThisMonth[d.uid] ?? 0,
        );
        final leaveDays = paidAnnualDays;
        final unpaidLeaveDays =
            (unpaidLeaveDaysByDelegateId[d.uid] ?? 0).clamp(0, (elapsedWorkingDays - attendedDaysCount - leaveDays).clamp(0, elapsedWorkingDays));
        final absent = (elapsedWorkingDays - attendedDaysCount - leaveDays - unpaidLeaveDays).clamp(0, elapsedWorkingDays);

        // Configuration resolution (Custom Wallet Override vs Company Policy)
        final alloc = (walletData['monthlyAllocation'] as num?)?.toDouble() ?? 0.0;
        final base = (walletData['baseSalary'] as num?)?.toDouble() ?? 0.0;
        final delegateBaseSalary = alloc > 0
            ? alloc
            : (base > 0 ? base : _companyPayrollConfig.defaultMonthlyBaseSalary);

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
            unpaidLeaveDays: unpaidLeaveDays,
            absentDays: absent,
            elapsedWorkingDays: elapsedWorkingDays,
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
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
      await FirebaseFirestore.instance
          .collection('company_payroll_configs')
          .doc(widget.hrDelegate.companyUID)
          .set(newConfig.toMap(), SetOptions(merge: true));

      if (mounted) {
        setState(() {
          _companyPayrollConfig = newConfig;
        });
        _loadPayrollData();

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
  }

  /// نافذة تعديل راتب وساعات العمل لمندوب بعينه
  void _openDelegateSalaryDialog(_DelegatePayrollItem item) {
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
    _DelegatePayrollItem item,
    double baseSal,
    double shiftH,
    double? customRate,
    PayrollCalculationMode selectedMode,
  ) async {
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
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.hrDelegate.companyName,
                    style: TextStyle(
                      fontSize: 11,
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

                      // ── Search Bar ──
                      SizedBox(
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
    final isWide = MediaQuery.of(context).size.width > 768;

    if (!isWide) {
      showModalBottomSheet(
        context: context,
        isScrollControlled: true,
        useSafeArea: true,
        backgroundColor: Theme.of(context).colorScheme.surface,
        barrierColor: Colors.black54,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
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
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
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
                  borderRadius: BorderRadius.circular(10),
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
                      style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                    ),
                    Text(
                      'ضبط معايير الورديات واحتساب الساعات للشركة',
                      style: TextStyle(
                        fontSize: 11.5,
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 13),
                ),
                const SizedBox(height: 8),
                Container(
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerLow,
                    borderRadius: BorderRadius.circular(14),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Column(
                    children: [
                      InkWell(
                        borderRadius:
                            const BorderRadius.vertical(top: Radius.circular(14)),
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
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'يُحدد راتب أساسي ثابت، ويُخصم منه ما يعادل ساعات الغياب أو العجز عن ساعات الوردية المحددة لكل موظف',
                                      style: TextStyle(
                                        fontSize: 11,
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
                            bottom: Radius.circular(14)),
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
                                        fontSize: 13,
                                        fontWeight: FontWeight.w600,
                                      ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      'يتقاضى المندوب أجراً مباشراً عن كل ساعة عمل منجزة + الإجازات الرسمية المعتمدة',
                                      style: TextStyle(
                                        fontSize: 11,
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
                            borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(12),
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
                    borderRadius: BorderRadius.circular(12),
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
                              fontSize: 12,
                              fontWeight: FontWeight.bold,
                            ),
                          ),
                          Text(
                            '${activeRate.toStringAsFixed(2)} ج.م / ساعة',
                            style: TextStyle(
                              color: colorScheme.primary,
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                            style: const TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${activeDailyRate.toStringAsFixed(2)} ج.م / يوم',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 13,
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
                            style: TextStyle(fontSize: 12),
                          ),
                          Text(
                            '${(workD * shiftH).toStringAsFixed(0)} ساعة عمل',
                            style: const TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 12,
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
              borderRadius: BorderRadius.circular(24),
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
                                fontSize: 13,
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
                                      fontSize: 13,
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
  final _DelegatePayrollItem item;
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
                        fontSize: 16,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                    Text(
                      'تعديل معايير الراتب وساعات الوردية الخاصة بالمندوب',
                      style: TextStyle(
                        fontSize: 11.5,
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
                      borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(12),
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
                            borderRadius: BorderRadius.circular(12),
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
                  style: TextStyle(fontWeight: FontWeight.bold, fontSize: 12),
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
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    ),
                  ),
                  child: Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      const Text(
                        'أجر الساعة الناتج:',
                        style: TextStyle(fontSize: 12),
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
              borderRadius: BorderRadius.circular(24),
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
                                fontSize: 13,
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
                                      fontSize: 13,
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
  final _DelegatePayrollItem item;
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
        borderRadius: BorderRadius.circular(16),
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
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 17, color: iconColor),
              ),
              const SizedBox(width: 8),
              Text(
                title,
                style: TextStyle(
                  fontWeight: FontWeight.bold,
                  fontSize: 13,
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
            style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
          ),
          const Spacer(),
          Text(
            value,
            style: TextStyle(
              fontSize: 12.5,
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
                        fontSize: 16,
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
                              fontSize: 10.5,
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
                              fontSize: 12,
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
                      valueColor: const Color(0xFF2E7D32),
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
                      valueColor: const Color(0xFF2E7D32),
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
                          borderRadius: BorderRadius.circular(10),
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
                                  fontSize: 11.5,
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
                          const Icon(Icons.verified_rounded, size: 18, color: Color(0xFF2E7D32)),
                          const SizedBox(width: 8),
                          Expanded(
                            child: Text(
                              'لا توجد أي جزاءات مسجلة على المندوب في هذا الشهر',
                              style: TextStyle(
                                fontSize: 12,
                                color: const Color(0xFF2E7D32),
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
                    color: const Color(0xFF2E7D32).withValues(alpha: 0.08),
                    borderRadius: BorderRadius.circular(16),
                    border: Border.all(
                      color: const Color(0xFF2E7D32).withValues(alpha: 0.35),
                      width: 1.2,
                    ),
                  ),
                  child: Row(
                    children: [
                      Container(
                        width: 44,
                        height: 44,
                        decoration: BoxDecoration(
                          color: const Color(0xFF2E7D32).withValues(alpha: 0.15),
                          borderRadius: BorderRadius.circular(12),
                        ),
                        child: const Icon(
                          Icons.payments_rounded,
                          color: Color(0xFF2E7D32),
                          size: 24,
                        ),
                      ),
                      const SizedBox(width: 12),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            const Text(
                              'صافي المستحق للصرف',
                              style: TextStyle(
                                fontSize: 12.5,
                                fontWeight: FontWeight.bold,
                                color: Color(0xFF1B5E20),
                              ),
                            ),
                            Text(
                              'مستحق عن ${item.payableDays} يوم عمل (بعد الخصومات والجزاءات)',
                              style: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                      Text(
                        '${item.netSalary.toStringAsFixed(0)} ج.م',
                        style: const TextStyle(
                          fontSize: 20,
                          fontWeight: FontWeight.w900,
                          color: Color(0xFF2E7D32),
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
              borderRadius: BorderRadius.circular(24),
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
                                fontSize: 13,
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
                                fontSize: 13,
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
