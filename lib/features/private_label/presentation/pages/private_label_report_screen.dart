import 'package:delegate_app/core/utils/file_download_helper.dart';
import 'package:delegate_app/core/widgets/app_snack_bar.dart';
import 'package:delegate_app/core/widgets/tashil_button_group.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_dates.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_report_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_access_denied_view.dart';

String _formatMonthLabel(String monthKey) {
  final parts = monthKey.split('-');
  if (parts.length != 2) return monthKey;
  final year = parts[0];
  final m = int.tryParse(parts[1]) ?? 1;
  const months = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];
  final name = (m >= 1 && m <= 12) ? months[m - 1] : parts[1];
  return '$name $year';
}

/// Private Label Report: Dedicated analytics and performance ranking for branches and marketers.
class PrivateLabelReportScreen extends StatelessWidget {
  final Delegate delegate;

  const PrivateLabelReportScreen({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    if (delegate.role == UserRole.superAdmin) {
      return _buildContent(context);
    }

    return StreamBuilder<PrivateLabelPermissions?>(
      stream: sl<PrivateLabelPermissionsRemoteDataSource>()
          .streamUserPermissions(delegate.uid),
      builder: (context, snapshot) {
        if (snapshot.connectionState == ConnectionState.waiting && !snapshot.hasData) {
          return const Scaffold(
            body: Center(child: CircularProgressIndicator()),
          );
        }
        final perms = snapshot.data;
        if (perms != null && perms.canViewReports) {
          return _buildContent(context);
        }
        return const PrivateLabelAccessDeniedView(
          title: 'تقارير Private Label',
          screenName: 'تقارير البرايفت ليبل ومؤشرات الأداء',
        );
      },
    );
  }

  Widget _buildContent(BuildContext context) {
    return BlocProvider<PrivateLabelReportBloc>(
      create: (_) => sl<PrivateLabelReportBloc>()
        ..add(PrivateLabelReportStarted(
          organizationUID: delegate.organizationUID,
          companyUID: delegate.companyUID,
        )),
      child: _ReportView(delegate: delegate),
    );
  }
}

class _ReportView extends StatelessWidget {
  final Delegate delegate;

  const _ReportView({required this.delegate});

