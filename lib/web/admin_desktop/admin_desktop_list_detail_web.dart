// Web-only desktop list-detail layouts for the supervisor delegates and
// requests tabs. They reuse the shared screens via their optional selection
// hooks; mobile never builds these widgets.
import 'package:material_ui/material_ui.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

/// Minimum list-pane width (M3 list-detail spec).
const double kListPaneWidth = 360;

/// Upper bound so the detail pane keeps most of the space on wide screens.
const double kListPaneMaxWidth = 520;

/// List pane grows with the available width: 48% of it, clamped to
/// [kListPaneWidth]..[kListPaneMaxWidth]. At a 1280 window with the 300px
/// drawer this gives ~430px, enough for two full 190px KPI cards of the
/// shared requests list (the rest scroll horizontally inside the pane).
double listPaneWidthFor(double available) =>
    (available * 0.48).clamp(kListPaneWidth, kListPaneMaxWidth).toDouble();

/// Two panes: responsive list (>= 360) on the start side + flexible detail.
class AdminListDetailWeb extends StatelessWidget {
  final Widget list;
  final Widget? detail;
  final IconData emptyIcon;
  final String emptyText;

  const AdminListDetailWeb({
    super.key,
    required this.list,
    required this.detail,
    required this.emptyIcon,
    required this.emptyText,
  });

  Widget _pane(BuildContext context, Widget child) {
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surfaceContainerLow,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
      child: child,
    );
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsets.all(16),
      child: LayoutBuilder(
        builder: (context, constraints) => Row(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            SizedBox(
              key: const ValueKey('list_detail_list_pane'),
              width: listPaneWidthFor(constraints.maxWidth),
              child: _pane(context, list),
            ),
            const SizedBox(width: 16),
            Expanded(
              child: _pane(
                context,
                detail ??
                    Center(
                      key: const ValueKey('list_detail_empty'),
                      child: Column(
                        mainAxisSize: MainAxisSize.min,
                        children: [
                          Icon(emptyIcon, size: 56, color: cs.onSurfaceVariant),
                          const SizedBox(height: 12),
                          Text(
                            emptyText,
                            style: Theme.of(context).textTheme.titleMedium
                                ?.copyWith(color: cs.onSurfaceVariant),
                          ),
                        ],
                      ),
                    ),
              ),
            ),
          ],
        ),
      ),
    );
  }
}

class AdminDelegatesListDetailWeb extends StatefulWidget {
  final Delegate adminDelegate;

  /// Test hooks.
  final Widget? listOverride;
  final Widget Function(Delegate)? detailBuilderOverride;

  const AdminDelegatesListDetailWeb({
    super.key,
    required this.adminDelegate,
    this.listOverride,
    this.detailBuilderOverride,
  });

  @override
  State<AdminDelegatesListDetailWeb> createState() =>
      _AdminDelegatesListDetailWebState();
}

class _AdminDelegatesListDetailWebState
    extends State<AdminDelegatesListDetailWeb> {
  Delegate? _selected;

  void _onSelect(Delegate d) => setState(() => _selected = d);

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return AdminListDetailWeb(
      list: AdminDelegateSelectionScope(
        selectedUid: sel?.uid,
        onSelect: _onSelect,
        child:
            widget.listOverride ??
            AdminDelegatesScreen(adminDelegate: widget.adminDelegate),
      ),
      detail: sel == null
          ? null
          : (widget.detailBuilderOverride?.call(sel) ??
                AdminDelegateDetailView(delegate: sel)),
      emptyIcon: Symbols.badge_rounded,
      emptyText: 'اختار مندوب لعرض التفاصيل',
    );
  }
}

class HRRequestsListDetailWeb extends StatefulWidget {
  final Delegate hrDelegate;

  /// Test hook: builds the list given the selection callback/key.
  final Widget Function(ValueChanged<HRLeaveSelection>, String?)?
  listBuilderOverride;

  const HRRequestsListDetailWeb({
    super.key,
    required this.hrDelegate,
    this.listBuilderOverride,
  });

  @override
  State<HRRequestsListDetailWeb> createState() =>
      _HRRequestsListDetailWebState();
}

class _HRRequestsListDetailWebState extends State<HRRequestsListDetailWeb> {
  HRLeaveSelection? _selected;

  void _onSelect(HRLeaveSelection s) => setState(() => _selected = s);

  @override
  Widget build(BuildContext context) {
    final sel = _selected;
    return AdminListDetailWeb(
      list:
          widget.listBuilderOverride?.call(_onSelect, sel?.key) ??
          HRLeavesAndExcusesScreen(
            hrDelegate: widget.hrDelegate,
            showAppBar: false,
            onSelectLeave: _onSelect,
            selectedLeaveKey: sel?.key,
          ),
      detail: sel == null
          ? null
          : HRLeaveDetailView(
              key: ValueKey(sel.key),
              selection: sel,
              // After an approve/reject the list stream refreshes; clear the
              // stale detail so the supervisor re-selects fresh data.
              onActionDone: () {
                if (mounted) setState(() => _selected = null);
              },
            ),
      emptyIcon: Symbols.event_note_rounded,
      emptyText: 'اختار طلب لعرض التفاصيل',
    );
  }
}
