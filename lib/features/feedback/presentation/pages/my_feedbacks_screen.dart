import 'package:animations/animations.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'package:delegate_app/core/widgets/app_photo_image.dart';
import 'package:delegate_app/core/widgets/m3/m3_expressive.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';
import 'package:delegate_app/features/hr/presentation/hr_account_pages.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';

/// «ملاحظاتي» (TAS-387, user review 27 Nov 2026), built from the playground:
/// a connected ButtonGroup filter (open / answered / all), each feedback as
/// a SummaryCard (type, first line, status label, date and whether the
/// admin answered), opened with a container transform into its details
/// (full text, screenshot, the admin's answer). PullToRefresh, skeletons,
/// EmptyState for empty and error, and an extended FAB for a new one.
class MyFeedbacksScreen extends StatefulWidget {
  final Delegate delegate;

  const MyFeedbacksScreen({super.key, required this.delegate});

  @override
  State<MyFeedbacksScreen> createState() => _MyFeedbacksScreenState();
}

enum _Filter { open, answered, all }

bool _isClosed(FeedbackStatus s) =>
    s == FeedbackStatus.resolved || s == FeedbackStatus.rejected;

class _MyFeedbacksScreenState extends State<MyFeedbacksScreen>
    with ExtendedFabScroll {
  _Filter _filter = _Filter.all;

  @override
  void initState() {
    super.initState();
    _load();
  }

  void _load() => context.read<FeedbackBloc>().add(
    LoadUserFeedbacksEvent(userId: widget.delegate.uid),
  );

  Future<void> _refresh() async {
    final bloc = context.read<FeedbackBloc>();
    final done = bloc.stream.firstWhere(
      (s) => s is FeedbacksLoaded || s is FeedbackError,
    );
    _load();
    try {
      await done.timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  Future<void> _newFeedback() async {
    await HrAccountPages.openSendFeedback(context, widget.delegate);
    if (mounted) _load();
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myFeedback)),
      floatingActionButton: M3ExtendedFab(
        key: const Key('feedback_new_fab'),
        onPressed: _newFeedback,
        icon: Symbols.add_comment_rounded,
        label: l10n.sendFeedback,
        extended: fabExtended,
      ),
      body: NotificationListener<UserScrollNotification>(
        onNotification: onFabScroll,
        child: BlocBuilder<FeedbackBloc, FeedbackState>(
          builder: (context, state) {
            if (state is FeedbackError) {
              return Center(
                child: EmptyState(
                  key: const Key('feedback_error'),
                  icon: Symbols.error_outline_rounded,
                  title: state.message,
                  action: FilledButton.tonalIcon(
                    onPressed: _load,
                    icon: const Icon(Symbols.refresh_rounded),
                    label: Text(l10n.retry),
                  ),
                ),
              );
            }
            if (state is! FeedbacksLoaded) {
              return ListView(
                key: const Key('feedback_skeleton'),
                padding: const EdgeInsets.all(TashilSpacing.page),
                children: const [
                  SummaryCardSkeleton(),
                  SummaryCardSkeleton(),
                  SummaryCardSkeleton(),
                ],
              );
            }

            final all = [...state.feedbacks]
              ..sort((a, b) => b.createdAt.compareTo(a.createdAt));
            final open = all.where((f) => !_isClosed(f.status)).length;
            final answered = all
                .where((f) => (f.adminResponse ?? '').trim().isNotEmpty)
                .length;
            final shown = all.where((f) {
              return switch (_filter) {
                _Filter.open => !_isClosed(f.status),
                _Filter.answered => (f.adminResponse ?? '').trim().isNotEmpty,
                _Filter.all => true,
              };
            }).toList();

            return PullToRefresh(
              onRefresh: _refresh,
              child: ListView(
                physics: const AlwaysScrollableScrollPhysics(),
                padding: const EdgeInsetsDirectional.fromSTEB(
                  TashilSpacing.page,
                  TashilSpacing.sm,
                  TashilSpacing.page,
                  TashilSpacing.xxl * 2,
                ),
                children: [
                  if (all.isNotEmpty) ...[
                    ButtonGroup<_Filter>(
                      key: const Key('feedback_filter'),
                      variant: ButtonGroupVariant.connected,
                      expand: true,
                      selected: {_filter},
                      onSelectionChanged: (v) =>
                          setState(() => _filter = v.first),
                      items: [
                        ButtonGroupItem(
                          value: _Filter.all,
                          label: '${l10n.all} ${Bidi.ltr('${all.length}')}',
                        ),
                        ButtonGroupItem(
                          value: _Filter.open,
                          label: '${l10n.feedbackOpen} ${Bidi.ltr('$open')}',
                        ),
                        ButtonGroupItem(
                          value: _Filter.answered,
                          label:
                              '${l10n.feedbackAnswered} ${Bidi.ltr('$answered')}',
                        ),
                      ],
                    ),
                    const SizedBox(height: TashilSpacing.md),
                  ],
                  if (shown.isEmpty)
                    Padding(
                      padding: const EdgeInsets.only(top: TashilSpacing.xxl),
                      child: EmptyState(
                        key: const Key('feedback_empty'),
                        icon: Symbols.rate_review_rounded,
                        title: l10n.noFeedbackYet,
                        message: l10n.sendFirstFeedback,
                        action: all.isEmpty
                            ? FilledButton.tonalIcon(
                                onPressed: _newFeedback,
                                icon: const Icon(Symbols.add_comment_rounded),
                                label: Text(l10n.sendFeedback),
                              )
                            : null,
                      ),
                    )
                  else
                    for (final f in shown) _FeedbackCard(feedback: f),
                ],
              ),
            );
          },
        ),
      ),
    );
  }
}

