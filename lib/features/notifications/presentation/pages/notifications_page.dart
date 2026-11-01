import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/core/network/connectivity_status.dart';
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
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
        title: Row(
          children: [
            Icon(Icons.delete_sweep_rounded, color: colorScheme.error),
            const SizedBox(width: 8),
            Text(
              AppLocalizations.of(context)!.deleteAllNotifications,
              style: TextStyle(fontSize: 18, fontWeight: FontWeight.bold, color: colorScheme.onSurface),
            ),
          ],
        ),
        content: Text(
          AppLocalizations.of(context)!.deleteAllNotificationsConfirm,
          style: TextStyle(fontSize: 14, color: colorScheme.onSurfaceVariant),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text('إلغاء', style: TextStyle(color: colorScheme.primary)),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
              foregroundColor: colorScheme.onErrorContainer,
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
                SnackBar(
                  content: Text(AppLocalizations.of(context)!.allNotificationsDeleted),
                  backgroundColor: colorScheme.inverseSurface,
                  behavior: SnackBarBehavior.floating,
                  shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(12)),
                  duration: const Duration(seconds: 2),
                ),
              );
            },
            child: Text(AppLocalizations.of(context)!.deleteAll),
          ),
        ],
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final canSendNotification = delegate.role == UserRole.technicalSupport ||
        delegate.role == UserRole.superAdmin;
    final colorScheme = Theme.of(context).colorScheme;

    return BlocProvider(
      create: (_) => di.sl<NotificationBloc>()
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
        ),
      child: Scaffold(
        backgroundColor: colorScheme.surfaceContainerLowest,
        floatingActionButton: canSendNotification
            ? FloatingActionButton.extended(
                onPressed: () {
                  Navigator.of(context).push(
                    MaterialPageRoute(
                      builder: (_) => SendNotificationScreen(senderDelegate: delegate),
                    ),
                  );
                },
                backgroundColor: colorScheme.primaryContainer,
                foregroundColor: colorScheme.onPrimaryContainer,
                elevation: 2,
                shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(16)),
                icon: const Icon(Icons.send_rounded),
                label: Text(AppLocalizations.of(context)!.sendNewNotification),
              )
            : null,
        appBar: AppBar(
          backgroundColor: colorScheme.surfaceContainer,
          elevation: 0,
          scrolledUnderElevation: 0,
          bottom: PreferredSize(
            preferredSize: const Size.fromHeight(1.0),
            child: Container(
              color: colorScheme.outlineVariant.withValues(alpha: 0.35),
              height: 1.0,
            ),
          ),
          title: Text(
            AppLocalizations.of(context)!.notifications,
            style: TextStyle(
              fontWeight: FontWeight.bold,
              fontSize: 15,
              letterSpacing: -0.2,
              color: colorScheme.onSurface,
            ),
          ),
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
                          icon: Icon(Icons.check_circle_rounded, size: 18, color: colorScheme.primary),
                          label: Text(
                            AppLocalizations.of(context)!.markAllRead,
                            style: TextStyle(fontSize: 12, color: colorScheme.primary, fontWeight: FontWeight.w600),
                          ),
                          style: TextButton.styleFrom(
                            visualDensity: VisualDensity.compact,
                            padding: const EdgeInsets.symmetric(horizontal: 6),
                          ),
                        ),
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.deleteAllNotifications,
                        icon: Icon(Icons.delete_sweep_rounded, color: colorScheme.error),
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
              return const Center(child: M3DelayedLoading());
            }

            if (state is NotificationError) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.error_outline_rounded,
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
              if (state.notifications.isEmpty &&
                  ConnectivityStatus.instance.isOffline.value) {
                final cs = Theme.of(context).colorScheme;
                return Center(
                  child: Padding(
                    padding: const EdgeInsets.all(32),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 64, color: cs.outline),
                        const SizedBox(height: 16),
                        Text(
                          AppLocalizations.of(context)!.offlineNotifications,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: 16),
                        FilledButton.tonal(
                          onPressed: () async {
                            final bloc = context.read<NotificationBloc>();
                            if (await ConnectivityStatus.instance.recheck()) {
                              bloc.add(LoadNotifications(
                                delegateUid: delegate.uid,
                                organizationId: delegate.organizationUID,
                                phoneNumber: delegate.phoneNumber,
                                userRole: delegate.role.name,
                                accountCreatedAt: delegate.createdAt,
                              ));
                            }
                          },
                          child: Text(AppLocalizations.of(context)!.retry),
                        ),
                      ],
                    ),
                  ),
                );
              }
              if (state.notifications.isEmpty) {
                return Center(
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.notifications_none_rounded,
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
                      userRole: delegate.role.name,
                      accountCreatedAt: delegate.createdAt,
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
