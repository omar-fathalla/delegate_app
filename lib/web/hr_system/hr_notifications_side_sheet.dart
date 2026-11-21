// WEB-ONLY: Material 3 modal side sheet for the HR header bell.
// Mobile keeps NotificationsPage. This file is reached only when
// [WebRuntimePolicy.isWeb] is true.
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/core/services/review_service.dart';
import 'package:delegate_app/core/time/cairo_clock.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/hr/presentation/hr_design_tokens.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_adaptive_sheet.dart';

/// Pinned clock for screenshots and tests. Production leaves this null.
@visibleForTesting
DateTime Function()? hrNotificationsSheetDebugNow;

/// Opens the first row menu once, for screenshots. Production leaves this false.
@visibleForTesting
bool hrNotificationsSheetDebugOpenFirstMenu = false;

DateTime _sheetNow() => hrNotificationsSheetDebugNow?.call() ?? DateTime.now();

const double _kFullScreenBreakpoint = 600;
const int _kPageSize = 15;

/// Opens the HR notifications side sheet from the reading end (the left
/// edge in RTL), like every other HR side sheet (TAS-137).
///
/// No-ops unless [WebRuntimePolicy.isWeb] is true, so a mobile call cannot
/// replace [NotificationsPage]. [bloc] is for previews; the app builds one
/// from the same factory the notifications page uses.
Future<void> showHrNotificationsSideSheet(
  BuildContext context, {
  required Delegate delegate,
  NotificationBloc? bloc,
}) async {
  if (!WebRuntimePolicy.isWeb) return;

  final host = context;
  final bridge = context
      .getInheritedWidgetOfExactType<HrWebHeaderBridgeScope>()
      ?.notifier;
  final ownsBloc = bloc == null;
  final resolved = bloc ?? di.sl<NotificationBloc>();
  if (ownsBloc) {
    resolved
      ..add(
        LoadNotifications(
          delegateUid: delegate.uid,
          organizationId: delegate.organizationUID,
          phoneNumber: delegate.phoneNumber,
          userRole: delegate.role.name,
          accountCreatedAt: delegate.createdAt,
        ),
      )
      ..add(
        SubscribeToUnreadCount(
          delegateUid: delegate.uid,
          organizationId: delegate.organizationUID,
          phoneNumber: delegate.phoneNumber,
          userRole: delegate.role.name,
          accountCreatedAt: delegate.createdAt,
        ),
      );
  }

  final scrim = Theme.of(context).colorScheme.scrim.withValues(alpha: 0.32);
  final direction = Directionality.of(context);
  bridge?.setSheetOpen(true);
  try {
    await Navigator.of(context).push<void>(
      _HrNotificationsSheetRoute(
        barrier: scrim,
        child: Directionality(
          textDirection: direction,
          child: BlocProvider.value(
            value: resolved,
            child: _HrNotificationsSheet(
              delegate: delegate,
              hostContext: host,
            ),
          ),
        ),
      ),
    );
  } finally {
    bridge?.setSheetOpen(false);
    if (ownsBloc) await resolved.close();
    final node = bridge?.notificationsFocus;
    if (node != null && node.context != null) {
      WidgetsBinding.instance.addPostFrameCallback((_) {
        if (node.context != null) node.requestFocus();
      });
    }
  }
}

class _HrNotificationsSheetRoute extends PopupRoute<void> {
  _HrNotificationsSheetRoute({required this.child, required Color barrier})
    : _barrier = barrier;

  final Widget child;
  final Color _barrier;

  @override
  Color get barrierColor => _barrier;

  @override
  bool get barrierDismissible => true;

  @override
  String get barrierLabel => 'إغلاق الإشعارات';

  @override
  Duration get transitionDuration => AppMotionDurations.medium4;

  @override
  Duration get reverseTransitionDuration => AppMotionDurations.short4;

  @override
  Widget buildPage(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
  ) {
    return child;
  }

  @override
  Widget buildTransitions(
    BuildContext context,
    Animation<double> animation,
    Animation<double> secondaryAnimation,
    Widget child,
  ) {
    return HrSideSheetTransition(animation: animation, child: child);
  }

}

