import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/features/admin/presentation/widgets/admin_header.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_state.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:go_router/go_router.dart';

class AdminFeedbacksScreen extends StatelessWidget {
  const AdminFeedbacksScreen({super.key});

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (_) =>
          di.sl<AdminFeedbackBloc>()..add(const LoadAllFeedbacksEvent()),
      child: const _AdminFeedbacksView(),
    );
  }
}

class _AdminFeedbacksView extends StatelessWidget {
  const _AdminFeedbacksView();

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final colorScheme = Theme.of(context).colorScheme;

    return Scaffold(
      appBar: AdminHeader(
        subtitle: 'إدارة المقترحات',
        showBackButton: true,
        onBackPressed: () {
          if (Navigator.of(context).canPop()) {
            Navigator.of(context).pop();
          } else if (GoRouter.of(context).canPop()) {
            context.pop();
          } else {
            Navigator.of(context).maybePop();
          }
        },
      ),
      body: BlocBuilder<AdminFeedbackBloc, AdminFeedbackState>(
        builder: (context, state) {
          if (state is AdminFeedbackLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is AdminFeedbackError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(Icons.error_outline_rounded, size: 48, color: colorScheme.error),
                  const SizedBox(height: 16),
                  Text(state.message, textAlign: TextAlign.center),
                  const SizedBox(height: 16),
                  FilledButton.tonal(
                    onPressed: () => context.read<AdminFeedbackBloc>().add(
                      const LoadAllFeedbacksEvent(),
                    ),
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }

          if (state is AdminFeedbacksLoaded) {
            if (state.feedbacks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.feedback_rounded,
                      size: 80,
                      color: colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(
                      'لا توجد مقترحات',
                      style: TextStyle(
                        fontSize: 24,
                        fontWeight: FontWeight.bold,
                        color: colorScheme.onSurfaceVariant,
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async => context.read<AdminFeedbackBloc>().add(
                const LoadAllFeedbacksEvent(),
              ),
              child: ListView.separated(
                padding: const EdgeInsets.all(16),
                itemCount: state.feedbacks.length,
                separatorBuilder: (context, i) => const SizedBox(height: 12),
                itemBuilder: (context, index) {
                  final feedback = state.feedbacks[index];

                  return Card(
                    child: ListTile(
                      contentPadding: const EdgeInsets.symmetric(
                        horizontal: 16,
                        vertical: 8,
                      ),
                      leading: CircleAvatar(
                        backgroundColor: colorScheme.primaryContainer,
                        child: Icon(
                          Icons.feedback_rounded,
                          color: colorScheme.primary,
                        ),
                      ),
                      title: Text(
                        feedback.type.getLabel(true),
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                      subtitle: Text(
                        feedback.content,
                        maxLines: 2,
                        overflow: TextOverflow.ellipsis,
                      ),
                      trailing: Chip(
                        label: Text(feedback.status.getLabel(true)),
                        backgroundColor: _getStatusColor(
                          feedback.status,
                          colorScheme,
                        ),
                      ),
                      onTap: () {
                        _showFeedbackDetails(context, feedback);
                      },
                    ),
                  );
                },
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }

  Color _getStatusColor(FeedbackStatus status, ColorScheme colorScheme) {
    switch (status) {
      case FeedbackStatus.pending:
        return colorScheme.errorContainer;
      case FeedbackStatus.reviewed:
        return colorScheme.primaryContainer;
      case FeedbackStatus.inProgress:
        return colorScheme.secondaryContainer;
      case FeedbackStatus.resolved:
        return colorScheme.tertiaryContainer;
      case FeedbackStatus.rejected:
        return colorScheme.errorContainer;
    }
  }

  void _showFeedbackDetails(BuildContext context, FeedbackEntity feedback) {
    final colorScheme = Theme.of(context).colorScheme;

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تفاصيل المقترح'),
        content: SingleChildScrollView(
          child: Column(
            crossAxisAlignment: CrossAxisAlignment.start,
            mainAxisSize: MainAxisSize.min,
            children: [
              Text('النوع: ${feedback.type.getLabel(true)}'),
              const SizedBox(height: 8),
              Text('الحالة: ${feedback.status.getLabel(true)}'),
              const SizedBox(height: 8),
              Text('المستخدم: ${feedback.userName}'),
              const SizedBox(height: 8),
              Text('البريد: ${feedback.userEmail}'),
              const SizedBox(height: 8),
              Text('المحتوى:'),
              const SizedBox(height: 4),
              Text(feedback.content),
              if (feedback.screenshotUrl != null) ...[
                const SizedBox(height: 16),
                Text('الصورة:'),
                const SizedBox(height: 4),
                Text(feedback.screenshotUrl!),
              ],
              if (feedback.adminResponse != null) ...[
                const SizedBox(height: 16),
                Text('رد الإدارة:'),
                const SizedBox(height: 4),
                Text(feedback.adminResponse!),
              ],
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إغلاق'),
          ),
          FilledButton(
            onPressed: () {
              Navigator.pop(context);
              _showUpdateDialog(context, feedback);
            },
            child: const Text('تحديث'),
          ),
          FilledButton.tonal(
            style: FilledButton.styleFrom(
              backgroundColor: colorScheme.errorContainer,
            ),
            onPressed: () {
              Navigator.pop(context);
              _deleteFeedback(context, feedback);
            },
            child: Text('حذف', style: TextStyle(color: colorScheme.error)),
          ),
        ],
      ),
    );
  }

  void _showUpdateDialog(BuildContext context, FeedbackEntity feedback) {
    FeedbackStatus selectedStatus = feedback.status;
    final replyController = TextEditingController(
      text: feedback.adminResponse ?? '',
    );

    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('تحديث المقترح'),
        content: SingleChildScrollView(
          child: Column(
            mainAxisSize: MainAxisSize.min,
            children: [
              DropdownButton<FeedbackStatus>(
                value: selectedStatus,
                isExpanded: true,
                items: FeedbackStatus.values
                    .map(
                      (status) => DropdownMenuItem(
                        value: status,
                        child: Text(status.getLabel(true)),
                      ),
                    )
                    .toList(),
                onChanged: (value) {
                  if (value != null) {
                    selectedStatus = value;
                  }
                },
              ),
              const SizedBox(height: 16),
              TextField(
                controller: replyController,
                decoration: const InputDecoration(
                  labelText: 'رد الإدارة',
                  hintText: 'أدخل رد الإدارة على المقترح',
                ),
                maxLines: 3,
              ),
            ],
          ),
        ),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            onPressed: () {
              context.read<AdminFeedbackBloc>().add(
                UpdateFeedbackStatusEvent(
                  feedbackId: feedback.id ?? '',
                  status: selectedStatus,
                  adminResponse: replyController.text,
                ),
              );
              Navigator.pop(context);
            },
            child: const Text('حفظ'),
          ),
        ],
      ),
    );
  }

  void _deleteFeedback(BuildContext context, FeedbackEntity feedback) {
    showDialog(
      context: context,
      builder: (context) => AlertDialog(
        title: const Text('حذف المقترح'),
        content: const Text('هل أنت متأكد من حذف هذا المقترح؟'),
        actions: [
          TextButton(
            onPressed: () => Navigator.pop(context),
            child: const Text('إلغاء'),
          ),
          FilledButton(
            style: FilledButton.styleFrom(
              backgroundColor: Theme.of(context).colorScheme.error,
            ),
            onPressed: () {
              context.read<AdminFeedbackBloc>().add(
                    DeleteFeedbackEvent(feedback.id ?? ''),
                  );
              Navigator.pop(context);
            },
            child: const Text('حذف'),
          ),
        ],
      ),
    );
  }
}
