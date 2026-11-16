// WEB-ONLY: «حضور النهاردة» card of the HR overview. Pure view over the
// attendance tab's records; filtering, sorting and paging happen here.
import 'package:flutter/material.dart';

import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/services/branch_display_cache.dart';
import 'package:delegate_app/core/widgets/app_avatar.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_attendance_tab.dart';
import 'package:delegate_app/web/hr_system/hr_home_side_cards_web.dart';

/// M3 window size classes used by the overview.
enum HrWindowClass { compact, medium, expanded }

HrWindowClass hrWindowClassOf(double width) => width < 600
    ? HrWindowClass.compact
    : width < 840
    ? HrWindowClass.medium
    : HrWindowClass.expanded;

enum HrPresenceFilter { all, present, departed }

enum HrAttendanceCardState { loading, error, empty, data }

const int kHrTableRowsPerPage = 10;
const int kHrListPreviewRows = 6;

String hrFormatTime(DateTime t) {
  final h = t.hour % 12 == 0 ? 12 : t.hour % 12;
  final m = t.minute.toString().padLeft(2, '0');
  return '$h:$m ${t.hour < 12 ? 'ص' : 'م'}';
}

String hrFormatDuration(Duration d) {
  if (d.isNegative) d = Duration.zero;
  final m = d.inMinutes.remainder(60).toString().padLeft(2, '0');
  return '${d.inHours}:$m';
}

/// Short code shown under the error text.
String hrAttendanceErrorCode(String message) {
  final lower = message.toLowerCase();
  for (final code in [
    'permission-denied',
    'unavailable',
    'deadline-exceeded',
    'unauthenticated',
    'not-found',
  ]) {
    if (lower.contains(code)) return code;
  }
  return 'HR-ATT-LOAD';
}

/// Chain a record belongs to: the check-in branch's chain, then the
/// delegate's organization.
String hrRecordChain(HRAttendanceRecord r, Map<String, Branch> branches) {
  final b = r.branchName == null
      ? null
      : branches[r.branchName!.trim().toLowerCase()];
  final org = b?.organizationName?.trim() ?? '';
  if (org.isNotEmpty) return org;
  return r.delegate.organizationName.trim();
}

/// Same chain match as the attendance tab's chain filter.
bool hrRecordInChain(
  HRAttendanceRecord r,
  String chain,
  Map<String, Branch> branches,
) {
  final c = chain.trim();
  final d = r.delegate;
  if (d.organizationName.trim() == c) return true;
  if (d.allOrganizationNames.any((o) => o.trim() == c)) return true;
  final b = r.branchName == null
      ? null
      : branches[r.branchName!.trim().toLowerCase()];
  return b?.organizationName?.trim() == c;
}

String hrBranchLabel(String? name) {
  final raw = name?.trim() ?? '';
  if (raw.isEmpty) return '—';
  final cache = BranchDisplayCache.instance;
  return cache.isLoaded ? cache.displayName(raw, fallback: raw) : raw;
}

/// Counts and rows derived from the day's records and the active filters.
class HrAttendanceSummary {
  final int total;
  final int attended;
  final int present;
  final int departed;
  final List<HRAttendanceRecord> absent;
  final List<HRAttendanceRecord> rows;

  const HrAttendanceSummary({
    required this.total,
    required this.attended,
    required this.present,
    required this.departed,
    required this.absent,
    required this.rows,
  });

  factory HrAttendanceSummary.compute({
    required List<HRAttendanceRecord> records,
    required Map<String, Branch> branches,
    required HrPresenceFilter presence,
    required String? chain,
    required String query,
  }) {
    final attended = records.where((r) => r.checkInTime != null).toList();
    final q = query.trim().toLowerCase();
    final rows = attended.where((r) {
      if (presence == HrPresenceFilter.present && !r.isPresent) return false;
      if (presence == HrPresenceFilter.departed && !r.isDeparted) return false;
      if (chain != null && !hrRecordInChain(r, chain, branches)) return false;
      if (q.isEmpty) return true;
      return r.delegate.fullName.toLowerCase().contains(q) ||
          r.delegate.delegatePublicId.toLowerCase().contains(q);
    }).toList()..sort((a, b) => a.checkInTime!.compareTo(b.checkInTime!));
    return HrAttendanceSummary(
      total: records.length,
      attended: attended.length,
      present: attended.where((r) => r.isPresent).length,
      departed: attended.where((r) => r.isDeparted).length,
      absent: records.where((r) => r.isAbsent && !r.isOnLeave).toList(),
      rows: rows,
    );
  }
}

class HrHomeAttendanceCard extends StatelessWidget {
  final HrAttendanceCardState state;
  final HrAttendanceSummary summary;
  final HrWindowClass windowClass;
  final bool showTable;
  final String? errorMessage;
  final DateTime now;
  final Map<String, Branch> branches;
  final List<String> chains;