  static Widget _centered(Widget child) => Center(
        child: ConstrainedBox(constraints: const BoxConstraints(maxWidth: 1100), child: child),
      );

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return BlocBuilder<PrivateLabelReportBloc, PrivateLabelReportState>(
      builder: (context, state) {
        final isBranches = state.viewMode == PrivateLabelReportViewMode.branches;
        final monthTitle = _formatMonthLabel(state.monthKey);

        return Scaffold(
          backgroundColor: cs.surface,
          appBar: AppBar(
            title: InkWell(
              borderRadius: BorderRadius.circular(8),
              onTap: () => _showMonthPickerSheet(context, state.monthKey),
              child: Padding(
                padding: const EdgeInsets.symmetric(vertical: 4, horizontal: 4),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Text('تقرير العلامة الخاصة'),
                    Text(
                      monthTitle,
                      style: theme.textTheme.labelMedium?.copyWith(
                        color: cs.primary,
                        fontWeight: FontWeight.bold,
                      ),
                    ),
                  ],
                ),
              ),
            ),
            centerTitle: false,
            actions: [
              IconButton(
                tooltip: 'تصدير إكسيل (${isBranches ? 'الفروع' : 'المسوقين'})',
                icon: const Icon(Icons.table_view_rounded),
                onPressed: () => _exportToExcel(context, state),
              ),
              IconButton(
                tooltip: 'تغيير الشهر ($monthTitle)',
                icon: const Icon(Icons.calendar_month_rounded),
                onPressed: () => _showMonthPickerSheet(context, state.monthKey),
              ),
              IconButton(
                tooltip: 'تحديث التقرير',
                icon: const Icon(Icons.refresh_rounded),
                onPressed: () => context
                    .read<PrivateLabelReportBloc>()
                    .add(const PrivateLabelReportRefreshRequested()),
              ),
              const SizedBox(width: 4),
            ],
          ),
          body: RefreshIndicator(
            onRefresh: () async {
              final bloc = context.read<PrivateLabelReportBloc>()
                ..add(const PrivateLabelReportRefreshRequested());
              await bloc.stream
                  .firstWhere((s) => s.status != PrivateLabelReportStatus.loading)
                  .timeout(const Duration(seconds: 20), onTimeout: () => bloc.state);
            },
            child: LayoutBuilder(
              builder: (context, constraints) {
                final desktop = constraints.maxWidth >= 768;
                return CustomScrollView(
                  physics: const AlwaysScrollableScrollPhysics(),
                  slivers: [
                    SliverPadding(
                      padding: const EdgeInsets.fromLTRB(16, 12, 16, 8),
                      sliver: SliverToBoxAdapter(
                        child: _centered(
                          Column(
                            crossAxisAlignment: CrossAxisAlignment.stretch,
                            children: [
                              _ViewModeToggle(state: state, desktop: desktop),
                              const SizedBox(height: 14),
                              _ExecutiveKpis(state: state, desktop: desktop),
                              const SizedBox(height: 14),
                              _Toolbar(state: state, desktop: desktop),
                            ],
                          ),
                        ),
                      ),
                    ),
                    ..._buildReportBody(context, state, desktop),
                    const SliverToBoxAdapter(child: SizedBox(height: 40)),
                  ],
                );
              },
            ),
          ),
        );
      },
    );
  }

  List<Widget> _buildReportBody(BuildContext context, PrivateLabelReportState state, bool desktop) {
    final cs = Theme.of(context).colorScheme;

    if (state.status == PrivateLabelReportStatus.loading &&
        state.branchReports.isEmpty &&
        state.marketerReports.isEmpty) {
      return const [
        SliverFillRemaining(hasScrollBody: false, child: Center(child: CircularProgressIndicator())),
      ];
    }

    if (state.status == PrivateLabelReportStatus.failure) {
      return [
        SliverFillRemaining(
          hasScrollBody: false,
          child: _Empty(
            icon: Icons.cloud_off_rounded,
            iconColor: cs.error,
            title: state.errorMessage ?? 'حصل خطأ أثناء تحميل التقرير',
          ),
        ),
      ];
    }

    if (state.viewMode == PrivateLabelReportViewMode.branches) {
      final branches = state.filteredBranchReports;
      if (branches.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Empty(
              icon: Icons.storefront_rounded,
              iconColor: cs.onSurfaceVariant,
              title: 'لا توجد بيانات فروع لهذا الشهر',
            ),
          ),
        ];
      }

      if (desktop) {
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverToBoxAdapter(
              child: _centered(
                LayoutBuilder(
                  builder: (context, c) {
                    final width = (c.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (int i = 0; i < branches.length; i++)
                          SizedBox(
                            width: width,
                            child: _BranchCard(
                              branch: branches[i],
                              rank: i + 1,
                              isHighestSort: state.sortMode == PrivateLabelReportSortMode.highestScore,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ];
      }

      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _centered(
                  _BranchCard(
                    branch: branches[index],
                    rank: index + 1,
                    isHighestSort: state.sortMode == PrivateLabelReportSortMode.highestScore,
                  ),
                ),
              ),
              childCount: branches.length,
            ),
          ),
        ),
      ];
    } else {
      final marketers = state.filteredMarketerReports;
      if (marketers.isEmpty) {
        return [
          SliverFillRemaining(
            hasScrollBody: false,
            child: _Empty(
              icon: Icons.groups_rounded,
              iconColor: cs.onSurfaceVariant,
              title: 'لا يوجد مسوقون مسجلون لهذا الشهر',
            ),
          ),
        ];
      }

      if (desktop) {
        return [
          SliverPadding(
            padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
            sliver: SliverToBoxAdapter(
              child: _centered(
                LayoutBuilder(
                  builder: (context, c) {
                    final width = (c.maxWidth - 12) / 2;
                    return Wrap(
                      spacing: 12,
                      runSpacing: 12,
                      children: [
                        for (int i = 0; i < marketers.length; i++)
                          SizedBox(
                            width: width,
                            child: _MarketerCard(
                              marketer: marketers[i],
                              rank: i + 1,
                              isHighestSort: state.sortMode == PrivateLabelReportSortMode.highestScore,
                            ),
                          ),
                      ],
                    );
                  },
                ),
              ),
            ),
          ),
        ];
      }

      return [
        SliverPadding(
          padding: const EdgeInsets.fromLTRB(16, 8, 16, 16),
          sliver: SliverList(
            delegate: SliverChildBuilderDelegate(
              (context, index) => Padding(
                padding: const EdgeInsets.only(bottom: 12),
                child: _centered(
                  _MarketerCard(
                    marketer: marketers[index],
                    rank: index + 1,
                    isHighestSort: state.sortMode == PrivateLabelReportSortMode.highestScore,
                  ),
                ),
              ),
              childCount: marketers.length,
            ),
          ),
        ),
      ];
    }
  }
}

// ─────────────────────────── View Mode Toggle (Elevated to Top) ───────────────────────────

class _ViewModeToggle extends StatelessWidget {
  final PrivateLabelReportState state;
  final bool desktop;