IconData _typeIcon(FeedbackType type) => switch (type) {
  FeedbackType.featureRequest => Symbols.lightbulb_rounded,
  FeedbackType.bugReport => Symbols.bug_report_rounded,
  FeedbackType.generalQuestion => Symbols.help_rounded,
  FeedbackType.improvement => Symbols.auto_awesome_rounded,
  FeedbackType.other => Symbols.chat_rounded,
};

/// Status as a label: resolved = success, pending = warning, rejected =
/// error, the rest neutral (TAS-358 F-04).
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
    FeedbackStatus.reviewed || FeedbackStatus.inProgress => (
      cs.secondaryContainer,
      cs.onSecondaryContainer,
    ),
  };
}

class _FeedbackCard extends StatelessWidget {
  const _FeedbackCard({required this.feedback});
  final FeedbackEntity feedback;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final locale = Localizations.localeOf(context).languageCode;
    final isArabic = locale == 'ar';
    final (bg, fg) = _statusColors(context, feedback.status);
    final answered = (feedback.adminResponse ?? '').trim().isNotEmpty;

    Widget summary(VoidCallback? onTap) => SummaryCard(
      key: ValueKey('feedback_card_${feedback.id}'),
      margin: EdgeInsets.zero,
      onTap: onTap,
      icon: _typeIcon(feedback.type),
      title: feedback.type.getLabel(isArabic),
      subtitle: feedback.content,
      labels: [
        SummaryLabel(
          key: ValueKey('feedback_status_${feedback.status.name}'),
          feedback.status.getLabel(isArabic),
          container: bg,
          onContainer: fg,
        ),
      ],
      facts: [
        SummaryFact(
          icon: Symbols.schedule_rounded,
          label: l10n.feedbackSentAt,
          value: DateFormat(
            'd MMMM • h:mm a',
            locale,
          ).format(feedback.createdAt),
        ),
        SummaryFact(
          icon: answered
              ? Symbols.mark_chat_read_rounded
              : Symbols.hourglass_top_rounded,
          label: l10n.adminResponse,
          value: answered ? l10n.feedbackHasAnswer : l10n.feedbackNoAnswer,
        ),
      ],
    );

    return Padding(
      padding: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
      child: OpenContainer<void>(
        closedElevation: 0,
        openElevation: 0,
        closedColor: cs.surfaceContainerHighest,
        openColor: cs.surface,
        middleColor: cs.surface,
        closedShape: RoundedRectangleBorder(
          borderRadius: BorderRadius.circular(TashilRadius.medium),
        ),
        transitionDuration: MediaQuery.maybeDisableAnimationsOf(context) == true
            ? Duration.zero
            : const Duration(milliseconds: 400),
        closedBuilder: (context, open) => summary(open),
        openBuilder: (context, _) =>
            _FeedbackDetails(feedback: feedback, summary: summary(null)),
      ),
    );
  }
}

/// One feedback in full: the summary, the whole text, the screenshot and
/// the admin's answer.
class _FeedbackDetails extends StatelessWidget {
  const _FeedbackDetails({required this.feedback, required this.summary});
  final FeedbackEntity feedback;
  final Widget summary;

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    final tt = Theme.of(context).textTheme;
    final answer = (feedback.adminResponse ?? '').trim();

    Widget title(IconData icon, String text) => Padding(
      padding: const EdgeInsetsDirectional.only(
        top: TashilSpacing.xl,
        bottom: TashilSpacing.sm,
      ),
      child: Row(
        children: [
          Icon(icon, size: 20, color: cs.primary),
          const SizedBox(width: TashilSpacing.sm),
          Text(text, style: tt.titleSmall),
        ],
      ),
    );

    return Scaffold(
      appBar: AppBar(title: Text(l10n.myFeedback)),
      body: ListView(
        key: const Key('feedback_details'),
        padding: const EdgeInsets.all(TashilSpacing.page),
        children: [
          summary,
          title(Symbols.notes_rounded, l10n.feedbackYourMessage),
          Text(feedback.content, style: tt.bodyLarge),
          if (feedback.screenshotUrl != null) ...[
            title(Symbols.image_rounded, l10n.feedbackScreenshot),
            ClipRRect(
              borderRadius: BorderRadius.circular(TashilRadius.large),
              child: AspectRatio(
                aspectRatio: 3 / 4,
                child: ColoredBox(
                  color: cs.surfaceContainerHighest,
                  child: InteractiveViewer(
                    maxScale: 4,
                    child: AppPhotoImage(
                      photoUrl: feedback.screenshotUrl!,
                      fit: BoxFit.contain,
                    ),
                  ),
                ),
              ),
            ),
          ],
          title(Symbols.support_agent_rounded, l10n.adminResponse),
          if (answer.isNotEmpty)
            Card.outlined(
              key: const Key('feedback_answer'),
              margin: EdgeInsets.zero,
              child: Padding(
                padding: const EdgeInsets.all(TashilSpacing.lg),
                child: Text(answer, style: tt.bodyLarge),
              ),
            )
          else
            Text(
              l10n.feedbackNoAnswerYet,
              key: const Key('feedback_no_answer'),
              style: tt.bodyMedium?.copyWith(color: cs.onSurfaceVariant),
            ),
        ],
      ),
    );
  }
}
