import 'package:flutter/material.dart';

import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';

/// Shared M3 data table pieces for HR web screens (TAS-115).
///
/// One look for the delegates, attendance and payroll tables: a 12px card,
/// a 56px header in labelLarge, 64px rows in bodyMedium, status chips with
/// an icon and a semantic color, and tabular figures for numbers.

/// Header height (M3 data table).
const double kHrTableHeaderHeight = 56;

/// Minimum row height.
const double kHrTableRowHeight = 64;

/// Horizontal padding inside every cell, shared by header and rows so the
/// columns always line up.
const double kHrTableCellPadding = 8;

/// One column: same flex and alignment for the header and every cell.
@immutable
class HrTableColumn {
  const HrTableColumn(this.title, this.flex, {this.center = false});

  final String title;
  final int flex;
  final bool center;
}

/// A cell laid out for [column].
class HrTableCell extends StatelessWidget {
  const HrTableCell({super.key, required this.column, required this.child});

  final HrTableColumn column;
  final Widget child;

  @override
  Widget build(BuildContext context) => Expanded(
        flex: column.flex,
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: kHrTableCellPadding),
          child: Align(
            alignment: column.center
                ? Alignment.center
                : AlignmentDirectional.centerStart,
            child: child,
          ),
        ),
      );
}

/// Outlined card that holds a table. Scrolls sideways below [minWidth].
class HrTableCard extends StatefulWidget {
  const HrTableCard({
    super.key,
    required this.builder,
    this.minWidth = 860,
    this.horizontalController,
  });

  /// Builds the table for the given width.
  final Widget Function(BuildContext context, double width) builder;
  final double minWidth;

  /// Optional; the card makes its own when none is given.
  final ScrollController? horizontalController;

  @override
  State<HrTableCard> createState() => _HrTableCardState();
}

class _HrTableCardState extends State<HrTableCard> {
  ScrollController? _own;

  ScrollController get _controller =>
      widget.horizontalController ?? (_own ??= ScrollController());

  @override
  void dispose() {
    _own?.dispose();
    super.dispose();
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      decoration: BoxDecoration(
        color: colorScheme.surface,
        borderRadius: BorderRadius.circular(HrRadius.card),
        border: Border.all(color: colorScheme.outlineVariant),
      ),
      clipBehavior: Clip.antiAlias,
      child: LayoutBuilder(
        builder: (context, constraints) {
          final available = constraints.maxWidth;
          final width =
              available > widget.minWidth ? available : widget.minWidth;
          final table = SizedBox(
            width: width,
            child: widget.builder(context, width),
          );
          if (width <= available) return table;
          return Scrollbar(
            controller: _controller,
            thumbVisibility: true,
            notificationPredicate: (n) =>
                n.depth == 0 && n.metrics.axis == Axis.horizontal,
            child: SingleChildScrollView(
              controller: _controller,
              scrollDirection: Axis.horizontal,
              child: table,
            ),
          );
        },
      ),
    );
  }
}

/// 56px header row in labelLarge / onSurfaceVariant.
class HrTableHeader extends StatelessWidget {
  const HrTableHeader({super.key, required this.columns, this.keyPrefix});

  final List<HrTableColumn> columns;

  /// When set, each title gets `Key('$keyPrefix${column.title}')`.
  final String? keyPrefix;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    return Container(
      height: kHrTableHeaderHeight,
      padding: const EdgeInsets.symmetric(horizontal: kHrTableCellPadding),
      decoration: BoxDecoration(
        color: colorScheme.surfaceContainerLow,
        border: Border(bottom: BorderSide(color: colorScheme.outlineVariant)),
      ),
      child: Row(
        children: [
          for (final c in columns)
            HrTableCell(
              column: c,
              child: Text(
                c.title,
                key: keyPrefix == null ? null : Key('$keyPrefix${c.title}'),
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
                style: TextStyle(
                  fontSize: HrFont.body,
                  fontWeight: FontWeight.w600,
                  color: colorScheme.onSurfaceVariant,
                ),
              ),
            ),
        ],
      ),
    );
  }
}

/// A body row: at least 64px, cells laid out by [columns].
class HrTableRow extends StatelessWidget {
  const HrTableRow({
    super.key,
    required this.columns,
    required this.cells,
    this.onTap,
  });

  final List<HrTableColumn> columns;
  final List<Widget> cells;
  final VoidCallback? onTap;

  @override
  Widget build(BuildContext context) {
    assert(columns.length == cells.length, 'one cell per column');
    final row = ConstrainedBox(
      constraints: const BoxConstraints(minHeight: kHrTableRowHeight),
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: kHrTableCellPadding),
        child: Row(
          children: [
            for (var i = 0; i < columns.length; i++)
              HrTableCell(column: columns[i], child: cells[i]),
          ],
        ),
      ),
    );
    if (onTap == null) return row;
    return InkWell(onTap: onTap, child: row);
  }
}

/// Divider between rows.
class HrTableDivider extends StatelessWidget {
  const HrTableDivider({super.key});

  @override
  Widget build(BuildContext context) => Divider(
        height: 1,
        thickness: 1,
        color: Theme.of(context).colorScheme.outlineVariant.withValues(
              alpha: 0.5,
            ),
      );
}

/// Status tone for [HrStatusChip].
enum HrStatusTone { success, warning, danger, neutral }

/// Status chip: icon + label on the tone's container color, so the state
/// never depends on color alone and text keeps M3 container contrast.
class HrStatusChip extends StatelessWidget {
  const HrStatusChip({
    super.key,
    required this.label,
    required this.tone,
    this.icon,
  });

  final String label;
  final HrStatusTone tone;

  /// Defaults per tone: check, schedule, error, remove.
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final status = HrStatusColors.of(context);
    final (bg, fg, defaultIcon) = switch (tone) {
      HrStatusTone.success => (
          status.successContainer,
          status.onSuccessContainer,
          Icons.check_circle_rounded,
        ),
      HrStatusTone.warning => (
          status.warningContainer,
          status.onWarningContainer,
          Icons.schedule_rounded,
        ),
      HrStatusTone.danger => (
          status.dangerContainer,
          status.onDangerContainer,
          Icons.error_rounded,
        ),
      HrStatusTone.neutral => (
          colorScheme.surfaceContainerHighest,
          colorScheme.onSurfaceVariant,
          Icons.remove_circle_outline_rounded,
        ),
    };
    return Container(
      height: 28,
      padding: const EdgeInsetsDirectional.fromSTEB(8, 0, 10, 0),
      decoration: BoxDecoration(
        color: bg,
        borderRadius: BorderRadius.circular(HrRadius.chip),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon ?? defaultIcon, size: 16, color: fg),
          const SizedBox(width: 4),
          Flexible(
            child: Text(
              label,
              maxLines: 1,
              overflow: TextOverflow.ellipsis,
              style: TextStyle(
                fontSize: HrFont.labelMedium,
                fontWeight: FontWeight.w600,
                color: fg,
              ),
            ),
          ),
        ],
      ),
    );
  }
}

/// Body text with tabular figures, for IDs, phones, money and counts.
TextStyle hrTabularStyle(BuildContext context, {Color? color}) {
  final colorScheme = Theme.of(context).colorScheme;
  return TextStyle(
    fontSize: HrFont.body,
    fontWeight: FontWeight.w500,
    color: color ?? colorScheme.onSurface,
    fontFeatures: const [FontFeature.tabularFigures()],
  );
}