  const _ViewModeToggle({required this.state, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final bloc = context.read<PrivateLabelReportBloc>();

    return TashilConnectedButtonGroup<PrivateLabelReportViewMode>(
      isScrollable: false,
      width: desktop ? 360 : double.infinity,
      height: 46,
      itemPadding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
      selectedValue: state.viewMode,
      onSelected: (mode) => bloc.add(PrivateLabelReportViewModeChanged(mode)),
      items: const [
        TashilConnectedButtonItem(
          value: PrivateLabelReportViewMode.branches,
          label: 'تقارير الفروع',
          icon: Icons.storefront_rounded,
        ),
        TashilConnectedButtonItem(
          value: PrivateLabelReportViewMode.marketers,
          label: 'تقارير المسوقين',
          icon: Icons.groups_rounded,
        ),
      ],
    );
  }
}

// ─────────────────────────── Month Picker Modal ───────────────────────────

Future<void> _showMonthPickerSheet(BuildContext context, String currentMonthKey) async {
  final bloc = context.read<PrivateLabelReportBloc>();
  final media = MediaQuery.of(context);
  final isMobile = media.size.width <= 768;

  if (isMobile) {
    await showModalBottomSheet<void>(
      context: context,
      isScrollControlled: true,
      useSafeArea: true,
      backgroundColor: Theme.of(context).colorScheme.surface,
      shape: const RoundedRectangleBorder(
        borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
      ),
      builder: (ctx) => _MonthPickerSheet(
        initialMonthKey: currentMonthKey,
        onMonthSelected: (newMonthKey) {
          bloc.add(PrivateLabelReportMonthChanged(newMonthKey));
        },
      ),
    );
  } else {
    await showDialog<void>(
      context: context,
      builder: (ctx) => Dialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        child: ConstrainedBox(
          constraints: const BoxConstraints(maxWidth: 420),
          child: _MonthPickerSheet(
            initialMonthKey: currentMonthKey,
            isDialog: true,
            onMonthSelected: (newMonthKey) {
              bloc.add(PrivateLabelReportMonthChanged(newMonthKey));
            },
          ),
        ),
      ),
    );
  }
}

class _MonthPickerSheet extends StatefulWidget {
  final String initialMonthKey;
  final ValueChanged<String> onMonthSelected;
  final bool isDialog;

  const _MonthPickerSheet({
    required this.initialMonthKey,
    required this.onMonthSelected,
    this.isDialog = false,
  });

  @override
  State<_MonthPickerSheet> createState() => _MonthPickerSheetState();
}

class _MonthPickerSheetState extends State<_MonthPickerSheet> {
  late int _selectedYear;
  late int _selectedMonth;

  @override
  void initState() {
    super.initState();
    final parts = widget.initialMonthKey.split('-');
    _selectedYear = int.tryParse(parts[0]) ?? DateTime.now().year;
    _selectedMonth = parts.length > 1
        ? (int.tryParse(parts[1]) ?? DateTime.now().month)
        : DateTime.now().month;
  }

  static const _arabicMonths = [
    'يناير', 'فبراير', 'مارس', 'أبريل', 'مايو', 'يونيو',
    'يوليو', 'أغسطس', 'سبتمبر', 'أكتوبر', 'نوفمبر', 'ديسمبر'
  ];

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final now = DateTime.now();