class _HrNotificationsSheet extends StatefulWidget {
  final Delegate delegate;
  final BuildContext hostContext;

  const _HrNotificationsSheet({
    required this.delegate,
    required this.hostContext,
  });

  @override
  State<_HrNotificationsSheet> createState() => _HrNotificationsSheetState();
}

class _HrNotificationsSheetState extends State<_HrNotificationsSheet> {
  final GlobalKey<ScaffoldMessengerState> _messenger =
      GlobalKey<ScaffoldMessengerState>();
  final Set<String> _pendingDelete = <String>{};
  _SheetFilter _filter = _SheetFilter.all;
  int _limit = _kPageSize;

  void _revealOlder() {
    setState(() => _limit += _kPageSize);
  }

  void _setFilter(_SheetFilter filter) {
    if (_filter == filter) return;
    setState(() {
      _filter = filter;
      _limit = _kPageSize;
    });
  }

  void _markAll() {
    final delegate = widget.delegate;
    context.read<NotificationBloc>().add(
      MarkAllAsRead(
        delegateUid: delegate.uid,
        organizationId: delegate.organizationUID,
        phoneNumber: delegate.phoneNumber,
      ),
    );
  }

  void _markOne(NotificationEntity notification) {
    if (notification.isRead) return;
    final delegate = widget.delegate;
    context.read<NotificationBloc>().add(
      MarkAsRead(
        notificationId: notification.id,
        delegateUid: delegate.uid,
        organizationId: delegate.organizationUID,
        phoneNumber: delegate.phoneNumber,
      ),
    );
  }

  void _delete(NotificationEntity notification) {
    final id = notification.id;
    if (_pendingDelete.contains(id)) return;
    setState(() => _pendingDelete.add(id));

    final bloc = context.read<NotificationBloc>();
    final delegate = widget.delegate;
    final message = AppLocalizations.of(context)!.notificationDeleted;
    var undone = false;
    final messenger = _messenger.currentState;
    messenger?.hideCurrentSnackBar();
    final controller = messenger?.showSnackBar(
      SnackBar(
        behavior: SnackBarBehavior.floating,
        content: Text(
          message,
          style: const TextStyle(fontFamily: 'Cairo'),
        ),
        action: SnackBarAction(
          label: 'تراجع',
          onPressed: () {
            undone = true;
            if (!mounted) return;
            setState(() => _pendingDelete.remove(id));
          },
        ),
      ),
    );
    controller?.closed.then((reason) {
      if (undone || reason == SnackBarClosedReason.action) return;
      bloc.add(
        DeleteNotificationRequested(
          notificationId: id,
          delegateUid: delegate.uid,
          organizationId: delegate.organizationUID,
          phoneNumber: delegate.phoneNumber,
        ),
      );
      if (mounted) setState(() => _pendingDelete.remove(id));
    });
  }

