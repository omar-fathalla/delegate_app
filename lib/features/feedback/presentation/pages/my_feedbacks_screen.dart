import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:intl/intl.dart';

class MyFeedbacksScreen extends StatefulWidget {
  final Delegate delegate;

  const MyFeedbacksScreen({super.key, required this.delegate});

  @override
  State<MyFeedbacksScreen> createState() => _MyFeedbacksScreenState();
}

class _MyFeedbacksScreenState extends State<MyFeedbacksScreen> {
  @override
  void initState() {
    super.initState();
    context.read<FeedbackBloc>().add(
      LoadUserFeedbacksEvent(userId: widget.delegate.uid),
    );
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final isArabic = Localizations.localeOf(context).languageCode == 'ar';

    return Scaffold(
      appBar: AppBar(
        title: Text(AppLocalizations.of(context)!.myFeedback),
        centerTitle: true,
      ),
      body: BlocBuilder<FeedbackBloc, FeedbackState>(
        builder: (context, state) {
          if (state is FeedbackLoading) {
            return const Center(child: CircularProgressIndicator());
          }

          if (state is FeedbackError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Icon(
                    Icons.error_outline,
                    size: 64,
                    color: theme.colorScheme.error,
                  ),
                  const SizedBox(height: 16),
                  Text(
                    state.message,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: 16),
                  FilledButton.icon(
                    onPressed: () {
                      context.read<FeedbackBloc>().add(
                        LoadUserFeedbacksEvent(userId: widget.delegate.uid),
                      );
                    },
                    icon: const Icon(Icons.refresh),
                    label: Text(AppLocalizations.of(context)!.retry),
                  ),
                ],
              ),
            );
          }

          if (state is FeedbacksLoaded) {
            if (state.feedbacks.isEmpty) {
              return Center(
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.feedback_outlined,
                      size: 64,
                      color: theme.colorScheme.primary.withValues(alpha: 0.5),
                    ),
                    const SizedBox(height: 16),
                    Text(AppLocalizations.of(context)!.noFeedbackYet,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: 8),
                    Text(AppLocalizations.of(context)!.sendFirstFeedback,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurface.withValues(
                          alpha: 0.6,
                        ),
                      ),
                    ),
                  ],
                ),
              );
            }

            return RefreshIndicator(
              onRefresh: () async {
                context.read<FeedbackBloc>().add(
                  LoadUserFeedbacksEvent(userId: widget.delegate.uid),
                );
              },
              child: ListView.builder(
                padding: const EdgeInsets.all(16),
                itemCount: state.feedbacks.length,
                itemBuilder: (context, index) {
                  final feedback = state.feedbacks[index];
                  return _FeedbackCard(feedback: feedback, isArabic: isArabic);
                },
              ),
            );
          }

          return const SizedBox.shrink();
        },
      ),
    );
  }
}

class _FeedbackCard extends StatelessWidget {
  final FeedbackEntity feedback;
  final bool isArabic;

  const _FeedbackCard({required this.feedback, required this.isArabic});

  Color _getStatusColor(FeedbackStatus status) {
    switch (status) {
      case FeedbackStatus.pending:
        return Colors.orange;
      case FeedbackStatus.reviewed:
        return Colors.blue;
      case FeedbackStatus.inProgress:
        return Colors.purple;
      case FeedbackStatus.resolved:
        return Colors.green;
      case FeedbackStatus.rejected:
        return Colors.red;
    }
  }

  IconData _getTypeIcon(FeedbackType type) {
    switch (type) {
      case FeedbackType.featureRequest:
        return Icons.lightbulb_outline;
      case FeedbackType.bugReport:
        return Icons.bug_report_outlined;
      case FeedbackType.generalQuestion:
        return Icons.help_outline;
      case FeedbackType.improvement:
        return Icons.star_outline;
      case FeedbackType.other:
        return Icons.chat_bubble_outline;
    }
  }

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final dateFormat = DateFormat('dd/MM/yyyy - HH:mm');

    return Card(
      margin: const EdgeInsets.only(bottom: 16),
      child: Padding(
        padding: const EdgeInsets.all(16),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: النوع والحالة
            Row(
              children: [
                Icon(
                  _getTypeIcon(feedback.type),
                  color: theme.colorScheme.primary,
                  size: 20,
                ),
                const SizedBox(width: 8),
                Expanded(
                  child: Text(
                    feedback.type.getLabel(isArabic),
                    style: theme.textTheme.titleMedium?.copyWith(
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
                Container(
                  padding: const EdgeInsets.symmetric(
                    horizontal: 12,
                    vertical: 6,
                  ),
                  decoration: BoxDecoration(
                    color: _getStatusColor(
                      feedback.status,
                    ).withValues(alpha: 0.1),
                    borderRadius: BorderRadius.circular(12),
                    border: Border.all(
                      color: _getStatusColor(feedback.status),
                      width: 1,
                    ),
                  ),
                  child: Text(
                    feedback.status.getLabel(isArabic),
                    style: TextStyle(
                      color: _getStatusColor(feedback.status),
                      fontSize: 12,
                      fontWeight: FontWeight.bold,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: 12),

            // المحتوى
            Text(
              feedback.content,
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: 12),

            // الصورة إذا كانت موجودة
            if (feedback.screenshotUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(8),
                child: AppPhotoImage(
                  photoUrl: feedback.screenshotUrl!,
                  height: 120,
                  width: double.infinity,
                  fit: BoxFit.cover,
                  errorWidget: Container(
                    height: 120,
                    color: theme.colorScheme.surfaceContainerHighest,
                    child: const Icon(Icons.broken_image),
                  ),
                ),
              ),
              const SizedBox(height: 12),
            ],

            // رد الإدارة إذا كان موجوداً
            if (feedback.adminResponse != null) ...[
              Container(
                padding: const EdgeInsets.all(12),
                decoration: BoxDecoration(
                  color: theme.colorScheme.primaryContainer.withValues(
                    alpha: 0.3,
                  ),
                  borderRadius: BorderRadius.circular(8),
                  border: Border.all(
                    color: theme.colorScheme.primary.withValues(alpha: 0.3),
                  ),
                ),
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Row(
                      children: [
                        Icon(
                          Icons.admin_panel_settings,
                          size: 16,
                          color: theme.colorScheme.primary,
                        ),
                        const SizedBox(width: 4),
                        Text(AppLocalizations.of(context)!.adminResponse,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: 4),
                    Text(
                      feedback.adminResponse!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 12),
            ],

            // التاريخ
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                ),
                const SizedBox(width: 4),
                Text(
                  dateFormat.format(feedback.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurface.withValues(alpha: 0.6),
                  ),
                ),
              ],
            ),
          ],
        ),
      ),
    );
  }
}
