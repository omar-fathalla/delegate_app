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
    final rawSenderRole = widget.notification.senderRole?.trim();

    final displaySenderName = (rawSenderName != null && rawSenderName.isNotEmpty)
        ? NotificationModel.sanitizeText(rawSenderName)
        : l10n.systemAdministration;
    final displaySenderRoleArabic = NotificationModel.formatSenderRoleArabic(rawSenderRole);

    final isTask = widget.notification.type == 'task' &&
        widget.notification.taskId != null;
    final isUpdate = widget.notification.type == 'update' ||
        widget.notification.title.contains('تحديث') ||
        widget.notification.body.contains('تحديث التطبيق');

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
                    Container(
                      padding: const EdgeInsets.all(TashilSpacing.sm),
                      decoration: BoxDecoration(
                        color: colorScheme.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        _getIcon(widget.notification.type),
                        color: colorScheme.onPrimary,
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
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: TashilSpacing.xs / 2),
                          Text(
                            _formatDateTime(widget.notification.createdAt),
                            style: tt.labelSmall?.copyWith(
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: const Icon(Icons.delete_rounded),
                      tooltip: l10n.deleteNotification,
                      onPressed: _confirmDelete,
                    ),
                  ],
                ),
                const SizedBox(height: TashilSpacing.sm),
                Row(
                  children: [
                    Icon(
                      Icons.person_pin_rounded,
                      size: 16,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(width: TashilSpacing.xs),
                    Flexible(
                      child: Text(
                        l10n.senderLine(
                          displaySenderName,
                          _localizedSenderRole(displaySenderRoleArabic, l10n),
                        ),
                        style: tt.labelMedium?.copyWith(
                          color: colorScheme.onSurfaceVariant,
                        ),
                        overflow: TextOverflow.ellipsis,
                      ),
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
                      if (isUnread)
                        TextButton.icon(
                          onPressed: _markAsRead,
                          icon: const Icon(Icons.done_rounded),
                          label: Text(l10n.markAsRead),
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

  String _formatDateTime(DateTime dateTime) {
    return DateFormat('dd/MM/yyyy • hh:mm a').format(dateTime);
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

/// Maps the Arabic sender role from [NotificationModel.formatSenderRoleArabic]
/// to the active locale. Unknown values are shown as-is (raw data).
String _localizedSenderRole(String arabicRole, AppLocalizations l10n) {
  switch (arabicRole) {
    case 'النظام':
      return l10n.senderRoleSystem;
    case 'مشرف الشركة':
      return l10n.senderRoleCompanySupervisor;
    case 'سوبر أدمن':
      return l10n.roleSuperAdmin;
    case 'مسؤول المنظمة':
      return l10n.senderRoleOrgAdmin;
    case 'مسؤول تسويق الفروع':
      return l10n.senderRoleBranchesMarketing;
    case 'مسؤول تسويق العروض':
      return l10n.senderRolePromotionMarketing;
    case 'مسؤول التسويق':
      return l10n.senderRoleMarketing;
    case 'الدعم الفني':
      return l10n.senderRoleTechSupport;
    case 'مروج':
    case 'مندوب':
      return l10n.roleDelegate;
  }
  return arabicRole;
}