  void _open(NotificationEntity notification) {
    _markOne(notification);
    if (!_hasTarget(notification)) return;
    final host = widget.hostContext;
    Navigator.of(context).pop();
    if (!host.mounted) return;
    _openTarget(host, notification, widget.delegate);
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final viewport = MediaQuery.sizeOf(context).width;
    final fullScreen = viewport < _kFullScreenBreakpoint;

    final sheet = Material(
      key: const ValueKey('hr_notifications_side_sheet'),
      color: cs.surfaceContainerLow,
      elevation: fullScreen ? 0 : 1,
      shadowColor: cs.shadow,
      surfaceTintColor: cs.surfaceTint.withValues(alpha: 0),
      clipBehavior: Clip.antiAlias,
      child: DecoratedBox(
        decoration: BoxDecoration(
          border: fullScreen
              ? null
              : Border(left: BorderSide(color: cs.outlineVariant)),
        ),
        child: ScaffoldMessenger(
          key: _messenger,
          child: Scaffold(
            backgroundColor: cs.surfaceContainerLow,
            body: SafeArea(
              child: BlocBuilder<NotificationBloc, NotificationState>(
                builder: (context, state) {
                  final loaded = state is NotificationLoaded
                      ? state.notifications
                            .where((n) => !_pendingDelete.contains(n.id))
                            .toList()
                      : const <NotificationEntity>[];
                  final sorted = [...loaded]
                    ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
                  final unread = sorted.where((n) => !n.isRead).length;
                  final filtered = _filter == _SheetFilter.unread
                      ? sorted.where((n) => !n.isRead).toList()
                      : sorted;
                  final visible = filtered.take(_limit).toList();
                  final hasMore = visible.length < filtered.length;

                  return Column(
                    children: [
                      _Header(
                        unread: unread,
                        filter: _filter,
                        onClose: () => Navigator.of(context).pop(),
                        onMarkAll: unread > 0 ? _markAll : null,
                        onFilter: _setFilter,
                      ),
                      Expanded(
                        child: _body(
                          context,
                          state,
                          visible,
                          filtered,
                          hasMore,
                        ),
                      ),
                    ],
                  );
                },
              ),
            ),
          ),
        ),
      ),
    );

    if (fullScreen) return SizedBox.expand(child: sheet);
    return Align(
      alignment: AlignmentDirectional.centerEnd,
      child: SizedBox(
        width: HrSheet.sideWidth,
        height: MediaQuery.sizeOf(context).height,
        child: sheet,
      ),
    );
  }

  Widget _body(
    BuildContext context,
    NotificationState state,
    List<NotificationEntity> visible,
    List<NotificationEntity> filtered,
    bool hasMore,
  ) {
    if (state is NotificationLoading || state is NotificationInitial) {
      return const Center(child: M3DelayedLoading());
    }
    if (state is NotificationError) {
      return _Message(
        icon: Icons.error_rounded,
        text: state.message,
        action: TextButton(
          onPressed: () {
            final delegate = widget.delegate;
            context.read<NotificationBloc>().add(
              LoadNotifications(
                delegateUid: delegate.uid,
                organizationId: delegate.organizationUID,
                phoneNumber: delegate.phoneNumber,
                userRole: delegate.role.name,
                accountCreatedAt: delegate.createdAt,
              ),
            );
          },
          child: Text(AppLocalizations.of(context)!.retry),
        ),
      );
    }
    if (filtered.isEmpty) {
      final unreadFilter = _filter == _SheetFilter.unread;
      return _Message(
        key: const ValueKey('hr_notifications_empty'),
        icon: Icons.notifications_off_rounded,
        text: unreadFilter ? 'مفيش إشعارات غير مقروءة' : 'مفيش إشعارات',
      );
    }

    final now = _sheetNow();
    final groups = _group(visible, now);
    final cs = Theme.of(context).colorScheme;
    return ListView(
      padding: const EdgeInsets.only(bottom: 8),
      children: [
        for (final group in groups) ...[
          _GroupLabel(group.label),
          for (final notification in group.items)
            _NotificationRow(
              key: ValueKey('hr_notification_row_${notification.id}'),
              notification: notification,
              now: now,
              onOpen: () => _open(notification),
              onMarkRead: () => _markOne(notification),
              onDelete: () => _delete(notification),
            ),
        ],
        if (hasMore)
          Padding(
            padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 16),
            child: Center(
              child: OutlinedButton.icon(
                key: const ValueKey('hr_notifications_older'),
                onPressed: _revealOlder,
                icon: const Icon(Icons.expand_more_rounded, size: 18),
                label: const Text('عرض الأقدم'),
                style: OutlinedButton.styleFrom(
                  minimumSize: const Size(0, 44),
                  padding: const EdgeInsets.symmetric(horizontal: 16),
                  side: BorderSide(color: cs.outlineVariant),
                  foregroundColor: cs.onSurface,
                  textStyle: const TextStyle(
                    fontFamily: 'Cairo',
                    fontSize: HrFont.body,
                    fontWeight: FontWeight.w600,
                  ),
                ),
              ),
            ),
          ),
      ],
    );
  }
}

enum _SheetFilter { all, unread }

class _Header extends StatelessWidget {
  final int unread;
  final _SheetFilter filter;
  final VoidCallback onClose;
  final VoidCallback? onMarkAll;
  final ValueChanged<_SheetFilter> onFilter;

