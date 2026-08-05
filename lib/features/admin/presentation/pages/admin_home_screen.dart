import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/constants.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_state.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_admin_tasks.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_summary_card.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';

class AdminHomeScreen extends StatelessWidget {
  final Delegate adminDelegate;

  const AdminHomeScreen({super.key, required this.adminDelegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => sl<AdminDashboardBloc>()
        ..add(
          LoadDashboard(
            organizationUID: adminDelegate.organizationUID,
            companyUID: adminDelegate.companyUID,
          ),
        ),
      child: _AdminHomeBody(adminDelegate: adminDelegate),
    );
  }
}

class _AdminHomeBody extends StatelessWidget {
  final Delegate adminDelegate;

  const _AdminHomeBody({required this.adminDelegate});

  void _showAttendanceDetailsSheet(BuildContext context, String initialFilter) {
    showModalBottomSheet(
      context: context,
      isScrollControlled: true,
      backgroundColor: Colors.transparent,
      builder: (modalContext) {
        return _AttendanceDetailsBottomSheet(
          adminDelegate: adminDelegate,
          initialFilter: initialFilter,
        );
      },
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return RefreshIndicator(
      onRefresh: () async {
        context.read<AdminDashboardBloc>().add(
          LoadDashboard(
            organizationUID: adminDelegate.organizationUID,
            companyUID: adminDelegate.companyUID,
          ),
        );
      },
      child: ListView(
        padding: const EdgeInsets.all(20),
        children: [
          // Section title
          Row(
            children: [
              Icon(
                Icons.insights_rounded,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.todayOverview,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 8),
          Text(
            _formatDate(context),
            style: theme.textTheme.bodyMedium?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
            ),
          ),
          const SizedBox(height: 24),

          // Summary Cards
          BlocBuilder<AdminDashboardBloc, AdminDashboardState>(
            builder: (context, state) {
              if (state is AdminDashboardLoading) {
                return const Center(
                  child: Padding(
                    padding: EdgeInsets.only(top: 60),
                    child: CircularProgressIndicator(),
                  ),
                );
              }

              if (state is AdminDashboardError) {
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.only(top: 40),
                    child: Column(
                      children: [
                        Icon(
                          Icons.error_outline_rounded,
                          size: 48,
                          color: theme.colorScheme.error,
                        ),
                        const SizedBox(height: 12),
                        Text(
                          state.message,
                          style: theme.textTheme.bodyLarge?.copyWith(
                            color: theme.colorScheme.error,
                          ),
                        ),
                        const SizedBox(height: 16),
                        FilledButton.icon(
                          onPressed: () {
                            context.read<AdminDashboardBloc>().add(
                              LoadDashboard(
                                organizationUID: adminDelegate.organizationUID,
                                companyUID: adminDelegate.companyUID,
                              ),
                            );
                          },
                          icon: const Icon(Icons.refresh_rounded),
                          label: Text(l10n.retry),
                        ),
                      ],
                    ),
                  ),
                );
              }

              if (state is AdminDashboardLoaded) {
                final summary = state.summary;
                final canSeeCompaniesCount =
                    adminDelegate.role == UserRole.superAdmin ||
                    adminDelegate.role == UserRole.marketing;
                return Column(
                  children: [
                    // بطاقة "عدد الشركات" تظهر فقط للمدير العام والتسويق
                    if (canSeeCompaniesCount) ...[
                      Row(
                        children: [
                          Expanded(
                            child: _CompactSummaryCard(
                              icon: Icons.business_rounded,
                              title: 'عدد الشركات',
                              value: '${summary.totalCompanies}',
                              color: theme.colorScheme.tertiary,
                              backgroundColor: theme
                                  .colorScheme
                                  .tertiaryContainer
                                  .withValues(alpha: 0.5),
                            ),
                          ),
                          const SizedBox(width: 14),
                          Expanded(
                            child: _CompactSummaryCard(
                              icon: Icons.groups_rounded,
                              title: l10n.totalDelegates,
                              value: '${summary.totalDelegates}',
                              color: theme.colorScheme.primary,
                              backgroundColor: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.5),
                              onTap: () =>
                                  _showAttendanceDetailsSheet(context, 'all'),
                            ),
                          ),
                        ],
                      ),
                      const SizedBox(height: 14),
                    ] else ...[
                      // مشرفين: 3 بطاقات في صف واحد بشكل مضغوط
                      IntrinsicHeight(
                        child: Row(
                          crossAxisAlignment: CrossAxisAlignment.stretch,
                          children: [
                            Expanded(
                              child: _CompactSummaryCard(
                                icon: Icons.groups_rounded,
                                title: l10n.totalDelegates,
                                value: '${summary.totalDelegates}',
                                color: theme.colorScheme.primary,
                                backgroundColor: theme.colorScheme.primaryContainer
                                    .withValues(alpha: 0.5),
                                onTap: () =>
                                    _showAttendanceDetailsSheet(context, 'all'),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactSummaryCard(
                                icon: Icons.check_circle_rounded,
                                title: l10n.checkedInToday,
                                value: '${summary.checkedInToday}',
                                color: theme.colorScheme.secondary,
                                backgroundColor: theme
                                    .colorScheme
                                    .secondaryContainer
                                    .withValues(alpha: 0.5),
                                onTap: () => _showAttendanceDetailsSheet(
                                    context, 'checked_in'),
                                isDense: true,
                              ),
                            ),
                            const SizedBox(width: 8),
                            Expanded(
                              child: _CompactSummaryCard(
                                icon: Icons.cancel_rounded,
                                title: l10n.absentToday,
                                value: '${summary.absentToday}',
                                color: theme.colorScheme.onSurfaceVariant,
                                backgroundColor: theme
                                    .colorScheme
                                    .surfaceContainerHighest
                                    .withValues(alpha: 0.7),
                                onTap: () =>
                                    _showAttendanceDetailsSheet(context, 'absent'),
                                isDense: true,
                              ),
                            ),
                          ],
                        ),
                      ),
                    ],
                  ],
                );
              }

              return const SizedBox.shrink();
            },
          ),

          // ── Quick Actions for Company Admin / Supervisor ──
          if (adminDelegate.role == UserRole.admin || adminDelegate.role == UserRole.organizationAdmin) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.bolt_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'إجراءات سريعة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.camera_alt_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                title: const Text(
                  'إدارة أذونات التصوير',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: Text(
                  adminDelegate.role == UserRole.organizationAdmin
                      ? 'استعراض أذونات التصوير ومتابعة تقارير المناديب (للعلم فقط)'
                      : 'طلب إذن تصوير جديد، تفعيل/تعطيل الأذونات، ومتابعة تقارير المناديب',
                ),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  context.push('/photo-permissions/supervisor', extra: adminDelegate);
                },
              ),
            ),
            const SizedBox(height: 12),
            Card(
              clipBehavior: Clip.antiAlias,
              shape: RoundedRectangleBorder(
                borderRadius: BorderRadius.circular(16),
              ),
              child: ListTile(
                leading: Icon(
                  Icons.photo_library_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                title: const Text(
                  'تقارير الصور',
                  style: TextStyle(fontWeight: FontWeight.bold),
                ),
                subtitle: const Text('استعراض تقارير الصور الشهرية المرفوعة بواسطة مناديب الشركة'),
                trailing: const Icon(Icons.arrow_forward_ios_rounded, size: 16),
                onTap: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => BlocProvider(
                        create: (context) => sl<PhotoPermissionBloc>(),
                        child: MonthlyPhotoReportScreen(
                          delegate: adminDelegate,
                          showAppBar: true,
                        ),
                      ),
                    ),
                  );
                },
              ),
            ),
          ],

          // ── Quick Actions for Marketing / Super Admin ──
          if (adminDelegate.role == UserRole.marketing || adminDelegate.role == UserRole.superAdmin) ...[
            const SizedBox(height: 24),
            Row(
              children: [
                Icon(
                  Icons.dashboard_rounded,
                  color: theme.colorScheme.primary,
                  size: 28,
                ),
                const SizedBox(width: 10),
                Text(
                  'الإجراءات السريعة',
                  style: theme.textTheme.titleLarge?.copyWith(
                    fontWeight: FontWeight.bold,
                    color: theme.colorScheme.onSurface,
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),

            // Quick Action Buttons
            Row(
              children: [
                Expanded(
                  child: FilledButton.icon(
                    onPressed: () {
                      Navigator.pushNamed(context, '/admin/company-search');
                    },
                    icon: const Icon(Icons.search_rounded),
                    label: const Text('البحث عن الشركات'),
                    style: FilledButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: OutlinedButton.icon(
                    onPressed: () {
                      // يمكن إضافة إجراءات أخرى هنا
                    },
                    icon: const Icon(Icons.business_rounded),
                    label: const Text('إدارة الشركات'),
                    style: OutlinedButton.styleFrom(
                      padding: const EdgeInsets.symmetric(vertical: 12),
                    ),
                  ),
                ),
              ],
            ),
          ],

          // ── Task Summary ──
          const SizedBox(height: 24),
          Row(
            children: [
              Icon(
                Icons.task_alt_rounded,
                color: theme.colorScheme.primary,
                size: 28,
              ),
              const SizedBox(width: 10),
              Text(
                l10n.tasksSummary,
                style: theme.textTheme.titleLarge?.copyWith(
                  fontWeight: FontWeight.bold,
                  color: theme.colorScheme.onSurface,
                ),
              ),
            ],
          ),
          const SizedBox(height: 12),
          _AdminTaskSummary(adminDelegate: adminDelegate),
        ],
      ),
    );
  }

  String _formatDate(BuildContext context) {
    final now = DateTime.now();
    final locale = Localizations.localeOf(context).languageCode;
    final months = locale == 'ar'
        ? [
            'يناير',
            'فبراير',
            'مارس',
            'أبريل',
            'مايو',
            'يونيو',
            'يوليو',
            'أغسطس',
            'سبتمبر',
            'أكتوبر',
            'نوفمبر',
            'ديسمبر',
          ]
        : [
            'January',
            'February',
            'March',
            'April',
            'May',
            'June',
            'July',
            'August',
            'September',
            'October',
            'November',
            'December',
          ];
    final days = locale == 'ar'
        ? [
            'الأحد',
            'الإثنين',
            'الثلاثاء',
            'الأربعاء',
            'الخميس',
            'الجمعة',
            'السبت',
          ]
        : [
            'Sunday',
            'Monday',
            'Tuesday',
            'Wednesday',
            'Thursday',
            'Friday',
            'Saturday',
          ];

    final dayName = days[now.weekday % 7];
    return '$dayName, ${now.day} ${months[now.month - 1]} ${now.year}';
  }
}