  final HrPresenceFilter presence;
  final String? chain;
  final TextEditingController search;
  final int page;
  final bool showAllRows;

  final ValueChanged<HrPresenceFilter> onPresenceChanged;
  final ValueChanged<String?> onChainChanged;
  final VoidCallback onSearchChanged;
  final ValueChanged<int> onPageChanged;
  final VoidCallback onToggleShowAll;
  final VoidCallback onOpenAbsent;
  final VoidCallback onOpenAttendanceLog;
  final VoidCallback onOpenDelegates;
  final VoidCallback onRetry;
  final ValueChanged<HRAttendanceRecord> onOpenRecord;

  const HrHomeAttendanceCard({
    super.key,
    required this.state,
    required this.summary,
    required this.windowClass,
    required this.showTable,
    required this.errorMessage,
    required this.now,
    required this.branches,
    required this.chains,
    required this.presence,
    required this.chain,
    required this.search,
    required this.page,
    required this.showAllRows,
    required this.onPresenceChanged,
    required this.onChainChanged,
    required this.onSearchChanged,
    required this.onPageChanged,
    required this.onToggleShowAll,
    required this.onOpenAbsent,
    required this.onOpenAttendanceLog,
    required this.onOpenDelegates,
    required this.onRetry,
    required this.onOpenRecord,
  });

  bool get _compact => windowClass == HrWindowClass.compact;
  bool get _enabled =>
      state == HrAttendanceCardState.data ||
      state == HrAttendanceCardState.empty;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return HrOverviewCard(
      key: const ValueKey('hr_home_attendance_card'),
      padding: EdgeInsets.all(_compact ? 16 : 24),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          HrCardTitle(
            icon: Icons.how_to_reg_rounded,
            text: 'حضور النهاردة',
            fontSize: _compact ? 19 : 22,
            trailing: TextButton.icon(
              key: const ValueKey('hr_home_attendance_log_link'),
              onPressed: onOpenAttendanceLog,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: const StadiumBorder(),
              ).copyWith(overlayColor: hrStateLayer(cs.primary)),
              icon: const M3DirIcon(Icons.arrow_forward_rounded, size: 18),
              label: const Text(
                'كل سجل الحضور',
                style: TextStyle(fontSize: 14, fontWeight: FontWeight.w600),
              ),
            ),
          ),
          if (state == HrAttendanceCardState.loading)
            const M3DelayedLoading(
              key: ValueKey('hr_home_loading_bar'),
              delay: AppMotionDurations.medium2,
              child: Padding(
                padding: EdgeInsets.only(top: 8),
                child: LinearProgressIndicator(minHeight: 4),
              ),
            ),
          SizedBox(height: _compact ? 12 : 16),
          _StatsRow(
            state: state,
            summary: summary,
            compact: _compact,
            onOpenAbsent: onOpenAbsent,
          ),
          SizedBox(height: _compact ? 12 : 20),
          _FilterBar(
            enabled: _enabled,
            compact: _compact,
            inline: windowClass == HrWindowClass.expanded,
            summary: summary,
            chains: chains,
            presence: presence,
            chain: chain,
            search: search,
            onPresenceChanged: onPresenceChanged,
            onChainChanged: onChainChanged,
            onSearchChanged: onSearchChanged,
          ),
          const SizedBox(height: 16),
          _body(context),
        ],
      ),
    );
  }

  Widget _body(BuildContext context) {
    switch (state) {
      case HrAttendanceCardState.loading:
        return const M3DelayedLoading(
          key: ValueKey('hr_home_skeleton'),
          delay: AppMotionDurations.medium2,
          child: _SkeletonRows(),
        );
      case HrAttendanceCardState.error:
        return _ErrorPanel(message: errorMessage ?? '', onRetry: onRetry);
      case HrAttendanceCardState.empty:
        return _EmptyPanel(onOpenDelegates: onOpenDelegates);
      case HrAttendanceCardState.data:
        if (summary.rows.isEmpty) return const _NoMatches();
        return showTable
            ? _AttendanceTable(
                rows: summary.rows,
                page: page,
                now: now,
                branches: branches,
                onPageChanged: onPageChanged,
                onOpenRecord: onOpenRecord,
              )
            : _AttendanceList(
                rows: summary.rows,
                showAll: showAllRows,
                now: now,
                branches: branches,
                onToggleShowAll: onToggleShowAll,
                onOpenRecord: onOpenRecord,
              );
    }
  }
}

// ───────────────────────── Stats ─────────────────────────

class _StatsRow extends StatelessWidget {
  final HrAttendanceCardState state;
  final HrAttendanceSummary summary;
  final bool compact;
  final VoidCallback onOpenAbsent;

