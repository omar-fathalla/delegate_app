import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/core/network/connectivity_status.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/notifications/domain/entities/notification_entity.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/widgets/notification_list_item.dart';
import 'package:delegate_app/features/notifications/presentation/pages/send_notification_screen.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class NotificationsPage extends StatelessWidget {
  final Delegate delegate;

  const NotificationsPage({super.key, required this.delegate});

  // TAS-356 (C-27): kit dialog, text buttons, the confirm says what
  // happens; the result is a text-only snackbar.
  void _confirmDeleteAll(BuildContext context, List<NotificationEntity> notifications) {
    final bloc = context.read<NotificationBloc>();
    final l10n = AppLocalizations.of(context)!;

    showTashilDialog<void>(
      context: context,
      builder: (dialogCtx) => AlertDialog(
        key: const Key('deleteAllNotificationsDialog'),
        title: Text(l10n.deleteAllNotifications),
        content: Text(l10n.deleteAllNotificationsConfirm),
        actions: [
          TextButton(
            onPressed: () => Navigator.of(dialogCtx).pop(),
            child: Text(l10n.cancel),
          ),
          TextButton(
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
              if (context.mounted) {
                showTashilSnackBar(context, l10n.allNotificationsDeleted);
              }
            },
            child: Text(l10n.deleteAll),
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
                icon: const Icon(Icons.send_rounded),
                label: Text(AppLocalizations.of(context)!.sendNewNotification),
              )
            : null,
        // TAS-356 (C-21): the app bar takes its colour and scrolled state
        // from the theme, like every inner page.
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
                          icon: const Icon(Icons.done_all_rounded),
                          label: Text(AppLocalizations.of(context)!.markAllRead),
                        ),
                      IconButton(
                        tooltip: AppLocalizations.of(context)!.deleteAllNotifications,
                        icon: const Icon(Icons.delete_sweep_rounded),
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
                    const SizedBox(height: TashilSpacing.lg),
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
                    padding: const EdgeInsets.all(TashilSpacing.xxl),
                    child: Column(
                      mainAxisAlignment: MainAxisAlignment.center,
                      children: [
                        Icon(Icons.cloud_off_rounded, size: 64, color: cs.onSurfaceVariant),
                        const SizedBox(height: TashilSpacing.lg),
                        Text(
                          AppLocalizations.of(context)!.offlineNotifications,
                          style: Theme.of(context).textTheme.bodyLarge,
                          textAlign: TextAlign.center,
                        ),
                        const SizedBox(height: TashilSpacing.lg),
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
                        color: Theme.of(context).colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: TashilSpacing.lg),
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
