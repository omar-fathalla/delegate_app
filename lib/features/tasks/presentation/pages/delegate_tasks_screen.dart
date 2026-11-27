import 'package:delegate_app/core/design/widgets/summary_card.dart';
import 'package:delegate_app/core/design/widgets/skeleton.dart';
import 'package:delegate_app/core/design/widgets/pull_to_refresh.dart';
import 'package:delegate_app/core/design/widgets/empty_state.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:delegate_app/core/design/bidi.dart';
import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_image_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_state.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart' hide Bidi, TextDirection;

class DelegateTasksScreen extends StatefulWidget {
  final Delegate delegate;

  const DelegateTasksScreen({super.key, required this.delegate});

  @override
  State<DelegateTasksScreen> createState() => _DelegateTasksScreenState();
}

/// The list filter (C-06 connected ButtonGroup): open, done or all.
enum _TaskFilter { open, done, all }

class _DelegateTasksScreenState extends State<DelegateTasksScreen> {
  final ScrollController _scrollController = ScrollController();
  _TaskFilter _filter = _TaskFilter.open;

  @override
  void initState() {
    super.initState();
    _scrollController.addListener(_onScroll);
  }

  @override
  void dispose() {
    _scrollController.dispose();
    super.dispose();
  }

  void _onScroll() {
    if (_isBottom) {
      context.read<DelegateTasksBloc>().add(
        LoadMoreDelegateTasksRequested(
          organizationId: widget.delegate.organizationUID,
          delegateId: widget.delegate.uid,
          companyId: widget.delegate.companyUID,
          delegateRoleName: widget.delegate.role.name,
        ),
      );
    }
  }

  bool get _isBottom {
    if (!_scrollController.hasClients) return false;
    final maxScroll = _scrollController.position.maxScrollExtent;
    final currentScroll = _scrollController.offset;
    return currentScroll >= (maxScroll * 0.9);
  }

  /// TAS-387: always load every status; the filter is local, so «المفتوحة»
  /// can hold pending and in-progress together.
  void _loadTasks() {
    context.read<DelegateTasksBloc>().add(
      LoadDelegateTasksRequested(
        organizationId: widget.delegate.organizationUID,
        delegateId: widget.delegate.uid,
        companyId: widget.delegate.companyUID,
        delegateRoleName: widget.delegate.role.name,
      ),
    );
  }