  const _StatsRow({
    required this.state,
    required this.summary,
    required this.compact,
    required this.onOpenAbsent,
  });

  @override
  Widget build(BuildContext context) {
    final known =
        state == HrAttendanceCardState.data ||
        state == HrAttendanceCardState.empty;
    final ratio = summary.total == 0 ? 0.0 : summary.attended / summary.total;
    final gap = compact ? 8.0 : 12.0;
    return IntrinsicHeight(
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          Expanded(
            child: _StatTile(
              key: const ValueKey('hr_home_stat_total'),
              compact: compact,
              icon: Icons.groups_rounded,
              label: 'إجمالي المناديب',
              value: known ? '${summary.total}' : '—',
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _StatTile(
              key: const ValueKey('hr_home_stat_present'),
              compact: compact,
              icon: Icons.how_to_reg_rounded,
              label: 'حضروا',
              value: known ? '${summary.attended}' : '—',
              suffix: known ? 'من ${summary.total}' : null,
              footer: Row(
                children: [
                  Expanded(
                    child: ClipRRect(
                      borderRadius: BorderRadius.circular(4),
                      child: LinearProgressIndicator(
                        key: const ValueKey('hr_home_present_progress'),
                        value: known ? ratio : 0,
                        minHeight: 6,
                      ),
                    ),
                  ),
                  const SizedBox(width: 8),
                  Text(
                    known ? '${(ratio * 100).round()}%' : '—',
                    style: TextStyle(
                      fontSize: 12,
                      fontWeight: FontWeight.w700,
                      color: Theme.of(context).colorScheme.primary,
                      fontFeatures: kHrTabularFigures,
                    ),
                  ),
                ],
              ),
            ),
          ),
          SizedBox(width: gap),
          Expanded(
            child: _StatTile(
              key: const ValueKey('hr_home_stat_absent'),
              compact: compact,
              icon: state == HrAttendanceCardState.empty
                  ? Icons.hourglass_empty_rounded
                  : Icons.person_off_outlined,
              label: state == HrAttendanceCardState.empty
                  ? 'لسه مسجلوش'
                  : 'غايبين',
              value: known ? '${summary.absent.length}' : '—',
              onTap:
                  state == HrAttendanceCardState.data &&
                      summary.absent.isNotEmpty
                  ? onOpenAbsent
                  : null,
            ),
          ),
        ],
      ),
    );
  }
}

class _StatTile extends StatelessWidget {
  final bool compact;
  final IconData icon;
  final String label;
  final String value;
  final String? suffix;
  final Widget? footer;
  final VoidCallback? onTap;

  const _StatTile({
    super.key,
    required this.compact,
    required this.icon,
    required this.label,
    required this.value,
    this.suffix,
    this.footer,
    this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final content = Padding(
      padding: EdgeInsets.all(compact ? 12 : 16),
      child: Column(
        crossAxisAlignment: CrossAxisAlignment.start,
        mainAxisSize: MainAxisSize.min,
        children: [
          Row(
            children: [
              Icon(icon, size: compact ? 16 : 20, color: cs.onSurfaceVariant),
              const SizedBox(width: 6),
              Expanded(
                child: Text(
                  label,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: compact ? 12 : 13,
                    fontWeight: FontWeight.w600,
                    color: cs.onSurfaceVariant,
                  ),
                ),
              ),
              if (onTap != null)
                M3DirIcon(
                  Icons.chevron_right_rounded,
                  size: 18,
                  color: cs.onSurfaceVariant,
                ),
            ],
          ),
          SizedBox(height: compact ? 4 : 8),
          FittedBox(
            fit: BoxFit.scaleDown,
            alignment: AlignmentDirectional.centerStart,
            child: Row(
              crossAxisAlignment: CrossAxisAlignment.baseline,
              textBaseline: TextBaseline.alphabetic,
              children: [
                Text(
                  value,
                  style: TextStyle(
                    fontSize: compact ? 22 : 30,
                    height: 1.2,
                    fontWeight: FontWeight.w700,
                    color: cs.onSurface,
                    fontFeatures: kHrTabularFigures,
                  ),
                ),
                if (suffix != null) ...[
                  const SizedBox(width: 6),
                  Text(
                    suffix!,
                    style: TextStyle(
                      fontSize: compact ? 12 : 15,
                      fontWeight: FontWeight.w600,
                      color: cs.onSurfaceVariant,
                      fontFeatures: kHrTabularFigures,
                    ),
                  ),
                ],
              ],
            ),
          ),
          if (footer != null) ...[SizedBox(height: compact ? 6 : 10), footer!],
        ],
      ),
    );
    return Material(
      color: cs.surfaceContainerLowest,
      borderRadius: BorderRadius.circular(20),
      clipBehavior: Clip.antiAlias,
      child: onTap == null
          ? content
          : InkWell(
              onTap: onTap,
              overlayColor: hrStateLayer(cs.onSurface),
              child: content,
            ),
    );
  }
}

