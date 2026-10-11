import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/data/models/notification_model.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:flutter/material.dart';
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

  void _confirmDelete() {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (ctx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.delete_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            Text(
              'حذف الإشعار',
              style: TextStyle(
                fontSize: 18,
                fontWeight: FontWeight.bold,
                color: colorScheme.onSurface,
              ),
            ),
          ],
        ),
        content: Text(
          'هل تريد حذف هذا الإشعار من قائمة إشعاراتك؟\n(سيظل مسجلاً في سجل النظام العام).',
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(ctx).pop(),
            child: Text('إلغاء', style: TextStyle(color: colorScheme.primary)),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
            ),
            onPressed: () {
              Navigator.of(ctx).pop();
              context.read<NotificationBloc>().add(
                DeleteNotificationRequested(
                  notificationId: widget.notification.id,
                  delegateUid: widget.delegate.uid,
                  organizationId: widget.delegate.organizationUID,
                ),
              );
              ScaffoldMessenger.of(context).showSnackBar(
                SnackBar(
                  content: const Text('تم حذف الإشعار من قائمتك'),
                  backgroundColor: colorScheme.inverseSurface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final colorScheme = Theme.of(context).colorScheme;
    final isUnread = !widget.notification.isRead;

    // Sanitize title, body, and resolve sender info
    final cleanTitle = NotificationModel.sanitizeText(widget.notification.title);
    final cleanBody = NotificationModel.sanitizeText(widget.notification.body);
    final rawSenderName = widget.notification.senderName?.trim();
    final rawSenderRole = widget.notification.senderRole?.trim();

    final displaySenderName = (rawSenderName != null && rawSenderName.isNotEmpty)
        ? NotificationModel.sanitizeText(rawSenderName)
        : 'إدارة النظام';
    final displaySenderRoleArabic = NotificationModel.formatSenderRoleArabic(rawSenderRole);

    return Dismissible(
      key: Key(widget.notification.id),
      direction: DismissDirection.endToStart,
      confirmDismiss: (direction) async {
        _confirmDelete();
        return false; // let dialog handle the actual deletion
      },
      background: Container(
        margin: const EdgeInsets.symmetric(horizontal: 16, vertical: 5),
        decoration: BoxDecoration(
          color: colorScheme.errorContainer,
          borderRadius: BorderRadius.circular(16),
        ),
        alignment: Alignment.centerLeft,
        padding: const EdgeInsets.only(left: 20),
        child: Row(
          mainAxisSize: MainAxisSize.min,
          children: [
            Icon(Icons.delete_rounded, color: colorScheme.onErrorContainer, size: 24),
            const SizedBox(width: 8),
            Text(
              'حذف',
              style: TextStyle(
                color: colorScheme.onErrorContainer,
                fontWeight: FontWeight.bold,
              ),
            ),
          ],
        ),
      ),
      child: Card(
        elevation: 0,
        margin: const EdgeInsets.symmetric(horizontal: 14, vertical: 5),
        shape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(16),
          side: BorderSide(
            color: isUnread
                ? colorScheme.primary.withValues(alpha: 0.35)
                : colorScheme.outlineVariant.withValues(alpha: 0.35),
            width: isUnread ? 1.3 : 0.9,
          ),
        ),
        color: isUnread
            ? colorScheme.surfaceContainerLow
            : colorScheme.surfaceContainerLowest,
        child: InkWell(
          borderRadius: BorderRadius.circular(16),
          onTap: () {
            setState(() {
              _isExpanded = !_isExpanded;
            });
            if (_isExpanded && isUnread) {
              _markAsRead();
            }
          },
          child: Padding(
            padding: const EdgeInsets.all(12),
            child: Column(
              crossAxisAlignment: CrossAxisAlignment.start,
              children: [
                // Top Row: Icon + Title + Time + Unread indicator
                Row(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Container(
                      padding: const EdgeInsets.all(8),
                      decoration: BoxDecoration(
                        color: _getIconBackgroundColor(widget.notification.type, colorScheme),
                        borderRadius: BorderRadius.circular(12),
                      ),
                      child: Icon(
                        _getIcon(widget.notification.type),
                        color: _getIconColor(widget.notification.type, colorScheme),
                        size: 20,
                      ),
                    ),
                    const SizedBox(width: 10),
                    Expanded(
                      child: Column(
                        crossAxisAlignment: CrossAxisAlignment.start,
                        children: [
                          Row(
                            children: [
                              Expanded(
                                child: Text(
                                  cleanTitle,
                                  style: TextStyle(
                                    fontSize: 14.5,
                                    fontWeight: isUnread ? FontWeight.bold : FontWeight.w600,
                                    color: colorScheme.onSurface,
                                  ),
                                  maxLines: _isExpanded ? null : 1,
                                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                                ),
                              ),
                              if (isUnread)
                                Container(
                                  width: 8,
                                  height: 8,
                                  margin: const EdgeInsets.only(right: 6),
                                  decoration: BoxDecoration(
                                    color: colorScheme.primary,
                                    shape: BoxShape.circle,
                                  ),
                                ),
                            ],
                          ),
                          const SizedBox(height: 3),
                          Text(
                            _formatDateTime(widget.notification.createdAt),
                            style: TextStyle(
                              fontSize: 11.5,
                              color: colorScheme.outline,
                              fontWeight: FontWeight.normal,
                            ),
                          ),
                        ],
                      ),
                    ),
                    IconButton(
                      icon: Icon(
                        Icons.delete_rounded,
                        size: 19,
                        color: colorScheme.onSurfaceVariant.withValues(alpha: 0.6),
                      ),
                      tooltip: 'حذف الإشعار',
                      onPressed: _confirmDelete,
                      visualDensity: VisualDensity.compact,
                      padding: EdgeInsets.zero,
                      constraints: const BoxConstraints(),
                    ),
                  ],
                ),

                // Sender Info Pill
                Container(
                  margin: const EdgeInsets.only(top: 8, bottom: 4),
                  padding: const EdgeInsets.symmetric(horizontal: 8, vertical: 3),
                  decoration: BoxDecoration(
                    color: colorScheme.surfaceContainerHighest.withValues(alpha: 0.4),
                    borderRadius: BorderRadius.circular(8),
                    border: Border.all(
                      color: colorScheme.outlineVariant.withValues(alpha: 0.35),
                      width: 0.8,
                    ),
                  ),
                  child: Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      Icon(
                        Icons.person_pin_rounded,
                        size: 13,
                        color: colorScheme.primary,
                      ),
                      const SizedBox(width: 4),
                      Flexible(
                        child: Text(
                          'المرسل: $displaySenderName ($displaySenderRoleArabic)',
                          style: TextStyle(
                            fontSize: 11,
                            fontWeight: FontWeight.w600,
                            color: colorScheme.onSurfaceVariant,
                          ),
                          overflow: TextOverflow.ellipsis,
                        ),
                      ),
                    ],
                  ),
                ),

                const SizedBox(height: 4),

                // Body text (compact or expanded)
                Text(
                  cleanBody,
                  style: TextStyle(
                    fontSize: 13,
                    color: colorScheme.onSurfaceVariant,
                    height: 1.4,
                  ),
                  maxLines: _isExpanded ? null : 2,
                  overflow: _isExpanded ? null : TextOverflow.ellipsis,
                ),

                // Expanded Action Buttons
                if (_isExpanded) ...[
                  const SizedBox(height: 10),
                  Divider(height: 1, color: colorScheme.outlineVariant.withValues(alpha: 0.4)),
                  const SizedBox(height: 6),
                  Row(
                    mainAxisAlignment: MainAxisAlignment.spaceBetween,
                    children: [
                      Text(
                        _formatTimeAgo(widget.notification.createdAt),
                        style: TextStyle(fontSize: 11, color: colorScheme.outline),
                      ),
                      Row(
                        children: [
                          if (isUnread)
                            TextButton.icon(
                              onPressed: _markAsRead,
                              icon: Icon(Icons.check_circle_rounded, size: 16, color: colorScheme.primary),
                              label: Text(
                                'تعليم كمقروء',
                                style: TextStyle(
                                  fontSize: 12,
                                  color: colorScheme.primary,
                                  fontWeight: FontWeight.w600,
                                ),
                              ),
                              style: TextButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 8),
                              ),
                            ),
                          if (widget.notification.type == 'task' &&
                              widget.notification.taskId != null)
                            FilledButton.tonalIcon(
                              onPressed: () {
                                _markAsRead();
                                context.push(
                                  '/tasks/${widget.notification.taskId}',
                                  extra: widget.delegate,
                                );
                              },
                              icon: const Icon(Icons.arrow_forward_rounded, size: 16),
                              label: const Text('عرض المهمة', style: TextStyle(fontSize: 12)),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 10),
                              ),
                            ),
                          if (widget.notification.type == 'update' ||
                              widget.notification.title.contains('تحديث') ||
                              widget.notification.body.contains('تحديث التطبيق'))
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
                              icon: const Icon(Icons.system_update_rounded, size: 16),
                              label: const Text(
                                'تحديث التطبيق الآن',
                                style: TextStyle(fontSize: 12, fontWeight: FontWeight.bold),
                              ),
                              style: FilledButton.styleFrom(
                                visualDensity: VisualDensity.compact,
                                padding: const EdgeInsets.symmetric(horizontal: 12),
                                backgroundColor: colorScheme.primary,
                                foregroundColor: colorScheme.onPrimary,
                              ),
                            ),
                        ],
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

  Color _getIconColor(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'attendance_check_in':
        return colorScheme.primary;
      case 'attendance_check_out':
        return colorScheme.secondary;
      case 'penalty':
      case 'subscription_rejected':
        return colorScheme.error;
      case 'photo_permission':
      case 'permission':
        return colorScheme.tertiary;
      case 'delegate_subscription_request':
      case 'subscription_approved':
      case 'task':
        return colorScheme.primary;
      case 'wallet_allocation':
      case 'wallet_payout':
        return Colors.teal.shade700;
      case 'support_alert':
      case 'support_direct':
        return colorScheme.secondary;
      case 'update':
      case 'announcement':
        return colorScheme.tertiary;
      default:
        return colorScheme.onSurfaceVariant;
    }
  }

  Color _getIconBackgroundColor(String type, ColorScheme colorScheme) {
    switch (type) {
      case 'attendance_check_in':
        return colorScheme.primaryContainer;
      case 'attendance_check_out':
        return colorScheme.secondaryContainer;
      case 'penalty':
      case 'subscription_rejected':
        return colorScheme.errorContainer;
      case 'photo_permission':
      case 'permission':
        return colorScheme.tertiaryContainer;
      case 'delegate_subscription_request':
      case 'subscription_approved':
        return colorScheme.primaryContainer;
      case 'wallet_allocation':
      case 'wallet_payout':
        return Colors.teal.shade50;
      case 'task':
        return colorScheme.primaryContainer.withValues(alpha: 0.6);
      case 'support_alert':
      case 'support_direct':
        return colorScheme.secondaryContainer;
      case 'update':
      case 'announcement':
        return colorScheme.tertiaryContainer;
      default:
        return colorScheme.surfaceContainerHighest;
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
      return 'منذ ${difference.inDays} ${difference.inDays == 1 ? 'يوم' : 'أيام'}';
    } else if (difference.inHours > 0) {
      return 'منذ ${difference.inHours} ${difference.inHours == 1 ? 'ساعة' : 'ساعات'}';
    } else if (difference.inMinutes > 0) {
      return 'منذ ${difference.inMinutes} ${difference.inMinutes == 1 ? 'دقيقة' : 'دقائق'}';
    } else {
      return 'الآن';
    }
  }
}