  const _Header({
    required this.unread,
    required this.filter,
    required this.onClose,
    required this.onMarkAll,
    required this.onFilter,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final text = Theme.of(context).textTheme;
    return DecoratedBox(
      decoration: BoxDecoration(
        border: Border(
          bottom: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.6)),
        ),
      ),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 24, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Flexible(
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Flexible(
                        child: Text(
                          'الإشعارات',
                          key: const ValueKey('hr_notifications_title'),
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: text.titleLarge?.copyWith(
                            fontFamily: 'Cairo',
                            fontWeight: FontWeight.w700,
                            color: cs.onSurface,
                            fontSize: HrFont.titleLarge,
                          ),
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadCount(unread),
                      ],
                    ],
                  ),
                ),
                if (onMarkAll != null)
                  TextButton(
                    key: const ValueKey('hr_notifications_mark_all'),
                    onPressed: onMarkAll,
                    style: TextButton.styleFrom(
                      foregroundColor: cs.primary,
                      visualDensity: VisualDensity.compact,
                      tapTargetSize: MaterialTapTargetSize.shrinkWrap,
                      minimumSize: const Size(0, 36),
                      padding: const EdgeInsets.symmetric(horizontal: 8),
                      textStyle: const TextStyle(
                        fontFamily: 'Cairo',
                        fontSize: HrFont.body,
                        fontWeight: FontWeight.w600,
                      ),
                    ),
                    child: const Text('تعليم الكل كمقروء'),
                  ),
                IconButton(
                  key: const ValueKey('hr_notifications_close'),
                  tooltip: 'إغلاق',
                  autofocus: true,
                  onPressed: onClose,
                  icon: const Icon(Icons.close_rounded),
                ),
              ],
            ),
            const SizedBox(height: 8),
            Row(
              children: [
                _FilterChip(
                  label: 'الكل',
                  selected: filter == _SheetFilter.all,
                  onSelected: () => onFilter(_SheetFilter.all),
                  chipKey: const ValueKey('hr_notifications_filter_all'),
                ),
                const SizedBox(width: 8),
                _FilterChip(
                  label: 'غير مقروء',
                  selected: filter == _SheetFilter.unread,
                  onSelected: () => onFilter(_SheetFilter.unread),
                  chipKey: const ValueKey('hr_notifications_filter_unread'),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}

class _UnreadCount extends StatelessWidget {
  final int count;

  const _UnreadCount(this.count);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final label = count > 99 ? '99+' : '$count';
    return Container(
      key: const ValueKey('hr_notifications_unread_count'),
      padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 2),
      decoration: BoxDecoration(
        color: cs.primaryContainer,
        borderRadius: BorderRadius.circular(HrRadius.card),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: HrFont.labelMedium,
          fontWeight: FontWeight.w700,
          color: cs.onPrimaryContainer,
        ),
      ),
    );
  }
}

class _FilterChip extends StatelessWidget {
  final String label;
  final bool selected;
  final VoidCallback onSelected;
  final Key chipKey;

  const _FilterChip({
    required this.label,
    required this.selected,
    required this.onSelected,
    required this.chipKey,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return FilterChip(
      key: chipKey,
      label: Text(label),
      selected: selected,
      showCheckmark: false,
      onSelected: (_) => onSelected(),
      labelStyle: TextStyle(
        fontFamily: 'Cairo',
        fontSize: HrFont.body,
        fontWeight: FontWeight.w600,
        color: selected ? cs.onSecondaryContainer : cs.onSurfaceVariant,
      ),
      selectedColor: cs.secondaryContainer,
      backgroundColor: cs.surfaceContainerLow,
      side: BorderSide(
        color: selected ? cs.secondaryContainer : cs.outlineVariant,
      ),
      visualDensity: VisualDensity.compact,
    );
  }
}

class _GroupLabel extends StatelessWidget {
  final String label;

  const _GroupLabel(this.label);

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(24, 14, 24, 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: HrFont.body,
          fontWeight: FontWeight.w700,
          color: cs.onSurfaceVariant,
        ),
      ),
    );
  }
}