// ───────────────────────── Filters ─────────────────────────

class _FilterBar extends StatelessWidget {
  final bool enabled;
  final bool compact;
  final bool inline;
  final HrAttendanceSummary summary;
  final List<String> chains;
  final HrPresenceFilter presence;
  final String? chain;
  final TextEditingController search;
  final ValueChanged<HrPresenceFilter> onPresenceChanged;
  final ValueChanged<String?> onChainChanged;
  final VoidCallback onSearchChanged;

  const _FilterBar({
    required this.enabled,
    required this.compact,
    required this.inline,
    required this.summary,
    required this.chains,
    required this.presence,
    required this.chain,
    required this.search,
    required this.onPresenceChanged,
    required this.onChainChanged,
    required this.onSearchChanged,
  });

  @override
  Widget build(BuildContext context) {
    final chips = <Widget>[
      _chip(context, HrPresenceFilter.all, 'الكل', summary.attended),
      _chip(context, HrPresenceFilter.present, 'لسه موجود', summary.present),
      _chip(context, HrPresenceFilter.departed, 'انصرف', summary.departed),
      _ChainFilterChip(
        enabled: enabled,
        chains: chains,
        selected: chain,
        onChanged: onChainChanged,
      ),
    ];
    final field = _SearchField(
      controller: search,
      enabled: enabled,
      onChanged: onSearchChanged,
    );
    if (inline) {
      return Row(
        children: [
          Expanded(child: Wrap(spacing: 8, runSpacing: 8, children: chips)),
          const SizedBox(width: 12),
          SizedBox(width: 280, child: field),
        ],
      );
    }
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        if (compact)
          SingleChildScrollView(
            key: const ValueKey('hr_home_chip_scroller'),
            scrollDirection: Axis.horizontal,
            child: Row(
              children: [
                for (var i = 0; i < chips.length; i++) ...[
                  if (i > 0) const SizedBox(width: 8),
                  chips[i],
                ],
              ],
            ),
          )
        else
          Wrap(spacing: 8, runSpacing: 8, children: chips),
        const SizedBox(height: 12),
        field,
      ],
    );
  }

  Widget _chip(
    BuildContext context,
    HrPresenceFilter value,
    String label,
    int count,
  ) {
    final cs = Theme.of(context).colorScheme;
    final selected = presence == value;
    return FilterChip(
      key: ValueKey('hr_home_filter_${value.name}'),
      label: Text(enabled ? '$label  $count' : label),
      labelStyle: TextStyle(
        fontSize: 13,
        fontWeight: FontWeight.w600,
        fontFeatures: kHrTabularFigures,
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
      selected: selected,
      showCheckmark: selected,
      checkmarkColor: cs.onSecondaryContainer,
      selectedColor: cs.secondaryContainer,
      backgroundColor: cs.surfaceContainerLowest,
      side: BorderSide(
        color: selected ? Colors.transparent : cs.outlineVariant,
      ),
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(8)),
      materialTapTargetSize: MaterialTapTargetSize.padded,
      onSelected: enabled ? (_) => onPresenceChanged(value) : null,
    );
  }
}

class _ChainFilterChip extends StatelessWidget {
  final bool enabled;
  final List<String> chains;
  final String? selected;
  final ValueChanged<String?> onChanged;

  const _ChainFilterChip({
    required this.enabled,
    required this.chains,
    required this.selected,
    required this.onChanged,
  });

