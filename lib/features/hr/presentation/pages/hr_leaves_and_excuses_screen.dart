import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:flutter/material.dart';
import 'package:intl/intl.dart' hide TextDirection;

import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;

/// شاشة تقديم ومراجعة واعتماد طلبات الإجازات ومبررات الغياب (HR Leaves & Excuses)
class HRLeavesAndExcusesScreen extends StatefulWidget {
  final Delegate hrDelegate;
  final bool showAppBar;

  const HRLeavesAndExcusesScreen({
    super.key,
    required this.hrDelegate,
    this.showAppBar = true,
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

  @override
  void initState() {
    super.initState();
    _loadCompanyDelegates();
  }

  @override
  void dispose() {
    _searchController.dispose();
    super.dispose();
  }

  Future<void> _loadCompanyDelegates() async {
    try {
      final res = await di.sl<GetCompanyDelegates>()(
        GetCompanyDelegatesParams(
          organizationUID: widget.hrDelegate.organizationUID,
          companyUID: widget.hrDelegate.companyUID,
        ),
      );
      res.fold((_) {}, (list) {
        if (mounted) setState(() => _companyDelegates = list);
      });
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('leave_requests')
        .where('companyUID', isEqualTo: widget.hrDelegate.companyUID);

    return Scaffold(
      backgroundColor: colorScheme.surfaceContainerLowest,
      appBar: widget.showAppBar
          ? AppBar(
        title: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            const Text(
              'الإجازات ومبررات الغياب',
              style: TextStyle(fontWeight: FontWeight.bold, fontSize: 18),
            ),
            Text(
              widget.hrDelegate.companyName,
              style: TextStyle(
                fontSize: 12,
                color: colorScheme.onSurfaceVariant,
              ),
            ),
          ],
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            tooltip: 'تحديث',
            onPressed: () => setState(() {}),
          ),
          const SizedBox(width: 8),
        ],
      )
          : null,
      floatingActionButton: FloatingActionButton.extended(
        onPressed: _showCreateLeaveDialog,
        icon: const Icon(Icons.add_task_rounded),
        label: const Text('تسجيل إجازة / عذر'),
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
                        color: pendingCount > 0 ? const Color(0xFFD97706) : colorScheme.outline,
                        colorScheme: colorScheme,
                      ),
                      _buildKpiCard(
                        title: 'الإجازات المعتمدة',
                        value: '$approvedCount',
                        subtitle: 'إجازات مقبولة',
                        icon: Icons.check_circle_rounded,
                        color: const Color(0xFF2E7D32),
                        colorScheme: colorScheme,
                      ),
                      _buildKpiCard(
                        title: 'الطلبات المرفوضة',
                        value: '$rejectedCount',
                        subtitle: 'تم رفض الإجازة',
                        icon: Icons.cancel_outlined,
                        color: rejectedCount > 0 ? const Color(0xFFC62828) : colorScheme.outline,
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

                    return SizedBox(
                      height: 100,
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

              // ── 2. Unified Single-Row Toolbar ──
              Padding(
                padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                child: LayoutBuilder(
                  builder: (context, constraints) {
                    final isDesktop = constraints.maxWidth >= 850;

                    final searchWidget = SizedBox(
                      height: 44,
                      child: TextField(
                        controller: _searchController,
                        onChanged: (val) =>
                            setState(() => _searchQuery = val.trim()),
                        textAlignVertical: TextAlignVertical.center,
                        style: TextStyle(fontSize: 13, color: colorScheme.onSurface),
                        decoration: InputDecoration(
                          hintText: 'بحث باسم المندوب أو رقم الهاتف أو العذر...',
                          hintStyle: TextStyle(
                            fontSize: 12,
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
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          enabledBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
                            borderSide: BorderSide(
                              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                            ),
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(22),
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
                              ? const Color(0xFFD97706)
                              : colorScheme.primary,
                          activeForegroundColor: Colors.white,
                        ),
                        TashilConnectedButtonItem<String>(
                          value: 'approved',
                          label: 'المعتمدة ($approvedCount)',
                          icon: Icons.check_circle_rounded,
                          activeColor: const Color(0xFF2E7D32),
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

                    if (isDesktop) {
                      return Row(
                        children: [
                          Expanded(child: searchWidget),
                          const SizedBox(width: 12),
                          statusButtonGroup,
                        ],
                      );
                    }

                    return Column(
                      crossAxisAlignment: CrossAxisAlignment.stretch,
                      children: [
                        searchWidget,
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
    ColorScheme colorScheme,
  ) {
    final status = (leave['status'] ?? 'pending').toString();
    final name = (leave['delegateName'] ?? 'مندوب').toString();
    final phone = (leave['delegatePhone'] ?? '').toString();
    final type = (leave['type'] ?? 'annual').toString();
    final reason = (leave['reason'] ?? '').toString();
    final rejectReason = (leave['rejectReason'] ?? '').toString();
    final daysCount = (leave['daysCount'] as num?)?.toInt() ?? 1;

    DateTime? startDate;
    if (leave['startDate'] is Timestamp) {
      startDate = (leave['startDate'] as Timestamp).toDate();
    }
    DateTime? endDate;
    if (leave['endDate'] is Timestamp) {
      endDate = (leave['endDate'] as Timestamp).toDate();
    }

    final dateRangeStr = (startDate != null && endDate != null)
        ? '${DateFormat('yyyy-MM-dd').format(startDate)}  إلى  ${DateFormat('yyyy-MM-dd').format(endDate)}'
        : (startDate != null
            ? DateFormat('yyyy-MM-dd').format(startDate)
            : '-');

    Color statusColor;
    String statusLabel;
    IconData statusIcon;

    if (status == 'approved') {
      statusColor = const Color(0xFF2E7D32);
      statusLabel = 'معتمد';
      statusIcon = Icons.check_circle_rounded;
    } else if (status == 'rejected') {
      statusColor = colorScheme.error;
      statusLabel = 'مرفوض';
      statusIcon = Icons.cancel_rounded;
    } else {
      statusColor = const Color(0xFFE65100);
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
      case 'absence':
        typeLabel = 'عذر غياب';
        typeIcon = Icons.person_off_outlined;
        break;
      default:
        typeLabel = 'إجازة اعتيادية';
        typeIcon = Icons.beach_access_rounded;
        break;
    }

    return Card(
      margin: const EdgeInsets.only(bottom: 12),
      elevation: 0,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(
          color: status == 'pending'
              ? statusColor.withValues(alpha: 0.4)
              : colorScheme.outlineVariant.withValues(alpha: 0.6),
          width: status == 'pending' ? 1.5 : 1.0,
        ),
      ),
      color: colorScheme.surface,
      child: Padding(
        padding: const EdgeInsets.all(14),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            Row(
              children: [
                AppAvatar(
                  fallbackText: name,
                  radius: 20,
                ),
                const SizedBox(width: 10),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        name,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                      if (phone.isNotEmpty) ...[
                        const SizedBox(height: 2),
                        Directionality(
                          textDirection: TextDirection.ltr,
                          child: Text(
                            phone,
                            style: theme.textTheme.bodySmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ],
                    ],
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 10,
                    vertical: 4,
                  ),
                  decoration: BoxDecoration(
                    color: statusColor.withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: statusColor.withValues(alpha: 0.3),
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(statusIcon, size: 13, color: statusColor),
                      const SizedBox(width: 4),
                      Text(
                        statusLabel,
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
            const SizedBox(height: 10),
            Container(
              padding: const EdgeInsets.all(10),
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHighest
                    .withValues(alpha: 0.35),
                borderRadius: BorderRadius.circular(12),
              ),
              child: Column(
                children: [
                  Row(
                    children: [
                      Icon(typeIcon, size: 16, color: colorScheme.primary),
                      const SizedBox(width: 6),
                      Text(
                        'نوع الطلب: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Text(
                        typeLabel,
                        style: TextStyle(
                          fontSize: 12,
                          fontWeight: FontWeight.bold,
                          color: colorScheme.primary,
                        ),
                      ),
                      const Spacer(),
                      Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 8,
                          vertical: 2,
                        ),
                        decoration: BoxDecoration(
                          color: colorScheme.surface,
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.outlineVariant
                                .withValues(alpha: 0.5),
                          ),
                        ),
                        child: Text(
                          '$daysCount يوم',
                          style: const TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.bold,
                          ),
                        ),
                      ),
                    ],
                  ),
                  const SizedBox(height: 6),
                  Row(
                    children: [
                      Icon(
                        Icons.calendar_today_rounded,
                        size: 15,
                        color: colorScheme.outline,
                      ),
                      const SizedBox(width: 6),
                      Text(
                        'الفترة: ',
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      Expanded(
                        child: Text(
                          dateRangeStr,
                          style: const TextStyle(
                            fontSize: 12,
                            fontWeight: FontWeight.w600,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ],
              ),
            ),
            if (reason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.surfaceContainerHighest
                      .withValues(alpha: 0.2),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  'السبب: $reason',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
            if (rejectReason.isNotEmpty) ...[
              const SizedBox(height: 8),
              Container(
                width: double.infinity,
                padding: const EdgeInsets.symmetric(
                  horizontal: 10,
                  vertical: 6,
                ),
                decoration: BoxDecoration(
                  color: colorScheme.errorContainer.withValues(alpha: 0.25),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: colorScheme.error.withValues(alpha: 0.3),
                  ),
                ),
                child: Text(
                  'سبب الرفض: $rejectReason',
                  style: TextStyle(
                    fontSize: 11.5,
                    color: colorScheme.error,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ],
            if (status == 'pending') ...[
              const SizedBox(height: 12),
              Row(
                children: [
                  Expanded(
                    child: OutlinedButton.icon(
                      style: OutlinedButton.styleFrom(
                        foregroundColor: colorScheme.error,
                        side: BorderSide(
                          color: colorScheme.error.withValues(alpha: 0.5),
                        ),
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _rejectLeave(leave),
                      icon: const Icon(Icons.close_rounded, size: 18),
                      label: const Text(
                        'رفض',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Expanded(
                    flex: 2,
                    child: FilledButton.icon(
                      style: FilledButton.styleFrom(
                        backgroundColor: const Color(0xFF2E7D32),
                        foregroundColor: Colors.white,
                        padding: const EdgeInsets.symmetric(vertical: 10),
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(10),
                        ),
                      ),
                      onPressed: () => _approveLeave(leave),
                      icon: const Icon(Icons.check_circle_rounded, size: 18),
                      label: const Text(
                        'اعتماد الإجازة',
                        style: TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ),
                ],
              ),
            ],
          ],
        ),
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
        builder: (context, setDlgState) => AlertDialog(
          shape:
              RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
          title: const Text(
            'تسجيل إجازة / عذر غياب جديد',
            style: TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
          ),
          content: SingleChildScrollView(
            child: Column(
              mainAxisSize: MainAxisSize.min,
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                const Text('المندوب:'),
                const SizedBox(height: 4),
                DropdownButtonFormField<Delegate>(
                  initialValue: selectedDelegate,
                  isExpanded: true,
                  items: _companyDelegates
                      .map((d) => DropdownMenuItem(
                            value: d,
                            child: Text(d.fullName),
                          ))
                      .toList(),
                  onChanged: (val) => setDlgState(() => selectedDelegate = val),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                const Text('نوع الطلب:'),
                const SizedBox(height: 4),
                DropdownButtonFormField<String>(
                  initialValue: selectedType,
                  items: const [
                    DropdownMenuItem(
                        value: 'annual', child: Text('إجازة اعتيادية')),
                    DropdownMenuItem(
                        value: 'sick', child: Text('إجازة مرضية')),
                    DropdownMenuItem(
                        value: 'emergency', child: Text('إجازة عارضة')),
                    DropdownMenuItem(
                        value: 'delay', child: Text('عذر تأخير')),
                    DropdownMenuItem(
                        value: 'absence', child: Text('عذر غياب')),
                  ],
                  onChanged: (val) =>
                      setDlgState(() => selectedType = val ?? 'annual'),
                  decoration: const InputDecoration(border: OutlineInputBorder()),
                ),
                const SizedBox(height: 12),
                Row(
                  children: [
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.date_range_rounded, size: 16),
                        label: Text(
                          'من: ${DateFormat('yyyy-MM-dd').format(startDate)}',
                        ),
                        onPressed: () async {
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
                      ),
                    ),
                    Expanded(
                      child: TextButton.icon(
                        icon: const Icon(Icons.date_range_rounded, size: 16),
                        label: Text(
                          'إلى: ${DateFormat('yyyy-MM-dd').format(endDate)}',
                        ),
                        onPressed: () async {
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
                      ),
                    ),
                  ],
                ),
                const SizedBox(height: 12),
                TextField(
                  controller: reasonCtrl,
                  decoration: const InputDecoration(
                    labelText: 'سبب الإجازة / العذر',
                    border: OutlineInputBorder(),
                  ),
                  maxLines: 2,
                ),
              ],
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.pop(ctx),
              child: const Text('إلغاء'),
            ),
            FilledButton(
              onPressed: () async {
                if (selectedDelegate == null) return;
                final messenger = ScaffoldMessenger.of(context);
                final days = endDate.difference(startDate).inDays + 1;
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
                    const SnackBar(
                      content: Text('تم تسجيل واعتماد الإجازة بنجاح'),
                      backgroundColor: Color(0xFF2E7D32),
                    ),
                  );
                }
              },
              child: const Text('حفظ واعتماد'),
            ),
          ],
        ),
      ),
    );
  }

  Future<void> _approveLeave(Map<String, dynamic> leave) async {
    final docId = leave['docId']?.toString() ?? '';
    final delegateUid = leave['delegateUid']?.toString() ?? '';
    final delegateName = leave['delegateName']?.toString() ?? '';

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
        'title': 'تمت الموافقة على طلب الإجازة',
        'body': 'تم اعتماد طلب إجازتك من قِبل إدارة الموارد البشرية.',
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
            backgroundColor: const Color(0xFF2E7D32),
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
        title: const Text('رفض طلب الإجازة'),
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
        'title': 'تم رفض طلب الإجازة',
        'body': 'تم رفض طلب الإجازة: ${reasonCtrl.text.trim()}',
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
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: colorScheme.outlineVariant.withValues(alpha: 0.35),
        ),
      ),
      padding: const EdgeInsets.all(12),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisAlignment: MainAxisAlignment.spaceBetween,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                title,
                style: TextStyle(
                  fontSize: 12,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Container(
                padding: const EdgeInsets.all(6),
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Icon(icon, size: 16, color: color),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            value,
            style: TextStyle(
              fontSize: 18,
              fontWeight: FontWeight.bold,
              color: colorScheme.onSurface,
            ),
          ),
          const SizedBox(height: 2),
          Text(
            subtitle,
            style: TextStyle(
              fontSize: 11,
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
