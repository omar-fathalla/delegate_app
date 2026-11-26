// Web-only desktop attendance tab (>= 840dp): existing filters on top, then a
// table. Reads the shared HRAttendanceTab state through its viewBuilder hook;
// no query or filter logic lives here.
import 'package:material_ui/material_ui.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class AdminDesktopAttendanceWeb extends StatelessWidget {
  final Delegate hrDelegate;
  const AdminDesktopAttendanceWeb({super.key, required this.hrDelegate});

  @override
  Widget build(BuildContext context) => HRAttendanceTab(
        hrDelegate: hrDelegate,
        viewBuilder: (context, data) => AttendanceDesktopTableWeb(data: data),
      );
}

class AttendanceDesktopTableWeb extends StatelessWidget {
  final HRAttendanceViewData data;
  const AttendanceDesktopTableWeb({super.key, required this.data});

  static const _statuses = <String, String>{
    'all': 'الكل',
    'present': 'حاضر',
    'departed': 'انصرف',
    'leave': 'إجازة',
    'absent': 'غائب',
    'violation': 'مخالفة',
  };

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        _FilterBar(data: data),
        Divider(height: 1, color: cs.outlineVariant),
        Expanded(child: _body(context)),
      ],
    );
  }

  Widget _body(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    if (data.isLoading) return const Center(child: CircularProgressIndicator());
    if (data.errorMessage != null) {
      return Center(
        child: Text(data.errorMessage!,
            style: tt.bodyLarge?.copyWith(color: cs.error)),
      );
    }
    if (data.records.isEmpty) {
      return Center(
        child: Column(mainAxisSize: MainAxisSize.min, children: [
          Icon(Symbols.event_busy_rounded, size: 56, color: cs.onSurfaceVariant),
          const SizedBox(height: 12),
          Text('لا توجد سجلات', style: tt.titleMedium?.copyWith(color: cs.onSurfaceVariant)),
        ]),
      );
    }
    final fmt = DateFormat('hh:mm a', 'ar');
    String t(DateTime? d) => d == null ? '—' : fmt.format(d);
    return SingleChildScrollView(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, c) => ConstrainedBox(
          constraints: BoxConstraints(minWidth: c.maxWidth),
          child: DataTable(
            showCheckboxColumn: false,
            headingTextStyle: tt.titleSmall?.copyWith(color: cs.onSurfaceVariant),
            dataTextStyle: tt.bodyMedium?.copyWith(color: cs.onSurface),
            dataRowColor: WidgetStateProperty.resolveWith((s) =>
                s.contains(WidgetState.hovered) ? cs.surfaceContainerHighest : null),
            columns: const [
              DataColumn(label: Text('المندوب')),
              DataColumn(label: Text('الدخول')),
              DataColumn(label: Text('الخروج')),
              DataColumn(label: Text('الحالة')),
            ],
            rows: [
              for (final r in data.records)
                DataRow(
                  // Non-null so rows get hover feedback; no action/behaviour.
                  onSelectChanged: (_) {},
                  cells: [
                    DataCell(Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        Text(r.delegate.fullName),
                        if ((r.branchName ?? '').isNotEmpty)
                          Text(r.branchName!,
                              style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant)),
                      ],
                    )),
                    DataCell(Text(t(r.checkInTime))),
                    DataCell(Text(t(r.checkOutTime))),
                    DataCell(AttendanceStatusChipWeb(record: r)),
                  ],
                ),
            ],
          ),
        ),
      ),
    );
  }
}