  static const String _all = '__all__';

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final active = selected != null;
    final fg = active ? cs.onSecondaryContainer : cs.onSurfaceVariant;
    return PopupMenuButton<String>(
      key: const ValueKey('hr_home_filter_chain'),
      enabled: enabled && chains.isNotEmpty,
      tooltip: 'فلترة حسب السلسلة',
      color: cs.surfaceContainerHigh,
      elevation: 3,
      position: PopupMenuPosition.under,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (v) => onChanged(v == _all ? null : v),
      itemBuilder: (context) => [
        _item(context, _all, 'كل السلاسل', null, selected == null),
        for (final c in chains) _item(context, c, c, c, selected == c),
      ],
      child: Container(
        height: 48,
        alignment: Alignment.center,
        child: Container(
          height: 32,
          padding: const EdgeInsetsDirectional.only(start: 8, end: 6),
          decoration: BoxDecoration(
            color: active ? cs.secondaryContainer : cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(8),
            border: active ? null : Border.all(color: cs.outlineVariant),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              if (active)
                HrChainAvatar(chain: selected!, size: 20)
              else
                Icon(Icons.storefront_outlined, size: 18, color: fg),
              const SizedBox(width: 6),
              Text(
                selected ?? 'السلسلة',
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w600,
                  color: enabled ? fg : fg.withValues(alpha: 0.38),
                ),
              ),
              const SizedBox(width: 2),
              Icon(Icons.expand_more_rounded, size: 18, color: fg),
            ],
          ),
        ),
      ),
    );
  }

  PopupMenuItem<String> _item(
    BuildContext context,
    String value,
    String label,
    String? chain,
    bool isSelected,
  ) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuItem<String>(
      value: value,
      height: 48,
      child: Row(
        children: [
          if (chain == null)
            Icon(Icons.storefront_rounded, size: 22, color: cs.primary)
          else
            HrChainAvatar(chain: chain, size: 24),
          const SizedBox(width: 12),
          Expanded(
            child: Text(
              label,
              style: TextStyle(
                fontSize: 14,
                fontWeight: isSelected ? FontWeight.w700 : FontWeight.w500,
              ),
            ),
          ),
          if (isSelected)
            Icon(Icons.check_rounded, size: 20, color: cs.primary),
        ],
      ),
    );
  }
}

class _SearchField extends StatelessWidget {
  final TextEditingController controller;
  final bool enabled;
  final VoidCallback onChanged;

  const _SearchField({
    required this.controller,
    required this.enabled,
    required this.onChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final border = OutlineInputBorder(
      borderRadius: BorderRadius.circular(999),
      borderSide: BorderSide(color: cs.outlineVariant),
    );
    return SizedBox(
      height: 48,
      child: TextField(
        key: const ValueKey('hr_home_search'),
        controller: controller,
        enabled: enabled,
        onChanged: (_) => onChanged(),
        style: const TextStyle(fontSize: 14, fontWeight: FontWeight.normal),
        textAlignVertical: TextAlignVertical.center,
        decoration: InputDecoration(
          isDense: true,
          filled: true,
          fillColor: cs.surfaceContainerLowest,
          hintText: 'ابحث بالاسم أو الكود',
          hintStyle: TextStyle(
            fontSize: 14,
            fontWeight: FontWeight.normal,
            color: cs.onSurfaceVariant.withValues(alpha: 0.7),
          ),
          prefixIcon: Icon(Icons.search_rounded, color: cs.onSurfaceVariant),
          suffixIcon: controller.text.isEmpty
              ? null
              : IconButton(
                  tooltip: 'مسح البحث',
                  icon: const Icon(Icons.close_rounded),
                  onPressed: () {
                    controller.clear();
                    onChanged();
                  },
                ),
          contentPadding: const EdgeInsets.symmetric(horizontal: 16),
          border: border,
          enabledBorder: border,
          disabledBorder: border.copyWith(
            borderSide: BorderSide(
              color: cs.outlineVariant.withValues(alpha: 0.5),
            ),
          ),
          focusedBorder: border.copyWith(
            borderSide: BorderSide(color: cs.primary, width: 2),
          ),
        ),
      ),
    );
  }
}

// ───────────────────────── Rows ─────────────────────────

class _TimeText extends StatelessWidget {
  final String text;
  final Color? color;
  final FontWeight weight;

  const _TimeText(this.text, {this.color, this.weight = FontWeight.w500});

  @override
  Widget build(BuildContext context) => Text(
    text,
    maxLines: 1,
    style: TextStyle(
      fontSize: 15,
      fontWeight: weight,
      color: color ?? Theme.of(context).colorScheme.onSurface,
      fontFeatures: kHrTabularFigures,
    ),
  );
}

class _StillHere extends StatelessWidget {
  const _StillHere();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      mainAxisSize: MainAxisSize.min,
      children: [
        Container(
          width: 8,
          height: 8,
          decoration: BoxDecoration(color: cs.primary, shape: BoxShape.circle),
        ),
        const SizedBox(width: 6),
        Flexible(
          child: Text(
            'لسه موجود',
            maxLines: 1,
            overflow: TextOverflow.ellipsis,
            style: TextStyle(
              fontSize: 13,
              fontWeight: FontWeight.w700,
              color: cs.primary,
            ),
          ),
        ),
      ],
    );
  }
}

Duration? _rowDuration(HRAttendanceRecord r, DateTime now) {
  final inAt = r.checkInTime;
  if (inAt == null) return null;
  if (r.isPresent) return now.difference(inAt);
  return r.duration;
}

class _DelegateCell extends StatelessWidget {
  final HRAttendanceRecord record;

