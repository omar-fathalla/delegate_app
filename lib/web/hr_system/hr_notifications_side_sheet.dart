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
import 'package:material_symbols_icons/symbols.dart';
import 'package:shared_preferences/shared_preferences.dart';

/// Pinned clock for screenshots and tests. Production leaves this null.
@visibleForTesting
DateTime Function()? hrNotificationsSheetDebugNow;

DateTime _sheetNow() => hrNotificationsSheetDebugNow?.call() ?? DateTime.now();

const double _kSheetWidth = 440;
const double _kSheetMaxWidth = 480;
const double _kFullScreenBreakpoint = 600;
const int _kPageSize = 15;

/// Opens the HR notifications side sheet from the physical right edge.
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
  Animation<double>? _source;
  CurvedAnimation? _slide;

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
    if (_source != animation) {
      _slide?.dispose();
      _source = animation;
      _slide = CurvedAnimation(
        parent: animation,
        curve: AppMotionCurves.emphasizedDecelerate,
        reverseCurve: AppMotionCurves.emphasizedAccelerate,
      );
    }
    return SlideTransition(
      textDirection: TextDirection.ltr,
      position: Tween<Offset>(
        begin: const Offset(1, 0),
        end: Offset.zero,
      ).animate(_slide!),
      child: child,
    );
  }

  @override
  void dispose() {
    _slide?.dispose();
    super.dispose();
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
  final ScrollController _scroll = ScrollController();
  _SheetFilter _filter = _SheetFilter.all;
  int _limit = _kPageSize;

  @override
  void initState() {
    super.initState();
    _scroll.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scroll.removeListener(_onScroll);
    _scroll.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (!_scroll.hasClients) return;
    final position = _scroll.position;
    if (position.maxScrollExtent <= 0) return;
    if (position.pixels >= position.maxScrollExtent - 72) {
      _revealOlder();
    }
  }

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

  Future<void> _delete(NotificationEntity notification) async {
    final confirmed = await _confirmDelete(context);
    if (!confirmed || !mounted) return;
    final delegate = widget.delegate;
    context.read<NotificationBloc>().add(
      DeleteNotificationRequested(
        notificationId: notification.id,
        delegateUid: delegate.uid,
        organizationId: delegate.organizationUID,
        phoneNumber: delegate.phoneNumber,
      ),
    );
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.notificationDeleted),
      ),
    );
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
    final width = fullScreen
        ? viewport
        : _kSheetWidth.clamp(400, _kSheetMaxWidth).toDouble();

    return Align(
      alignment: Alignment.centerRight,
      child: SizedBox(
        width: width,
        height: MediaQuery.sizeOf(context).height,
        child: Material(
          key: const ValueKey('hr_notifications_side_sheet'),
          color: cs.surfaceContainerLow,
          elevation: 1,
          shadowColor: cs.shadow,
          surfaceTintColor: cs.surfaceTint.withValues(alpha: 0),
          child: DecoratedBox(
            decoration: BoxDecoration(
              border: fullScreen
                  ? null
                  : Border(
                      left: BorderSide(color: cs.outlineVariant),
                    ),
            ),
            child: SafeArea(
              child: BlocBuilder<NotificationBloc, NotificationState>(
                builder: (context, state) {
                  final loaded = state is NotificationLoaded
                      ? state.notifications
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
                      Expanded(child: _body(context, state, visible, filtered)),
                      if (hasMore)
                        Padding(
                          padding: const EdgeInsets.fromLTRB(16, 4, 16, 12),
                          child: Center(
                            child: OutlinedButton.icon(
                              key: const ValueKey('hr_notifications_older'),
                              onPressed: _revealOlder,
                              icon: const Icon(Symbols.expand_more_rounded, size: 18),
                              label: const Text('عرض الأقدم'),
                              style: OutlinedButton.styleFrom(
                                minimumSize: const Size(0, 44),
                                padding: const EdgeInsets.symmetric(horizontal: 16),
                                side: BorderSide(color: cs.outlineVariant),
                                foregroundColor: cs.onSurface,
                                textStyle: const TextStyle(
                                  fontFamily: 'Cairo',
                                  fontSize: 13,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                            ),
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
  }

  Widget _body(
    BuildContext context,
    NotificationState state,
    List<NotificationEntity> visible,
    List<NotificationEntity> filtered,
  ) {
    if (state is NotificationLoading || state is NotificationInitial) {
      return const Center(child: M3DelayedLoading());
    }
    if (state is NotificationError) {
      return _Message(
        icon: Symbols.error_rounded,
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
        icon: Symbols.notifications_off_rounded,
        text: unreadFilter ? 'لا توجد إشعارات غير مقروءة' : 'لا توجد إشعارات',
      );
    }

    final now = _sheetNow();
    final groups = _group(visible, now);
    return ListView(
      controller: _scroll,
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
        padding: const EdgeInsets.fromLTRB(8, 8, 16, 12),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            Row(
              children: [
                Expanded(
                  child: Row(
                    children: [
                      Text(
                        'الإشعارات',
                        key: const ValueKey('hr_notifications_title'),
                        style: text.titleLarge?.copyWith(
                          fontFamily: 'Cairo',
                          fontWeight: FontWeight.w700,
                          color: cs.onSurface,
                          fontSize: 22,
                        ),
                      ),
                      if (unread > 0) ...[
                        const SizedBox(width: 8),
                        _UnreadCount(unread),
                      ],
                    ],
                  ),
                ),
                IconButton(
                  key: const ValueKey('hr_notifications_close'),
                  tooltip: 'إغلاق',
                  autofocus: true,
                  onPressed: onClose,
                  icon: const Icon(Symbols.close_rounded),
                ),
              ],
            ),
            if (onMarkAll != null)
              Align(
                alignment: AlignmentDirectional.centerStart,
                child: TextButton.icon(
                  key: const ValueKey('hr_notifications_mark_all'),
                  onPressed: onMarkAll,
                  icon: Icon(Symbols.done_all_rounded, size: 18, color: cs.primary),
                  label: Text(
                    'تعليم الكل كمقروء',
                    style: TextStyle(
                      fontFamily: 'Cairo',
                      fontSize: 13,
                      fontWeight: FontWeight.w600,
                      color: cs.primary,
                    ),
                  ),
                  style: TextButton.styleFrom(
                    visualDensity: VisualDensity.compact,
                    padding: const EdgeInsets.symmetric(horizontal: 8),
                  ),
                ),
              ),
            const SizedBox(height: 4),
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
        borderRadius: BorderRadius.circular(12),
      ),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
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
        fontSize: 13,
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
      padding: const EdgeInsets.fromLTRB(16, 14, 16, 4),
      child: Text(
        label,
        style: TextStyle(
          fontFamily: 'Cairo',
          fontSize: 13,
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
  bool _hover = false;

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final notification = widget.notification;
    final unread = !notification.isRead;
    final title = NotificationModel.sanitizeText(notification.title);
    final body = NotificationModel.sanitizeText(notification.body);
    final compact = MediaQuery.sizeOf(context).width < _kFullScreenBreakpoint;
    final showLabels = _hover && !compact;
    final showMenu = _hover || compact;
    final visuals = _visuals(notification.type, cs);

    return MouseRegion(
      onEnter: (_) => setState(() => _hover = true),
      onExit: (_) => setState(() => _hover = false),
      child: InkWell(
        onTap: widget.onOpen,
        hoverColor: cs.onSurface.withValues(alpha: 0.06),
        splashColor: cs.onSurface.withValues(alpha: 0.08),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              _TypeIcon(visuals: visuals),
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
                              fontSize: 14,
                              height: 1.3,
                              fontWeight: unread ? FontWeight.w700 : FontWeight.w500,
                              color: cs.onSurface,
                            ),
                          ),
                        ),
                        if (!showLabels) ...[
                          const SizedBox(width: 8),
                          Text(
                            _formatWhen(notification.createdAt, widget.now),
                            style: TextStyle(
                              fontFamily: 'Cairo',
                              fontSize: 12,
                              color: cs.onSurfaceVariant,
                            ),
                          ),
                        ],
                        if (showLabels) ...[
                          const SizedBox(width: 4),
                          if (unread)
                            _ActionLabel(
                              label: 'تحديد كمقروء',
                              color: cs.primary,
                              onPressed: widget.onMarkRead,
                            ),
                          _ActionLabel(
                            label: 'حذف',
                            color: cs.error,
                            onPressed: widget.onDelete,
                          ),
                        ],
                        if (showMenu)
                          _OverflowMenu(
                            unread: unread,
                            onMarkRead: widget.onMarkRead,
                            onDelete: widget.onDelete,
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
                            fontSize: 13,
                            height: 1.35,
                            color: cs.onSurfaceVariant,
                          ),
                        ),
                      ),
                  ],
                ),
              ),
            ],
          ),
        ),
      ),
    );
  }
}