  Future<void> _refresh() async {
    final bloc = context.read<DelegateTasksBloc>();
    final done = bloc.stream.firstWhere(
      (s) => s is DelegateTasksLoaded || s is DelegateTasksError,
    );
    _loadTasks();
    try {
      await done.timeout(const Duration(seconds: 8));
    } catch (_) {}
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      backgroundColor: theme.colorScheme.surfaceContainerLowest,
      appBar: AppBar(
        title: Text(l10n.tasks),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(56),
          child: BlocBuilder<DelegateTasksBloc, DelegateTasksState>(
            builder: (context, state) {
              final tasks = state is DelegateTasksLoaded
                  ? state.tasks
                  : const <TaskEntity>[];
              final open = tasks.where(_isOpen).length;
              return Padding(
                padding: const EdgeInsetsDirectional.fromSTEB(
                  TashilSpacing.page,
                  0,
                  TashilSpacing.page,
                  TashilSpacing.sm,
                ),
                child: ButtonGroup<_TaskFilter>(
                  key: const Key('tasks_filter'),
                  variant: ButtonGroupVariant.connected,
                  expand: true,
                  selected: {_filter},
                  onSelectionChanged: (v) => setState(() => _filter = v.first),
                  items: [
                    ButtonGroupItem(
                      key: const Key('tasks_filter_open'),
                      value: _TaskFilter.open,
                      label: '${l10n.tasksFilterOpen} ${Bidi.ltr('$open')}',
                    ),
                    ButtonGroupItem(
                      key: const Key('tasks_filter_done'),
                      value: _TaskFilter.done,
                      label: l10n.tasksFilterDone,
                    ),
                    ButtonGroupItem(
                      key: const Key('tasks_filter_all'),
                      value: _TaskFilter.all,
                      label: l10n.all,
                    ),
                  ],
                ),
              );
            },
          ),
        ),
      ),
      body: BlocConsumer<DelegateTasksBloc, DelegateTasksState>(
        listener: (context, state) {
          if (state is TaskStatusUpdateSuccess) {
            showTashilSnackBar(
              context,
              state.newStatus == TaskStatus.completed
                  ? l10n.taskCompletedConfirmed
                  : l10n.taskStarted,
            );
            _loadTasks();
          } else if (state is DelegateTasksError) {
            showTashilSnackBar(context, state.message);
          }
        },
        builder: (context, state) {
          if (state is DelegateTasksInitial) {
            _loadTasks();
          }
          if (state is DelegateTasksInitial || state is DelegateTasksLoading) {
            return ListView(
              key: const Key('tasks_skeleton'),
              padding: const EdgeInsets.all(TashilSpacing.page),
              children: const [
                SummaryCardSkeleton(),
                SummaryCardSkeleton(),
                SummaryCardSkeleton(),
              ],
            );
          }
          if (state is DelegateTasksError) {
            return Center(
              child: EmptyState(
                key: const Key('tasks_error'),
                icon: Symbols.error_outline_rounded,
                title: state.message,
                action: FilledButton.tonalIcon(
                  onPressed: _loadTasks,
                  icon: const Icon(Symbols.refresh_rounded),
                  label: Text(l10n.retry),
                ),
              ),
            );
          }
          if (state is! DelegateTasksLoaded) return const SizedBox.shrink();

          final groups = _groupTasks(state.tasks, l10n);
          final items = <Widget>[];
          var index = 0;
          for (final (title, tasks) in groups) {
            items.add(_GroupHeader(title: title, count: tasks.length));
            for (final t in tasks) {
              items.add(
                M3StaggeredItem(
                  index: index++,
                  child: _TaskCard(
                    task: t,
                    delegate: widget.delegate,
                    organizationId: widget.delegate.organizationUID,
                  ),
                ),
              );
            }
          }

          return PullToRefresh(
            onRefresh: _refresh,
            child: items.isEmpty
                ? ListView(
                    physics: const AlwaysScrollableScrollPhysics(),
                    children: [
                      const SizedBox(height: TashilSpacing.xxl * 2),
                      EmptyState(
                        key: const Key('tasks_empty'),
                        icon: Symbols.task_alt_rounded,
                        title: l10n.noTasksNow,
                        message: l10n.tasksAppearHere,
                      ),
                    ],
                  )
                : ListView.builder(
                    controller: _scrollController,
                    physics: const AlwaysScrollableScrollPhysics(),
                    padding: const EdgeInsetsDirectional.fromSTEB(
                      TashilSpacing.page,
                      0,
                      TashilSpacing.page,
                      TashilSpacing.xxl,
                    ),
                    itemCount: items.length + (state.hasReachedMax ? 0 : 1),
                    itemBuilder: (context, i) => i < items.length
                        ? items[i]
                        : const Padding(
                            padding: EdgeInsets.all(TashilSpacing.lg),
                            child: Center(child: DelayedLoadingIndicator()),
                          ),
                  ),
          );
        },
      ),
    );
  }

  /// Overdue first, then the open ones by nearest due date, then the
  /// finished ones newest first (user review 27 Nov 2026).
  List<(String, List<TaskEntity>)> _groupTasks(
    List<TaskEntity> all,
    AppLocalizations l10n,
  ) {
    final overdue = <TaskEntity>[];
    final open = <TaskEntity>[];
    final done = <TaskEntity>[];
    for (final t in all) {
      if (!_isOpen(t)) {
        done.add(t);
      } else if (_overdueDays(t) > 0) {
        overdue.add(t);
      } else {
        open.add(t);
      }
    }
    overdue.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    open.sort((a, b) => a.dueDate.compareTo(b.dueDate));
    done.sort(
      (a, b) =>
          (b.completedAt ?? b.dueDate).compareTo(a.completedAt ?? a.dueDate),
    );
    return [
      if (_filter != _TaskFilter.done && overdue.isNotEmpty)
        (l10n.tasksGroupOverdue, overdue),
      if (_filter != _TaskFilter.done && open.isNotEmpty)
        (l10n.tasksGroupOpen, open),
      if (_filter != _TaskFilter.open && done.isNotEmpty)
        (l10n.tasksGroupDone, done),
    ];
  }
}

bool _isOpen(TaskEntity t) =>
    t.status == TaskStatus.pending || t.status == TaskStatus.inProgress;

/// Days an open task is past its due date (0 when on time).
int _overdueDays(TaskEntity t) {
  if (!_isOpen(t)) return 0;
  final today = DateUtils.dateOnly(DateTime.now());
  final due = DateUtils.dateOnly(t.dueDate);
  return due.isBefore(today) ? today.difference(due).inDays : 0;
}