  const _DelegateCell(this.record);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final d = record.delegate;
    final code = d.delegatePublicId.trim();
    return Row(
      children: [
        AppAvatar(
          imageUrl: d.personalPhotoUrl,
          fallbackText: d.fullName.isNotEmpty ? d.fullName : '؟',
          radius: 18,
        ),
        const SizedBox(width: 12),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                d.fullName,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 15,
                  fontWeight: FontWeight.w600,
                  color: cs.onSurface,
                ),
              ),
              if (code.isNotEmpty)
                Text(
                  code,
                  maxLines: 1,
                  overflow: TextOverflow.ellipsis,
                  style: TextStyle(
                    fontSize: 13,
                    color: cs.onSurfaceVariant,
                    fontFeatures: kHrTabularFigures,
                  ),
                ),
            ],
          ),
        ),
      ],
    );
  }
}

class _ChainCell extends StatelessWidget {
  final String chain;
  final String branch;

  const _ChainCell({required this.chain, required this.branch});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Row(
      children: [
        HrChainAvatar(chain: chain, size: 32),
        const SizedBox(width: 10),
        Expanded(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text(
                chain.isEmpty ? '—' : chain,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: 13,
                  fontWeight: FontWeight.w700,
                  color: cs.onSurface,
                ),
              ),
              Text(
                branch,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(fontSize: 13, color: cs.onSurfaceVariant),
              ),
            ],
          ),
        ),
      ],
    );
  }
}

const List<int> _kColumnFlex = [5, 5, 2, 3, 2];

class _AttendanceTable extends StatelessWidget {
  final List<HRAttendanceRecord> rows;
  final int page;
  final DateTime now;
  final Map<String, Branch> branches;
  final ValueChanged<int> onPageChanged;
  final ValueChanged<HRAttendanceRecord> onOpenRecord;

  const _AttendanceTable({
    required this.rows,
    required this.page,
    required this.now,
    required this.branches,
    required this.onPageChanged,
    required this.onOpenRecord,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final pages = (rows.length / kHrTableRowsPerPage).ceil();
    final current = page.clamp(0, pages - 1);
    final start = current * kHrTableRowsPerPage;
    final end = (start + kHrTableRowsPerPage).clamp(0, rows.length);
    final headerStyle = TextStyle(
      fontSize: 13,
      fontWeight: FontWeight.w700,
      color: cs.onSurfaceVariant,
    );
    Widget cells(List<Widget> children) => Row(
      children: [
        for (var i = 0; i < children.length; i++) ...[
          if (i > 0) const SizedBox(width: 12),
          Expanded(flex: _kColumnFlex[i], child: children[i]),
        ],
      ],
    );
    return Container(
      key: const ValueKey('hr_home_attendance_table'),
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
        border: Border.all(color: cs.outlineVariant.withValues(alpha: 0.6)),
      ),
      child: Column(
        children: [
          Container(
            height: 48,
            padding: const EdgeInsets.symmetric(horizontal: 16),
            color: cs.surfaceContainer,
            child: cells([
              Text('المندوب', style: headerStyle),
              Text('السلسلة والفرع', style: headerStyle),
              Text('الدخول', style: headerStyle),
              Text('الخروج', style: headerStyle),
              Text('المدة', style: headerStyle),
            ]),
          ),
          for (var i = start; i < end; i++) ...[
            if (i > start)
              Divider(
                height: 1,
                thickness: 1,
                color: cs.outlineVariant.withValues(alpha: 0.5),
              ),
            InkWell(
              key: ValueKey('hr_home_row_${rows[i].delegate.uid}'),
              onTap: () => onOpenRecord(rows[i]),
              overlayColor: hrStateLayer(cs.onSurface),
              child: Container(
                constraints: const BoxConstraints(minHeight: 64),
                padding: const EdgeInsets.symmetric(
                  horizontal: 16,
                  vertical: 10,
                ),
                child: cells([
                  _DelegateCell(rows[i]),
                  _ChainCell(
                    chain: hrRecordChain(rows[i], branches),
                    branch: hrBranchLabel(rows[i].branchName),
                  ),
                  _TimeText(hrFormatTime(rows[i].checkInTime!)),
                  rows[i].isPresent
                      ? const Align(
                          alignment: AlignmentDirectional.centerStart,
                          child: _StillHere(),
                        )
                      : _TimeText(
                          rows[i].checkOutTime == null
                              ? '—'
                              : hrFormatTime(rows[i].checkOutTime!),
                        ),
                  _TimeText(
                    _rowDuration(rows[i], now) == null
                        ? '—'
                        : hrFormatDuration(_rowDuration(rows[i], now)!),
                    color: rows[i].isPresent ? cs.primary : null,
                    weight: FontWeight.w700,
                  ),
                ]),
              ),
            ),
          ],
          Divider(height: 1, thickness: 1, color: cs.outlineVariant),
          _Pagination(
            start: start,
            end: end,
            total: rows.length,
            page: current,
            pages: pages,
            onPageChanged: onPageChanged,
          ),
        ],
      ),
    );
  }
}