class _ActionLabel extends StatelessWidget {
  final String label;
  final Color color;
  final VoidCallback onPressed;

  const _ActionLabel({
    required this.label,
    required this.color,
    required this.onPressed,
  });

  @override
  Widget build(BuildContext context) {
    return TextButton(
      onPressed: onPressed,
        style: TextButton.styleFrom(
          foregroundColor: color,
          visualDensity: VisualDensity.compact,
          tapTargetSize: MaterialTapTargetSize.shrinkWrap,
          minimumSize: const Size(0, 32),
          padding: const EdgeInsets.symmetric(horizontal: 6),
        textStyle: const TextStyle(
          fontFamily: 'Cairo',
          fontSize: 12,
          fontWeight: FontWeight.w600,
        ),
      ),
      child: Text(label),
    );
  }
}

class _OverflowMenu extends StatelessWidget {
  final bool unread;
  final VoidCallback onMarkRead;
  final VoidCallback onDelete;

  const _OverflowMenu({
    required this.unread,
    required this.onMarkRead,
    required this.onDelete,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    return PopupMenuButton<String>(
      tooltip: 'المزيد',
      icon: Icon(Symbols.more_vert_rounded, size: 18, color: cs.onSurfaceVariant),
      color: cs.surfaceContainerHigh,
      elevation: 3,
      padding: EdgeInsets.zero,
      style: IconButton.styleFrom(
        visualDensity: VisualDensity.compact,
        tapTargetSize: MaterialTapTargetSize.shrinkWrap,
        minimumSize: const Size(32, 32),
      ),
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(14),
        side: BorderSide(color: cs.outlineVariant.withValues(alpha: 0.5)),
      ),
      onSelected: (value) {
        if (value == 'read') onMarkRead();
        if (value == 'delete') onDelete();
      },
      itemBuilder: (context) => [
        if (unread)
          PopupMenuItem(
            value: 'read',
            child: _MenuRow(icon: Symbols.mark_email_read_rounded, label: 'تحديد كمقروء'),
          ),
        PopupMenuItem(
          value: 'delete',
          child: _MenuRow(
            icon: Symbols.delete_rounded,
            label: 'حذف',
            color: cs.error,
          ),
        ),
      ],
    );
  }
}