/// Status pill. Absence uses error/errorContainer only.
class AttendanceStatusChipWeb extends StatelessWidget {
  final HRAttendanceRecord record;
  const AttendanceStatusChipWeb({super.key, required this.record});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final r = record;
    late final String label;
    late final Color bg, fg;
    late final IconData icon;
    if (r.isOnLeave) {
      (label, bg, fg, icon) = ('إجازة', cs.tertiaryContainer, cs.onTertiaryContainer, Symbols.beach_access_rounded);
    } else if (r.isAbsent) {
      (label, bg, fg, icon) = ('غائب', cs.errorContainer, cs.onErrorContainer, Symbols.person_off_rounded);
    } else if (r.isDeparted) {
      (label, bg, fg, icon) = ('انصرف', cs.secondaryContainer, cs.onSecondaryContainer, Symbols.logout_rounded);
    } else {
      (label, bg, fg, icon) = ('حاضر', cs.primaryContainer, cs.onPrimaryContainer, Symbols.check_circle_rounded);
    }
    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 4),
      decoration: BoxDecoration(color: bg, borderRadius: BorderRadius.circular(8)),
      child: Row(mainAxisSize: MainAxisSize.min, children: [
        Icon(icon, size: 16, color: fg, fill: 1),
        const SizedBox(width: 6),
        Text(label, style: TextStyle(color: fg, fontWeight: FontWeight.w600)),
      ]),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final HRAttendanceViewData data;
  const _FilterBar({required this.data});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final d = data;
    Widget dropdown(String label, String value, Set<String> opts, ValueChanged<String> on) =>
        SizedBox(
          width: 200,
          child: DropdownButtonFormField<String>(
            initialValue: opts.contains(value) || value == 'all' ? value : 'all',
            isExpanded: true,
            decoration: InputDecoration(labelText: label, isDense: true,
                border: const OutlineInputBorder()),
            items: [
              const DropdownMenuItem(value: 'all', child: Text('الكل')),
              for (final o in (opts.toList()..sort()))
                DropdownMenuItem(value: o, child: Text(o, overflow: TextOverflow.ellipsis)),
            ],
            onChanged: (v) => on(v ?? 'all'),
          ),
        );
    final rtl = Directionality.of(context) == TextDirection.rtl;
    // Drawn in LTR so RTL does not mirror a chevron that was already chosen.
    // Previous points toward the past: right in RTL, left in LTR.
    Widget dayChevron(bool previous) => Icon(
          previous
              ? (rtl ? Symbols.chevron_right_rounded : Symbols.chevron_left_rounded)
              : (rtl ? Symbols.chevron_left_rounded : Symbols.chevron_right_rounded),
          textDirection: TextDirection.ltr,
        );
    return Padding(
      padding: const EdgeInsets.all(16),
      child: Wrap(
        spacing: 12,
        runSpacing: 12,
        crossAxisAlignment: WrapCrossAlignment.center,
        children: [
          Row(mainAxisSize: MainAxisSize.min, children: [
            IconButton(
              tooltip: 'اليوم السابق',
              icon: dayChevron(true),
              onPressed: () => d.onDateChanged(d.selectedDate.subtract(const Duration(days: 1))),
            ),
            // Fixed width so the Wrap does not reflow when the date label changes.
            SizedBox(
              key: const ValueKey('attendance_date_button'),
              width: 230,
              child: TextButton.icon(
              icon: const Icon(Symbols.calendar_month_rounded),
              label: Text(DateFormat('EEEE d MMMM yyyy', 'ar').format(d.selectedDate),
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: tt.titleSmall?.copyWith(color: cs.onSurface)),
              onPressed: () async {
                final picked = await showDatePicker(
                  context: context,
                  initialDate: d.selectedDate,
                  firstDate: DateTime(2020),
                  lastDate: DateTime.now(),
                );
                if (picked != null) d.onDateChanged(picked);
              },
            ),
            ),
            IconButton(
              tooltip: 'اليوم التالي',
              icon: dayChevron(false),
              onPressed: d.isToday
                  ? null
                  : () => d.onDateChanged(d.selectedDate.add(const Duration(days: 1))),
            ),
          ]),
          SegmentedButton<String>(
            showSelectedIcon: false,
            segments: [
              for (final e in AttendanceDesktopTableWeb._statuses.entries)
                ButtonSegment(value: e.key, label: Text(e.value)),
            ],
            selected: {d.statusFilter},
            onSelectionChanged: (s) => d.onStatusChanged(s.first),
          ),
          dropdown('السلسلة', d.selectedChain, d.chains, d.onChainChanged),
          dropdown('الفرع', d.selectedBranch, d.branches, d.onBranchChanged),
          SizedBox(
            width: 240,
            child: TextField(
              controller: d.searchController,
              onChanged: (_) => d.onSearchChanged(),
              decoration: const InputDecoration(
                isDense: true,
                prefixIcon: Icon(Symbols.search_rounded),
                hintText: 'بحث بالاسم أو الهاتف أو الفرع',
                border: OutlineInputBorder(),
              ),
            ),
          ),
          IconButton(
            tooltip: 'تحديث',
            icon: const Icon(Symbols.refresh_rounded),
            onPressed: d.onRefresh,
          ),
        ],
      ),
    );
  }
}
