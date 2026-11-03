// Web-only desktop list-detail layouts for the supervisor delegates and
// requests tabs. They reuse the shared screens via their optional selection
// hooks; mobile never builds these widgets.
import 'package:flutter/material.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:delegate_app/features/admin/presentation/pages/admin_delegates_screen.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

const double kListPaneWidth = 360;

/// Two panes: fixed 360 list on the start side + flexible detail.
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
      child: Row(
        crossAxisAlignment: CrossAxisAlignment.stretch,
        children: [
          SizedBox(width: kListPaneWidth, child: _pane(context, list)),
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
                          style: Theme.of(context)
                              .textTheme
                              .titleMedium
                              ?.copyWith(color: cs.onSurfaceVariant),
                        ),
                      ],
                    ),
                  ),
            ),
          ),
        ],
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
        child: widget.listOverride ??
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
  final Widget Function(ValueChanged<HRLeaveSelection>, String?)? listBuilderOverride;

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
      list: widget.listBuilderOverride?.call(_onSelect, sel?.key) ??
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