/// Compact vertical card for the two side-by-side summary cards
class _CompactSummaryCard extends StatelessWidget {
  final IconData icon;
  final String title;
  final String value;
  final Color color;
  final Color backgroundColor;
  final VoidCallback? onTap;
  final bool isDense;

  const _CompactSummaryCard({
    required this.icon,
    required this.title,
    required this.value,
    required this.color,
    required this.backgroundColor,
    this.onTap,
    this.isDense = false,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    return Card(
      elevation: 0,
      color: backgroundColor,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(16),
        side: BorderSide(color: color.withValues(alpha: 0.15)),
      ),
      child: InkWell(
        onTap: onTap,
        child: Padding(
          padding: EdgeInsets.all(isDense ? 10 : 18),
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.center,
            mainAxisAlignment: MainAxisAlignment.center,
            children: [
              Container(
                width: isDense ? 36 : 44,
                height: isDense ? 36 : 44,
                decoration: BoxDecoration(
                  color: color.withValues(alpha: 0.15),
                  borderRadius: BorderRadius.circular(12),
                ),
                child: Icon(icon, color: color, size: isDense ? 20 : 24),
              ),
              SizedBox(height: isDense ? 8 : 12),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  title,
                  textAlign: TextAlign.center,
                  style: theme.textTheme.bodySmall?.copyWith(
                    color: color.withValues(alpha: 0.8),
                    fontWeight: FontWeight.w600,
                    letterSpacing: 0.3,
                    fontSize: isDense ? 11 : null,
                  ),
                ),
              ),
              SizedBox(height: isDense ? 4 : 6),
              FittedBox(
                fit: BoxFit.scaleDown,
                child: Text(
                  value,
                  style: theme.textTheme.headlineMedium?.copyWith(
                    color: color,
                    fontWeight: FontWeight.bold,
                    fontSize: isDense ? 22 : null,
                  ),
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _AttendanceDetailsBottomSheet extends StatefulWidget {
  final Delegate adminDelegate;
  final String initialFilter;

  const _AttendanceDetailsBottomSheet({
    required this.adminDelegate,
    required this.initialFilter,
  });

  @override
  State<_AttendanceDetailsBottomSheet> createState() =>
      _AttendanceDetailsBottomSheetState();
}

class _AttendanceDetailsBottomSheetState
    extends State<_AttendanceDetailsBottomSheet> {
  bool _isLoading = true;
  late String _filter;
  String _searchQuery = '';
  List<_DelegateAttendanceData> _allData = [];

  @override
  void initState() {
    super.initState();
    _filter = widget.initialFilter;
    _fetchAttendanceData();
  }

  Future<void> _fetchAttendanceData() async {
    setState(() => _isLoading = true);
    final firestore = FirebaseFirestore.instance;
    final now = DateTime.now();
    final startOfDay = DateTime(now.year, now.month, now.day);
    final endOfDay = startOfDay.add(const Duration(days: 1));

    try {
      // 1. Fetch delegates for the company
      final delegatesSnapshot = await firestore
          .collection('organizations')
          .doc(widget.adminDelegate.organizationUID)
          .collection('companies')
          .doc(widget.adminDelegate.companyUID)
          .collection('delegates')
          .get();

      final delegates = delegatesSnapshot.docs
          .map((doc) => DelegateModel.fromJson(doc.data(), doc.id))
          .toList();

      // 2. Fetch today's attendance logs
      final attendanceSnapshot = await firestore
          .collection(kAttendanceCollection)
          .where('organizationId', isEqualTo: widget.adminDelegate.organizationUID)
          .where('companyId', isEqualTo: widget.adminDelegate.companyUID)
          .get();

      final Map<String, List<Map<String, dynamic>>> logsByDelegate = {};
      for (var doc in attendanceSnapshot.docs) {
        final data = doc.data();
        final timestamp = data['timestamp'];
        if (timestamp is Timestamp) {
          final date = timestamp.toDate();
          if (date.isBefore(startOfDay) || date.isAfter(endOfDay)) continue;
        }

        final delegateId = (data['delegateId'] ?? data['userId'] ?? '').toString();
        if (delegateId.isNotEmpty) {
          logsByDelegate.putIfAbsent(delegateId, () => []).add(data);
        }
      }

      final List<_DelegateAttendanceData> list = [];
      for (var d in delegates) {
        final logs = logsByDelegate[d.uid] ?? [];
        DateTime? checkIn;
        DateTime? checkOut;
        String? branch;

        for (var log in logs) {
          final type = (log['type'] ?? '').toString();
          final ts = log['timestamp'];
          DateTime? logTime;
          if (ts is Timestamp) logTime = ts.toDate();

          if (type == 'check_in') {
            if (checkIn == null || (logTime != null && logTime.isBefore(checkIn))) {
              checkIn = logTime;
            }
            if (branch == null && log['branchName'] != null) {
              branch = log['branchName'].toString();
            }
          } else if (type == 'check_out') {
            if (checkOut == null || (logTime != null && logTime.isAfter(checkOut))) {
              checkOut = logTime;
            }
          }
        }

        list.add(_DelegateAttendanceData(
          delegate: d,
          checkInTime: checkIn,
          checkOutTime: checkOut,
          branchName: branch,
        ));
      }

      if (mounted) {
        setState(() {
          _allData = list;
          _isLoading = false;
        });
      }
    } catch (e) {
      if (mounted) {
        setState(() => _isLoading = false);
      }
    }
  }

  List<_DelegateAttendanceData> get _filteredData {
    return _allData.where((item) {
      final matchesSearch = _searchQuery.isEmpty ||
          item.delegate.fullName.toLowerCase().contains(_searchQuery.toLowerCase()) ||
          item.delegate.phoneNumber.contains(_searchQuery);

      if (!matchesSearch) return false;

      if (_filter == 'checked_in') {
        return item.checkInTime != null;
      } else if (_filter == 'absent') {
        return item.checkInTime == null;
      }
      return true; // 'all'
    }).toList();
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final media = MediaQuery.of(context);

    final checkedInCount = _allData.where((i) => i.checkInTime != null).length;
    final absentCount = _allData.where((i) => i.checkInTime == null).length;

    return Material(
      color: colorScheme.surface,
      borderRadius: const BorderRadius.vertical(top: Radius.circular(24)),
      clipBehavior: Clip.antiAlias,
      child: Container(
        height: media.size.height * 0.85,
        padding: const EdgeInsets.symmetric(horizontal: 20, vertical: 16),
        child: Column(
          children: [
            // Drag handle
            Container(
              width: 40,
              height: 4,
              decoration: BoxDecoration(
                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.3),
                borderRadius: BorderRadius.circular(2),
              ),
            ),
            const SizedBox(height: 16),

            // Sheet Title & Close
            Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  children: [
                    Icon(
                      Icons.badge_rounded,
                      color: colorScheme.primary,
                      size: 24,
                    ),
                    const SizedBox(width: 8),
                    Text(
                      'سجل حضور وانصراف اليوم',
                      style: theme.textTheme.titleLarge?.copyWith(
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
                IconButton(
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () => Navigator.pop(context),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // Choice Chips Filter
            SingleChildScrollView(
              scrollDirection: Axis.horizontal,
              child: Row(
                children: [
                  ChoiceChip(
                    label: Text('الحاضرون اليوم ($checkedInCount)'),
                    selected: _filter == 'checked_in',
                    selectedColor: Colors.green.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: _filter == 'checked_in' ? Colors.green : null,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'checked_in');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('الغائبون اليوم ($absentCount)'),
                    selected: _filter == 'absent',
                    selectedColor: Colors.red.withValues(alpha: 0.2),
                    labelStyle: TextStyle(
                      color: _filter == 'absent' ? Colors.red : null,
                      fontWeight: FontWeight.bold,
                    ),
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'absent');
                    },
                  ),
                  const SizedBox(width: 8),
                  ChoiceChip(
                    label: Text('إجمالي المناديب (${_allData.length})'),
                    selected: _filter == 'all',
                    onSelected: (selected) {
                      if (selected) setState(() => _filter = 'all');
                    },
                  ),
                ],
              ),
            ),
            const SizedBox(height: 12),

            // Search Bar
            TextField(
              onChanged: (val) => setState(() => _searchQuery = val),
              decoration: InputDecoration(
                hintText: 'ابحث باسم المندوب أو رقم الهاتف...',
                prefixIcon: const Icon(Icons.search_rounded),
                contentPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
                border: OutlineInputBorder(
                  borderRadius: BorderRadius.circular(12),
                  borderSide: BorderSide(color: colorScheme.outlineVariant),
                ),
                filled: true,
                fillColor: colorScheme.surfaceContainerHighest.withValues(alpha: 0.3),
              ),
            ),
            const SizedBox(height: 16),

            // Content List
            Expanded(
              child: _isLoading
                  ? const Center(child: CircularProgressIndicator())
                  : _filteredData.isEmpty
                      ? Center(
                          child: Column(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(
                                Icons.person_off_rounded,
                                size: 56,
                                color: colorScheme.onSurfaceVariant.withValues(alpha: 0.4),
                              ),
                              const SizedBox(height: 12),
                              Text(
                                'لا توجد بيانات مناديب تطابق هذا البحث',
                                style: theme.textTheme.titleSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        )
                      : ListView.builder(
                          itemCount: _filteredData.length,
                          itemBuilder: (context, index) {
                            final item = _filteredData[index];
                            final isCheckedIn = item.checkInTime != null;
                            final timeFormat = DateFormat('hh:mm a');

                            return Card(
                              margin: const EdgeInsets.only(bottom: 12),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(14),
                                side: BorderSide(
                                  color: isCheckedIn
                                      ? Colors.green.withValues(alpha: 0.3)
                                      : colorScheme.outlineVariant.withValues(alpha: 0.5),
                                ),
                              ),
                              child: Padding(
                                padding: const EdgeInsets.all(14),
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Row(
                                      children: [
                                        CircleAvatar(
                                          backgroundColor: isCheckedIn
                                              ? Colors.green.withValues(alpha: 0.15)
                                              : colorScheme.surfaceContainerHighest,
                                          child: Text(
                                            item.delegate.fullName.isNotEmpty
                                                ? item.delegate.fullName[0]
                                                : 'D',
                                            style: TextStyle(
                                              fontWeight: FontWeight.bold,
                                              color: isCheckedIn ? Colors.green : colorScheme.onSurfaceVariant,
                                            ),
                                          ),
                                        ),
                                        const SizedBox(width: 12),
                                        Expanded(
                                          child: Column(
                                            crossAxisAlignment: CrossAxisAlignment.start,
                                            children: [
                                              Text(
                                                item.delegate.fullName,
                                                style: theme.textTheme.titleMedium?.copyWith(
                                                  fontWeight: FontWeight.bold,
                                                ),
                                              ),
                                              const SizedBox(height: 2),
                                              Text(
                                                'الهاتف: ${item.delegate.phoneNumber}',
                                                style: theme.textTheme.bodySmall?.copyWith(
                                                  color: colorScheme.onSurfaceVariant,
                                                ),
                                              ),
                                            ],
                                          ),
                                        ),
                                        Container(
                                          padding: const EdgeInsets.symmetric(horizontal: 10, vertical: 4),
                                          decoration: BoxDecoration(
                                            color: isCheckedIn
                                                ? Colors.green.withValues(alpha: 0.12)
                                                : Colors.red.withValues(alpha: 0.12),
                                            borderRadius: BorderRadius.circular(8),
                                          ),
                                          child: Text(
                                            isCheckedIn ? 'حاضر 🟢' : 'غائب 🔴',
                                            style: TextStyle(
                                              color: isCheckedIn ? Colors.green : Colors.red,
                                              fontSize: 12,
                                              fontWeight: FontWeight.bold,
                                            ),
                                          ),
                                        ),
                                      ],
                                    ),
                                    if (isCheckedIn) ...[
                                      const Divider(height: 20),
                                      Row(
                                        children: [
                                          Icon(Icons.login_rounded, size: 16, color: Colors.green.shade700),
                                          const SizedBox(width: 6),
                                          Text(
                                            'الحضور: ${timeFormat.format(item.checkInTime!)}',
                                            style: const TextStyle(
                                              fontWeight: FontWeight.bold,
                                              fontSize: 13,
                                            ),
                                          ),
                                          const SizedBox(width: 16),
                                          Icon(
                                            Icons.logout_rounded,
                                            size: 16,
                                            color: item.checkOutTime != null ? Colors.orange.shade700 : Colors.grey,
                                          ),
                                          const SizedBox(width: 6),
                                          Text(
                                            item.checkOutTime != null
                                                ? 'الانصراف: ${timeFormat.format(item.checkOutTime!)}'
                                                : 'لم يسجل انصراف بعد',
                                            style: TextStyle(
                                              fontWeight: item.checkOutTime != null ? FontWeight.bold : FontWeight.normal,
                                              fontSize: 13,
                                              color: item.checkOutTime != null ? Colors.black87 : Colors.grey.shade700,
                                            ),
                                          ),
                                        ],
                                      ),
                                      if (item.branchName != null && item.branchName!.isNotEmpty) ...[
                                        const SizedBox(height: 6),
                                        Row(
                                          children: [
                                            Icon(Icons.location_on_rounded, size: 16, color: colorScheme.primary),
                                            const SizedBox(width: 6),
                                            Text(
                                              'الفرع: ${item.branchName}',
                                              style: theme.textTheme.bodySmall?.copyWith(
                                                fontWeight: FontWeight.w600,
                                              ),
                                            ),
                                          ],
                                        ),
                                      ],
                                    ],
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
}

class _DelegateAttendanceData {
  final Delegate delegate;
  final DateTime? checkInTime;
  final DateTime? checkOutTime;
  final String? branchName;

  _DelegateAttendanceData({
    required this.delegate,
    this.checkInTime,
    this.checkOutTime,
    this.branchName,
  });
}

/// Fetches admin tasks and displays them in a [TaskSummaryCard].
class _AdminTaskSummary extends StatefulWidget {
  final Delegate adminDelegate;

  const _AdminTaskSummary({required this.adminDelegate});

  @override
  State<_AdminTaskSummary> createState() => _AdminTaskSummaryState();
}

class _AdminTaskSummaryState extends State<_AdminTaskSummary> {
  late Future<List<TaskEntity>> _tasksFuture;

  @override
  void initState() {
    super.initState();
    _tasksFuture = _fetchTasks();
  }

  Future<List<TaskEntity>> _fetchTasks() async {
    final getAdminTasks = sl<GetAdminTasks>();
    final result = await getAdminTasks(
      widget.adminDelegate.organizationUID,
      widget.adminDelegate.companyUID,
    );
    return result.fold((_) => [], (tasks) => tasks);
  }

  @override
  Widget build(BuildContext context) {
    return FutureBuilder<List<TaskEntity>>(
      future: _tasksFuture,
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting) {
          return const TaskSummaryCard(tasks: [], isLoading: true);
        }
        return TaskSummaryCard(tasks: snapshot.data ?? []);
      },
    );
  }
}
