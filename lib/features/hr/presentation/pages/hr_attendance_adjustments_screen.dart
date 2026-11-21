import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/core/widgets/tashil_icon_button.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// نموذج سجل تعديل الحضور والانصراف الإداري
class AttendanceAdjustmentRecord {
  final String id;
  final String companyUID;
  final String organizationUID;
  final String delegateUID;
  final String delegateName;
  final String? delegatePhotoUrl;
  final String delegatePhone;
  final String delegateRole;
  final String branchName;
  final String attendanceSessionId;
  final DateTime sessionDate;
  final DateTime originalCheckInTime;
  final DateTime newCheckInTime;
  final bool wasCheckInModified;
  final DateTime? originalCheckOutTime;
  final DateTime? newCheckOutTime;
  final bool wasCheckOutModified;
  final bool isNewCheckOutCreated;
  final int? originalDurationMinutes;
  final int? newDurationMinutes;
  final String adjustedByUID;
  final String adjustedByName;
  final String adjustedByRole;
  final String reason;
  final String? notes;
  final DateTime adjustedAt;

  const AttendanceAdjustmentRecord({
    required this.id,
    required this.companyUID,
    required this.organizationUID,
    required this.delegateUID,
    required this.delegateName,
    this.delegatePhotoUrl,
    required this.delegatePhone,
    required this.delegateRole,
    required this.branchName,
    required this.attendanceSessionId,
    required this.sessionDate,
    required this.originalCheckInTime,
    required this.newCheckInTime,
    required this.wasCheckInModified,
    this.originalCheckOutTime,
    this.newCheckOutTime,
    required this.wasCheckOutModified,
    required this.isNewCheckOutCreated,
    this.originalDurationMinutes,
    this.newDurationMinutes,
    required this.adjustedByUID,
    required this.adjustedByName,
    required this.adjustedByRole,
    required this.reason,
    this.notes,
    required this.adjustedAt,
  });

  factory AttendanceAdjustmentRecord.fromFirestore(DocumentSnapshot<Map<String, dynamic>> doc) {
    final data = doc.data() ?? {};

    DateTime toDate(dynamic value, [DateTime? fallback]) {
      if (value is Timestamp) return value.toDate();
      if (value is String) return DateTime.tryParse(value) ?? (fallback ?? DateTime.now());
      return fallback ?? DateTime.now();
    }

    return AttendanceAdjustmentRecord(
      id: doc.id,
      companyUID: data['companyUID']?.toString() ?? '',
      organizationUID: data['organizationUID']?.toString() ?? '',
      delegateUID: data['delegateUID']?.toString() ?? '',
      delegateName: data['delegateName']?.toString() ?? 'غير معروف',
      delegatePhotoUrl: data['delegatePhotoUrl']?.toString(),
      delegatePhone: data['delegatePhone']?.toString() ?? '',
      delegateRole: data['delegateRole']?.toString() ?? '',
      branchName: data['branchName']?.toString() ?? 'غير محدد',
      attendanceSessionId: data['attendanceSessionId']?.toString() ?? '',
      sessionDate: toDate(data['sessionDate']),
      originalCheckInTime: toDate(data['originalCheckInTime']),
      newCheckInTime: toDate(data['newCheckInTime']),
      wasCheckInModified: data['wasCheckInModified'] == true,
      originalCheckOutTime: data['originalCheckOutTime'] != null ? toDate(data['originalCheckOutTime']) : null,
      newCheckOutTime: data['newCheckOutTime'] != null ? toDate(data['newCheckOutTime']) : null,
      wasCheckOutModified: data['wasCheckOutModified'] == true,
      isNewCheckOutCreated: data['isNewCheckOutCreated'] == true,
      originalDurationMinutes: (data['originalDurationMinutes'] as num?)?.toInt(),
      newDurationMinutes: (data['newDurationMinutes'] as num?)?.toInt(),
      adjustedByUID: data['adjustedByUID']?.toString() ?? '',
      adjustedByName: data['adjustedByName']?.toString() ?? 'مسؤول الموارد البشرية',
      adjustedByRole: data['adjustedByRole']?.toString() ?? 'HR',
      reason: data['reason']?.toString() ?? 'تصحيح إداري',
      notes: data['notes']?.toString(),
      adjustedAt: toDate(data['adjustedAt']),
    );
  }

  /// فارق مدة العمل بالدقائق (+ أو -)
  int get durationDiffMinutes {
    final newMin = newDurationMinutes ?? 0;
    final origMin = originalDurationMinutes ?? 0;
    return newMin - origMin;
  }

  /// نص منسق لفارق الساعات
  String get formattedDurationDiff {
    final diff = durationDiffMinutes;
    if (diff == 0) return 'بدون تغيير';
    final sign = diff > 0 ? '+' : '-';
    final absDiff = diff.abs();
    final h = absDiff ~/ 60;
    final m = absDiff % 60;
    if (h > 0 && m > 0) {
      return '$sign$h س و $m د';
    } else if (h > 0) {
      return '$sign$h ساعة';
    } else {
      return '$sign$m دقيقة';
    }
  }
}

/// A request from the web shell to show «سجل تعديلات الحضور» for one
/// delegate (TAS-146). Each request is a new object, so asking again for the
/// same delegate after the user cleared the filter applies it again.
class HrAdjustmentsDelegateFilter {
  HrAdjustmentsDelegateFilter({required this.uid, required this.name});

  final String uid;
  final String name;
}

/// شاشة سجل تعديلات الحضور والانصراف الإدارية (Audit Trail)
class HRAttendanceAdjustmentsScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;
  final String? initialDelegateUID;

  /// Web shell: delegate filter opened from «سجل الحضور والانصراف التفصيلي»
  /// (TAS-146). Shown as a chip the user can clear.
  final HrAdjustmentsDelegateFilter? delegateFilter;

  const HRAttendanceAdjustmentsScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
    this.initialDelegateUID,
    this.delegateFilter,
  });

  /// Tests swap in a fake Firestore for the reads.
  @visibleForTesting
  static FirebaseFirestore Function()? debugFirestore;

  @override
  State<HRAttendanceAdjustmentsScreen> createState() => _HRAttendanceAdjustmentsScreenState();
}

