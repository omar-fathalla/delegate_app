import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/widgets/notification_list_item.dart';
import 'package:delegate_app/features/notifications/presentation/pages/send_notification_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class NotificationsPage extends StatelessWidget {
  final Delegate delegate;

  const NotificationsPage({super.key, required this.delegate});

  void _confirmDeleteAll(BuildContext context, List<NotificationEntity> notifications) {
    final bloc = context.read<NotificationBloc>();
    final messenger = ScaffoldMessenger.of(context);

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
        title: const Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: Colors.red),
            SizedBox(width: 8),
            Text('حذف جميع الإشعارات', style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold)),
          ],
        ),
        content: const Text(
          'هل أنت متأكد من حذف جميع الإشعارات من قائمتك؟\n(لن تظهر هذه الإشعارات في حسابك مرة أخرى، مع بقائها في السجل المركزي للنظام).',
          style: TextStyle(fontSize: 14),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: const Text('إلغاء'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: Colors.red.shade50,
              foregroundColor: Colors.red.shade700,
            ),
            onPressed: () {
              Navigator.of(dialogCtx).pop();
              final notificationIds = notifications.map((n) => n.id).toList();
              bloc.add(
                DeleteAllNotificationsRequested(
                  delegateUid: delegate.uid,
                  organizationId: delegate.organizationUID,
                  phoneNumber: delegate.phoneNumber,
                  notificationIds: notificationIds,
                ),
              );
              messenger.showSnackBar(
                const SnackBar(
                  content: Text('تم حذف جميع الإشعارات من قائمتك'),
                  duration: Duration(seconds: 2),
                ),
              );
            },
            child: const Text('حذف الكل'),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSendNotification = delegate.role == UserRole.technicalSupport ||
        delegate.role == UserRole.superAdmin;

    return BlocProvider(
      create: (_) => di.sl<NotificationBloc>()
        ..add(
          LoadNotifications(
            delegateUid: delegate.uid,
            organizationId: delegate.organizationUID,
            phoneNumber: delegate.phoneNumber,
          ),
        )
        ..add(
          SubscribeToUnreadCount(
            delegateUid: delegate.uid,
            organizationId: delegate.organizationUID,
            phoneNumber: delegate.phoneNumber,
          ),
        ),
      child: Scaffold(
        floatingActionButton: canSendNotification
            ? FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SendNotificationScreen(senderDelegate: delegate),
                    ),
                  );
                },
                icon: const Icon(Icons.send_rounded),
                label: const Text('إرسال إشعار جديد'),
              )
            : null,
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.notifications),
          actions: [
            BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, state) {
                if (state is NotificationLoaded && state.notifications.isNotEmpty) {
                  return Row(
                    mainAxisSize: MainAxisSize.min,
                    children: [
                      if (state.unreadCount > 0)
                        TextButton.icon(
                          onPressed: () {
                            context.read<NotificationBloc>().add(
                              MarkAllAsRead(
                                delegateUid: delegate.uid,
                                organizationId: delegate.organizationUID,
                                phoneNumber: delegate.phoneNumber,
                              ),
                            );
                          },
                          icon: const Icon(Icons.done_all, size: 18),
                          label: Text(
                            AppLocalizations.of(context)!.markAllRead,
                            style: const TextStyle(fontSize: 12),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                        ),
                      IconButton(
                        tooltip: 'حذف جميع الإشعارات',
                        icon: const Icon(Icons.delete_sweep_outlined, color: Colors.redAccent),
                        onPressed: () => _confirmDeleteAll(context, state.notifications),
                      ),
                    ],
                  );
                }
                return const SizedBox.shrink();
              },
            ),
          ],
        ),
        body: BlocBuilder<NotificationBloc, NotificationState>(
          builder: (context, state) {
            if (state is NotificationLoading) {
              return const Center(child: CircularProgressIndicator());
            }

            if (state is NotificationError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline,
                      size: 64,
                      color: Theme.of(context).colorScheme.error,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      state.message,
                      style: Theme.of(context).textTheme.bodyLarge,
                      textAlign: TextAlign.center,
                    ),
                  ],
                ),
              );
            }

            if (state is NotificationLoaded) {
              if (state.notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none,
                        size: 64,
                        color: Theme.of(context).colorScheme.outline,
                      ),
                      const SizedBox(height: 16),
                      Text(
                        AppLocalizations.of(context)!.noNotifications,
                        style: Theme.of(context).textTheme.bodyLarge,
                      ),
                    ],
                  ),
                );
              }

              return RefreshIndicator(
                onRefresh: () async {
                  context.read<NotificationBloc>().add(
                    LoadNotifications(
                      delegateUid: delegate.uid,
                      organizationId: delegate.organizationUID,
                      phoneNumber: delegate.phoneNumber,
                    ),
                  );
                },
                child: ListView.builder(
                  itemCount: state.notifications.length,
                  itemBuilder: (context, index) {
                    final notification = state.notifications[index];
                    return NotificationListItem(
                      notification: notification,
                      delegate: delegate,
                      isFirst: index == 0, // فقط الأول يكون مفتوح
                    );
                  },
                ),
              );
            }

            return const SizedBox.shrink();
          },
        ),
      ),
    );
  }
}
