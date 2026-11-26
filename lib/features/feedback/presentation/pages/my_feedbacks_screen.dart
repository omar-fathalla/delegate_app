import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/tokens.dart';
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
            return const Center(child: LoadingIndicator());
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
                  const SizedBox(height: TashilSpacing.lg),
                  Text(
                    state.message,
                    style: theme.textTheme.bodyLarge,
                    textAlign: TextAlign.center,
                  ),
                  const SizedBox(height: TashilSpacing.lg),
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
                      color: theme.colorScheme.onSurfaceVariant,
                    ),
                    const SizedBox(height: TashilSpacing.lg),
                    Text(AppLocalizations.of(context)!.noFeedbackYet,
                      style: theme.textTheme.titleMedium,
                    ),
                    const SizedBox(height: TashilSpacing.sm),
                    Text(AppLocalizations.of(context)!.sendFirstFeedback,
                      style: theme.textTheme.bodyMedium?.copyWith(
                        color: theme.colorScheme.onSurfaceVariant,
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
                padding: const EdgeInsets.all(TashilSpacing.page),
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

  /// TAS-358 (F-04): status as a compact label with a container role and
  /// its on colour. Resolved = success, pending = warning, rejected = error,
  /// the rest neutral (was hand-picked orange/blue/purple/green/red).
  (Color, Color) _statusColors(BuildContext context, FeedbackStatus status) {
    final cs = Theme.of(context).colorScheme;
    final sem = Theme.of(context).extension<TashilSemanticColors>();
    return switch (status) {
      FeedbackStatus.resolved => (
        sem?.successContainer ?? cs.primaryContainer,
        sem?.onSuccessContainer ?? cs.onPrimaryContainer,
      ),
      FeedbackStatus.pending => (
        sem?.warningContainer ?? cs.tertiaryContainer,
        sem?.onWarningContainer ?? cs.onTertiaryContainer,
      ),
      FeedbackStatus.rejected => (cs.errorContainer, cs.onErrorContainer),
      FeedbackStatus.reviewed ||
      FeedbackStatus.inProgress => (
        cs.secondaryContainer,
        cs.onSecondaryContainer,
      ),
    };
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

    final (statusBg, statusFg) = _statusColors(context, feedback.status);
    final cs = theme.colorScheme;

    return Card.filled(
      margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.md),
      child: Padding(
        padding: const EdgeInsets.all(TashilSpacing.lg),
        child: Column(
          crossAxisAlignment: CrossAxisAlignment.start,
          children: [
            // Header: النوع والحالة
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(TashilSpacing.sm),
                  decoration: BoxDecoration(
                    color: cs.primary,
                    shape: BoxShape.circle,
                  ),
                  child: Icon(
                    _getTypeIcon(feedback.type),
                    color: cs.onPrimary,
                    size: 20,
                  ),
                ),
                const SizedBox(width: TashilSpacing.md),
                Expanded(
                  child: Text(
                    feedback.type.getLabel(isArabic),
                    style: theme.textTheme.titleSmall,
                  ),
                ),
                Container(
                  key: ValueKey('feedback_status_${feedback.status.name}'),
                  padding: const EdgeInsetsDirectional.symmetric(
                    horizontal: TashilSpacing.sm,
                    vertical: TashilSpacing.xs / 2,
                  ),
                  decoration: BoxDecoration(
                    color: statusBg,
                    borderRadius: BorderRadius.circular(TashilRadius.small),
                  ),
                  child: Text(
                    feedback.status.getLabel(isArabic),
                    style: theme.textTheme.labelMedium?.copyWith(
                      color: statusFg,
                    ),
                  ),
                ),
              ],
            ),
            const SizedBox(height: TashilSpacing.md),

            // المحتوى
            Text(
              feedback.content,
              style: theme.textTheme.bodyMedium,
              maxLines: 3,
              overflow: TextOverflow.ellipsis,
            ),
            const SizedBox(height: TashilSpacing.md),

            // الصورة إذا كانت موجودة
            if (feedback.screenshotUrl != null) ...[
              ClipRRect(
                borderRadius: BorderRadius.circular(TashilRadius.medium),
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
              const SizedBox(height: TashilSpacing.md),
            ],

            // رد الإدارة إذا كان موجوداً
            if (feedback.adminResponse != null) ...[
              Container(
                padding: const EdgeInsets.all(TashilSpacing.md),
                decoration: BoxDecoration(
                  color: cs.surface,
                  borderRadius: BorderRadius.circular(TashilRadius.medium),
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
                        const SizedBox(width: TashilSpacing.xs),
                        Text(AppLocalizations.of(context)!.adminResponse,
                          style: theme.textTheme.labelSmall?.copyWith(
                            fontWeight: FontWeight.bold,
                            color: theme.colorScheme.primary,
                          ),
                        ),
                      ],
                    ),
                    const SizedBox(height: TashilSpacing.xs),
                    Text(
                      feedback.adminResponse!,
                      style: theme.textTheme.bodySmall,
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TashilSpacing.md),
            ],

            // التاريخ
            Row(
              children: [
                Icon(
                  Icons.access_time,
                  size: 14,
                  color: theme.colorScheme.onSurfaceVariant,
                ),
                const SizedBox(width: TashilSpacing.xs),
                Text(
                  dateFormat.format(feedback.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: theme.colorScheme.onSurfaceVariant,
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