/// A group title with its count (same style as «آخر النشاط» on home).
class _GroupHeader extends StatelessWidget {
  const _GroupHeader({required this.title, required this.count});
  final String title;
  final int count;

  @override
  Widget build(BuildContext context) {
    final tt = Theme.of(context).textTheme;
    final cs = Theme.of(context).colorScheme;
    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.xs,
        TashilSpacing.lg,
        TashilSpacing.xs,
        TashilSpacing.sm,
      ),
      child: Row(
        children: [
          Expanded(child: Text(title, style: tt.titleSmall)),
          Text(
            Bidi.ltr('$count'),
            style: tt.labelLarge?.copyWith(color: cs.onSurfaceVariant),
          ),
        ],
      ),
    );
  }
}

/// TAS-387: one task as a SummaryCard (P-07). The due date is the value on
/// the end side; status, high priority and «متأخرة» are labels; the photo
/// is a small thumbnail; the next step is in the ⋮ menu (C-24).
class _TaskCard extends StatelessWidget {
  final TaskEntity task;
  final Delegate delegate;
  final String organizationId;

  const _TaskCard({
    required this.task,
    required this.delegate,
    required this.organizationId,
  });

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final locale = Localizations.localeOf(context).toLanguageTag();
    final overdue = _overdueDays(task);
    final open = _isOpen(task);

    final today = DateUtils.dateOnly(DateTime.now());
    final dueIn = DateUtils.dateOnly(task.dueDate).difference(today).inDays;
    // The date stays short on the end side; how near it is goes under it
    // (a long word there squeezed the title).
    final String dueValue = DateFormat(
      'd MMM',
      locale,
    ).format(open ? task.dueDate : (task.completedAt ?? task.dueDate));
    final String dueCaption = !open
        ? ''
        : overdue > 0
        ? l10n.taskLateBy(overdue)
        : dueIn == 0
        ? l10n.today
        : l10n.taskDueInDays(dueIn);

    final next = switch (task.status) {
      TaskStatus.pending => TaskStatus.inProgress,
      TaskStatus.inProgress => TaskStatus.completed,
      _ => null,
    };

    return SummaryCard(
      key: ValueKey('task_card_${task.uid}'),
      icon: Symbols.assignment_rounded,
      // The photo as a small thumbnail over the task icon, so the icon
      // still shows when the viewer may not read the photo.
      leading: task.hasImage
          ? IgnorePointer(
              child: SizedBox.square(
                dimension: 44,
                child: Stack(
                  fit: StackFit.expand,
                  children: [
                    DecoratedBox(
                      decoration: BoxDecoration(
                        color: cs.primary,
                        shape: BoxShape.circle,
                      ),
                      child: Icon(
                        Symbols.assignment_rounded,
                        size: 20,
                        color: cs.onPrimary,
                      ),
                    ),
                    TaskImageThumbnail(
                      key: ValueKey('task_thumb_${task.uid}'),
                      imagePath: task.resolvedImagePaths.first,
                      taskId: task.uid,
                      organizationId: organizationId,
                      height: 44,
                    ),
                  ],
                ),
              ),
            )
          : null,
      title: task.title,
      subtitle: task.description,
      labels: [
        _StatusSmallChip(status: task.status),
        if (task.priority == TaskPriority.high && open)
          SummaryLabel(
            l10n.high,
            container: cs.tertiaryContainer,
            onContainer: cs.onTertiaryContainer,
          ),
        if (overdue > 0)
          SummaryLabel(
            key: ValueKey('task_overdue_${task.uid}'),
            l10n.taskOverdueLabel,
            container: cs.errorContainer,
            onContainer: cs.onErrorContainer,
          ),
      ],
      // The date and the sender go across the card under a divider, so the
      // title keeps the width (a big date on the end squeezed it).
      facts: [
        SummaryFact(
          icon: open ? Symbols.event_rounded : Symbols.task_alt_rounded,
          label: open ? l10n.taskDueDate : l10n.taskDoneAt,
          value: open ? '$dueValue • $dueCaption' : dueValue,
        ),
        if (task.createdByName.trim().isNotEmpty)
          SummaryFact(
            icon: Symbols.person_rounded,
            label: l10n.taskFrom,
            value: task.createdByName.trim(),
          ),
      ],
      action: next == null
          ? null
          : MenuAnchor(
              builder: (context, controller, _) => IconButton(
                key: ValueKey('task_menu_${task.uid}'),
                icon: const Icon(Symbols.more_vert_rounded),
                tooltip: MaterialLocalizations.of(context).showMenuTooltip,
                onPressed: () =>
                    controller.isOpen ? controller.close() : controller.open(),
              ),
              menuChildren: [
                MenuItemButton(
                  key: ValueKey('task_quick_${next.name}_${task.uid}'),
                  leadingIcon: Icon(
                    next == TaskStatus.completed
                        ? Symbols.task_alt_rounded
                        : Symbols.play_arrow_rounded,
                  ),
                  onPressed: () => _updateStatus(context, next),
                  child: Text(
                    next == TaskStatus.completed
                        ? l10n.taskFinish
                        : l10n.taskStart,
                  ),
                ),
              ],
            ),
      onTap: () async {
        await context.push(
          '/task-details',
          extra: {
            'task': task,
            'isAdmin': false,
            'organizationId': organizationId,
            'currentUserId': delegate.uid,
            'currentUserRole': delegate.role.name,
            'currentUserCompanyId': delegate.companyUID,
            'currentUserName': delegate.fullName,
          },
        );
        if (context.mounted) {
          context.read<DelegateTasksBloc>().add(
            LoadDelegateTasksRequested(
              organizationId: organizationId,
              delegateId: delegate.uid,
              companyId: delegate.companyUID,
              delegateRoleName: delegate.role.name,
            ),
          );
        }
      },
    );
  }

  void _updateStatus(BuildContext context, TaskStatus newStatus) {
    context.read<DelegateTasksBloc>().add(
      UpdateTaskStatusRequested(
        organizationId: delegate.organizationUID,
        taskId: task.uid,
        newStatus: newStatus,
      ),
    );
  }
}