class _NotificationRow extends StatefulWidget {
  final NotificationEntity notification;
  final DateTime now;
  final VoidCallback onOpen;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  const _NotificationRow({
    super.key,
    required this.notification,
    required this.now,
    required this.onOpen,
    required this.onMarkRead,
    required this.onDelete,
  });

  @override
  State<_NotificationRow> createState() => _NotificationRowState();
}

class _NotificationRowState extends State<_NotificationRow> {
  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notification = widget.notification;
    final unread = !notification.isRead;
    final title = NotificationModel.sanitizeText(notification.title);
    final body = NotificationModel.sanitizeText(notification.body);
    final tone = _toneFor(
      notification.type,
      Theme.of(context).brightness,
      cs,
    );

    return InkWell(
      onTap: widget.onOpen,
      hoverColor: cs.onSurface.withValues(alpha: 0.06),
      splashColor: cs.onSurface.withValues(alpha: 0.08),
      child: Padding(
        padding: const EdgeInsetsDirectional.fromSTEB(24, 8, 12, 8),
        child: Row(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            _TypeIcon(
              icon: _iconFor(notification.type),
              background: tone.background,
              foreground: tone.foreground,
            ),
            const SizedBox(width: 12),
            Expanded(
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  Row(
                    children: [
                      if (unread) ...[
                        const _UnreadDot(),
                        const SizedBox(width: 6),
                      ],
                      Expanded(
                        child: Text(
                          title,
                          maxLines: 1,
                          overflow: TextOverflow.ellipsis,
                          style: TextStyle(
                            fontFamily: 'Cairo',
                            fontSize: HrFont.body,
                            height: 1.3,
                            fontWeight: unread
                                ? FontWeight.w700
                                : FontWeight.w500,
                            color: cs.onSurface,
                          ),
                        ),
                      ),
                      const SizedBox(width: 8),
                      Text(
                        _formatWhen(notification.createdAt, widget.now),
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: HrFont.labelMedium,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ],
                  ),
                  if (body.isNotEmpty)
                    Padding(
                      padding: EdgeInsetsDirectional.only(
                        start: unread ? 14 : 0,
                      ),
                      child: Text(
                        body,
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                        style: TextStyle(
                          fontFamily: 'Cairo',
                          fontSize: HrFont.body,
                          height: 1.35,
                          color: cs.onSurfaceVariant,
                        ),
                      ),
                    ),
                ],
              ),
            ),
            _OverflowMenu(
              unread: unread,
              onMarkRead: widget.onMarkRead,
              onDelete: widget.onDelete,
            ),
          ],
        ),
      ),
    );
  }
}

class _OverflowMenu extends StatefulWidget {
  final bool unread;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  const _OverflowMenu({
    required this.unread,
    required this.onMarkRead,
    required this.onDelete,
  });

  @override
  State<_OverflowMenu> createState() => _OverflowMenuState();
}

class _OverflowMenuState extends State<_OverflowMenu> {
  final GlobalKey _button = GlobalKey();

  @override
  void initState() {
    super.initState();
    if (!hrNotificationsSheetDebugOpenFirstMenu) return;
    hrNotificationsSheetDebugOpenFirstMenu = false;
    WidgetsBinding.instance.addPostFrameCallback((_) {
      Future<void>.delayed(AppMotionDurations.medium4, () {
        if (mounted) _open();
      });
    });
  }