class _Pagination extends StatelessWidget {
  final int start;
  final int end;
  final int total;
  final int page;
  final int pages;
  final ValueChanged<int> onPageChanged;

  const _Pagination({
    required this.start,
    required this.end,
    required this.total,
    required this.page,
    required this.pages,
    required this.onPageChanged,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 4),
      child: Row(
        mainAxisAlignment: MainAxisAlignment.end,
        children: [
          Text(
            '${start + 1}–$end من $total',
            key: const ValueKey('hr_home_page_label'),
            style: TextStyle(
              fontSize: 13,
              color: cs.onSurfaceVariant,
              fontFeatures: kHrTabularFigures,
            ),
          ),
          const SizedBox(width: 8),
          IconButton(
            key: const ValueKey('hr_home_page_prev'),
            tooltip: 'الصفحة السابقة',
            onPressed: page > 0 ? () => onPageChanged(page - 1) : null,
            icon: const M3DirIcon(Icons.chevron_left_rounded),
          ),
          IconButton(
            key: const ValueKey('hr_home_page_next'),
            tooltip: 'الصفحة التالية',
            onPressed: page < pages - 1 ? () => onPageChanged(page + 1) : null,
            icon: const M3DirIcon(Icons.chevron_right_rounded),
          ),
        ],
      ),
    );
  }
}

class _AttendanceList extends StatelessWidget {
  final List<HRAttendanceRecord> rows;
  final bool showAll;
  final DateTime now;
  final Map<String, Branch> branches;
  final VoidCallback onToggleShowAll;
  final ValueChanged<HRAttendanceRecord> onOpenRecord;

  const _AttendanceList({
    required this.rows,
    required this.showAll,
    required this.now,
    required this.branches,
    required this.onToggleShowAll,
    required this.onOpenRecord,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final visible = showAll ? rows : rows.take(kHrListPreviewRows).toList();
    return Column(
      crossAxisAlignment: CrossAxisAlignment.stretch,
      children: [
        Container(
          key: const ValueKey('hr_home_attendance_list'),
          clipBehavior: Clip.antiAlias,
          decoration: BoxDecoration(
            color: cs.surfaceContainerLowest,
            borderRadius: BorderRadius.circular(16),
          ),
          child: Column(
            children: [
              for (var i = 0; i < visible.length; i++) ...[
                if (i > 0)
                  Divider(
                    height: 1,
                    thickness: 1,
                    indent: 64,
                    color: cs.outlineVariant.withValues(alpha: 0.5),
                  ),
                _ListRow(
                  record: visible[i],
                  now: now,
                  chain: hrRecordChain(visible[i], branches),
                  onTap: () => onOpenRecord(visible[i]),
                ),
              ],
            ],
          ),
        ),
        if (rows.length > kHrListPreviewRows) ...[
          const SizedBox(height: 8),
          Center(
            child: TextButton(
              key: const ValueKey('hr_home_show_all'),
              onPressed: onToggleShowAll,
              style: TextButton.styleFrom(
                minimumSize: const Size(48, 48),
                shape: const StadiumBorder(),
              ),
              child: Text(
                showAll ? 'عرض أقل' : 'عرض كل الحاضرين (${rows.length})',
                style: const TextStyle(
                  fontSize: 14,
                  fontWeight: FontWeight.w600,
                  fontFeatures: kHrTabularFigures,
                ),
              ),
            ),
          ),
        ],
      ],
    );
  }
}

class _ListRow extends StatelessWidget {
  final HRAttendanceRecord record;
  final DateTime now;
  final String chain;
  final VoidCallback onTap;