class _HRAttendanceAdjustmentsScreenState extends State<HRAttendanceAdjustmentsScreen> {
  final TextEditingController _searchController = TextEditingController();
  String _selectedPeriodFilter = 'all'; // 'all', 'today', 'this_week', 'this_month'
  String _selectedReasonFilter = 'all';
  String _searchQuery = '';
  Map<String, Delegate> _delegatesByUid = {};
  int? _hoveredRowIndex;
  HrAdjustmentsDelegateFilter? _delegateFilter;

  @override
  void initState() {
    super.initState();
    _delegateFilter = widget.delegateFilter;
    _loadCompanyDelegates();
    _searchController.addListener(() {
      setState(() => _searchQuery = _searchController.text.trim());
    });
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
        if (mounted) {
          setState(() {
            _delegatesByUid = {for (final d in page.delegates) d.uid: d};
          });
        }
      });
    } catch (_) {}
  }

  @override
  void didUpdateWidget(covariant HRAttendanceAdjustmentsScreen oldWidget) {
    super.didUpdateWidget(oldWidget);
    if (!identical(oldWidget.delegateFilter, widget.delegateFilter)) {
      _delegateFilter = widget.delegateFilter;
    }
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  bool _matchesPeriod(DateTime date, String period) {
    final now = DateTime.now();
    switch (period) {
      case 'today':
        return date.year == now.year && date.month == now.month && date.day == now.day;
      case 'this_week':
        final startOfWeek = now.subtract(Duration(days: now.weekday % 7));
        final diff = date.difference(startOfWeek).inDays;
        return diff >= 0 && diff < 7;
      case 'this_month':
        return date.year == now.year && date.month == now.month;
      case 'all':
      default:
        return true;
    }
  }

  List<AttendanceAdjustmentRecord> _filterRecords(List<AttendanceAdjustmentRecord> records) {
    return records.where((r) {
      // 1. Strict Company Multi-Tenant Scoping (Zero Leakage)
      if (r.companyUID.isNotEmpty &&
          widget.hrDelegate.companyUID.isNotEmpty &&
          r.companyUID != widget.hrDelegate.companyUID) {
        return false;
      }

      // 2. Delegate specific initial filter (if opened for a single delegate)
      if (widget.initialDelegateUID != null &&
          widget.initialDelegateUID!.isNotEmpty &&
          r.delegateUID != widget.initialDelegateUID) {
        return false;
      }

      // 2b. Delegate filter from the web shell (TAS-146)
      final delegateFilter = _delegateFilter;
      if (delegateFilter != null && r.delegateUID != delegateFilter.uid) {
        return false;
      }

      // 3. Search query (name or phone)
      if (_searchQuery.isNotEmpty) {
        final q = _searchQuery.toLowerCase();
        final nameMatch = r.delegateName.toLowerCase().contains(q);
        final phoneMatch = r.delegatePhone.contains(q);
        final branchMatch = r.branchName.toLowerCase().contains(q);
        final adminMatch = r.adjustedByName.toLowerCase().contains(q);
        if (!nameMatch && !phoneMatch && !branchMatch && !adminMatch) return false;
      }

      // 4. Reason filter
      if (_selectedReasonFilter != 'all') {
        if (r.reason != _selectedReasonFilter) return false;
      }

      // 5. Period filter
      if (!_matchesPeriod(r.adjustedAt, _selectedPeriodFilter)) {
        return false;
      }

      return true;
    }).toList();
  }

  Future<void> _exportToCSV(List<AttendanceAdjustmentRecord> records) async {
    if (records.isEmpty) {
      ScaffoldMessenger.of(context).showSnackBar(
        const SnackBar(content: Text('لا توجد سجلات تعديل لتصديرها')),
      );
      return;
    }

    final dateStr = DateFormat('yyyy_MM_dd', 'en').format(DateTime.now());
    final fileName = 'سجل_تعديلات_الحضور_والانصراف_$dateStr.csv';

    final buffer = StringBuffer();
    // UTF-8 BOM for Arabic support in Excel
    buffer.write('\uFEFF');

    buffer.writeln('سجل التعديلات الإدارية على الحضور والانصراف');
    buffer.writeln('الشركة:,"${widget.hrDelegate.companyName}"');
    buffer.writeln('تاريخ التصدير:,"${DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(DateTime.now())}"');
    buffer.writeln('إجمالي السجلات المصدرة:,"${records.length}"');
    buffer.writeln('');

    buffer.writeln('التاريخ,اسم المندوب,الهاتف,الفرع,الحضور الأصلي,الحضور المعدل,الانصراف الأصلي,الانصراف المعدل,فارق الساعات,سبب التعديل,الملاحظات,المسؤول المنفذ,توقيت التعديل');

    for (final r in records) {
      final sessionDate = DateFormat('yyyy/MM/dd', 'en').format(r.sessionDate);
      final inOrig = DateFormat('hh:mm a', 'ar').format(r.originalCheckInTime);
      final inNew = DateFormat('hh:mm a', 'ar').format(r.newCheckInTime);
      final outOrig = r.originalCheckOutTime != null
          ? DateFormat('hh:mm a', 'ar').format(r.originalCheckOutTime!)
          : 'لم يسجل';
      final outNew = r.newCheckOutTime != null
          ? DateFormat('hh:mm a', 'ar').format(r.newCheckOutTime!)
          : 'لم يسجل';
      final diffStr = r.formattedDurationDiff;
      final adjTime = DateFormat('yyyy/MM/dd hh:mm a', 'ar').format(r.adjustedAt);

      buffer.writeln(
        '"$sessionDate","${r.delegateName}","${r.delegatePhone}","${r.branchName}","$inOrig","$inNew","$outOrig","$outNew","$diffStr","${r.reason}","${r.notes ?? ''}","${r.adjustedByName}","$adjTime"',
      );
    }

    await FileDownloadHelper.downloadString(
      content: buffer.toString(),
      fileName: fileName,
      mimeType: 'text/csv;charset=utf-8',
    );

    if (mounted) {
      ScaffoldMessenger.of(context).showSnackBar(
        SnackBar(
          content: Text('تم تصدير $fileName بنجاح'),
          backgroundColor: HrStatusColors.of(context).success,
        ),
      );
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isWide = MediaQuery.of(context).size.width >= 900;

    // Strict multi-tenant query
    final db = HRAttendanceAdjustmentsScreen.debugFirestore?.call() ??
        FirebaseFirestore.instance;
    Query<Map<String, dynamic>> query = db.collection(
      kAttendanceAdjustmentLogsCollection,
    );

    if (widget.hrDelegate.companyUID.isNotEmpty) {
      query = query.where('companyUID', isEqualTo: widget.hrDelegate.companyUID);
    }

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
                    'سجل تعديلات الحضور والانصراف',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: HrFont.body,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.hrDelegate.companyName.isNotEmpty
                        ? widget.hrDelegate.companyName
                        : 'إدارة الرقابة الإدارية والامتثال',
                    style: TextStyle(
                      fontSize: HrFont.labelSmall,
                      color: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                ],
              ),
              centerTitle: false,
              elevation: 0,
            )
          : null,
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.hasError) {
            return Center(
              child: Padding(
                padding: const EdgeInsets.all(24),
                child: Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                    const SizedBox(height: 12),
                    Text('حدث خطأ أثناء تحميل السجلات: ${snapshot.error}', textAlign: TextAlign.center),
                  ],
                ),
              ),
            );
          }

          if (snapshot.connectionState == ConnectionState.waiting) {
            return const Center(child: CircularProgressIndicator());
          }

          final allDocs = snapshot.data?.docs ?? [];
          final allRecords = allDocs
              .map((doc) => AttendanceAdjustmentRecord.fromFirestore(doc))
              .toList();

          // Sort descending by adjustedAt
          allRecords.sort((a, b) => b.adjustedAt.compareTo(a.adjustedAt));

          final filteredRecords = _filterRecords(allRecords);

          // Calculate unique reasons for dropdown
          final distinctReasons = <String>{};
          for (final r in allRecords) {
            if (r.reason.isNotEmpty) distinctReasons.add(r.reason);
          }

          // KPI calculations
          final now = DateTime.now();
          final todayCount = allRecords.where((r) =>
              r.adjustedAt.year == now.year &&
              r.adjustedAt.month == now.month &&
              r.adjustedAt.day == now.day).length;
          final thisMonthCount = allRecords.where((r) =>
              r.adjustedAt.year == now.year &&
              r.adjustedAt.month == now.month).length;
          final uniqueDelegatesCount = allRecords.map((r) => r.delegateUID).toSet().length;

          return CustomScrollView(
            slivers: [
              SliverPadding(
                padding: EdgeInsets.symmetric(
                  horizontal: isWide ? 24 : 16,
                  vertical: 16,
                ),
                sliver: SliverList(
                  delegate: SliverChildListDelegate([
                    // 1. KPI Summary Cards
                    _buildKpiSection(
                      totalCount: allRecords.length,
                      thisMonthCount: thisMonthCount,
                      todayCount: todayCount,
                      uniqueDelegatesCount: uniqueDelegatesCount,
                      colorScheme: colorScheme,
                      isWide: isWide,
                    ),
                    const SizedBox(height: 16),

                    // 2. Search & Filter Bar
                    _buildFilterControls(
                      distinctReasons: distinctReasons,
                      recordCount: filteredRecords.length,
                      onExport: () => _exportToCSV(filteredRecords),
                      colorScheme: colorScheme,
                      isWide: isWide,
                    ),
                    const SizedBox(height: 16),

                    // 3. Records Table or Empty State
                    if (filteredRecords.isEmpty)
                      _buildEmptyState(colorScheme)
                    else if (isWide)
                      _buildDesktopTable(filteredRecords, colorScheme)
                    else
                      _buildMobileList(filteredRecords, colorScheme),
                  ]),
                ),
              ),
            ],
          );
        },
      ),
    );
  }

  // --- 1. KPI Cards ---
  Widget _buildKpiSection({
    required int totalCount,
    required int thisMonthCount,
    required int todayCount,
    required int uniqueDelegatesCount,
    required ColorScheme colorScheme,
    required bool isWide,
  }) {
    final kpis = [
      _AuditKpiItem(
        title: 'إجمالي التعديلات',
        value: '$totalCount واقعة',
        subtitle: 'مسجلة في النظام',
        icon: Icons.history_edu_rounded,
        color: colorScheme.primary,
      ),
      _AuditKpiItem(
        title: 'تعديلات هذا الشهر',
        value: '$thisMonthCount تعديل',
        subtitle: DateFormat('MMMM yyyy', 'ar').format(DateTime.now()),
        icon: Icons.calendar_month_rounded,
        color: colorScheme.tertiary,
      ),
      _AuditKpiItem(
        title: 'تعديلات اليوم',
        value: '$todayCount اليوم',
        subtitle: DateFormat('EEEE، d MMMM', 'ar').format(DateTime.now()),
        icon: Icons.today_rounded,
        color: colorScheme.secondary,
      ),
      _AuditKpiItem(
        title: 'المناديب المعدل لهم',
        value: '$uniqueDelegatesCount مندوب',
        subtitle: 'مستفيد من التعديل',
        icon: Icons.people_alt_rounded,
        color: colorScheme.primary,
      ),
    ];

    if (isWide) {
      return IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: kpis.map((kpi) {
            return Expanded(
              child: Padding(
                padding: const EdgeInsets.symmetric(horizontal: 6),
                child: _buildKpiCard(kpi, colorScheme),
              ),
            );
          }).toList(),
        ),
      );
    }

    return Column(
      children: [
        Row(
          children: [
            Expanded(child: _buildKpiCard(kpis[0], colorScheme)),
            const SizedBox(width: 8),
            Expanded(child: _buildKpiCard(kpis[1], colorScheme)),
          ],
        ),
        const SizedBox(height: 8),
        Row(
          children: [
            Expanded(child: _buildKpiCard(kpis[2], colorScheme)),
            const SizedBox(width: 8),
            Expanded(child: _buildKpiCard(kpis[3], colorScheme)),
          ],
        ),
      ],
    );
  }

  Widget _buildKpiCard(_AuditKpiItem kpi, ColorScheme colorScheme) {
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
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Flexible(
                child: Text(
                  kpi.title,
                  style: TextStyle(
                    fontSize: HrFont.labelSmall,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Container(
                padding: const EdgeInsets.all(5),
                decoration: BoxDecoration(
                  color: kpi.color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(HrRadius.chip),
                ),
                child: Icon(kpi.icon, size: 14, color: kpi.color),
              ),
            ],
          ),
          const SizedBox(height: 6),
          Text(
            kpi.value,
            style: TextStyle(
              fontSize: HrFont.body,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          const SizedBox(height: 2),
          Text(
            kpi.subtitle,
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

  // --- 2. Filter Bar ---
  Widget _buildFilterControls({
    required Set<String> distinctReasons,
    required int recordCount,
    required VoidCallback onExport,
    required ColorScheme colorScheme,
    required bool isWide,
  }) {
    if (isWide) {
      return Wrap(
        spacing: 10,
        runSpacing: 10,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          if (_delegateFilter != null) _buildDelegateFilterChip(colorScheme),
          SizedBox(
            width: 260,
            height: 42,
            child: _buildSearchTextField(colorScheme),
          ),
          TashilConnectedButtonGroup<String>(
            height: 42.0,
            selectedValue: _selectedPeriodFilter,
            items: const [
              TashilConnectedButtonItem(value: 'all', label: 'الكل'),
              TashilConnectedButtonItem(value: 'today', label: 'اليوم'),
              TashilConnectedButtonItem(value: 'this_week', label: 'الأسبوع'),
              TashilConnectedButtonItem(value: 'this_month', label: 'الشهر'),
            ],
            onSelected: (val) => setState(() => _selectedPeriodFilter = val),
          ),
          // Web: a normal dropdown sized to its content, not a bar across
          // the whole page (TAS-146). Mobile keeps its selector.
          if (WebRuntimePolicy.isWeb)
            _buildReasonDropdown(distinctReasons, colorScheme)
          else
            _buildReasonSelector(distinctReasons, colorScheme),
          _buildCountAndExportGroup(recordCount, onExport, colorScheme),
        ],
      );
    } else {
      return Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (_delegateFilter != null) ...[
            Align(
              alignment: AlignmentDirectional.centerStart,
              child: _buildDelegateFilterChip(colorScheme),
            ),
            const SizedBox(height: 8),
          ],
          SizedBox(
            height: 42,
            child: _buildSearchTextField(colorScheme),
          ),
          const SizedBox(height: 8),
          TashilConnectedButtonGroup<String>(
            height: 40.0,
            width: double.infinity,
            selectedValue: _selectedPeriodFilter,
            items: const [
              TashilConnectedButtonItem(value: 'all', label: 'الكل'),
              TashilConnectedButtonItem(value: 'today', label: 'اليوم'),
              TashilConnectedButtonItem(value: 'this_week', label: 'الأسبوع'),
              TashilConnectedButtonItem(value: 'this_month', label: 'الشهر'),
            ],
            onSelected: (val) => setState(() => _selectedPeriodFilter = val),
          ),
          const SizedBox(height: 8),
          Row(
            children: [
              Expanded(
                child: _buildReasonSelector(distinctReasons, colorScheme),
              ),
              const SizedBox(width: 8),
              _buildCountAndExportGroup(recordCount, onExport, colorScheme),
            ],
          ),
        ],
      );
    }
  }

  Widget _buildSearchTextField(ColorScheme colorScheme) {
    return TextField(
      controller: _searchController,
      style: TextStyle(fontSize: HrFont.body, color: colorScheme.onSurface),
      textAlignVertical: TextAlignVertical.center,
      decoration: InputDecoration(
        hintText: 'بحث باسم المندوب أو الهاتف...',
        hintStyle: TextStyle(
          fontSize: HrFont.labelMedium,
          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
        ),
        prefixIcon: Icon(Icons.search_rounded, size: 19, color: colorScheme.primary),
        suffixIcon: _searchQuery.isNotEmpty
            ? IconButton(
                icon: const Icon(Icons.clear_rounded, size: 16),
                tooltip: 'مسح البحث',
                onPressed: () => _searchController.clear(),
              )
            : null,
        contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 0),
        isDense: true,
        filled: true,
        fillColor: colorScheme.surfaceContainerHigh,
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
    );
  }

  /// Active delegate filter from the web shell; deleting it shows every
  /// delegate again (TAS-146).
  Widget _buildDelegateFilterChip(ColorScheme colorScheme) {
    final filter = _delegateFilter!;
    final name = filter.name.isNotEmpty
        ? filter.name
        : (_delegatesByUid[filter.uid]?.fullName ?? '');
    return InputChip(
      key: const Key('hr_adjustments_delegate_filter'),
      avatar: Icon(Icons.person_rounded, size: 18, color: colorScheme.primary),
      label: Text(
        name.isNotEmpty ? 'المندوب: $name' : 'مندوب محدد',
        maxLines: 1,
        overflow: TextOverflow.ellipsis,
      ),
      deleteButtonTooltipMessage: 'عرض كل المناديب',
      onDeleted: () => setState(() => _delegateFilter = null),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.chip),
      ),
    );
  }

  /// Web reason filter: a standard M3 dropdown with a fixed width (TAS-146).
  Widget _buildReasonDropdown(
    Set<String> distinctReasons,
    ColorScheme colorScheme,
  ) {
    final reasons = ['all', ...distinctReasons];
    final selected = reasons.contains(_selectedReasonFilter)
        ? _selectedReasonFilter
        : 'all';
    return DropdownMenu<String>(
      key: const Key('hr_adjustments_reason_filter'),
      width: 240,
      initialSelection: selected,
      leadingIcon: Icon(
        Icons.tune_rounded,
        size: 18,
        color: selected != 'all'
            ? colorScheme.primary
            : colorScheme.onSurfaceVariant,
      ),
      textStyle: TextStyle(fontSize: HrFont.body, color: colorScheme.onSurface),
      inputDecorationTheme: InputDecorationTheme(
        isDense: true,
        constraints: const BoxConstraints(maxHeight: 42),
        contentPadding: const EdgeInsets.symmetric(horizontal: 12),
        border: OutlineInputBorder(
          borderRadius: BorderRadius.circular(HrRadius.pill),
        ),
      ),
      onSelected: (val) {
        if (val != null) setState(() => _selectedReasonFilter = val);
      },
      dropdownMenuEntries: [
        for (final r in reasons)
          DropdownMenuEntry<String>(
            value: r,
            label: r == 'all' ? 'جميع الأسباب' : r,
          ),
      ],
    );
  }

  Widget _buildReasonSelector(Set<String> distinctReasons, ColorScheme colorScheme) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(HrRadius.button),
        border: Border.all(
          color: _selectedReasonFilter != 'all'
              ? colorScheme.primary
              : colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: _selectedReasonFilter != 'all' ? 1.4 : 1.0,
        ),
      ),
      child: PopupMenuButton<String>(
        tooltip: 'تصفية حسب السبب',
        color: colorScheme.surfaceContainerHigh,
        elevation: 3,
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(HrRadius.card),
          side: BorderSide(
            color: colorScheme.outlineVariant.withValues(alpha: 0.4),
          ),
        ),
        initialValue: _selectedReasonFilter,
        onSelected: (val) => setState(() => _selectedReasonFilter = val),
        itemBuilder: (ctx) {
          final reasonsList = ['all', ...distinctReasons];
          return reasonsList.map((r) {
            final isSelected = r == _selectedReasonFilter;
            return PopupMenuItem<String>(
              value: r,
              child: Row(
                children: [
                  Icon(
                    r == 'all' ? Icons.filter_alt_rounded : Icons.label_outline_rounded,
                    size: 17,
                    color: isSelected ? colorScheme.primary : colorScheme.onSurfaceVariant,
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    child: Text(
                      r == 'all' ? 'جميع الأسباب' : r,
                      style: TextStyle(
                        fontSize: HrFont.labelMedium,
                        fontWeight: isSelected ? FontWeight.bold : FontWeight.normal,
                        color: isSelected ? colorScheme.primary : colorScheme.onSurface,
                      ),
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (isSelected) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, size: 16, color: colorScheme.primary),
                  ],
                ],
              ),
            );
          }).toList();
        },
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12),
          child: Row(
            children: [
              Icon(
                Icons.tune_rounded,
                size: 16,
                color: _selectedReasonFilter != 'all'
                    ? colorScheme.primary
                    : colorScheme.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _selectedReasonFilter == 'all' ? 'جميع الأسباب' : _selectedReasonFilter,
                  style: TextStyle(
                    fontSize: HrFont.labelMedium,
                    fontWeight: FontWeight.w600,
                    color: _selectedReasonFilter != 'all'
                        ? colorScheme.primary
                        : colorScheme.onSurface,
                  ),
                  overflow: TextOverflow.ellipsis,
                  maxLines: 1,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.keyboard_arrow_down_rounded,
                size: 18,
                color: colorScheme.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }

  Widget _buildCountAndExportGroup(int recordCount, VoidCallback onExport, ColorScheme colorScheme) {
    return Container(
      height: 40,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerHigh,
        borderRadius: BorderRadius.circular(HrRadius.button),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
          width: 1.0,
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          // 1. Record Count Badge
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 11),
            child: Row(
              mainAxisSize: MainAxisSize.min,
              children: [
                Icon(Icons.receipt_long_rounded, size: 15, color: colorScheme.primary),
                const SizedBox(width: 5),
                Text(
                  'عدد: $recordCount',
                  style: TextStyle(
                    fontSize: HrFont.labelMedium,
                    fontWeight: FontWeight.bold,
                    color: colorScheme.onSurface,
                  ),
                ),
              ],
            ),
          ),

          // Divider
          SizedBox(
            height: 20,
            child: VerticalDivider(
              width: 1,
              thickness: 1,
              color: colorScheme.outlineVariant.withValues(alpha: 0.4),
            ),
          ),

          // 2. CSV Export Button
          Material(
            color: Colors.transparent,
            child: InkWell(
              onTap: onExport,
              hoverColor: colorScheme.primary.withValues(alpha: 0.08),
              child: Tooltip(
                message: 'تصدير ملف CSV',
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 11),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.arrow_downward_rounded,
                        size: 14,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Text(
                        'CSV',
                        style: TextStyle(
                          fontSize: HrFont.labelMedium,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                          letterSpacing: 0.5,
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

  // --- 3. Desktop Table ---
  Widget _buildDesktopTable(List<AttendanceAdjustmentRecord> records, ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          const double minWidth = 1160.0;
          final bool needsScroll = constraints.maxWidth < minWidth;
          final double tableWidth = needsScroll ? minWidth : constraints.maxWidth;

          Widget tableContent = SizedBox(
            width: tableWidth,
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.stretch,
              children: [
                // Header
                Container(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                  color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.5),
                  child: Row(
                    children: [
                      _buildHeaderCell('المندوب والفرع', flex: 20),
                      _buildHeaderCell('تاريخ الجلسة', flex: 13),
                      _buildHeaderCell('وقت الحضور', flex: 15),
                      _buildHeaderCell('وقت الانصراف', flex: 15),
                      _buildHeaderCell('فارق الساعات', flex: 14),
                      _buildHeaderCell('سبب التعديل', flex: 15),
                      _buildHeaderCell('المسؤول المنفذ', flex: 16),
                      _buildHeaderCell('التفاصيل', flex: 6, alignment: AlignmentDirectional.center),
                    ],
                  ),
                ),
                const Divider(height: 1, thickness: 1),

                // Rows
                ListView.separated(
                  shrinkWrap: true,
                  physics: const NeverScrollableScrollPhysics(),
                  itemCount: records.length,
                  separatorBuilder: (_, _) => Divider(
                    height: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                  itemBuilder: (ctx, index) {
                    final r = records[index];
                    final isEven = index % 2 == 0;
                    final isHovered = _hoveredRowIndex == index;

                    // Resolve delegate photo URL
                    final photoUrl = r.delegatePhotoUrl ??
                        _delegatesByUid[r.delegateUID]?.personalPhotoUrl;

                    return MouseRegion(
                      onEnter: (_) => setState(() => _hoveredRowIndex = index),
                      onExit: (_) => setState(() {
                        if (_hoveredRowIndex == index) _hoveredRowIndex = null;
                      }),
                      child: AnimatedContainer(
                        duration: AppMotionDurations.short3,
                        curve: AppMotionCurves.standard,
                        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                        color: isHovered
                            ? colorScheme.primary.withValues(alpha: 0.05)
                            : (isEven
                                ? colorScheme.surface
                                : colorScheme.surfaceContainerHighest.withValues(alpha: 0.15)),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.center,
                          children: [
                            // 1. Delegate & Branch (flex: 20)
                            Expanded(
                              flex: 20,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    AppAvatar(
                                      imageUrl: photoUrl,
                                      fallbackText: r.delegateName,
                                      radius: 19,
                                    ),
                                    const SizedBox(width: 10),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            r.delegateName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: HrFont.body,
                                              letterSpacing: 0.1,
                                            ),
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          Row(
                                            children: [
                                              Icon(
                                                Icons.storefront_rounded,
                                                size: 13,
                                                color: colorScheme.primary,
                                              ),
                                              const SizedBox(width: 4),
                                              Expanded(
                                                child: Text(
                                                  r.branchName,
                                                  style: TextStyle(
                                                    fontSize: HrFont.labelSmall,
                                                    color: colorScheme.onSurfaceVariant,
                                                  ),
                                                  overflow: TextOverflow.ellipsis,
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

                            // 2. Session Date (flex: 13)
                            Expanded(
                              flex: 13,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  mainAxisSize: MainAxisSize.min,
                                  children: [
                                    Text(
                                      DateFormat('EEEE', 'ar').format(r.sessionDate),
                                      style: const TextStyle(
                                        fontWeight: FontWeight.bold,
                                        fontSize: HrFont.labelMedium,
                                      ),
                                    ),
                                    const SizedBox(height: 3),
                                    Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          Icons.calendar_today_outlined,
                                          size: 11,
                                          color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                                        ),
                                        const SizedBox(width: 4),
                                        Text(
                                          DateFormat('yyyy/MM/dd', 'en').format(r.sessionDate),
                                          style: TextStyle(
                                            fontSize: HrFont.labelSmall,
                                            color: colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 3. Check-in Diff (flex: 15)
                            Expanded(
                              flex: 15,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: _buildTimeDiffCell(
                                  orig: DateFormat('hh:mm a', 'ar').format(r.originalCheckInTime),
                                  updated: DateFormat('hh:mm a', 'ar').format(r.newCheckInTime),
                                  wasModified: r.wasCheckInModified,
                                  activeColor: HrStatusColors.of(context).success,
                                  colorScheme: colorScheme,
                                ),
                              ),
                            ),

                            // 4. Check-out Diff (flex: 15)
                            Expanded(
                              flex: 15,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: _buildTimeDiffCell(
                                  orig: r.originalCheckOutTime != null
                                      ? DateFormat('hh:mm a', 'ar').format(r.originalCheckOutTime!)
                                      : 'لم يسجل',
                                  updated: r.newCheckOutTime != null
                                      ? DateFormat('hh:mm a', 'ar').format(r.newCheckOutTime!)
                                      : 'لم يسجل',
                                  wasModified: r.wasCheckOutModified || r.isNewCheckOutCreated,
                                  activeColor: Colors.indigo.shade800,
                                  colorScheme: colorScheme,
                                ),
                              ),
                            ),

                            // 5. Duration Diff (flex: 14) - Content-sized Pill Badge
                            Expanded(
                              flex: 14,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Align(
                                  alignment: AlignmentDirectional.centerStart,
                                  child: Container(
                                    padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 5),
                                    decoration: BoxDecoration(
                                      color: r.durationDiffMinutes > 0
                                          ? const Color(0xFFE8F5E9)
                                          : r.durationDiffMinutes < 0
                                              ? const Color(0xFFFFEBEE)
                                              : colorScheme.surfaceContainerHighest,
                                      borderRadius: BorderRadius.circular(HrRadius.button),
                                      border: Border.all(
                                        color: r.durationDiffMinutes > 0
                                            ? const Color(0xFFA5D6A7)
                                            : r.durationDiffMinutes < 0
                                                ? const Color(0xFFEF9A9A)
                                                : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                        width: 1,
                                      ),
                                    ),
                                    child: Row(
                                      mainAxisSize: MainAxisSize.min,
                                      children: [
                                        Icon(
                                          r.durationDiffMinutes > 0
                                              ? Icons.add_rounded
                                              : r.durationDiffMinutes < 0
                                                  ? Icons.remove_rounded
                                                  : Icons.horizontal_rule_rounded,
                                          size: 13,
                                          color: r.durationDiffMinutes > 0
                                              ? HrStatusColors.of(context).success
                                              : r.durationDiffMinutes < 0
                                                  ? HrStatusColors.of(context).danger
                                                  : colorScheme.onSurfaceVariant,
                                        ),
                                        const SizedBox(width: 3),
                                        Text(
                                          r.formattedDurationDiff,
                                          style: TextStyle(
                                            fontSize: HrFont.labelSmall,
                                            fontWeight: FontWeight.bold,
                                            color: r.durationDiffMinutes > 0
                                                ? HrStatusColors.of(context).success
                                                : r.durationDiffMinutes < 0
                                                    ? HrStatusColors.of(context).danger
                                                    : colorScheme.onSurfaceVariant,
                                          ),
                                        ),
                                      ],
                                    ),
                                  ),
                                ),
                              ),
                            ),

                            // 6. Reason (flex: 15)
                            Expanded(
                              flex: 15,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Row(
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 3,
                                      height: 22,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primary.withValues(alpha: 0.4),
                                        borderRadius: BorderRadius.circular(2),
                                      ),
                                    ),
                                    const SizedBox(width: 7),
                                    Expanded(
                                      child: Text(
                                        r.reason,
                                        style: TextStyle(
                                          fontSize: HrFont.labelMedium,
                                          fontWeight: FontWeight.w600,
                                          color: colorScheme.onSurface,
                                          height: 1.3,
                                        ),
                                        maxLines: 2,
                                        overflow: TextOverflow.ellipsis,
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 7. Adjusted By (flex: 16) - Harmonious Admin Cell
                            Expanded(
                              flex: 16,
                              child: Padding(
                                padding: const EdgeInsetsDirectional.only(end: 12),
                                child: Row(
                                  mainAxisSize: MainAxisSize.min,
                                  crossAxisAlignment: CrossAxisAlignment.center,
                                  children: [
                                    Container(
                                      width: 28,
                                      height: 28,
                                      decoration: BoxDecoration(
                                        color: colorScheme.primaryContainer.withValues(alpha: 0.5),
                                        shape: BoxShape.circle,
                                      ),
                                      child: Icon(
                                        Icons.admin_panel_settings_rounded,
                                        size: 15,
                                        color: colorScheme.primary,
                                      ),
                                    ),
                                    const SizedBox(width: 8),
                                    Expanded(
                                      child: Column(
                                        crossAxisAlignment: CrossAxisAlignment.start,
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        mainAxisSize: MainAxisSize.min,
                                        children: [
                                          Text(
                                            r.adjustedByName,
                                            style: const TextStyle(
                                              fontWeight: FontWeight.w600,
                                              fontSize: HrFont.labelMedium,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                          const SizedBox(height: 3),
                                          Text(
                                            DateFormat('yyyy/MM/dd • hh:mm a', 'ar').format(r.adjustedAt),
                                            style: TextStyle(
                                              fontSize: HrFont.labelSmall,
                                              color: colorScheme.onSurfaceVariant,
                                            ),
                                            maxLines: 1,
                                            overflow: TextOverflow.ellipsis,
                                          ),
                                        ],
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ),

                            // 8. Action Details (flex: 6)
                            Expanded(
                              flex: 6,
                              child: Align(
                                alignment: AlignmentDirectional.center,
                                child: TashilIconButton(
                                  icon: Icons.info_outline_rounded,
                                  size: 32,
                                  iconSize: 17,
                                  tooltip: 'عرض تفاصيل التعديل كاملة',
                                  onPressed: () => _showRecordDetailsModal(r),
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
          );

          if (needsScroll) {
            return SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              physics: const BouncingScrollPhysics(),
              child: tableContent,
            );
          }
          return tableContent;
        },
      ),
    );
  }

  Widget _buildTimeDiffCell({
    required String orig,
    required String updated,
    required bool wasModified,
    required Color activeColor,
    required ColorScheme colorScheme,
  }) {
    if (!wasModified) {
      return Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(
            Icons.access_time_rounded,
            size: 13,
            color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
          ),
          const SizedBox(width: 5),
          Text(
            updated,
            style: TextStyle(
              fontSize: HrFont.labelMedium,
              fontWeight: FontWeight.w500,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ],
      );
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 5),
      decoration: BoxDecoration(
        color: activeColor.withValues(alpha: 0.06),
        borderRadius: BorderRadius.circular(HrRadius.chip),
        border: Border.all(
          color: activeColor.withValues(alpha: 0.22),
          width: 1,
        ),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.history_rounded,
                size: 11,
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
              ),
              const SizedBox(width: 3),
              Text(
                orig,
                style: TextStyle(
                  fontSize: HrFont.labelSmall,
                  decoration: TextDecoration.lineThrough,
                  decorationColor: colorScheme.onSurfaceVariant.withValues(alpha: 0.8),
                  color: colorScheme.onSurfaceVariant.withValues(alpha: 0.75),
                ),
              ),
            ],
          ),
          const SizedBox(height: 3),
          Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(
                Icons.check_circle_outline_rounded,
                size: 12,
                color: activeColor,
              ),
              const SizedBox(width: 3),
              Text(
                updated,
                style: TextStyle(
                  fontSize: HrFont.labelMedium,
                  fontWeight: FontWeight.bold,
                  color: activeColor,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildHeaderCell(
    String text, {
    required int flex,
    AlignmentDirectional alignment = AlignmentDirectional.centerStart,
  }) {
    final colorScheme = Theme.of(context).colorScheme;
    return Expanded(
      flex: flex,
      child: Padding(
        padding: const EdgeInsetsDirectional.only(end: 12),
        child: Align(
          alignment: alignment,
          child: Text(
            text,
            style: TextStyle(
              fontSize: HrFont.labelMedium,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurfaceVariant,
            ),
          ),
        ),
      ),
    );
  }

  // --- 4. Mobile List ---
  Widget _buildMobileList(List<AttendanceAdjustmentRecord> records, ColorScheme colorScheme) {
    return ListView.separated(
      shrinkWrap: true,
      physics: const NeverScrollableScrollPhysics(),
      itemCount: records.length,
      separatorBuilder: (_, _) => const SizedBox(height: 10),
      itemBuilder: (ctx, index) {
        final r = records[index];
        final sessionDateStr = DateFormat('EEEE، d MMMM yyyy', 'ar').format(r.sessionDate);
        final photoUrl = r.delegatePhotoUrl ??
            _delegatesByUid[r.delegateUID]?.personalPhotoUrl;

        return Card(
          elevation: 0,
          color: colorScheme.surface,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(HrRadius.card),
            side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
          ),
          child: InkWell(
            borderRadius: BorderRadius.circular(HrRadius.card),
            onTap: () => _showRecordDetailsModal(r),
            child: Padding(
              padding: const EdgeInsets.all(14),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      AppAvatar(
                        imageUrl: photoUrl,
                        fallbackText: r.delegateName,
                        radius: 18,
                      ),
                      const SizedBox(width: 10),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text(r.delegateName, style: const TextStyle(fontWeight: FontWeight.bold, fontSize: HrFont.body)),
                            Text('${r.branchName} • $sessionDateStr', style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant)),
                          ],
                        ),
                      ),
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 9, vertical: 4),
                        decoration: BoxDecoration(
                          color: r.durationDiffMinutes > 0
                              ? const Color(0xFFE8F5E9)
                              : r.durationDiffMinutes < 0
                                  ? const Color(0xFFFFEBEE)
                                  : colorScheme.surfaceContainerHighest,
                          borderRadius: BorderRadius.circular(HrRadius.button),
                          border: Border.all(
                            color: r.durationDiffMinutes > 0
                                ? const Color(0xFFA5D6A7)
                                : r.durationDiffMinutes < 0
                                    ? const Color(0xFFEF9A9A)
                                    : colorScheme.outlineVariant.withValues(alpha: 0.5),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(
                              r.durationDiffMinutes > 0
                                  ? Icons.add_rounded
                                  : r.durationDiffMinutes < 0
                                      ? Icons.remove_rounded
                                      : Icons.horizontal_rule_rounded,
                              size: 12,
                              color: r.durationDiffMinutes > 0
                                  ? HrStatusColors.of(context).success
                                  : r.durationDiffMinutes < 0
                                      ? HrStatusColors.of(context).danger
                                      : colorScheme.onSurfaceVariant,
                            ),
                            const SizedBox(width: 3),
                            Text(
                              r.formattedDurationDiff,
                              style: TextStyle(
                                fontSize: HrFont.labelSmall,
                                fontWeight: FontWeight.bold,
                                color: r.durationDiffMinutes > 0
                                    ? HrStatusColors.of(context).success
                                    : r.durationDiffMinutes < 0
                                        ? HrStatusColors.of(context).danger
                                        : colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const Divider(height: 18),
                  Row(
                    children: [
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('حضور معدل', style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                              DateFormat('hh:mm a', 'ar').format(r.newCheckInTime),
                              style: TextStyle(fontSize: HrFont.labelMedium, fontWeight: FontWeight.bold, color: HrStatusColors.of(context).success),
                            ),
                          ],
                        ),
                      ),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Text('انصراف معدل', style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant)),
                            const SizedBox(height: 2),
                            Text(
                              r.newCheckOutTime != null ? DateFormat('hh:mm a', 'ar').format(r.newCheckOutTime!) : 'لم يسجل',
                              style: TextStyle(
                                fontSize: HrFont.labelMedium,
                                fontWeight: FontWeight.bold,
                                color: r.newCheckOutTime != null ? Colors.indigo.shade800 : colorScheme.error,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 8),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Expanded(
                        child: Text(
                          'السبب: ${r.reason}',
                          style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurface),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                      const SizedBox(width: 8),
                      Row(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(Icons.admin_panel_settings_outlined, size: 13, color: colorScheme.onSurfaceVariant),
                          const SizedBox(width: 3),
                          Text(
                            r.adjustedByName,
                            style: TextStyle(fontSize: HrFont.labelSmall, color: colorScheme.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ],
                  ),
                ],
              ),
            ),
          ),
        );
      },
    );
  }

  // --- 5. Empty State ---
  Widget _buildEmptyState(ColorScheme colorScheme) {
    return Card(
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: colorScheme.outlineVariant.withValues(alpha: 0.35)),
      ),
      child: Padding(
        padding: const EdgeInsets.all(48),
        child: Column(
          children: [
            Icon(Icons.history_toggle_off_rounded, size: 56, color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4)),
            const SizedBox(height: 16),
            Text(
              'لا توجد تعديلات إدارية مسجلة',
              style: TextStyle(fontSize: HrFont.titleMedium, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
            const SizedBox(height: 8),
            Text(
              'جميع جلسات الحضور والانصراف مسجلة تلقائياً بدون تعديل يدوي، أو لا توجد نتائج تطابق الفلاتر المحددة.',
              style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant),
              textAlign: TextAlign.center,
            ),
          ],
        ),
      ),
    );
  }

  // --- 6. Record Details Modal ---
  void _showRecordDetailsModal(AttendanceAdjustmentRecord r) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(HrRadius.button)),
        title: Row(
          children: [
            AppAvatar(
              imageUrl: r.delegatePhotoUrl ?? _delegatesByUid[r.delegateUID]?.personalPhotoUrl,
              fallbackText: r.delegateName,
              radius: 22,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  const Text('تفاصيل التعديل الإداري', style: TextStyle(fontSize: HrFont.titleMedium, fontWeight: FontWeight.bold)),
                  const SizedBox(height: 2),
                  Text(
                    '${r.delegateName} • ${r.branchName}',
                    style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant),
                  ),
                ],
              ),
            ),
          ],
        ),
        content: SizedBox(
          width: 480,
          child: SingleChildScrollView(
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              mainAxisSize: MainAxisSize.min,
              children: [
                _buildModalRow(Icons.calendar_today_rounded, 'تاريخ جلسة الحضور', DateFormat('EEEE، d MMMM yyyy', 'ar').format(r.sessionDate)),
                const Divider(height: 16),
                _buildModalRow(
                  Icons.login_rounded,
                  'وقت الحضور',
                  'الأصلي: ${DateFormat('hh:mm a', 'ar').format(r.originalCheckInTime)} ➔ الجديد: ${DateFormat('hh:mm a', 'ar').format(r.newCheckInTime)}',
                  valueColor: HrStatusColors.of(context).success,
                ),
                const SizedBox(height: 6),
                _buildModalRow(
                  Icons.logout_rounded,
                  'وقت الانصراف',
                  'الأصلي: ${r.originalCheckOutTime != null ? DateFormat('hh:mm a', 'ar').format(r.originalCheckOutTime!) : 'لم يسجل'} ➔ الجديد: ${r.newCheckOutTime != null ? DateFormat('hh:mm a', 'ar').format(r.newCheckOutTime!) : 'لم يسجل'}',
                  valueColor: r.newCheckOutTime != null ? Colors.indigo.shade800 : colorScheme.error,
                ),
                const SizedBox(height: 6),
                _buildModalRow(
                  Icons.timelapse_rounded,
                  'فارق مدة العمل',
                  r.formattedDurationDiff,
                  valueColor: r.durationDiffMinutes >= 0 ? HrStatusColors.of(context).success : HrStatusColors.of(context).danger,
                ),
                const Divider(height: 16),
                _buildModalRow(Icons.help_outline_rounded, 'سبب التعديل', r.reason),
                if (r.notes != null && r.notes!.isNotEmpty) ...[
                  const SizedBox(height: 6),
                  _buildModalRow(Icons.notes_rounded, 'ملاحظات إدارية', r.notes!),
                ],
                const Divider(height: 16),
                _buildModalRow(Icons.person_pin_rounded, 'المسؤول المنفذ', '${r.adjustedByName} (${r.adjustedByRole})'),
                const SizedBox(height: 6),
                _buildModalRow(Icons.schedule_rounded, 'توقيت تسجيل الواقعة', DateFormat('yyyy/MM/dd hh:mm:ss a', 'ar').format(r.adjustedAt)),
              ],
            ),
          ),
        ),
        actions: [
          FilledButton.tonal(
            onPressed: () => Navigator.pop(ctx),
            child: const Text('إغلاق'),
          ),
        ],
      ),
    );
  }

  Widget _buildModalRow(IconData icon, String label, String value, {Color? valueColor}) {
    final colorScheme = Theme.of(context).colorScheme;
    return Row(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Icon(icon, size: 16, color: colorScheme.onSurfaceVariant),
        const SizedBox(width: 8),
        SizedBox(
          width: 130,
          child: Text(label, style: TextStyle(fontSize: HrFont.labelMedium, color: colorScheme.onSurfaceVariant)),
        ),
        Expanded(
          child: Text(
            value,
            style: TextStyle(
              fontSize: HrFont.labelMedium,
              fontWeight: FontWeight.w600,
              color: valueColor ?? colorScheme.onSurface,
            ),
          ),
        ),
      ],
    );
  }
}

class _AuditKpiItem {
  final String title;
  final String value;
  final String subtitle;
  final IconData icon;
  final Color color;

  const _AuditKpiItem({
    required this.title,
    required this.value,
    required this.subtitle,
    required this.icon,
    required this.color,
  });
}