class _MenuRow extends StatelessWidget {
  final IconData icon;
  final String label;
  final Color? color;

  const _MenuRow({required this.icon, required this.label, this.color});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final ink = color ?? cs.onSurface;
    return Row(
      children: [
        Icon(icon, size: 18, color: ink),
        const SizedBox(width: 8),
        Text(
          label,
          style: TextStyle(
            fontFamily: 'Cairo',
            fontSize: 13,
            fontWeight: FontWeight.w600,
            color: ink,
          ),
        ),
      ],
    );
  }
}

class _TypeIcon extends StatelessWidget {
  final _TypeVisuals visuals;

  const _TypeIcon({required this.visuals});

  @override
  Widget build(BuildContext context) {
    return Container(
      width: 40,
      height: 40,
      alignment: Alignment.center,
      decoration: BoxDecoration(color: visuals.background, shape: BoxShape.circle),
      child: Icon(visuals.icon, size: 20, color: visuals.foreground),
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
                fontSize: 14,
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

class _TypeVisuals {
  final IconData icon;
  final Color background;
  final Color foreground;

  const _TypeVisuals(this.icon, this.background, this.foreground);
}

_TypeVisuals _visuals(String type, ColorScheme cs) {
  if (type == 'attendance_check_in') {
    return _TypeVisuals(Symbols.login_rounded, cs.primaryContainer, cs.onPrimaryContainer);
  }
  if (type == 'attendance_check_out') {
    return _TypeVisuals(
      Symbols.logout_rounded,
      cs.surfaceContainerHigh,
      cs.onSurfaceVariant,
    );
  }
  if (_isRequest(type)) {
    return _TypeVisuals(
      _requestIcon(type),
      cs.secondaryContainer,
      cs.onSecondaryContainer,
    );
  }
  if (type == 'penalty' || type == 'subscription_rejected') {
    return _TypeVisuals(Symbols.gavel_rounded, cs.errorContainer, cs.onErrorContainer);
  }
  return _TypeVisuals(_neutralIcon(type), cs.surfaceContainerHigh, cs.onSurfaceVariant);
}

bool _isRequest(String type) {
  switch (type) {
    case 'photo_permission':
    case 'permission':
    case 'delegate_subscription_request':
    case 'subscription_renewal_reminder':
    case 'leave':
    case 'leave_request':
    case 'excuse':
    case 'device_unbind':
    case 'device_unbind_request':
      return true;
    default:
      return type.contains('request') ||
          type.contains('leave') ||
          type.contains('permission');
  }
}

IconData _requestIcon(String type) {
  if (type.contains('photo') || type == 'permission') return Symbols.photo_camera_rounded;
  if (type.contains('device')) return Symbols.phonelink_lock_rounded;
  if (type.contains('subscription')) return Symbols.person_add_rounded;
  return Symbols.assignment_rounded;
}

IconData _neutralIcon(String type) {
  switch (type) {
    case 'task':
      return Symbols.task_alt_rounded;
    case 'support_alert':
    case 'support_direct':
      return Symbols.support_agent_rounded;
    case 'wallet_allocation':
      return Symbols.account_balance_wallet_rounded;
    case 'wallet_payout':
      return Symbols.payments_rounded;
    case 'update':
      return Symbols.system_update_rounded;
    case 'announcement':
      return Symbols.campaign_rounded;
    case 'penalty':
    case 'subscription_rejected':
      return Symbols.gavel_rounded;
    default:
      return Symbols.notifications_rounded;
  }
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

Future<bool> _confirmDelete(BuildContext context) async {
  final l10n = AppLocalizations.of(context)!;
  final wide = MediaQuery.sizeOf(context).width > 768;
  if (wide) {
    final result = await showDialog<bool>(
      context: context,
      builder: (dialogContext) {
        final cs = Theme.of(dialogContext).colorScheme;
        return AlertDialog(
          shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
          title: Text(
            l10n.deleteNotification,
            style: TextStyle(
              fontFamily: 'Cairo',
              fontWeight: FontWeight.w700,
              color: cs.onSurface,
            ),
          ),
          content: Text(
            l10n.deleteNotificationConfirm,
            style: TextStyle(
              fontFamily: 'Cairo',
              color: cs.onSurfaceVariant,
            ),
          ),
          actions: [
            TextButton(
              onPressed: () => Navigator.of(dialogContext).pop(false),
              child: const Text('إلغاء'),
            ),
            FilledButton.tonal(
              style: FilledButton.styleFrom(
                backgroundColor: cs.errorContainer,
                foregroundColor: cs.onErrorContainer,
              ),
              onPressed: () => Navigator.of(dialogContext).pop(true),
              child: Text(l10n.delete),
            ),
          ],
        );
      },
    );
    return result ?? false;
  }

  final result = await showModalBottomSheet<bool>(
    context: context,
    isScrollControlled: true,
    backgroundColor: Theme.of(context).colorScheme.surfaceContainerLow,
    shape: const RoundedRectangleBorder(
      borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
    ),
    builder: (sheetContext) {
      final cs = Theme.of(sheetContext).colorScheme;
      return Padding(
        padding: EdgeInsets.only(
          bottom: MediaQuery.viewInsetsOf(sheetContext).bottom + 16,
          left: 16,
          right: 16,
          top: 8,
        ),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          children: [
            Container(
              width: 38,
              height: 4.5,
              decoration: BoxDecoration(
                color: cs.outlineVariant.withValues(alpha: 0.6),
                borderRadius: BorderRadius.circular(3),
              ),
            ),
            const SizedBox(height: 16),
            Text(
              l10n.deleteNotification,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 18,
                fontWeight: FontWeight.w700,
                color: cs.onSurface,
              ),
            ),
            const SizedBox(height: 8),
            Text(
              l10n.deleteNotificationConfirm,
              textAlign: TextAlign.center,
              style: TextStyle(
                fontFamily: 'Cairo',
                fontSize: 14,
                color: cs.onSurfaceVariant,
              ),
            ),
            const SizedBox(height: 16),
            Container(
              height: 48,
              decoration: BoxDecoration(
                borderRadius: BorderRadius.circular(24),
                border: Border.all(color: cs.outlineVariant),
              ),
              child: Row(
                children: [
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(false),
                      child: const Text('إلغاء'),
                    ),
                  ),
                  VerticalDivider(width: 1, color: cs.outlineVariant),
                  Expanded(
                    child: TextButton(
                      onPressed: () => Navigator.of(sheetContext).pop(true),
                      child: Text('حذف', style: TextStyle(color: cs.error)),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    },
  );
  return result ?? false;
}