  Future<void> _open() async {
    final button = _button.currentContext?.findRenderObject() as RenderBox?;
    if (button == null || !button.hasSize) return;
    final overlay = Overlay.of(context).context.findRenderObject() as RenderBox;
    final cs = Theme.of(context).colorScheme;
    final value = await showMenu<String>(
      context: context,
      position: RelativeRect.fromRect(
        button.localToGlobal(Offset.zero, ancestor: overlay) & button.size,
        Offset.zero & overlay.size,
      ),
      color: cs.surfaceContainerHigh,
      elevation: 3,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(HrRadius.card),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      items: [
        if (widget.unread)
          PopupMenuItem(
            value: 'read',
            child: _MenuRow(
              icon: Icons.mark_email_read_rounded,
              label: 'تحديد كمقروء',
            ),
          ),
        const PopupMenuItem(
          value: 'delete',
          child: _MenuRow(icon: Icons.delete_rounded, label: 'حذف'),
        ),
      ],
    );
    if (!mounted || value == null) return;
    if (value == 'read') widget.onMarkRead();
    if (value == 'delete') widget.onDelete();
  }

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return IconButton(
      key: _button,
      tooltip: 'المزيد',
      onPressed: _open,
      icon: Icon(Icons.more_vert_rounded, size: 18, color: cs.onSurfaceVariant),
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(32, 32),
        padding: EdgeInsets.zero,
      ),
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;

  const _MenuRow({required this.icon, required this.label});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = cs.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: ink),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: HrFont.body,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ],
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _TypeIcon({
    required this.icon,
    required this.background,
    required this.foreground,
  });

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: background, shape: BoxShape.circle),
      child: Icon(icon, size: 20, color: foreground),
    );
  }
}

class _UnreadDot extends StatelessWidget {
  const _UnreadDot();

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 8,
      height: 8,
      decoration: BoxDecoration(
        color: Theme.of(context).colorScheme.primary,
        shape: BoxShape.circle,
      ),
    );
  }
}

class _Message extends StatelessWidget {
  final IconData icon;
  final String text;
  final Widget? action;

  const _Message({super.key, required this.icon, required this.text, this.action});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return Center(
      child: Padding(
        padding: const EdgeInsets.all(32),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(icon, size: 40, color: cs.outline),
            const SizedBox(height: 12),
            Text(
              text,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: HrFont.body,
                color: cs.onSurfaceVariant,
              ),
            ),
            if (action != null) ...[const SizedBox(height: 12), action!],
          ],
        ),
      ),
    );
  }
}

class _DayGroup {
  final String label;
  final List<NotificationEntity> items;

  const _DayGroup(this.label, this.items);
}

List<_DayGroup> _group(List<NotificationEntity> items, DateTime now) {
  CairoClock.ensureInitialized();
  final today = <NotificationEntity>[];
  final yesterday = <NotificationEntity>[];
  final older = <NotificationEntity>[];
  for (final item in items) {
    if (CairoClock.isSameCairoCalendarDay(item.createdAt, now)) {
      today.add(item);
    } else if (_isCairoYesterday(item.createdAt, now)) {
      yesterday.add(item);
    } else {
      older.add(item);
    }
  }
  return [
    if (today.isNotEmpty) _DayGroup('النهاردة', today),
    if (yesterday.isNotEmpty) _DayGroup('امبارح', yesterday),
    if (older.isNotEmpty) _DayGroup('أقدم', older),
  ];
}

bool _isCairoYesterday(DateTime created, DateTime now) {
  final today = _cairoDate(now);
  final day = _cairoDate(created);
  final yesterday = DateTime(today.year, today.month, today.day).subtract(
    const Duration(days: 1),
  );
  return day == yesterday;
}

DateTime _cairoDate(DateTime instant) {
  final cairo = CairoClock.toCairo(instant);
  return DateTime(cairo.year, cairo.month, cairo.day);
}

const _kMonths = [
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
];

String _formatWhen(DateTime created, DateTime now) {
  CairoClock.ensureInitialized();
  if (CairoClock.isSameCairoCalendarDay(created, now)) {
    return _relative(now.difference(created));
  }
  final cairo = CairoClock.toCairo(created);
  final clock = _clock(cairo.hour, cairo.minute);
  if (_isCairoYesterday(created, now)) return 'امبارح · $clock';
  return '${cairo.day} ${_kMonths[cairo.month - 1]} · $clock';
}

String _relative(Duration difference) {
  if (difference.inMinutes < 1) return 'الآن';
  final minutes = difference.inMinutes;
  if (minutes < 60) return 'منذ ${_count(minutes, 'دقيقة', 'دقيقتين', 'دقائق', 'دقيقة')}';
  final hours = difference.inHours;
  return 'منذ ${_count(hours, 'ساعة', 'ساعتين', 'ساعات', 'ساعة')}';
}