  const _ListRow({
    required this.record,
    required this.now,
    required this.chain,
    required this.onTap,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final duration = _rowDuration(record, now);
    return InkWell(
      key: ValueKey('hr_home_row_${record.delegate.uid}'),
      onTap: onTap,
      overlayColor: hrStateLayer(cs.onSurface),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 10),
        child: Row(
          children: [
            Expanded(child: _DelegateCell(record)),
            const SizedBox(width: 8),
            if (chain.isNotEmpty) ...[
              HrChainAvatar(chain: chain, size: 28),
              const SizedBox(width: 12),
            ],
            Column(
              crossAxisAlignment: CrossAxisAlignment.end,
              mainAxisSize: MainAxisSize.min,
              children: [
                _TimeText(
                  record.isPresent || record.checkOutTime == null
                      ? hrFormatTime(record.checkInTime!)
                      : '${hrFormatTime(record.checkInTime!)} – ${hrFormatTime(record.checkOutTime!)}',
                ),
                const SizedBox(height: 2),
                if (record.isPresent)
                  Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      const _StillHere(),
                      const SizedBox(width: 8),
                      _TimeText(
                        duration == null ? '—' : hrFormatDuration(duration),
                        color: cs.primary,
                        weight: FontWeight.w700,
                      ),
                    ],
                  )
                else
                  _TimeText(
                    duration == null ? '—' : hrFormatDuration(duration),
                    color: cs.onSurfaceVariant,
                  ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

// ───────────────────────── States ─────────────────────────

class _SkeletonRows extends StatelessWidget {
  const _SkeletonRows();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      clipBehavior: Clip.antiAlias,
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          for (var i = 0; i < 5; i++)
            Container(
              key: ValueKey('hr_home_skeleton_row_$i'),
              height: 64,
              padding: const EdgeInsets.symmetric(horizontal: 16),
              child: const Row(
                children: [
                  M3Skeleton(width: 36, height: 36, radius: 18),
                  SizedBox(width: 12),
                  Expanded(
                    flex: 4,
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        M3Skeleton(height: 12, width: 140),
                        SizedBox(height: 8),
                        M3Skeleton(height: 10, width: 72),
                      ],
                    ),
                  ),
                  SizedBox(width: 12),
                  Expanded(flex: 3, child: M3Skeleton(height: 12)),
                  SizedBox(width: 24),
                  Expanded(flex: 2, child: M3Skeleton(height: 12)),
                ],
              ),
            ),
        ],
      ),
    );
  }
}

class _EmptyPanel extends StatelessWidget {
  final VoidCallback onOpenDelegates;

  const _EmptyPanel({required this.onOpenDelegates});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('hr_home_empty'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 32),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          HrExpressiveShape.cookie(
            size: 112,
            color: cs.primaryContainer,
            child: Icon(
              Icons.schedule_rounded,
              size: 48,
              color: cs.onPrimaryContainer,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            'لسه محدش سجّل حضور النهاردة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.tonalIcon(
            key: const ValueKey('hr_home_open_delegates'),
            onPressed: onOpenDelegates,
            icon: const Icon(Icons.badge_rounded),
            label: const Text('عرض المناديب'),
            style: FilledButton.styleFrom(
              minimumSize: const Size(48, 48),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ),
          ),
        ],
      ),
    );
  }
}

class _ErrorPanel extends StatelessWidget {
  final String message;
  final VoidCallback onRetry;

  const _ErrorPanel({required this.message, required this.onRetry});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('hr_home_error'),
      padding: const EdgeInsets.symmetric(horizontal: 24, vertical: 28),
      decoration: BoxDecoration(
        color: cs.errorContainer,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.cloud_off_rounded, size: 44, color: cs.onErrorContainer),
          const SizedBox(height: 12),
          Text(
            'مقدرناش نحمّل حضور النهاردة',
            textAlign: TextAlign.center,
            style: TextStyle(
              fontSize: 17,
              fontWeight: FontWeight.w700,
              color: cs.onErrorContainer,
            ),
          ),
          const SizedBox(height: 16),
          FilledButton.icon(
            key: const ValueKey('hr_home_retry'),
            onPressed: onRetry,
            icon: const Icon(Icons.refresh_rounded),
            label: const Text('إعادة المحاولة'),
            style: FilledButton.styleFrom(
              backgroundColor: cs.error,
              foregroundColor: cs.onError,
              minimumSize: const Size(48, 48),
              shape: const StadiumBorder(),
              padding: const EdgeInsets.symmetric(horizontal: 20),
            ).copyWith(overlayColor: hrStateLayer(cs.onError)),
          ),
          const SizedBox(height: 12),
          Text(
            'رمز الخطأ: ${hrAttendanceErrorCode(message)}',
            key: const ValueKey('hr_home_error_code'),
            style: TextStyle(
              fontSize: 12,
              color: cs.onErrorContainer.withValues(alpha: 0.8),
              fontFeatures: kHrTabularFigures,
            ),
          ),
        ],
      ),
    );
  }
}

class _NoMatches extends StatelessWidget {
  const _NoMatches();

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Container(
      key: const ValueKey('hr_home_no_matches'),
      padding: const EdgeInsets.all(24),
      decoration: BoxDecoration(
        color: cs.surfaceContainerLowest,
        borderRadius: BorderRadius.circular(16),
      ),
      child: Column(
        children: [
          Icon(Icons.search_off_rounded, size: 36, color: cs.onSurfaceVariant),
          const SizedBox(height: 8),
          Text(
            'مفيش نتايج مطابقة للفلتر أو البحث',
            textAlign: TextAlign.center,
            style: TextStyle(fontSize: 15, color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}
