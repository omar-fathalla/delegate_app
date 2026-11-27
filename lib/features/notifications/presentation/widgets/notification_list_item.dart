import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:go_router/go_router.dart';
import 'package:intl/intl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/core/services/review_service.dart';

class NotificationListItem extends StatefulWidget {
  final NotificationEntity notification;
  final Delegate delegate;
  final bool isFirst;

  const NotificationListItem({
    super.key,
    required this.notification,
    required this.delegate,
    this.isFirst = false,
  });

  @override
  State<NotificationListItem> createState() => _NotificationListItemState();
}

class _NotificationListItemState extends State<NotificationListItem> {
  bool _isExpanded = false;

  @override
  void initState() {
    super.initState();
    _isExpanded = widget.isFirst;
  }

  void _markAsRead() {
    if (!widget.notification.isRead) {
      context.read<NotificationBloc>().add(
        MarkAsRead(
          notificationId: widget.notification.id,
          delegateUid: widget.delegate.uid,
          organizationId: widget.delegate.organizationUID,
        ),
      );
    }
  }

  // TAS-356 (C-27): kit dialog, text buttons, the confirm says what happens.
  void _confirmDelete() {
    final l10n = AppLocalizations.of(context)!;
    final bloc = context.read<NotificationBloc>();

    showTashilDialog<void>(
      context: context,
      builder: (ctx) => AlertDialog(
        key: const Key('deleteNotificationDialog'),
        title: Text(l10n.deleteNotification),
        content: Text(l10n.deleteNotificationConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
            onPressed: () {
              Navigator.of(ctx).pop();
              bloc.add(
                DeleteNotificationRequested(
                  notificationId: widget.notification.id,
                  delegateUid: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                ),
              );
              if (mounted) showTashilSnackBar(context, l10n.notificationDeleted);
            },
            child: Text(l10n.delete),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final l10n = AppLocalizations.of(context)!;
    final isUnread = !widget.notification.isRead;

    // Sanitize title, body, and resolve sender info
    final cleanTitle = NotificationModel.sanitizeText(widget.notification.title);
    final cleanBody = NotificationModel.sanitizeText(widget.notification.body);
    final rawSenderName = widget.notification.senderName?.trim();

    final displaySenderName = (rawSenderName != null && rawSenderName.isNotEmpty)
        ? NotificationModel.sanitizeText(rawSenderName)
        : l10n.systemAdministration;

    final isTask = widget.notification.type == 'task' &&
        widget.notification.taskId != null;
    final isUpdate = widget.notification.type == 'update' ||
        widget.notification.title.contains('تحديث') ||
        widget.notification.body.contains('تحديث التطبيق');

    final kind = _kindOf(context, widget.notification.type, l10n);
    // TAS-356: one Card.filled per notification, the type icon on primary +
    // onPrimary (TAS-384 rule), text from the textTheme; unread = dot and a
    // stronger title, no tinted borders.
    return Dismissible(
      key: Key(widget.notification.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        _confirmDelete();
        return false; // let dialog handle the actual deletion
      },
      background: Container(
        margin: const EdgeInsetsDirectional.symmetric(
          horizontal: TashilSpacing.lg,
          vertical: TashilSpacing.xs,
        ),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(TashilRadius.medium),
        ),
        alignment: AlignmentDirectional.centerEnd,
        padding: const EdgeInsetsDirectional.only(end: TashilSpacing.xl),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_rounded, color: colorScheme.onErrorContainer),
            const SizedBox(width: TashilSpacing.sm),
            Text(
              l10n.delete,
              style: tt.labelLarge?.copyWith(color: colorScheme.onErrorContainer),
            ),
          ],
        ),
      ),
      child: Card.filled(
        margin: const EdgeInsetsDirectional.symmetric(
          horizontal: TashilSpacing.lg,
          vertical: TashilSpacing.xs,
        ),
        clipBehavior: Clip.antiAlias,
        child: InkWell(
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
            if (_isExpanded && isUnread) {
              _markAsRead();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(TashilSpacing.md),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    // Notifications colour rule (user decision 27 Nov,
                    // TAS-387): each kind gets its own role pair so the list
                    // reads at a glance; still roles, never hex.
                    Container(
                      key: const Key('notificationTypeIcon'),
                      padding: const EdgeInsets.all(TashilSpacing.sm),
                      decoration: BoxDecoration(
                        color: kind.fill,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(widget.notification.type),
                        color: kind.onFill,
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: TashilSpacing.md),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cleanTitle,
                                  style: (isUnread ? tt.titleSmall : tt.bodyLarge)
                                      ?.copyWith(color: colorScheme.onSurface),
                                  maxLines: _isExpanded ? null : 1,
                                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                                ),
                              ),
                              if (isUnread)
                                Container(
                                  key: const Key('notificationUnreadDot'),
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsetsDirectional.only(
                                    start: TashilSpacing.sm,
                                  ),
                                  decoration: BoxDecoration(
                                    color: kind.fill,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: TashilSpacing.xs),
                          Wrap(
                            spacing: TashilSpacing.sm,
                            runSpacing: TashilSpacing.xs,
                            crossAxisAlignment: WrapCrossAlignment.center,
                            children: [
                              Container(
                                key: const Key('notificationKindLabel'),
                                padding: const EdgeInsetsDirectional.symmetric(
                                  horizontal: TashilSpacing.sm,
                                  vertical: TashilSpacing.xs / 2,
                                ),
                                decoration: BoxDecoration(
                                  color: kind.container,
                                  borderRadius: BorderRadius.circular(
                                    TashilRadius.small,
                                  ),
                                ),
                                child: Text(
                                  kind.label,
                                  style: tt.labelSmall?.copyWith(
                                    color: kind.onContainer,
                                  ),
                                ),
                              ),
                              Text(
                                '$displaySenderName · ${_formatDateTime(widget.notification.createdAt)}',
                                style: tt.labelSmall?.copyWith(
                                  color: colorScheme.onSurfaceVariant,
                                ),
                              ),
                            ],
                          ),
                        ],
                      ),
                    ),
                    // Actions on the item in a menu (C-24), not a trash
                    // button on every card; swipe still deletes.
                    MenuAnchor(
                      builder: (context, controller, _) => IconButton(
                        key: const Key('notificationMenuButton'),
                        icon: const Icon(Icons.more_vert_rounded),
                        tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                        onPressed: () => controller.isOpen
                            ? controller.close()
                            : controller.open(),
                      ),
                      menuChildren: [
                        if (isUnread)
                          MenuItemButton(
                            leadingIcon: const Icon(Icons.done_rounded),
                            onPressed: _markAsRead,
                            child: Text(l10n.markAsRead),
                          ),
                        MenuItemButton(
                          leadingIcon: const Icon(Icons.delete_outline_rounded),
                          onPressed: _confirmDelete,
                          child: Text(l10n.deleteNotification),
                        ),
                      ],
                    ),
                  ],
                ),
                const SizedBox(height: TashilSpacing.xs),
                Text(
                  cleanBody,
                  style: tt.bodyMedium?.copyWith(
                    color: colorScheme.onSurfaceVariant,
                  ),
                  maxLines: _isExpanded ? null : 2,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                ),
                if (_isExpanded) ...[
                  const Divider(height: TashilSpacing.xl),
                  Wrap(
                    alignment: WrapAlignment.spaceBetween,
                    crossAxisAlignment: WrapCrossAlignment.center,
                    spacing: TashilSpacing.sm,
                    runSpacing: TashilSpacing.xs,
                    children: [
                      Text(
                        _formatTimeAgo(widget.notification.createdAt),
                        style: tt.labelSmall?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                      ),
                      if (isTask)
                        FilledButton.tonalIcon(
                          onPressed: () {
                            _markAsRead();
                            context.push(
                              '/tasks/${widget.notification.taskId}',
                              extra: widget.delegate,
                            );
                          },
                          icon: const Icon(Icons.arrow_forward_rounded),
                          label: Text(l10n.viewTask),
                        ),
                      if (isUpdate)
                        FilledButton.icon(
                          onPressed: () async {
                            _markAsRead();
                            try {
                              final prefs = await SharedPreferences.getInstance();
                              await ReviewService(prefs: prefs).openStoreListing();
                            } catch (e) {
                              debugPrint('Error opening store listing: $e');
                            }
                          },
                          icon: const Icon(Icons.system_update_rounded),
                          label: Text(l10n.updateAppNow),
                        ),
                    ],
                  ),
                ],
              ],
            ),
          ),
        ),
      ),
    );
  }


  IconData _getIcon(String type) {
    switch (type) {
      case 'attendance_check_in':
        return Icons.login_rounded;
      case 'attendance_check_out':
        return Icons.logout_rounded;
      case 'penalty':
        return Icons.gavel_rounded;
      case 'photo_permission':
      case 'permission':
        return Icons.camera_alt_rounded;
      case 'delegate_subscription_request':
        return Icons.person_add_alt_1_rounded;
      case 'subscription_approved':
        return Icons.how_to_reg_rounded;
      case 'subscription_renewal_reminder':
        return Icons.event_available_rounded;
      case 'subscription_rejected':
        return Icons.person_off_rounded;
      case 'leave_approved':
        return Icons.event_available_rounded;
      case 'leave_rejected':
        return Icons.event_busy_rounded;
      case 'attendance_adjusted':
        return Icons.edit_calendar_rounded;
      case 'device_unbound':
        return Icons.phonelink_erase_rounded;
      case 'device_unbind_rejected':
        return Icons.phonelink_lock_rounded;
      case 'geofence_violation':
      case 'security_violation':
        return Icons.wrong_location_rounded;
      case 'task':
        return Icons.task_alt_rounded;
      case 'support_alert':
      case 'support_direct':
        return Icons.support_agent_rounded;
      case 'wallet_allocation':
        return Icons.account_balance_wallet_rounded;
      case 'wallet_payout':
        return Icons.payments_rounded;
      case 'update':
        return Icons.system_update_rounded;
      case 'announcement':
        return Icons.campaign_rounded;
      default:
        return Icons.notifications_active_rounded;
    }
  }

  // TAS-387: date and time in the app language (ص / م in Arabic).
  String _formatDateTime(DateTime dateTime) {
    final locale = Localizations.localeOf(context).languageCode;
    return DateFormat('d MMMM • h:mm a', locale).format(dateTime);
  }

  String _formatTimeAgo(DateTime dateTime) {
    final now = DateTime.now();
    final difference = now.difference(dateTime);

    if (difference.inDays > 7) {
      return DateFormat('dd/MM/yyyy').format(dateTime);
    } else if (difference.inDays > 0) {
      return AppLocalizations.of(context)!.timeAgoDays(difference.inDays);
    } else if (difference.inHours > 0) {
      return AppLocalizations.of(context)!.timeAgoHours(difference.inHours);
    } else if (difference.inMinutes > 0) {
      return AppLocalizations.of(context)!.timeAgoMinutes(difference.inMinutes);
    } else {
      return AppLocalizations.of(context)!.justNow;
    }
  }
}

