import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/notifications/presentation/widgets/notification_list_item.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class NotificationsPage extends StatelessWidget {
  final Delegate delegate;

  const NotificationsPage({super.key, required this.delegate});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) => di.sl<NotificationBloc>()
        ..add(
          LoadNotifications(
            delegateUid: delegate.uid,
            organizationId: delegate.organizationUID,
          ),
        )
        ..add(
          SubscribeToUnreadCount(
            delegateUid: delegate.uid,
            organizationId: delegate.organizationUID,
          ),
        ),
      child: Scaffold(
        appBar: AppBar(
          title: Text(AppLocalizations.of(context)!.notifications),
          actions: [
            BlocBuilder<NotificationBloc, NotificationState>(
              builder: (context, state) {
                if (state is NotificationLoaded && state.unreadCount > 0) {
                  return TextButton.icon(
                    onPressed: () {
                      context.read<NotificationBloc>().add(
                        MarkAllAsRead(
                          delegateUid: delegate.uid,
                          organizationId: delegate.organizationUID,
                        ),
                      );
                    },
                    icon: const Icon(Icons.done_all),
                    label: Text(AppLocalizations.of(context)!.markAllRead),
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