/// Compact read-only label: a container role with its on colour.
class _TaskLabel extends StatelessWidget {
  const _TaskLabel({
    required this.text,
    required this.container,
    required this.onContainer,
    this.icon,
  });
  final String text;
  final Color container;
  final Color onContainer;
  final IconData? icon;

  @override
  Widget build(BuildContext context) {
    return Container(
      padding: const EdgeInsetsDirectional.symmetric(
        horizontal: TashilSpacing.sm,
        vertical: TashilSpacing.xs / 2,
      ),
      decoration: BoxDecoration(
        color: container,
        borderRadius: BorderRadius.circular(TashilRadius.small),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          if (icon != null) ...[
            Icon(icon, size: 14, color: onContainer),
            const SizedBox(width: TashilSpacing.xs),
          ],
          Text(
            text,
            style: Theme.of(
              context,
            ).textTheme.labelSmall?.copyWith(color: onContainer),
          ),
        ],
      ),
    );
  }
}

/// Task status as a compact label. Completed is success, in progress the
/// secondary container, pending and cancelled neutral (cancelled is not an
/// error).
class _StatusSmallChip extends StatelessWidget {
  final TaskStatus status;

  const _StatusSmallChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final cs = Theme.of(context).colorScheme;
    final sem = Theme.of(context).extension<TashilSemanticColors>();
    final (Color bg, Color fg, IconData icon) = switch (status) {
      // Visible on the card (was surfaceContainerHighest = the card).
      TaskStatus.pending => (
        cs.surface,
        cs.onSurfaceVariant,
        Icons.access_time_rounded,
      ),
      TaskStatus.inProgress => (
        cs.secondaryContainer,
        cs.onSecondaryContainer,
        Icons.sync_rounded,
      ),
      TaskStatus.completed => (
        sem?.successContainer ?? cs.primaryContainer,
        sem?.onSuccessContainer ?? cs.onPrimaryContainer,
        Icons.check_circle_rounded,
      ),
      TaskStatus.cancelled => (
        cs.surface,
        cs.onSurfaceVariant,
        Icons.block_rounded,
      ),
    };
    return _TaskLabel(
      text: _getStatusLabel(context, status),
      container: bg,
      onContainer: fg,
      icon: icon,
    );
  }

  String _getStatusLabel(BuildContext context, TaskStatus status) {
    final l10n = AppLocalizations.of(context)!;
    switch (status) {
      case TaskStatus.pending:
        return l10n.taskPending;
      case TaskStatus.inProgress:
        return l10n.taskInProgress;
      case TaskStatus.completed:
        return l10n.taskCompleted;
      case TaskStatus.cancelled:
        return l10n.taskCancelled;
    }
  }
}