/// The colour family of a notification kind (TAS-387, user decision
/// 2026-11-27): each family is a role pair, so kinds stay apart at a glance
/// in both themes and under the user's seed colour.
class _Kind {
  const _Kind(this.fill, this.onFill, this.container, this.onContainer, this.label);
  final Color fill;
  final Color onFill;
  final Color container;
  final Color onContainer;
  final String label;
}

_Kind _kindOf(BuildContext context, String type, AppLocalizations l10n) {
  final cs = Theme.of(context).colorScheme;
  final sem = Theme.of(context).extension<TashilSemanticColors>();
  switch (type) {
    // Needs attention: something against the delegate or refused.
    case 'penalty':
    case 'leave_rejected':
    case 'subscription_rejected':
    case 'device_unbind_rejected':
    case 'geofence_violation':
    case 'security_violation':
      return _Kind(cs.error, cs.onError, cs.errorContainer,
          cs.onErrorContainer, l10n.notifKindAttention);
    // Done in the delegate's favour.
    case 'leave_approved':
    case 'subscription_approved':
    case 'wallet_payout':
    case 'wallet_allocation':
    case 'device_unbound':
      return _Kind(
        sem?.success ?? cs.primary,
        sem?.onSuccess ?? cs.onPrimary,
        sem?.successContainer ?? cs.primaryContainer,
        sem?.onSuccessContainer ?? cs.onPrimaryContainer,
        l10n.notifKindDone,
      );
    // A change the delegate should know about.
    case 'attendance_adjusted':
    case 'subscription_renewal_reminder':
      return _Kind(
        sem?.warning ?? cs.tertiary,
        sem?.onWarning ?? cs.onTertiary,
        sem?.warningContainer ?? cs.tertiaryContainer,
        sem?.onWarningContainer ?? cs.onTertiaryContainer,
        l10n.notifKindChange,
      );
    // Work for the delegate.
    case 'task':
    case 'photo_permission':
    case 'permission':
      return _Kind(cs.primary, cs.onPrimary, cs.primaryContainer,
          cs.onPrimaryContainer, l10n.notifKindWork);
    case 'attendance_check_in':
    case 'attendance_check_out':
      return _Kind(cs.secondary, cs.onSecondary, cs.secondaryContainer,
          cs.onSecondaryContainer, l10n.notifKindAttendance);
    // News: announcements, updates, support.
    default:
      return _Kind(cs.tertiary, cs.onTertiary, cs.tertiaryContainer,
          cs.onTertiaryContainer, l10n.notifKindInfo);
  }
}