    return Padding(
      padding: EdgeInsets.only(
        bottom: widget.isDialog ? 0 : MediaQuery.of(context).viewInsets.bottom,
      ),
      child: Column(
        mainAxisSize: MainAxisSize.min,
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          if (!widget.isDialog) ...[
            const SizedBox(height: 12),
            Center(
              child: Container(
                width: 38,
                height: 4.5,
                decoration: BoxDecoration(
                  color: cs.outlineVariant.withValues(alpha: 0.6),
                  borderRadius: BorderRadius.circular(3),
                ),
              ),
            ),
            const SizedBox(height: 14),
          ] else
            const SizedBox(height: 20),

          // Header: Title and Quick 'Current Month' button
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Row(
              mainAxisAlignment: MainAxisAlignment.spaceBetween,
              children: [
                Row(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    Icon(Icons.calendar_month_rounded, size: 22, color: cs.primary),
                    const SizedBox(width: 8),
                    Text(
                      'اختر شهر التقرير',
                      style: theme.textTheme.titleMedium?.copyWith(
                        fontWeight: FontWeight.bold,
                        color: cs.onSurface,
                      ),
                    ),
                  ],
                ),
                TextButton.icon(
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    foregroundColor: cs.primary,
                  ),
                  onPressed: () {
                    setState(() {
                      _selectedYear = now.year;
                      _selectedMonth = now.month;
                    });
                  },
                  icon: const Icon(Icons.today_rounded, size: 16),
                  label: const Text('الشهر الحالي'),
                ),
              ],
            ),
          ),
          const SizedBox(height: 14),

          // Year Selector
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: Container(
              height: 46,
              decoration: BoxDecoration(
                color: cs.surfaceContainerLow,
                borderRadius: BorderRadius.circular(14),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                mainAxisAlignment: MainAxisAlignment.spaceBetween,
                children: [
                  IconButton(
                    tooltip: 'السنة السابقة',
                    icon: const Icon(Icons.chevron_right_rounded, textDirection: TextDirection.ltr),
                    onPressed: _selectedYear > (now.year - 3)
                        ? () => setState(() => _selectedYear--)
                        : null,
                  ),
                  Text(
                    '$_selectedYear',
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                      color: cs.onSurface,
                    ),
                  ),
                  IconButton(
                    tooltip: 'السنة التالية',
                    icon: const Icon(Icons.chevron_left_rounded, textDirection: TextDirection.ltr),
                    onPressed: _selectedYear < now.year
                        ? () => setState(() => _selectedYear++)
                        : null,
                  ),
                ],
              ),
            ),
          ),
          const SizedBox(height: 16),

          // 12 Months Grid (4 rows x 3 columns)
          Padding(
            padding: const EdgeInsets.symmetric(horizontal: 20),
            child: GridView.builder(
              shrinkWrap: true,
              physics: const NeverScrollableScrollPhysics(),
              gridDelegate: const SliverGridDelegateWithFixedCrossAxisCount(
                crossAxisCount: 3,
                crossAxisSpacing: 10,
                mainAxisSpacing: 10,
                childAspectRatio: 2.2,
              ),
              itemCount: 12,
              itemBuilder: (context, index) {
                final monthNum = index + 1;
                final isSelected = (_selectedMonth == monthNum);
                final isFuture = (_selectedYear > now.year) ||
                    (_selectedYear == now.year && monthNum > now.month);

                return Material(
                  color: isSelected
                      ? cs.primary
                      : (isFuture ? cs.surfaceContainerLowest : cs.surfaceContainerLow),
                  shape: RoundedRectangleBorder(
                    borderRadius: BorderRadius.circular(12),
                    side: BorderSide(
                      color: isSelected
                          ? cs.primary
                          : (isFuture
                              ? cs.outlineVariant.withValues(alpha: 0.2)
                              : cs.outlineVariant.withValues(alpha: 0.6)),
                    ),
                  ),
                  clipBehavior: Clip.antiAlias,
                  child: InkWell(
                    onTap: isFuture
                        ? null
                        : () {
                            setState(() => _selectedMonth = monthNum);
                          },
                    child: Center(
                      child: Row(
                        mainAxisAlignment: MainAxisAlignment.center,
                        children: [
                          if (isSelected) ...[
                            Icon(Icons.check_rounded, size: 16, color: cs.onPrimary),
                            const SizedBox(width: 4),
                          ],
                          Text(
                            _arabicMonths[index],
                            style: theme.textTheme.labelMedium?.copyWith(
                              fontWeight: isSelected ? FontWeight.bold : FontWeight.w600,
                              color: isSelected
                                  ? cs.onPrimary
                                  : (isFuture
                                      ? cs.onSurfaceVariant.withValues(alpha: 0.35)
                                      : cs.onSurface),
                            ),
                          ),
                        ],
                      ),
                    ),
                  ),
                );
              },
            ),
          ),
          const SizedBox(height: 24),

          // Connected Action Button Group
          Padding(
            padding: const EdgeInsets.fromLTRB(20, 0, 20, 20),
            child: Container(
              height: 48,
              decoration: BoxDecoration(
                color: cs.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6), width: 1.2),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  Expanded(
                    flex: 2,
                    child: InkWell(
                      onTap: () => Navigator.of(context).pop(),
                      child: Center(
                        child: Row(
                          mainAxisAlignment: MainAxisAlignment.center,
                          children: [
                            Icon(Icons.close_rounded, size: 18, color: cs.onSurfaceVariant),
                            const SizedBox(width: 6),
                            Text('إلغاء',
                                style: TextStyle(
                                    color: cs.onSurfaceVariant, fontWeight: FontWeight.bold)),
                          ],
                        ),
                      ),
                    ),
                  ),
                  Container(
                      width: 1.2, height: 28, color: cs.outlineVariant.withValues(alpha: 0.6)),
                  Expanded(
                    flex: 3,
                    child: Material(
                      color: cs.primary,
                      child: InkWell(
                        onTap: () {
                          final newKey =
                              PrivateLabelDates.monthKey(_selectedYear, _selectedMonth);
                          widget.onMonthSelected(newKey);
                          Navigator.of(context).pop();
                        },
                        child: Center(
                          child: Row(
                            mainAxisAlignment: MainAxisAlignment.center,
                            children: [
                              Icon(Icons.check_rounded, size: 18, color: cs.onPrimary),
                              const SizedBox(width: 6),
                              Text('تطبيق الشهر',
                                  style: TextStyle(
                                      color: cs.onPrimary, fontWeight: FontWeight.bold)),
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
      ),
    );
  }
}

// ─────────────────────────── Excel Export ───────────────────────────

Future<void> _exportToExcel(BuildContext context, PrivateLabelReportState state) async {
  final isBranches = state.viewMode == PrivateLabelReportViewMode.branches;
  final buffer = StringBuffer();
  buffer.write('\uFEFF'); // UTF-8 BOM for Microsoft Excel Arabic support

  String escape(Object? v) {
    if (v == null) return '""';
    final s = v.toString().replaceAll('"', '""');
    return '"$s"';
  }

  if (isBranches) {
    final list = state.filteredBranchReports;
    if (list.isEmpty) {
      AppSnackBar.showError(context, 'لا توجد بيانات فروع لتصديرها');
      return;
    }
    buffer.writeln([
      'الترتيب',
      'اسم الفرع',
      'نسبة الإنجاز الشهري',
      'إجمالي التوثيقات',
      'التوثيقات المرفوضة',
      'عدد المسوقين',
      'أسماء المسوقين',
      'الشهر',
    ].map(escape).join(','));

    for (int i = 0; i < list.length; i++) {
      final b = list[i];
      buffer.writeln([
        '#${i + 1}',
        b.branchName,
        '${b.achievementScore.toStringAsFixed(1)}%',
        b.totalAudits,
        b.totalRejected,
        b.marketerNames.length,
        b.marketerNames.join(' - '),
        state.monthKey,
      ].map(escape).join(','));
    }
  } else {
    final list = state.filteredMarketerReports;
    if (list.isEmpty) {
      AppSnackBar.showError(context, 'لا توجد بيانات مسوقين لتصديرها');
      return;
    }
    buffer.writeln([
      'الترتيب',
      'اسم المسوق',
      'نسبة الإنجاز الشهري',
      'الأيام المكتملة',
      'أيام الشهر',
      'أيام الإجازة المعتمدة',
      'الأيام غير الموثقة',
      'إجمالي التوثيقات',
      'التوثيقات المرفوضة',
      'الفروع المغطاة',
      'الشهر',
    ].map(escape).join(','));

    for (int i = 0; i < list.length; i++) {
      final m = list[i];
      buffer.writeln([
        '#${i + 1}',
        m.delegateName,
        '${m.scorePercentage.toStringAsFixed(1)}%',
        m.kpi.completedDays,
        m.kpi.daysInMonth,
        m.kpi.countedRestDays,
        m.kpi.missedDays,
        m.totalAudits,
        m.totalRejected,
        m.branchNames.join(' - '),
        state.monthKey,
      ].map(escape).join(','));
    }
  }

  final fileName = isBranches
      ? 'تقرير_فروع_Private_Label_${state.monthKey}.csv'
      : 'تقرير_مسوقين_Private_Label_${state.monthKey}.csv';

  try {
    await FileDownloadHelper.downloadString(
      content: buffer.toString(),
      fileName: fileName,
      shareText: isBranches
          ? 'تقرير إنجاز فروع Private Label لـ ${state.monthKey}'
          : 'تقرير إنجاز مسوقي Private Label لـ ${state.monthKey}',
    );
    if (context.mounted) {
      AppSnackBar.showSuccess(context, 'تم تصدير تقرير الإكسيل بنجاح');
    }
  } catch (e) {
    if (context.mounted) {
      AppSnackBar.showError(context, 'حدث خطأ أثناء تصدير التقرير: $e');
    }
  }
}

// ─────────────────────────── Executive KPIs ───────────────────────────

class _ExecutiveKpis extends StatelessWidget {
  final PrivateLabelReportState state;
  final bool desktop;

  const _ExecutiveKpis({required this.state, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;

    final cards = [
      _ExecutiveKpiCard(
        title: 'متوسط الإنجاز العام',
        value: '${state.averageScore}%',
        icon: Icons.insights_rounded,
        color: state.averageScore >= 80
            ? const Color(0xFF2E7D32)
            : (state.averageScore >= 50 ? const Color(0xFFE65100) : cs.primary),
      ),
      _ExecutiveKpiCard(
        title: 'الفروع النشطة',
        value: '${state.totalActiveBranches}',
        icon: Icons.storefront_rounded,
        color: cs.primary,
      ),
      _ExecutiveKpiCard(
        title: 'المسوقون الملتزمون',
        value: '${state.totalActiveMarketers}',
        icon: Icons.groups_rounded,
        color: cs.secondary,
      ),
      _ExecutiveKpiCard(
        title: 'إجمالي التوثيقات',
        value: '${state.totalAuditsMonth}',
        icon: Icons.photo_library_rounded,
        color: cs.tertiary,
      ),
    ];

    if (desktop) {
      return Row(
        children: [
          for (int i = 0; i < cards.length; i++) ...[
            if (i > 0) const SizedBox(width: 12),
            Expanded(child: cards[i]),
          ],
        ],
      );
    }

    return LayoutBuilder(
      builder: (context, c) {
        final width = (c.maxWidth - 10) / 2;
        return Wrap(
          spacing: 10,
          runSpacing: 10,
          children: [
            for (final card in cards) SizedBox(width: width, child: card),
          ],
        );
      },
    );
  }
}

class _ExecutiveKpiCard extends StatelessWidget {
  final String title;
  final String value;
  final IconData icon;
  final Color color;

  const _ExecutiveKpiCard({
    required this.title,
    required this.value,
    required this.icon,
    required this.color,
  });

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 14, vertical: 12),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        children: [
          Row(
            mainAxisAlignment: MainAxisAlignment.spaceBetween,
            children: [
              Expanded(
                child: Text(
                  title,
                  style: theme.textTheme.labelMedium?.copyWith(
                    color: cs.onSurfaceVariant,
                    fontWeight: FontWeight.w500,
                    fontSize: 12,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
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
            style: theme.textTheme.headlineSmall?.copyWith(
              fontWeight: FontWeight.bold,
              color: color,
            ),
          ),
        ],
      ),
    );
  }
}

// ─────────────────────────── Toolbar (Search, Filter, Sort) ───────────────────────────

class _Toolbar extends StatelessWidget {
  final PrivateLabelReportState state;
  final bool desktop;

  const _Toolbar({required this.state, required this.desktop});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReportBloc>();

    final searchField = SizedBox(
      height: 44,
      child: TextField(
        style: theme.textTheme.bodyMedium?.copyWith(
          fontSize: 13,
          fontWeight: FontWeight.normal,
          color: cs.onSurface,
        ),
        decoration: InputDecoration(
          hintText: state.viewMode == PrivateLabelReportViewMode.branches
              ? 'ابحث باسم الفرع أو المسوق...'
              : 'ابحث باسم المسوق أو الفرع...',
          hintStyle: theme.textTheme.bodyMedium?.copyWith(
            fontSize: 13,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant.withValues(alpha: 0.65),
          ),
          prefixIcon: Icon(Icons.search_rounded, size: 20, color: cs.onSurfaceVariant),
          suffixIcon: state.searchQuery.isNotEmpty
              ? IconButton(
                  icon: const Icon(Icons.clear_rounded, size: 18),
                  onPressed: () => bloc.add(const PrivateLabelReportSearchQueryChanged('')),
                )
              : null,
          filled: true,
          fillColor: cs.surfaceContainerLow,
          contentPadding: const EdgeInsets.symmetric(horizontal: 14, vertical: 10),
          border: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          enabledBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.outlineVariant),
          ),
          focusedBorder: OutlineInputBorder(
            borderRadius: BorderRadius.circular(14),
            borderSide: BorderSide(color: cs.primary, width: 1.5),
          ),
        ),
        onChanged: (val) => bloc.add(PrivateLabelReportSearchQueryChanged(val)),
      ),
    );

    final branchFilter = _BranchReportDropdown(state: state);
    final sortDropdown = _SortReportDropdown(state: state);

    if (desktop) {
      return Row(
        children: [
          Expanded(child: searchField),
          const SizedBox(width: 12),
          branchFilter,
          const SizedBox(width: 12),
          sortDropdown,
        ],
      );
    }

    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        searchField,
        const SizedBox(height: 10),
        Row(
          children: [
            Expanded(child: branchFilter),
            const SizedBox(width: 10),
            Expanded(child: sortDropdown),
          ],
        ),
      ],
    );
  }
}