String _count(int n, String one, String two, String few, String many) {
  if (n == 1) return one;
  if (n == 2) return two;
  if (n >= 3 && n <= 10) return '$n $few';
  return '$n $many';
}

String _clock(int hour24, int minute) {
  final isPm = hour24 >= 12;
  var hour = hour24 % 12;
  if (hour == 0) hour = 12;
  final mm = minute.toString().padLeft(2, '0');
  return '$hour:$mm ${isPm ? 'م' : 'ص'}';
}

enum _IconKind {
  checkIn,
  checkOut,
  notice,
  penalty,
  photo,
  subscription,
  task,
  leave,
  support,
  wallet,
  device,
  neutral,
}

_IconKind _kindFor(String type) {
  switch (type) {
    case 'attendance_check_in':
    case 'check_in':
      return _IconKind.checkIn;
    case 'attendance_check_out':
    case 'check_out':
      return _IconKind.checkOut;
    case 'update':
    case 'announcement':
      return _IconKind.notice;
    case 'penalty':
    case 'mock_location_alert':
    case 'geofence_breach':
    case 'geofence_return':
    case 'geofence_breach_offline_sync':
      return _IconKind.penalty;
    case 'photo_permission':
      return _IconKind.photo;
    case 'delegate_subscription_request':
    case 'delegate_profile_edit':
    case 'delegate_national_id_request':
    case 'subscription_approved':
    case 'subscription_renewal_reminder':
    case 'subscription_rejected':
      return _IconKind.subscription;
    case 'task':
      return _IconKind.task;
    case 'leave':
    case 'leave_request':
    case 'permission':
    case 'excuse':
      return _IconKind.leave;
    case 'support_alert':
    case 'support_direct':
      return _IconKind.support;
    case 'wallet_allocation':
    case 'wallet_payout':
      return _IconKind.wallet;
    case 'device_unbind':
    case 'device_unbind_request':
      return _IconKind.device;
    default:
      break;
  }
  if (type.contains('photo')) return _IconKind.photo;
  if (type.contains('subscription')) return _IconKind.subscription;
  if (type.contains('leave') ||
      type.contains('permission') ||
      type.contains('excuse')) {
    return _IconKind.leave;
  }
  if (type.contains('device')) return _IconKind.device;
  if (type.contains('support')) return _IconKind.support;
  if (type.contains('wallet')) return _IconKind.wallet;
  if (type.contains('penalty') ||
      type.contains('geofence') ||
      type.contains('mock_location')) {
    return _IconKind.penalty;
  }
  if (type.contains('task')) return _IconKind.task;
  if (type.contains('check_in')) return _IconKind.checkIn;
  if (type.contains('check_out')) return _IconKind.checkOut;
  if (type.contains('update') || type.contains('announce')) {
    return _IconKind.notice;
  }
  return _IconKind.neutral;
}

IconData _iconFor(String type) {
  final kind = _kindFor(type);
  switch (kind) {
    case _IconKind.checkIn:
      return Icons.login_rounded;
    case _IconKind.checkOut:
      return Icons.logout_rounded;
    case _IconKind.notice:
      return type == 'announcement'
          ? Icons.campaign_rounded
          : Icons.system_update_rounded;
    case _IconKind.penalty:
      return type.contains('geofence') || type.contains('mock')
          ? Icons.warning_rounded
          : Icons.gavel_rounded;
    case _IconKind.photo:
      return Icons.photo_camera_rounded;
    case _IconKind.subscription:
      if (type == 'subscription_rejected') return Icons.person_off_rounded;
      if (type == 'subscription_approved') return Icons.how_to_reg_rounded;
      if (type == 'subscription_renewal_reminder') {
        return Icons.event_repeat_rounded;
      }
      return Icons.person_add_rounded;
    case _IconKind.task:
      return Icons.task_alt_rounded;
    case _IconKind.leave:
      return Icons.assignment_rounded;
    case _IconKind.support:
      return Icons.support_agent_rounded;
    case _IconKind.wallet:
      return type == 'wallet_payout'
          ? Icons.payments_rounded
          : Icons.account_balance_wallet_rounded;
    case _IconKind.device:
      return Icons.phonelink_lock_rounded;
    case _IconKind.neutral:
      return Icons.notifications_rounded;
  }
}

