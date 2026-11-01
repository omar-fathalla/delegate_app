import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'dart:async';
import 'package:flutter/material.dart';
import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:image_picker/image_picker.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class DelegateLeavesAndRequestsScreen extends StatefulWidget {
  final Delegate delegate;
  final bool showAppBar;

  const DelegateLeavesAndRequestsScreen({
    super.key,
    required this.delegate,
    this.showAppBar = true,
  });

  @override
  State<DelegateLeavesAndRequestsScreen> createState() =>
      _DelegateLeavesAndRequestsScreenState();
}

class _DelegateLeavesAndRequestsScreenState
    extends State<DelegateLeavesAndRequestsScreen> {
  String _selectedStatusFilter = 'all'; // all, pending, approved, rejected
  bool _isAnnualLeaveEnabled = false;
  int _annualLeaveQuota = 21; // الرصيد السنوي (21 يوم)
  int _currentRemainingBalance = 21;
  final Set<String> _expandedDocIds = {};
  StreamSubscription<DocumentSnapshot<Map<String, dynamic>>>? _userSub;

  @override
  void initState() {
    super.initState();
    _isAnnualLeaveEnabled = widget.delegate.isAnnualLeaveEnabled;
    _annualLeaveQuota = widget.delegate.annualLeaveQuota > 0
        ? widget.delegate.annualLeaveQuota
        : 21;
    _listenToDelegateStatus();
  }

  void _listenToDelegateStatus() {
    _userSub = FirebaseFirestore.instance
        .collection('users')
        .doc(widget.delegate.uid)
        .snapshots()
        .listen((doc) {
      if (doc.exists && mounted) {
        final data = doc.data();
        if (data != null) {
          setState(() {
            if (data.containsKey('isAnnualLeaveEnabled')) {
              _isAnnualLeaveEnabled = data['isAnnualLeaveEnabled'] == true;
            }
            if (data['annualLeaveQuota'] is num) {
              _annualLeaveQuota = (data['annualLeaveQuota'] as num).toInt();
            }
          });
        }
      }
    });
  }

  @override
  void dispose() {
    _userSub?.cancel();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    // الاستعلام المزدوج الصارم: يفلتر بـ companyUID و delegateUid
    final Query<Map<String, dynamic>> query = FirebaseFirestore.instance
        .collection('leave_requests')
        .where('companyUID', isEqualTo: widget.delegate.companyUID)
        .where('delegateUid', isEqualTo: widget.delegate.uid);

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
                    'طلباتي (الإجازات والأعذار)',
                    style: TextStyle(
                      fontWeight: FontWeight.bold,
                      fontSize: 14.5,
                      letterSpacing: -0.2,
                    ),
                    maxLines: 1,
                    overflow: TextOverflow.ellipsis,
                  ),
                  Text(
                    widget.delegate.companyName.isNotEmpty
                        ? widget.delegate.companyName
                        : widget.delegate.organizationName,
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
                  icon: const Icon(Symbols.refresh_rounded),
                  tooltip: 'تحديث',
                  onPressed: () => setState(() {}),
                ),
                const SizedBox(width: 8),
              ],
            )
          : null,
      floatingActionButton: M3ExtendedFab(
        onPressed: () => _showCreateRequestDialog(context),
        icon: Symbols.add_rounded,
        label: 'تسجيل إجازة / عذر',
      ),
      body: StreamBuilder<QuerySnapshot<Map<String, dynamic>>>(
        stream: query.snapshots(),
        builder: (context, snapshot) {
          if (snapshot.connectionState == ConnectionState.waiting &&
              !snapshot.hasData) {
            return const Center(child: M3DelayedLoading());
          }

          final docs = snapshot.data?.docs ?? [];
          final allLeaves = docs.map((d) {
            final data = d.data();
            return {
              'docId': d.id,
              ...data,
            };
          }).toList();

          // Dual-layer client-side security filtering (Zero leakage)
          allLeaves.removeWhere(
            (item) =>
                (item['companyUID'] ?? '') != widget.delegate.companyUID ||
                (item['delegateUid'] ?? '') != widget.delegate.uid,
          );

          // ترتيب زمني تنازلي من الأحدث للأقدم
          allLeaves.sort((a, b) {
            final aTime = a['createdAt'];
            final bTime = b['createdAt'];
            if (aTime is Timestamp && bTime is Timestamp) {
              return bTime.compareTo(aTime);
            }
            return 0;
          });

          // حساب الإحصائيات
          final pendingCount =
              allLeaves.where((r) => r['status'] == 'pending').length;
          final approvedCount =
              allLeaves.where((r) => r['status'] == 'approved').length;
          final rejectedCount =
              allLeaves.where((r) => r['status'] == 'rejected').length;

          // المقترح 5: احتساب رصيد الإجازات السنوي المستهلك والمتبقي للعام الحالي
          final currentYear = DateTime.now().year;
          int usedLeaveDaysThisYear = 0;
          for (final req in allLeaves) {
            if (req['status'] == 'approved' && req['isHourly'] != true) {
              final start = req['startDate'];
              if (start is Timestamp && start.toDate().year == currentYear) {
                final days = (req['daysCount'] as num?)?.toInt() ?? 1;
                usedLeaveDaysThisYear += days;
              }
            }
          }
          final remainingBalance = (_annualLeaveQuota - usedLeaveDaysThisYear)
              .clamp(0, _annualLeaveQuota);
          _currentRemainingBalance = remainingBalance;

          // فلترة القائمة حسب التبويب
          final filteredLeaves = allLeaves.where((req) {
            final status = (req['status'] ?? 'pending').toString();
            if (_selectedStatusFilter != 'all' &&
                status != _selectedStatusFilter) {
              return false;
            }
            return true;
          }).toList();

          return CustomScrollView(
            slivers: [
              // ── 1. Leave Balance & KPI Summary Cards ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      // كارت رصيد الإجازات السنوي أو كارت فترة التجربة (الإجازات الأسبوعية فقط)
                      if (_isAnnualLeaveEnabled)
                        _buildAnnualBalanceCard(
                          usedDays: usedLeaveDaysThisYear,
                          remainingDays: remainingBalance,
                          totalQuota: _annualLeaveQuota,
                          colorScheme: colorScheme,
                        )
                      else
                        _buildProbationWeeklyLeavesCard(
                          colorScheme: colorScheme,
                          theme: theme,
                          isArabic: isArabic,
                        ),
                      const SizedBox(height: 12),
                      // كروت الإحصائيات الأفقية
                      _buildKpiRow(
                        totalCount: allLeaves.length,
                        pendingCount: pendingCount,
                        approvedCount: approvedCount,
                        rejectedCount: rejectedCount,
                        colorScheme: colorScheme,
                      ),
                    ],
                  ),
                ),
              ),

              // ── 2. Filter Button Group (مجموعة أزرار متصلة بدون سكرول) ──
              SliverToBoxAdapter(
                child: Padding(
                  padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 6),
                  child: _buildFilterButtonGroup(
                    totalCount: allLeaves.length,
                    pendingCount: pendingCount,
                    approvedCount: approvedCount,
                    rejectedCount: rejectedCount,
                    colorScheme: colorScheme,
                  ),
                ),
              ),

              // ── 3. List of Requests ──
              if (filteredLeaves.isEmpty)
                SliverFillRemaining(
                  hasScrollBody: false,
                  child: Center(
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Container(
                          padding: const EdgeInsets.all(20),
                          decoration: BoxDecoration(
                            color: colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.4),
                            shape: BoxShape.circle,
                          ),
                          child: Icon(
                            Symbols.event_busy_rounded,
                            size: 54,
                            color: colorScheme.outline,
                          ),
                        ),
                        const SizedBox(height: 16),
                        Text(
                          _selectedStatusFilter == 'all'
                              ? 'لم تقم بتقديم أي طلبات إجازة أو عذر حتى الآن'
                              : 'لا توجد طلبات في هذا التبويب',
                          style: theme.textTheme.titleSmall?.copyWith(
                            color: colorScheme.onSurfaceVariant,
                            fontWeight: FontWeight.w600,
                          ),
                        ),
                        const SizedBox(height: 8),
                        Text(
                          'اضغط على زر "تسجيل إجازة / عذر" لتقديم طلبك لمشرف الشركة',
                          style: TextStyle(
                            fontSize: 12,
                            color: colorScheme.outline,
                          ),
                        ),
                      ],
                    ),
                  ),
                )
              else
                SliverPadding(
                  padding: const EdgeInsets.fromLTRB(16, 4, 16, 96),
                  sliver: SliverList(
                    delegate: SliverChildBuilderDelegate(
                      (context, index) {
                        final req = filteredLeaves[index];
                        return _buildRequestCard(
                          req: req,
                          colorScheme: colorScheme,
                          theme: theme,
                          isArabic: isArabic,
                        );
                      },
                      childCount: filteredLeaves.length,
                    ),
                  ),
                ),
            ],
          );
        },
      ),
    );
  }

  // ── Annual Balance Card ──
  Widget _buildAnnualBalanceCard({
    required int usedDays,
    required int remainingDays,
    required int totalQuota,
    required ColorScheme colorScheme,
  }) {
    final progress = (usedDays / totalQuota).clamp(0.0, 1.0);

    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: colorScheme.primary.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Symbols.account_balance_wallet_rounded,
                  size: 20,
                  color: colorScheme.primary,
                ),
              ),
              const SizedBox(width: 10),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    const Text(
                      'رصيد الإجازات السنوي',
                      style: TextStyle(
                        fontWeight: FontWeight.bold,
                        fontSize: 14,
                      ),
                    ),
                    Text(
                      'للعام الحالي ${DateTime.now().year}',
                      style: TextStyle(
                        fontSize: 11,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: remainingDays > 3
                      ? Theme.of(context).colorScheme.primary.withValues(alpha: 0.12)
                      : colorScheme.error.withValues(alpha: 0.12),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Text(
                  'المتبقي: $remainingDays يوم',
                  style: TextStyle(
                    fontSize: 12,
                    fontWeight: FontWeight.bold,
                    color: remainingDays > 3
                        ? Theme.of(context).colorScheme.primary
                        : colorScheme.error,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          ClipRRect(
            borderRadius: BorderRadius.circular(6),
            child: LinearProgressIndicator(
              value: progress,
              minHeight: 7,
              backgroundColor: colorScheme.surfaceContainerHighest,
              valueColor: AlwaysStoppedAnimation<Color>(
                progress > 0.85 ? colorScheme.error : colorScheme.primary,
              ),
            ),
          ),
          const SizedBox(height: 8),
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Text(
                'المستهلك: $usedDays يوم',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
              Text(
                'إجمالي الرصيد: $totalQuota يوم',
                style: TextStyle(
                  fontSize: 11,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  // ── Probation Weekly Leaves Card (نظام الإجازات الأسبوعية فقط) ──
  Widget _buildProbationWeeklyLeavesCard({
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isArabic,
  }) {
    return Container(
      padding: const EdgeInsets.all(16),
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(
          color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
        ),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.04),
            blurRadius: 8,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            children: [
              Container(
                padding: const EdgeInsets.all(8),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(10),
                ),
                child: Icon(
                  Symbols.event_repeat_rounded,
                  size: 20,
                  color: Theme.of(context).colorScheme.onTertiaryContainer,
                ),
              ),
              const SizedBox(width: 10),
              const Expanded(
                child: Text(
                  'نظام الإجازات الأسبوعية فقط',
                  style: TextStyle(
                    fontWeight: FontWeight.bold,
                    fontSize: 14,
                  ),
                ),
              ),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                decoration: BoxDecoration(
                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                  border: Border.all(
                    color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.4),
                  ),
                ),
                child: Text(
                  '4 أيام راحة شهرياً',
                  style: TextStyle(
                    fontSize: 11.5,
                    fontWeight: FontWeight.bold,
                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                  ),
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          Container(
            padding: const EdgeInsets.all(10),
            decoration: BoxDecoration(
              color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.35),
              borderRadius: BorderRadius.circular(10),
            ),
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Icon(
                  Symbols.info_rounded,
                  size: 16,
                  color: colorScheme.primary,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    'أنت حالياً على نظام الإجازات الأسبوعية (يوم راحة أسبوعياً بمعدل 4 أيام شهرياً). يتم تفعيل رصيد الإجازات السنوية الإضافي عند اعتماده من قِبل المشرف.',
                    style: TextStyle(
                      fontSize: 11,
                      color: colorScheme.onSurfaceVariant,
                      height: 1.4,
                    ),
                  ),
                ),
              ],
            ),
          ),
          const SizedBox(height: 10),
          Row(
            children: [
              Expanded(
                child: _buildLeaveFeaturePill(
                  icon: Symbols.calendar_today_rounded,
                  label: 'راحة أسبوعية',
                  sublabel: 'يوم لكل 7 أيام',
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLeaveFeaturePill(
                  icon: Symbols.schedule_rounded,
                  label: 'الأعذار الساعية',
                  sublabel: 'متاحة للتقديم',
                  colorScheme: colorScheme,
                ),
              ),
              const SizedBox(width: 8),
              Expanded(
                child: _buildLeaveFeaturePill(
                  icon: Symbols.lock_clock_rounded,
                  label: 'الرصيد السنوي (21)',
                  sublabel: 'عند التفعيل',
                  colorScheme: colorScheme,
                  isMuted: true,
                ),
              ),
            ],
          ),
        ],
      ),
    );
  }

  Widget _buildLeaveFeaturePill({
    required IconData icon,
    required String label,
    required String sublabel,
    required ColorScheme colorScheme,
    bool isMuted = false,
  }) {
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 6),
      decoration: BoxDecoration(
        color: isMuted
            ? colorScheme.surfaceContainerLow
            : colorScheme.primaryContainer.withValues(alpha: 0.25),
        borderRadius: BorderRadius.circular(8),
        border: Border.all(
          color: isMuted
              ? colorScheme.outlineVariant.withValues(alpha: 0.3)
              : colorScheme.primary.withValues(alpha: 0.2),
        ),
      ),
      child: Column(
        children: [
          Icon(
            icon,
            size: 15,
            color: isMuted ? colorScheme.outline : colorScheme.primary,
          ),
          const SizedBox(height: 2),
          Text(
            label,
            style: TextStyle(
              fontSize: 10,
              fontWeight: FontWeight.bold,
              color: isMuted ? colorScheme.outline : colorScheme.onSurface,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
          Text(
            sublabel,
            style: TextStyle(
              fontSize: 9,
              color: isMuted ? colorScheme.outline : colorScheme.onSurfaceVariant,
            ),
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
          ),
        ],
      ),
    );
  }

  // ── KPI Row (مدمجة في صف واحد متجاوب بدون سكرول أفقي) ──
  Widget _buildKpiRow({
    required int totalCount,
    required int pendingCount,
    required int approvedCount,
    required int rejectedCount,
    required ColorScheme colorScheme,
  }) {
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(14),
        boxShadow: [
          BoxShadow(
            color: colorScheme.shadow.withValues(alpha: 0.03),
            blurRadius: 6,
            offset: const Offset(0, 2),
          ),
        ],
      ),
      padding: const EdgeInsets.symmetric(vertical: 8, horizontal: 4),
      child: Row(
        children: [
          Expanded(
            child: _buildMiniKpi(
              title: 'الإجمالي',
              value: '$totalCount',
              icon: Symbols.event_note_rounded,
              color: colorScheme.primary,
              colorScheme: colorScheme,
            ),
          ),
          _buildKpiDivider(colorScheme),
          Expanded(
            child: _buildMiniKpi(
              title: 'المراجعة',
              value: '$pendingCount',
              icon: Symbols.hourglass_top_rounded,
              color: Theme.of(context).colorScheme.onTertiaryContainer,
              colorScheme: colorScheme,
            ),
          ),
          _buildKpiDivider(colorScheme),
          Expanded(
            child: _buildMiniKpi(
              title: 'المعتمدة',
              value: '$approvedCount',
              icon: Symbols.check_circle_rounded,
              color: Theme.of(context).colorScheme.primary,
              colorScheme: colorScheme,
            ),
          ),
          _buildKpiDivider(colorScheme),
          Expanded(
            child: _buildMiniKpi(
              title: 'المرفوضة',
              value: '$rejectedCount',
              icon: Symbols.cancel_rounded,
              color: colorScheme.error,
              colorScheme: colorScheme,
            ),
          ),
        ],
      ),
    );
  }

  Widget _buildKpiDivider(ColorScheme colorScheme) {
    return Container(
      width: 1,
      height: 30,
      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
    );
  }

  Widget _buildMiniKpi({
    required String title,
    required String value,
    required IconData icon,
    required Color color,
    required ColorScheme colorScheme,
  }) {
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 2),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Icon(icon, size: 12.5, color: color),
              const SizedBox(width: 3),
              Flexible(
                child: Text(
                  title,
                  style: TextStyle(
                    fontSize: 10,
                    fontWeight: FontWeight.w600,
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
            ],
          ),
          const SizedBox(height: 2),
          Text(
            value,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }

  // ── Filter Button Group (مجموعة أزرار متصلة للفلترة) ──
  Widget _buildFilterButtonGroup({
    required int totalCount,
    required int pendingCount,
    required int approvedCount,
    required int rejectedCount,
    required ColorScheme colorScheme,
  }) {
    return Container(
      height: 38,
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        borderRadius: BorderRadius.circular(10),
      ),
      padding: const EdgeInsets.all(2.5),
      child: Row(
        children: [
          _buildFilterSegment(
            label: 'الكل',
            count: totalCount,
            value: 'all',
            colorScheme: colorScheme,
          ),
          _buildFilterSegment(
            label: 'المراجعة',
            count: pendingCount,
            value: 'pending',
            activeColor: Theme.of(context).colorScheme.onTertiaryContainer,
            colorScheme: colorScheme,
          ),
          _buildFilterSegment(
            label: 'المعتمدة',
            count: approvedCount,
            value: 'approved',
            activeColor: Theme.of(context).colorScheme.primary,
            colorScheme: colorScheme,
          ),
          _buildFilterSegment(
            label: 'المرفوضة',
            count: rejectedCount,
            value: 'rejected',
            activeColor: colorScheme.error,
            colorScheme: colorScheme,
          ),
        ],
      ),
    );
  }

  Widget _buildFilterSegment({
    required String label,
    required int count,
    required String value,
    Color? activeColor,
    required ColorScheme colorScheme,
  }) {
    final isSelected = _selectedStatusFilter == value;
    final themeColor = activeColor ?? colorScheme.primary;

    return Expanded(
      child: InkWell(
        onTap: () => setState(() => _selectedStatusFilter = value),
        borderRadius: BorderRadius.circular(8),
        child: AnimatedContainer(
          duration: const Duration(milliseconds: 180),
          decoration: BoxDecoration(
            color: isSelected ? themeColor : Colors.transparent,
            borderRadius: BorderRadius.circular(8),
            boxShadow: isSelected
                ? [
                    BoxShadow(
                      color: themeColor.withValues(alpha: 0.25),
                      blurRadius: 4,
                      offset: const Offset(0, 1),
                    ),
                  ]
                : null,
          ),
          alignment: Alignment.center,
          child: Row(
            mainAxisAlignment: MainAxisAlignment.center,
            mainAxisSize: MainAxisSize.min,
            children: [
              Flexible(
                child: Text(
                  label,
                  style: TextStyle(
                    fontSize: 10.5,
                    fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                    color: isSelected
                        ? (themeColor == Theme.of(context).colorScheme.onTertiaryContainer ? Colors.black87 : Colors.white)
                        : colorScheme.onSurfaceVariant,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 3),
              Container(
                padding: const EdgeInsets.symmetric(horizontal: 4.5, vertical: 1),
                decoration: BoxDecoration(
                  color: isSelected
                      ? Colors.white.withValues(alpha: 0.25)
                      : colorScheme.surfaceContainerHighest.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(8),
                ),
                child: Text(
                  '$count',
                  style: TextStyle(
                    fontSize: 9.5,
                    fontWeight: FontWeight.bold,
                    color: isSelected
                        ? (themeColor == Theme.of(context).colorScheme.onTertiaryContainer ? Colors.black87 : Colors.white)
                        : colorScheme.onSurfaceVariant,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }

  // ── Request Card (كارت مدمج قابل للتوسيع عند الضغط) ──
  Widget _buildRequestCard({
    required Map<String, dynamic> req,
    required ColorScheme colorScheme,
    required ThemeData theme,
    required bool isArabic,
  }) {
    final docId = (req['docId'] ?? '').toString();
    final isExpanded = _expandedDocIds.contains(docId);

    final status = (req['status'] ?? 'pending').toString();
    final type = (req['type'] ?? 'annual').toString();
    final isHourly = req['isHourly'] == true;
    final hoursCount = (req['hoursCount'] as num?)?.toDouble() ?? 0;
    final daysCount = (req['daysCount'] as num?)?.toInt() ?? 1;
    final reason = (req['reason'] ?? '').toString();
    final rejectReason = (req['rejectReason'] ?? '').toString();
    final attachmentUrl = (req['attachmentUrl'] ?? '').toString();
    final resolvedByName = (req['resolvedByName'] ?? '').toString();
    final resolvedAt = req['resolvedAt'] is Timestamp
        ? (req['resolvedAt'] as Timestamp).toDate()
        : null;

    // Formatting dates
    String periodStr = '';
    if (isHourly) {
      final start = req['startDate'] is Timestamp
          ? (req['startDate'] as Timestamp).toDate()
          : DateTime.now();
      final dateStr = DateFormat('yyyy/MM/dd').format(start);
      final fromTime = (req['fromTime'] ?? '').toString();
      final toTime = (req['toTime'] ?? '').toString();
      if (fromTime.isNotEmpty && toTime.isNotEmpty) {
        periodStr = '$dateStr • ($fromTime - $toTime)';
      } else {
        periodStr = '$dateStr • ($hoursCount س)';
      }
    } else {
      final start = req['startDate'] is Timestamp
          ? (req['startDate'] as Timestamp).toDate()
          : null;
      final end = req['endDate'] is Timestamp
          ? (req['endDate'] as Timestamp).toDate()
          : null;
      if (start != null && end != null) {
        final fStart = DateFormat('yyyy/MM/dd').format(start);
        final fEnd = DateFormat('yyyy/MM/dd').format(end);
        periodStr = fStart == fEnd ? fStart : '$fStart ⬅️ $fEnd';
      }
    }

    // Type definition
    String typeLabel;
    IconData typeIcon;
    switch (type) {
      case 'sick':
        typeLabel = 'إجازة مرضية';
        typeIcon = Symbols.medical_services_rounded;
        break;
      case 'emergency':
        typeLabel = 'إجازة عارضة';
        typeIcon = Symbols.warning_amber_rounded;
        break;
      case 'delay':
        typeLabel = 'عذر تأخير';
        typeIcon = Symbols.timer_rounded;
        break;
      case 'early_leave':
        typeLabel = 'إذن انصراف مبكر';
        typeIcon = Symbols.logout_rounded;
        break;
      case 'absence':
        typeLabel = 'عذر غياب';
        typeIcon = Symbols.person_off_rounded;
        break;
      case 'unpaid':
        typeLabel = 'إجازة بدون أجر';
        typeIcon = Symbols.money_off_rounded;
        break;
      default:
        typeLabel = 'إجازة اعتيادية';
        typeIcon = Symbols.beach_access_rounded;
        break;
    }

    // Status styling
    Color statusColor;
    String statusLabel;
    IconData statusIcon;
    switch (status) {
      case 'approved':
        statusColor = Theme.of(context).colorScheme.primary;
        statusLabel = 'معتمد';
        statusIcon = Symbols.check_circle_rounded;
        break;
      case 'rejected':
        statusColor = colorScheme.error;
        statusLabel = 'مرفوض';
        statusIcon = Symbols.cancel_rounded;
        break;
      default:
        statusColor = Theme.of(context).colorScheme.onTertiaryContainer;
        statusLabel = 'قيد المراجعة';
        statusIcon = Symbols.hourglass_top_rounded;
        break;
    }

    final durationText = isHourly ? '$hoursCount ساعة' : '$daysCount يوم';

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      color: colorScheme.surface,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(
          color: isExpanded
              ? colorScheme.primary.withValues(alpha: 0.5)
              : colorScheme.outlineVariant.withValues(alpha: 0.45),
        ),
      ),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () {
          setState(() {
            if (isExpanded) {
              _expandedDocIds.remove(docId);
            } else {
              _expandedDocIds.add(docId);
            }
          });
        },
        child: Stack(
          children: [
            // Subtle 3.5px start border line (Right in RTL)
            Positioned(
              top: 0,
              bottom: 0,
              right: 0,
              width: 3.5,
              child: Container(
                color: statusColor,
              ),
            ),
            Padding(
              padding: const EdgeInsets.fromLTRB(10, 10, 14, 10),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                mainAxisSize: MainAxisSize.min,
                children: [
                  // Row الرئيسي المدمج دائماً (Collapsed View)
                  Row(
                    children: [
                      Container(
                        padding: const EdgeInsets.all(6),
                        decoration: BoxDecoration(
                          color: colorScheme.primary.withValues(alpha: 0.1),
                          borderRadius: BorderRadius.circular(8),
                        ),
                        child: Icon(typeIcon, size: 16, color: colorScheme.primary),
                      ),
                      const SizedBox(width: 8),
                      Expanded(
                        child: Column(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Row(
                              children: [
                                Text(
                                  typeLabel,
                                  style: const TextStyle(
                                    fontSize: 13,
                                    fontWeight: FontWeight.bold,
                                  ),
                                ),
                                const SizedBox(width: 6),
                                Container(
                                  padding: const EdgeInsets.symmetric(
                                    horizontal: 6,
                                    vertical: 1.5,
                                  ),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primaryContainer.withValues(alpha: 0.35),
                                    borderRadius: BorderRadius.circular(6),
                                  ),
                                  child: Text(
                                    durationText,
                                    style: TextStyle(
                                      fontSize: 10.5,
                                      fontWeight: FontWeight.bold,
                                      color: colorScheme.primary,
                                    ),
                                  ),
                                ),
                              ],
                            ),
                            const SizedBox(height: 2),
                            Row(
                              children: [
                                Icon(
                                  Symbols.calendar_today_rounded,
                                  size: 11,
                                  color: colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: 4),
                                Expanded(
                                  child: Text(
                                    periodStr,
                                    style: TextStyle(
                                      fontSize: 11,
                                      color: colorScheme.onSurfaceVariant,
                                      fontWeight: FontWeight.w500,
                                    ),
                                    overflow: TextOverflow.ellipsis,
                                  ),
                                ),
                              ],
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 6),
                      // Status Pill
                      Container(
                        padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 3),
                        decoration: BoxDecoration(
                          color: statusColor.withValues(alpha: 0.12),
                          borderRadius: BorderRadius.circular(10),
                          border: Border.all(
                            color: statusColor.withValues(alpha: 0.3),
                          ),
                        ),
                        child: Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(statusIcon, size: 11, color: statusColor),
                            const SizedBox(width: 3),
                            Text(
                              statusLabel,
                              style: TextStyle(
                                fontSize: 10,
                                fontWeight: FontWeight.bold,
                                color: statusColor,
                              ),
                            ),
                          ],
                        ),
                      ),
                      const SizedBox(width: 4),
                      // Animated Expand Chevron
                      AnimatedRotation(
                        turns: isExpanded ? 0.5 : 0.0,
                        duration: const Duration(milliseconds: 200),
                        child: Icon(
                          Symbols.expand_more_rounded,
                          size: 18,
                          color: colorScheme.outline,
                        ),
                      ),
                    ],
                  ),

                  // التفاصيل الموسعة فقط عند الضغط (Expanded View)
                  if (isExpanded) ...[
                    const SizedBox(height: 8),
                    Divider(
                      height: 1,
                      thickness: 1,
                      color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                    ),
                    const SizedBox(height: 8),

                    // السبب
                    if (reason.isNotEmpty)
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.25),
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

                    // سبب الرفض (إن وجد)
                    if (status == 'rejected' && rejectReason.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Container(
                        width: double.infinity,
                        padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                        decoration: BoxDecoration(
                          color: colorScheme.errorContainer.withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(8),
                          border: Border.all(
                            color: colorScheme.error.withValues(alpha: 0.35),
                          ),
                        ),
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.start,
                          children: [
                            Icon(
                              Symbols.info_rounded,
                              size: 14,
                              color: colorScheme.error,
                            ),
                            const SizedBox(width: 6),
                            Expanded(
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
                        ),
                      ),
                    ],

                    // الاعتماد (إن وجد)
                    if (status == 'approved' && resolvedByName.isNotEmpty) ...[
                      const SizedBox(height: 6),
                      Row(
                        children: [
                          Icon(
                            Symbols.verified_user_rounded,
                            size: 13,
                            color: Theme.of(context).colorScheme.primary,
                          ),
                          const SizedBox(width: 5),
                          Text(
                            'تم الاعتماد بواسطة: $resolvedByName',
                            style: TextStyle(
                              fontSize: 10.5,
                              fontWeight: FontWeight.w600,
                              color: Theme.of(context).colorScheme.primary,
                            ),
                          ),
                          if (resolvedAt != null) ...[
                            const SizedBox(width: 4),
                            Text(
                              '(${DateFormat('yyyy/MM/dd').format(resolvedAt)})',
                              style: TextStyle(
                                fontSize: 10,
                                color: colorScheme.onSurfaceVariant,
                              ),
                            ),
                          ],
                        ],
                      ),
                    ],

                    // أزرار العمليات (معاينة المرفق / إلغاء الطلب)
                    const SizedBox(height: 8),
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        if (attachmentUrl.isNotEmpty)
                          SizedBox(
                            height: 32,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(8),
                                ),
                              ),
                              icon: const Icon(Symbols.attachment_rounded, size: 14),
                              label: const Text(
                                'معاينة المرفق',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: () => _viewAttachment(context, attachmentUrl),
                            ),
                          )
                        else
                          const SizedBox.shrink(),

                        if (status == 'pending')
                          SizedBox(
                            height: 32,
                            child: TextButton.icon(
                              style: TextButton.styleFrom(
                                foregroundColor: colorScheme.error,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                              icon: const Icon(Symbols.delete_outline_rounded, size: 15),
                              label: const Text(
                                'إلغاء الطلب',
                                style: TextStyle(fontSize: 11),
                              ),
                              onPressed: () =>
                                  _cancelPendingRequest(context, req['docId']),
                            ),
                          ),
                      ],
                    ),
                  ],
                ],
              ),
            ),
          ],
        ),
      ),
    );
  }

  // ── إلغاء الطلب المعلق ──
  Future<void> _cancelPendingRequest(BuildContext context, String docId) async {
    final messenger = ScaffoldMessenger.of(context);
    final confirm = await showDialog<bool>(
      context: context,
      builder: (ctx) => AlertDialog(
        title: const Text('إلغاء الطلب'),
        content: const Text('هل أنت متأكد من رغبتك في إلغاء هذا الطلب المعلق؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(ctx, false),
            child: const Text('تراجع'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(ctx).colorScheme.error,
            ),
            onPressed: () => Navigator.pop(ctx, true),
            child: const Text('نعم، إلغاء'),
          ),
        ],
      ),
    );

    if (confirm != true) return;

    try {
      await FirebaseFirestore.instance
          .collection('leave_requests')
          .doc(docId)
          .delete();

      messenger.showSnackBar(
        const SnackBar(content: Text('تم إلغاء طلب الإجازة بنجاح')),
      );
    } catch (e) {
      messenger.showSnackBar(
        SnackBar(content: Text('حدث خطأ أثناء إلغاء الطلب: $e')),
      );
    }
  }

  // ── معاينة المرفق بدقة عالية ──
  void _viewAttachment(BuildContext context, String url) {
    showDialog(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
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
                    style: TextStyle(fontWeight: FontWeight.bold, fontSize: 16),
                  ),
                  IconButton(
                    icon: const Icon(Symbols.close_rounded),
                    onPressed: () => Navigator.pop(ctx),
                  ),
                ],
              ),
            ),
            ClipRRect(
              borderRadius: const BorderRadius.only(
                bottomLeft: Radius.circular(16),
                bottomRight: Radius.circular(16),
              ),
              child: InteractiveViewer(
                maxScale: 4.0,
                child: Image.network(
                  url,
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
          ],
        ),
      ),
    );
  }

  // ── تسجيل إجازة / عذر جديد (المقترحات 1 إلى 5) ──
  Future<void> _showCreateRequestDialog(BuildContext context) async {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;

    String selectedType = _isAnnualLeaveEnabled ? 'annual' : 'delay';
    DateTime startDate = DateTime.now();
    DateTime endDate = DateTime.now();

    // المقترح 4: حقول العذر الساعي
    bool isHourly = !_isAnnualLeaveEnabled; // افتراضياً ساعي إذا لم تكن الإجازة السنوية مفعلة
    double hoursCount = 2.0;
    TimeOfDay fromTime = const TimeOfDay(hour: 9, minute: 0);
    TimeOfDay toTime = const TimeOfDay(hour: 11, minute: 0);

    final reasonCtrl = TextEditingController();
    XFile? pickedAttachment;
    bool isSubmitting = false;

    await showDialog(
      context: context,
      barrierDismissible: false,
      builder: (ctx) => StatefulBuilder(
        builder: (context, setDlgState) {
          final isLeaveType = selectedType == 'annual' ||
              selectedType == 'sick' ||
              selectedType == 'emergency' ||
              selectedType == 'unpaid';

          // التحديث التلقائي لنمط الساعات عند اختيار عذر تأخير أو إذن مبكر
          if (selectedType == 'delay' || selectedType == 'early_leave') {
            isHourly = true;
          }

          final calculatedDays = endDate.difference(startDate).inDays + 1;

          return Dialog(
            backgroundColor: colorScheme.surface,
            surfaceTintColor: Colors.transparent,
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(20),
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
                            borderRadius: BorderRadius.circular(10),
                          ),
                          child: Icon(
                            Symbols.edit_calendar_rounded,
                            size: 18,
                            color: colorScheme.primary,
                          ),
                        ),
                        const SizedBox(width: 10),
                        const Expanded(
                          child: Text(
                            'تسجيل إجازة / عذر جديد',
                            style: TextStyle(
                              fontWeight: FontWeight.bold,
                              fontSize: 15.5,
                            ),
                          ),
                        ),
                        InkWell(
                          onTap: isSubmitting ? null : () => Navigator.pop(ctx),
                          borderRadius: BorderRadius.circular(20),
                          child: Padding(
                            padding: const EdgeInsets.all(4),
                            child: Icon(
                              Symbols.close_rounded,
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
                          if (!_isAnnualLeaveEnabled) ...[
                            Container(
                              padding: const EdgeInsets.all(10),
                              margin: const EdgeInsets.only(bottom: 12),
                              decoration: BoxDecoration(
                                color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.12),
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.35),
                                ),
                              ),
                              child: Row(
                                crossAxisAlignment: CrossAxisAlignment.start,
                                children: [
                                  Icon(
                                    Symbols.info_rounded,
                                    size: 16,
                                    color: Theme.of(context).colorScheme.onTertiaryContainer,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      'تنبيه: حسابك حالياً على نظام الإجازات الأسبوعية فقط. يمكنك التقديم على أعذار ساعية، أو عذر غياب، أو إجازة بدون أجر.',
                                      style: TextStyle(
                                        fontSize: 11,
                                        color: Theme.of(context).colorScheme.onTertiaryContainer,
                                        fontWeight: FontWeight.w600,
                                        height: 1.35,
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),
                          ],

                          // نوع الطلب
                          Text(
                            'نوع الطلب:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          DropdownButtonFormField<String>(
                            initialValue: selectedType,
                            isExpanded: true,
                            style: TextStyle(
                              fontSize: 12.5,
                              color: colorScheme.onSurface,
                              fontWeight: FontWeight.w500,
                            ),
                            decoration: InputDecoration(
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                            ),
                            items: [
                              if (_isAnnualLeaveEnabled)
                                const DropdownMenuItem(
                                  value: 'annual',
                                  child: Text('إجازة اعتيادية (خصم من الرصيد السنوي)'),
                                )
                              else
                                DropdownMenuItem(
                                  value: 'annual',
                                  enabled: false,
                                  child: Text(
                                    'إجازة اعتيادية (غير مفعلة لحسابك حالياً)',
                                    style: TextStyle(color: colorScheme.outline),
                                  ),
                                ),
                              const DropdownMenuItem(
                                value: 'sick',
                                child: Text('إجازة مرضية'),
                              ),
                              const DropdownMenuItem(
                                value: 'emergency',
                                child: Text('إجازة عارضة'),
                              ),
                              const DropdownMenuItem(
                                value: 'unpaid',
                                child: Text('إجازة بدون أجر (إجازة استثنائية)'),
                              ),
                              const DropdownMenuItem(
                                value: 'delay',
                                child: Text('عذر تأخير عن العمل (ساعي)'),
                              ),
                              const DropdownMenuItem(
                                value: 'early_leave',
                                child: Text('إذن انصراف مبكر (ساعي)'),
                              ),
                              const DropdownMenuItem(
                                value: 'absence',
                                child: Text('عذر غياب يوم كامل'),
                              ),
                            ],
                            onChanged: (val) {
                              if (val != null) {
                                setDlgState(() {
                                  selectedType = val;
                                  isHourly = (val == 'delay' || val == 'early_leave');
                                });
                              }
                            },
                          ),

                          const SizedBox(height: 12),

                          // المقترح 4: التمييز بين الإجازة بالأيام والعذر بالساعات
                          if (isHourly) ...[
                            // اختيار يوم العذر
                            Text(
                              'تاريخ العذر:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            InkWell(
                              onTap: () async {
                                final picked = await showDatePicker(
                                  context: context,
                                  initialDate: startDate,
                                  firstDate: DateTime.now().subtract(const Duration(days: 30)),
                                  lastDate: DateTime.now().add(const Duration(days: 60)),
                                );
                                if (picked != null) {
                                  setDlgState(() {
                                    startDate = picked;
                                    endDate = picked;
                                  });
                                }
                              },
                              borderRadius: BorderRadius.circular(10),
                              child: Container(
                                padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
                                decoration: BoxDecoration(
                                  color: colorScheme.surfaceContainerLow,
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Symbols.calendar_today_rounded,
                                      size: 15,
                                      color: colorScheme.primary,
                                    ),
                                    const SizedBox(width: 8),
                                    Text(
                                      DateFormat('yyyy-MM-dd (EEEE)', 'ar').format(startDate),
                                      style: const TextStyle(
                                        fontSize: 12,
                                        fontWeight: FontWeight.bold,
                                      ),
                                    ),
                                    const Spacer(),
                                    Icon(
                                      Symbols.edit_calendar_rounded,
                                      size: 15,
                                      color: colorScheme.onSurfaceVariant,
                                    ),
                                  ],
                                ),
                              ),
                            ),
                            const SizedBox(height: 10),
                            // ساعات الاستئذان أو التأخير (Button Group موحد ومتصل)
                            Text(
                              'ساعات الاستئذان أو التأخير:',
                              style: TextStyle(
                                fontWeight: FontWeight.w600,
                                fontSize: 12,
                                color: colorScheme.onSurface,
                              ),
                            ),
                            const SizedBox(height: 6),
                            Container(
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  // من الساعة
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: fromTime,
                                        );
                                        if (picked != null) {
                                          setDlgState(() => fromTime = picked);
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
                                              Symbols.schedule_rounded,
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
                                                    'من الساعة',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    fromTime.format(context),
                                                    style: const TextStyle(
                                                      fontSize: 12,
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
                                  ),
                                  Container(
                                    width: 1,
                                    height: 28,
                                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                  // إلى الساعة
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picked = await showTimePicker(
                                          context: context,
                                          initialTime: toTime,
                                        );
                                        if (picked != null) {
                                          setDlgState(() => toTime = picked);
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
                                              Symbols.schedule_rounded,
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
                                                    'إلى الساعة',
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    toTime.format(context),
                                                    style: const TextStyle(
                                                      fontSize: 12,
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
                                  ),
                                ],
                              ),
                            ),
                          ] else ...[
                            // اختيار الفترة بالأيام (Button Group موحد ومتصل)
                            Row(
                              children: [
                                Text(
                                  'الفترة بالأيام:',
                                  style: TextStyle(
                                    fontWeight: FontWeight.w600,
                                    fontSize: 12,
                                    color: colorScheme.onSurface,
                                  ),
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
                                    'المدة: $calculatedDays ${calculatedDays == 1 ? 'يوم' : 'أيام'}',
                                    style: TextStyle(
                                      fontSize: 11,
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
                                borderRadius: BorderRadius.circular(10),
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
                                              Symbols.calendar_today_rounded,
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
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    DateFormat('dd-MM-yyyy').format(startDate),
                                                    style: const TextStyle(
                                                      fontSize: 12,
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
                                              Symbols.event_available_rounded,
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
                                                    style: TextStyle(
                                                      fontSize: 9.5,
                                                      fontWeight: FontWeight.w600,
                                                      color: colorScheme.onSurfaceVariant,
                                                    ),
                                                  ),
                                                  const SizedBox(height: 1),
                                                  Text(
                                                    DateFormat('dd-MM-yyyy').format(endDate),
                                                    style: const TextStyle(
                                                      fontSize: 12,
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
                                  ),
                                ],
                              ),
                            ),
                            if (isLeaveType && calculatedDays > _currentRemainingBalance) ...[
                              const SizedBox(height: 6),
                              Container(
                                padding: const EdgeInsets.all(8),
                                decoration: BoxDecoration(
                                  color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.15),
                                  borderRadius: BorderRadius.circular(8),
                                  border: Border.all(color: Theme.of(context).colorScheme.tertiary.withValues(alpha: 0.4)),
                                ),
                                child: Row(
                                  children: [
                                    Icon(
                                      Symbols.warning_amber_rounded,
                                      size: 15,
                                      color: Theme.of(context).colorScheme.onTertiaryContainer,
                                    ),
                                    const SizedBox(width: 6),
                                    Expanded(
                                      child: Text(
                                        'تنبيه: الأيام المطلوبة ($calculatedDays يوم) تتجاوز رصيد إجازاتك المتبقي ($_currentRemainingBalance يوم)',
                                        style: TextStyle(
                                          fontSize: 10.5,
                                          color: Theme.of(context).colorScheme.onTertiaryContainer,
                                          fontWeight: FontWeight.w600,
                                        ),
                                      ),
                                    ),
                                  ],
                                ),
                              ),
                            ],
                          ],

                          const SizedBox(height: 12),

                          // سبب الطلب (بفونت وارتفاع أصغر وكتابة مختصرة)
                          Text(
                            'سبب الطلب:',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          TextField(
                            controller: reasonCtrl,
                            style: const TextStyle(fontSize: 12),
                            decoration: InputDecoration(
                              hintText: 'اكتب السبب باختصار...',
                              hintStyle: TextStyle(
                                fontSize: 11,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.7),
                              ),
                              contentPadding: const EdgeInsets.symmetric(
                                horizontal: 12,
                                vertical: 8,
                              ),
                              border: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              enabledBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                                ),
                              ),
                              focusedBorder: OutlineInputBorder(
                                borderRadius: BorderRadius.circular(10),
                                borderSide: BorderSide(
                                  color: colorScheme.primary,
                                  width: 1.5,
                                ),
                              ),
                            ),
                            maxLines: 2,
                          ),

                          const SizedBox(height: 12),

                          // المقترح 3: إرفاق صورة / تقرير طبي (Buttons Group: الكاميرا والمعرض)
                          Text(
                            'إرفاق تقرير طبي أو مستند (اختياري):',
                            style: TextStyle(
                              fontWeight: FontWeight.w600,
                              fontSize: 12,
                              color: colorScheme.onSurface,
                            ),
                          ),
                          const SizedBox(height: 6),
                          if (pickedAttachment != null)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 6),
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                                border: Border.all(
                                  color: Theme.of(context).colorScheme.primary.withValues(alpha: 0.4),
                                ),
                              ),
                              child: Row(
                                children: [
                                  Icon(
                                    Symbols.check_circle_rounded,
                                    color: Theme.of(context).colorScheme.primary,
                                    size: 16,
                                  ),
                                  const SizedBox(width: 8),
                                  Expanded(
                                    child: Text(
                                      pickedAttachment!.name,
                                      style: const TextStyle(
                                        fontSize: 11.5,
                                        fontWeight: FontWeight.w600,
                                      ),
                                      overflow: TextOverflow.ellipsis,
                                    ),
                                  ),
                                  InkWell(
                                    onTap: () => setDlgState(() => pickedAttachment = null),
                                    borderRadius: BorderRadius.circular(20),
                                    child: const Padding(
                                      padding: EdgeInsets.all(4),
                                      child: Icon(Symbols.close_rounded, size: 16, color: Colors.red),
                                    ),
                                  ),
                                ],
                              ),
                            )
                          else
                            Container(
                              height: 38,
                              decoration: BoxDecoration(
                                color: colorScheme.surfaceContainerLow,
                                borderRadius: BorderRadius.circular(10),
                              ),
                              child: Row(
                                children: [
                                  // الكاميرا
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picker = ImagePicker();
                                        final img = await picker.pickImage(
                                          source: ImageSource.camera,
                                          imageQuality: 80,
                                        );
                                        if (img != null) {
                                          setDlgState(() => pickedAttachment = img);
                                        }
                                      },
                                      borderRadius: const BorderRadius.horizontal(
                                        right: Radius.circular(9),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Symbols.camera_alt_rounded,
                                            size: 15,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'الكاميرا',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                  Container(
                                    width: 1,
                                    height: 20,
                                    color: colorScheme.outlineVariant.withValues(alpha: 0.5),
                                  ),
                                  // المعرض
                                  Expanded(
                                    child: InkWell(
                                      onTap: () async {
                                        final picker = ImagePicker();
                                        final img = await picker.pickImage(
                                          source: ImageSource.gallery,
                                          imageQuality: 80,
                                        );
                                        if (img != null) {
                                          setDlgState(() => pickedAttachment = img);
                                        }
                                      },
                                      borderRadius: const BorderRadius.horizontal(
                                        left: Radius.circular(9),
                                      ),
                                      child: Row(
                                        mainAxisAlignment: MainAxisAlignment.center,
                                        children: [
                                          Icon(
                                            Symbols.photo_library_rounded,
                                            size: 15,
                                            color: colorScheme.primary,
                                          ),
                                          const SizedBox(width: 6),
                                          const Text(
                                            'المعرض',
                                            style: TextStyle(
                                              fontSize: 12,
                                              fontWeight: FontWeight.w600,
                                            ),
                                          ),
                                        ],
                                      ),
                                    ),
                                  ),
                                ],
                              ),
                            ),

                          if (isSubmitting) ...[
                            const SizedBox(height: 12),
                            const Center(
                              child: Column(
                                children: [
                                  SizedBox(
                                    width: 20,
                                    height: 20,
                                    child: CircularProgressIndicator(strokeWidth: 2),
                                  ),
                                  SizedBox(height: 6),
                                  Text(
                                    'جاري رفع المرفق وإرسال الطلب للمشرف...',
                                    style: TextStyle(fontSize: 11),
                                  ),
                                ],
                              ),
                            ),
                          ],
                        ],
                      ),
                    ),
                  ),

                  // Dialog Footer: Buttons Group (إلغاء وإرسال الطلب)
                  Divider(
                    height: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.25),
                  ),
                  Padding(
                    padding: const EdgeInsets.fromLTRB(16, 12, 16, 14),
                    child: Row(
                      children: [
                        // زر الإلغاء
                        Expanded(
                          flex: 1,
                          child: SizedBox(
                            height: 42,
                            child: OutlinedButton.icon(
                              style: OutlinedButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                foregroundColor: colorScheme.onSurfaceVariant,
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: isSubmitting ? null : () => Navigator.pop(ctx),
                              icon: const Icon(Symbols.close_rounded, size: 16),
                              label: const Text(
                                'إلغاء',
                                style: TextStyle(
                                  fontSize: 12.5,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
                          ),
                        ),
                        const SizedBox(width: 10),
                        // زر إرسال الطلب
                        Expanded(
                          flex: 2,
                          child: SizedBox(
                            height: 42,
                            child: FilledButton.icon(
                              style: FilledButton.styleFrom(
                                shape: RoundedRectangleBorder(
                                  borderRadius: BorderRadius.circular(10),
                                ),
                                padding: EdgeInsets.zero,
                              ),
                              onPressed: isSubmitting
                                  ? null
                                  : () async {
                                      final reason = reasonCtrl.text.trim();
                                      final messenger = ScaffoldMessenger.of(context);
                                      final successColor = Theme.of(context).colorScheme.primary;
                                      if (reason.isEmpty) {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text('يرجى كتابة سبب الإجازة أو العذر'),
                                          ),
                                        );
                                        return;
                                      }

                                      if (!_isAnnualLeaveEnabled && selectedType == 'annual') {
                                        messenger.showSnackBar(
                                          const SnackBar(
                                            content: Text(
                                              'رصيد الإجازات السنوية غير مفعّل لحسابك حالياً. يرجى اختيار نوع آخر.',
                                            ),
                                          ),
                                        );
                                        return;
                                      }

                                      final String? fromTimeFormatted =
                                          isHourly ? fromTime.format(context) : null;
                                      final String? toTimeFormatted =
                                          isHourly ? toTime.format(context) : null;

                                      setDlgState(() => isSubmitting = true);

                                      try {
                                        String? attachmentUrl;

                                        // رفع المرفق إلى Firebase Storage
                                        if (pickedAttachment != null) {
                                          final bytes = await pickedAttachment!.readAsBytes();
                                          final fileName =
                                              '${DateTime.now().millisecondsSinceEpoch}_${pickedAttachment!.name}';
                                          final storageRef = FirebaseStorage.instance.ref().child(
                                                'leave_attachments/${widget.delegate.companyUID}/${widget.delegate.uid}/$fileName',
                                              );

                                          final metadata = SettableMetadata(
                                            contentType: 'image/jpeg',
                                            customMetadata: {
                                              'companyUID': widget.delegate.companyUID,
                                              'delegateUid': widget.delegate.uid,
                                            },
                                          );

                                          final uploadTask =
                                              await storageRef.putData(bytes, metadata);
                                          attachmentUrl = await uploadTask.ref.getDownloadURL();
                                        }

                                        // تسجيل الطلب في Firestore
                                        final docRef = FirebaseFirestore.instance
                                            .collection('leave_requests')
                                            .doc();

                                        final int finalDays = isHourly
                                            ? 0
                                            : (endDate.difference(startDate).inDays + 1);

                                        await docRef.set({
                                          'id': docRef.id,
                                          'delegateUid': widget.delegate.uid,
                                          'delegateName': widget.delegate.fullName,
                                          'delegatePhone': widget.delegate.phoneNumber,
                                          'companyUID': widget.delegate.companyUID,
                                          'organizationUID': widget.delegate.organizationUID,
                                          'type': selectedType,
                                          'isHourly': isHourly,
                                          'hoursCount': isHourly ? hoursCount : null,
                                          'fromTime': fromTimeFormatted,
                                          'toTime': toTimeFormatted,
                                          'startDate': Timestamp.fromDate(startDate),
                                          'endDate': Timestamp.fromDate(endDate),
                                          'daysCount': finalDays,
                                          'reason': reason,
                                          'attachmentUrl': attachmentUrl,
                                          'status': 'pending', // يبدأ دائماً بقيد المراجعة للمندوب
                                          'createdAt': FieldValue.serverTimestamp(),
                                          'resolvedAt': null,
                                          'resolvedBy': null,
                                          'resolvedByName': null,
                                          'rejectReason': null,
                                        });

                                        // إرسال إشعار فوري لمشرف الشركة الخاص بالمندوب
                                        String notifTitle;
                                        switch (selectedType) {
                                          case 'delay':
                                            notifTitle = 'عذر تأخير جديد قيد المراجعة';
                                            break;
                                          case 'sick':
                                            notifTitle = 'طلب إجازة مرضية جديدة';
                                            break;
                                          default:
                                            notifTitle = 'طلب إجازة جديد قيد المراجعة';
                                            break;
                                        }

                                        await FirebaseFirestore.instance
                                            .collection('notifications')
                                            .add({
                                          'delegateUid': widget.delegate.supervisorUid ?? '',
                                          'companyUID': widget.delegate.companyUID,
                                          'organizationUID': widget.delegate.organizationUID,
                                          'title': notifTitle,
                                          'body':
                                              'قدم المندوب ${widget.delegate.fullName} طلباً جديداً يحتاج إلى مراجعتك واعتمادك.',
                                          'type': 'leave_request_submitted',
                                          'targetRole': 'supervisor',
                                          'isRead': false,
                                          'createdAt': FieldValue.serverTimestamp(),
                                          'createdBy': widget.delegate.uid,
                                          'senderName': widget.delegate.fullName,
                                        });

                                        if (ctx.mounted) Navigator.pop(ctx);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: const Row(
                                              children: [
                                                M3AnimatedCheck(size: 28),
                                                SizedBox(width: 12),
                                                Expanded(
                                                  child: Text(
                                                    'تم إرسال طلبك بنجاح لمشرف الشركة وهو قيد المراجعة الآن.',
                                                  ),
                                                ),
                                              ],
                                            ),
                                            backgroundColor: successColor,
                                          ),
                                        );
                                      } catch (e) {
                                        setDlgState(() => isSubmitting = false);
                                        messenger.showSnackBar(
                                          SnackBar(
                                            content: Text('حدث خطأ أثناء إرسال الطلب: $e'),
                                          ),
                                        );
                                      }
                                    },
                              icon: isSubmitting
                                  ? const SizedBox(
                                      width: 15,
                                      height: 15,
                                      child: CircularProgressIndicator(
                                        strokeWidth: 2,
                                        color: Colors.white,
                                      ),
                                    )
                                  : const Icon(Symbols.send_rounded, size: 16),
                              label: Text(
                                isSubmitting ? 'جارٍ الإرسال...' : 'إرسال الطلب',
                                style: const TextStyle(
                                  fontSize: 12.5,
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
}