class _BranchReportDropdown extends StatelessWidget {
  final PrivateLabelReportState state;

  const _BranchReportDropdown({required this.state});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReportBloc>();
    final selected = state.selectedBranch;
    final isSelected = selected != null;
    final branchNames = state.branches;

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      child: PopupMenuButton<String?>(
        tooltip: 'فلترة بفروع فتح الله',
        offset: const Offset(0, 48),
        onSelected: (b) => bloc.add(PrivateLabelReportBranchFilterChanged(b)),
        itemBuilder: (context) => [
          PopupMenuItem<String?>(
            value: null,
            child: Row(
              children: [
                Icon(Icons.storefront_rounded, size: 18, color: cs.primary),
                const SizedBox(width: 10),
                const Expanded(
                  child: Text('جميع الفروع', style: TextStyle(fontWeight: FontWeight.bold)),
                ),
                if (!isSelected) Icon(Icons.check_rounded, size: 18, color: cs.primary),
              ],
            ),
          ),
          if (branchNames.isNotEmpty) const PopupMenuDivider(),
          for (final b in branchNames)
            PopupMenuItem<String?>(
              value: b,
              child: Row(
                children: [
                  Icon(Icons.storefront_outlined, size: 18, color: cs.onSurfaceVariant),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      b,
                      style: TextStyle(
                        fontWeight: selected == b ? FontWeight.bold : FontWeight.normal,
                      ),
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                    ),
                  ),
                  if (selected == b) ...[
                    const SizedBox(width: 6),
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                  ],
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(
              color: isSelected ? cs.primary.withValues(alpha: 0.5) : cs.outlineVariant,
            ),
          ),
          child: Row(
            children: [
              Icon(
                Icons.storefront_rounded,
                size: 18,
                color: isSelected ? cs.primary : cs.onSurfaceVariant,
              ),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  selected ?? 'كل الفروع',
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: isSelected ? cs.primary : cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(
                Icons.expand_more_rounded,
                size: 18,
                color: cs.onSurfaceVariant,
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _SortReportDropdown extends StatelessWidget {
  final PrivateLabelReportState state;

  const _SortReportDropdown({required this.state});

  String _label(PrivateLabelReportSortMode mode) {
    switch (mode) {
      case PrivateLabelReportSortMode.highestScore:
        return 'الأعلى تقييماً';
      case PrivateLabelReportSortMode.lowestScore:
        return 'الأقل تقييماً';
      case PrivateLabelReportSortMode.mostAudits:
        return 'الأكثر توثيقاً';
      case PrivateLabelReportSortMode.alphabetical:
        return 'أبجدياً';
    }
  }

  IconData _icon(PrivateLabelReportSortMode mode) {
    switch (mode) {
      case PrivateLabelReportSortMode.highestScore:
        return Icons.trending_up_rounded;
      case PrivateLabelReportSortMode.lowestScore:
        return Icons.trending_down_rounded;
      case PrivateLabelReportSortMode.mostAudits:
        return Icons.format_list_numbered_rounded;
      case PrivateLabelReportSortMode.alphabetical:
        return Icons.sort_by_alpha_rounded;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final bloc = context.read<PrivateLabelReportBloc>();

    return Theme(
      data: theme.copyWith(
        popupMenuTheme: PopupMenuThemeData(
          color: cs.surfaceContainerHigh,
          elevation: 3,
          shape: RoundedRectangleBorder(
            borderRadius: BorderRadius.circular(14),
            side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
          ),
        ),
      ),
      child: PopupMenuButton<PrivateLabelReportSortMode>(
        tooltip: 'ترتيب النتائج',
        offset: const Offset(0, 48),
        onSelected: (mode) => bloc.add(PrivateLabelReportSortModeChanged(mode)),
        itemBuilder: (context) => [
          for (final mode in PrivateLabelReportSortMode.values)
            PopupMenuItem(
              value: mode,
              child: Row(
                children: [
                  Icon(_icon(mode), size: 18, color: cs.primary),
                  const SizedBox(width: 10),
                  Expanded(
                    child: Text(
                      _label(mode),
                      style: TextStyle(
                        fontWeight: state.sortMode == mode ? FontWeight.bold : FontWeight.normal,
                      ),
                    ),
                  ),
                  if (state.sortMode == mode)
                    Icon(Icons.check_rounded, size: 18, color: cs.primary),
                ],
              ),
            ),
        ],
        child: Container(
          height: 44,
          padding: const EdgeInsets.symmetric(horizontal: 12),
          decoration: BoxDecoration(
            color: cs.surfaceContainerLow,
            borderRadius: BorderRadius.circular(14),
            border: Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            children: [
              Icon(_icon(state.sortMode), size: 18, color: cs.primary),
              const SizedBox(width: 8),
              Expanded(
                child: Text(
                  _label(state.sortMode),
                  style: theme.textTheme.labelMedium?.copyWith(
                    fontWeight: FontWeight.bold,
                    fontSize: 13,
                    color: cs.onSurface,
                  ),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                ),
              ),
              const SizedBox(width: 4),
              Icon(Icons.expand_more_rounded, size: 18, color: cs.onSurfaceVariant),
            ],
          ),
        ),
      ),
    );
  }
}

// ─────────────────────────── Branch Report Card ───────────────────────────

class _BranchCard extends StatelessWidget {
  final BranchReportData branch;
  final int rank;
  final bool isHighestSort;

  const _BranchCard({
    required this.branch,
    required this.rank,
    required this.isHighestSort,
  });

  Color _rankColor(int r, ColorScheme cs) {
    if (!isHighestSort) return cs.onSurfaceVariant;
    if (r == 1) return const Color(0xFFD4A017); // Gold
    if (r == 2) return const Color(0xFF757575); // Silver
    if (r == 3) return const Color(0xFFA0522D); // Bronze
    return cs.onSurfaceVariant;
  }

  Color _scoreColor(double s, ColorScheme cs) {
    if (s >= 80) return const Color(0xFF2E7D32);
    if (s >= 50) return const Color(0xFFE65100);
    if (s > 0) return cs.tertiary;
    return cs.outlineVariant; // Neutral for 0%
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final score = branch.achievementScore;
    final scoreColor = _scoreColor(score, cs);
    final rankColor = _rankColor(rank, cs);
    final hasScore = score > 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Start border line following card curvature cleanly
            Container(
              width: 3.5,
              color: hasScore ? scoreColor : cs.outlineVariant.withValues(alpha: 0.6),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top row: Rank, Branch name, Score Badge
                    Row(
                      children: [
                        // Rank pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: rankColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: rankColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            '#$rank',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: rankColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            branch.branchName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hasScore
                                ? scoreColor.withValues(alpha: 0.1)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasScore
                                  ? scoreColor.withValues(alpha: 0.25)
                                  : cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasScore ? Icons.trending_up_rounded : Icons.hourglass_empty_rounded,
                                size: 13,
                                color: hasScore ? scoreColor : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${score.toStringAsFixed(0)}% محقق',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: hasScore ? scoreColor : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (score / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          hasScore ? scoreColor : cs.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Bottom stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text(
                              '${branch.totalAudits} توثيق شهري',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.groups_outlined, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text(
                              '${branch.marketerNames.length} مسوقين',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Marketer tags if available
                    if (branch.marketerNames.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final name in branch.marketerNames)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.person_outline_rounded, size: 11, color: cs.primary),
                                  const SizedBox(width: 4),
                                  Text(
                                    name,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurface,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

// ─────────────────────────── Marketer Report Card ───────────────────────────

class _MarketerCard extends StatelessWidget {
  final MarketerReportData marketer;
  final int rank;
  final bool isHighestSort;

  const _MarketerCard({
    required this.marketer,
    required this.rank,
    required this.isHighestSort,
  });

  Color _rankColor(int r, ColorScheme cs) {
    if (!isHighestSort) return cs.onSurfaceVariant;
    if (r == 1) return const Color(0xFFD4A017); // Gold
    if (r == 2) return const Color(0xFF757575); // Silver
    if (r == 3) return const Color(0xFFA0522D); // Bronze
    return cs.onSurfaceVariant;
  }

  Color _scoreColor(double s, ColorScheme cs) {
    if (s >= 80) return const Color(0xFF2E7D32);
    if (s >= 50) return const Color(0xFFE65100);
    if (s > 0) return cs.tertiary;
    return cs.outlineVariant;
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final score = marketer.scorePercentage;
    final scoreColor = _scoreColor(score, cs);
    final rankColor = _rankColor(rank, cs);
    final hasScore = score > 0;

    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLow,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      child: IntrinsicHeight(
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            // Start border line following card curvature cleanly
            Container(
              width: 3.5,
              color: hasScore ? scoreColor : cs.outlineVariant.withValues(alpha: 0.6),
            ),
            Expanded(
              child: Padding(
                padding: const EdgeInsets.fromLTRB(14, 12, 14, 12),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.stretch,
                  children: [
                    // Top row: Rank, Marketer name, Score Badge
                    Row(
                      children: [
                        // Rank pill
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                          decoration: BoxDecoration(
                            color: rankColor.withValues(alpha: 0.1),
                            borderRadius: BorderRadius.circular(6),
                            border: Border.all(color: rankColor.withValues(alpha: 0.35)),
                          ),
                          child: Text(
                            '#$rank',
                            style: theme.textTheme.labelSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              fontSize: 11,
                              color: rankColor,
                            ),
                          ),
                        ),
                        const SizedBox(width: 8),
                        Expanded(
                          child: Text(
                            marketer.delegateName,
                            style: theme.textTheme.titleSmall?.copyWith(
                              fontWeight: FontWeight.bold,
                              color: cs.onSurface,
                            ),
                            maxLines: 1,
                            overflow: TextOverflow.ellipsis,
                          ),
                        ),
                        const SizedBox(width: 8),
                        Container(
                          padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                          decoration: BoxDecoration(
                            color: hasScore
                                ? scoreColor.withValues(alpha: 0.1)
                                : cs.surfaceContainerHighest,
                            borderRadius: BorderRadius.circular(8),
                            border: Border.all(
                              color: hasScore
                                  ? scoreColor.withValues(alpha: 0.25)
                                  : cs.outlineVariant.withValues(alpha: 0.4),
                            ),
                          ),
                          child: Row(
                            mainAxisSize: MainAxisSize.min,
                            children: [
                              Icon(
                                hasScore ? Icons.trending_up_rounded : Icons.hourglass_empty_rounded,
                                size: 13,
                                color: hasScore ? scoreColor : cs.onSurfaceVariant,
                              ),
                              const SizedBox(width: 4),
                              Text(
                                '${score.toStringAsFixed(0)}% إنجاز',
                                style: theme.textTheme.labelSmall?.copyWith(
                                  fontWeight: FontWeight.bold,
                                  color: hasScore ? scoreColor : cs.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 8),

                    // Progress bar
                    ClipRRect(
                      borderRadius: BorderRadius.circular(3),
                      child: LinearProgressIndicator(
                        value: (score / 100).clamp(0.0, 1.0),
                        minHeight: 5,
                        backgroundColor: cs.surfaceContainerHighest,
                        valueColor: AlwaysStoppedAnimation<Color>(
                          hasScore ? scoreColor : cs.outlineVariant,
                        ),
                      ),
                    ),
                    const SizedBox(height: 10),

                    // Bottom stats
                    Row(
                      mainAxisAlignment: MainAxisAlignment.spaceBetween,
                      children: [
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.event_available_rounded, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text(
                              '${marketer.kpi.completedDays} من ${marketer.kpi.daysInMonth} يوم شهرياً',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                        Row(
                          mainAxisSize: MainAxisSize.min,
                          children: [
                            Icon(Icons.photo_library_outlined, size: 14, color: cs.onSurfaceVariant),
                            const SizedBox(width: 5),
                            Text(
                              '${marketer.totalAudits} توثيق',
                              style: theme.textTheme.labelSmall?.copyWith(
                                color: cs.onSurfaceVariant,
                                fontWeight: FontWeight.w500,
                              ),
                            ),
                          ],
                        ),
                      ],
                    ),

                    // Branches covered
                    if (marketer.branchNames.isNotEmpty) ...[
                      const SizedBox(height: 8),
                      Wrap(
                        spacing: 6,
                        runSpacing: 4,
                        children: [
                          for (final branch in marketer.branchNames)
                            Container(
                              padding: const EdgeInsets.symmetric(horizontal: 7, vertical: 2.5),
                              decoration: BoxDecoration(
                                color: cs.surfaceContainerHighest.withValues(alpha: 0.6),
                                borderRadius: BorderRadius.circular(6),
                                border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.4)),
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Icon(Icons.storefront_outlined, size: 11, color: cs.secondary),
                                  const SizedBox(width: 4),
                                  Text(
                                    branch,
                                    style: theme.textTheme.labelSmall?.copyWith(
                                      color: cs.onSurface,
                                      fontSize: 11,
                                    ),
                                  ),
                                ],
                              ),
                            ),
                        ],
                      ),
                    ],
                  ],
                ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class _Empty extends StatelessWidget {
  final IconData icon;
  final Color iconColor;
  final String title;

  const _Empty({required this.icon, required this.iconColor, required this.title});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 52, color: iconColor.withValues(alpha: 0.7)),
            const SizedBox(height: 12),
            Text(
              title,
              textAlign: TextAlign.center,
              style: theme.textTheme.bodyLarge?.copyWith(color: theme.colorScheme.onSurfaceVariant),
            ),
          ],
        ),
      ),
    );
  }
}