class _Tone {
  final Color background;
  final Color foreground;

  const _Tone(this.background, this.foreground);
}

/// Light and dark pairs. Each pair stays above 4.5:1 so the glyph reads
/// on the tint in both themes. Unknown types stay on the neutral surface.
const _kTones = <_IconKind, (Color, Color, Color, Color)>{
  _IconKind.checkIn: (
    Color(0xFFE7F5EC),
    Color(0xFF0D652D),
    Color(0xFF1B3A28),
    Color(0xFF8FD9A8),
  ),
  _IconKind.checkOut: (
    Color(0xFFFEF4D8),
    Color(0xFF8A4B00),
    Color(0xFF3D2E12),
    Color(0xFFF5D48A),
  ),
  _IconKind.notice: (
    Color(0xFFE8F0FE),
    Color(0xFF185ABC),
    Color(0xFF1A3058),
    Color(0xFFA8C7FA),
  ),
  _IconKind.penalty: (
    Color(0xFFFDE8E4),
    Color(0xFF8C2F1B),
    Color(0xFF3F241C),
    Color(0xFFF2B8A8),
  ),
  _IconKind.photo: (
    Color(0xFFE0F4F3),
    Color(0xFF00695C),
    Color(0xFF0E3330),
    Color(0xFF8FD4CC),
  ),
  _IconKind.subscription: (
    Color(0xFFF3E8FD),
    Color(0xFF6A1B9A),
    Color(0xFF3A2448),
    Color(0xFFE2C2F5),
  ),
  _IconKind.task: (
    Color(0xFFE8EAF6),
    Color(0xFF283593),
    Color(0xFF22244A),
    Color(0xFFC5C8F5),
  ),
  _IconKind.leave: (
    Color(0xFFE0F7FA),
    Color(0xFF006064),
    Color(0xFF08343A),
    Color(0xFF9BE7F0),
  ),
  _IconKind.support: (
    Color(0xFFE8EEF3),
    Color(0xFF37474F),
    Color(0xFF2A343C),
    Color(0xFFC5D0D8),
  ),
  _IconKind.wallet: (
    Color(0xFFF1F4E4),
    Color(0xFF3E4E12),
    Color(0xFF2A3318),
    Color(0xFFD4E2A4),
  ),
  _IconKind.device: (
    Color(0xFFE7EEF5),
    Color(0xFF1F3A5F),
    Color(0xFF1C2A3A),
    Color(0xFFC5D4E8),
  ),
};

_Tone _toneFor(String type, Brightness brightness, ColorScheme scheme) {
  final kind = _kindFor(type);
  if (kind == _IconKind.neutral) {
    return _Tone(scheme.surfaceContainerHigh, scheme.onSurfaceVariant);
  }
  final tones = _kTones[kind]!;
  final dark = brightness == Brightness.dark;
  return _Tone(dark ? tones.$3 : tones.$1, dark ? tones.$4 : tones.$2);
}

bool _hasTarget(NotificationEntity notification) {
  if (notification.type == 'task' && (notification.taskId ?? '').isNotEmpty) {
    return true;
  }
  return notification.type == 'update' ||
      notification.title.contains('تحديث') ||
      notification.body.contains('تحديث التطبيق');
}

/// Same destinations as the expanded actions on [NotificationListItem].
Future<void> _openTarget(
  BuildContext context,
  NotificationEntity notification,
  Delegate delegate,
) async {
  if (notification.type == 'task' && (notification.taskId ?? '').isNotEmpty) {
    if (GoRouter.maybeOf(context) == null) return;
    context.push('/tasks/${notification.taskId}', extra: delegate);
    return;
  }
  try {
    final prefs = await SharedPreferences.getInstance();
    await ReviewService(prefs: prefs).openStoreListing();
  } catch (e) {
    debugPrint('Error opening store listing: $e');
  }
}
