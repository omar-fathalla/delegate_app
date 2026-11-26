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
import 'package:intl/intl.dart';

class DelegateTasksScreen extends StatefulWidget {
  final Delegate delegate;

  const DelegateTasksScreen({super.key, required this.delegate});

  @override
  State<DelegateTasksScreen> createState() => _DelegateTasksScreenState();
}

class _DelegateTasksScreenState extends State<DelegateTasksScreen> {
  final ScrollController _scrollController = ScrollController();

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

  void _loadTasks() {
    final bloc = context.read<DelegateTasksBloc>();
    bloc.add(
      LoadDelegateTasksRequested(
        // Keep the active filter on refresh (it used to reset to "all").
        status: bloc.state.statusFilter,
        organizationId: widget.delegate.organizationUID,
        delegateId: widget.delegate.uid,
        companyId: widget.delegate.companyUID,
        delegateRoleName: widget.delegate.role.name,
      ),
    );
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
          preferredSize: const Size.fromHeight(110),
          child: _FilterBarDelegate(delegate: widget.delegate),
        ),
        actions: [
          IconButton(
            icon: const Icon(Symbols.refresh_rounded),
            // TAS-356 (C-02): the button refreshes, so its tooltip says so.
            tooltip: AppLocalizations.of(context)!.refreshAction,
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: BlocConsumer<DelegateTasksBloc, DelegateTasksState>(
        listener: (context, state) {
          if (state is TaskStatusUpdateSuccess) {
            showTashilSnackBar(
              context,
              state.newStatus == TaskStatus.completed
                  ? AppLocalizations.of(context)!.taskCompletedConfirmed
                  : AppLocalizations.of(context)!.taskStarted,
            );
            _loadTasks();
          } else if (state is DelegateTasksError) {
            showTashilSnackBar(context, state.message);
          }
        },
        builder: (context, state) {
          if (state is DelegateTasksInitial) {
            _loadTasks();
            return const Center(child: LoadingIndicator());
          }
          if (state is DelegateTasksLoading) {
            return const Center(child: LoadingIndicator());
          }
          if (state is DelegateTasksError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    state.message,
                    style: theme.textTheme.bodyLarge?.copyWith(
                      color: theme.colorScheme.error,
                    ),
                  ),
                  const SizedBox(height: TashilSpacing.lg),
                  FilledButton.tonal(
                    onPressed: _loadTasks,
                    child: Text(l10n.retry),
                  ),
                ],
              ),
            );
          }
          if (state is DelegateTasksLoaded) {
            if (state.tasks.isEmpty) {
              return Center(
                child: Padding(
                  padding: const EdgeInsets.all(TashilSpacing.xxl),
                  child: Column(
                    mainAxisAlignment: MainAxisAlignment.center,
                    children: [
                      Icon(
                        Icons.task_alt_rounded,
                        size: 72,
                        color: theme.colorScheme.onSurfaceVariant,
                      ),
                      const SizedBox(height: TashilSpacing.lg),
                      Text(
                        AppLocalizations.of(context)!.noTasksNow,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                          color: theme.colorScheme.onSurface,
                        ),
                      ),
                      const SizedBox(height: TashilSpacing.sm),
                      Text(
                        AppLocalizations.of(context)!.tasksAppearHere,
                        style: theme.textTheme.bodyMedium?.copyWith(
                          color: theme.colorScheme.onSurfaceVariant,
                        ),
                        textAlign: TextAlign.center,
                      ),
                    ],
                  ),
                ),
              );
            }

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: TashilSpacing.page,
                vertical: TashilSpacing.sm,
              ),
              itemCount: state.hasReachedMax
                  ? state.tasks.length
                  : state.tasks.length + 1,
              itemBuilder: (context, index) {
                if (index >= state.tasks.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(TashilSpacing.lg),
                      child: LoadingIndicator(),
                    ),
                  );
                }

                final task = state.tasks[index];
                final prevTask = index > 0 ? state.tasks[index - 1] : null;

                final showHeader =
                    prevTask == null ||
                    !_isSameDay(task.createdAt, prevTask.createdAt);

                if (showHeader) {
                  return M3StaggeredItem(
                    index: index,
                    child: Column(
                      crossAxisAlignment: CrossAxisAlignment.start,
                      children: [
                        _DateHeader(date: task.createdAt),
                        _TaskCard(
                          task: task,
                          delegate: widget.delegate,
                          organizationId: widget.delegate.organizationUID,
                        ),
                      ],
                    ),
                  );
                }

                return M3StaggeredItem(
                  index: index,
                  child: _TaskCard(
                    task: task,
                    delegate: widget.delegate,
                    organizationId: widget.delegate.organizationUID,
                  ),
                );
              },
            );
          }
          return const SizedBox.shrink();
        },
      ),
    );
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

class _FilterBarDelegate extends StatelessWidget {
  final Delegate delegate;

  const _FilterBarDelegate({required this.delegate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocBuilder<DelegateTasksBloc, DelegateTasksState>(
      builder: (context, state) {
        final currentFilter = state.statusFilter;

        return Container(
          padding: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: TashilSpacing.page,
                ),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(l10n.all),
                      selected: currentFilter == null,
                      onSelected: (_) => _updateFilter(context, null),
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                    FilterChip(
                      label: Text(l10n.taskCancelled),
                      selected: currentFilter == TaskStatus.cancelled,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.cancelled),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: TashilSpacing.xs),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsetsDirectional.symmetric(
                  horizontal: TashilSpacing.page,
                ),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(l10n.taskPending),
                      selected: currentFilter == TaskStatus.pending,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.pending),
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                    FilterChip(
                      label: Text(l10n.taskInProgress),
                      selected: currentFilter == TaskStatus.inProgress,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.inProgress),
                    ),
                    const SizedBox(width: TashilSpacing.sm),
                    FilterChip(
                      label: Text(l10n.taskCompleted),
                      selected: currentFilter == TaskStatus.completed,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.completed),
                    ),
                  ],
                ),
              ),
            ],
          ),
        );
      },
    );
  }

  void _updateFilter(BuildContext context, TaskStatus? status) {
    context.read<DelegateTasksBloc>().add(
      StatusFilterChangedDelegate(
        organizationId: delegate.organizationUID,
        delegateId: delegate.uid,
        companyId: delegate.companyUID,
        delegateRoleName: delegate.role.name,
        status: status,
      ),
    );
  }
}

class _DateHeader extends StatelessWidget {
  final DateTime date;

  const _DateHeader({required this.date});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    String text;
    final now = DateTime.now();
    final today = DateTime(now.year, now.month, now.day);
    final yesterday = today.subtract(const Duration(days: 1));
    final checkDate = DateTime(date.year, date.month, date.day);

    if (checkDate == today) {
      text = l10n.today;
    } else if (checkDate == yesterday) {
      text = l10n.yesterday;
    } else {
      text = DateFormat.yMMMMd(Localizations.localeOf(context).toLanguageTag()).format(date);
    }

    return Padding(
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.xs,
        TashilSpacing.lg,
        TashilSpacing.xs,
        TashilSpacing.sm,
      ),
      child: Text(
        text,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
        ),
      ),
    );
  }
}

/// TAS-356: one Card.filled per task, the task icon on primary + onPrimary
/// (TAS-384 rule), status and high priority as compact labels, and the
/// quick «إكمال» as a 48dp IconButton.filled with a tooltip (was a 22dp
/// GestureDetector without a name).
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
    final theme = Theme.of(context);
    final cs = theme.colorScheme;
    final l10n = AppLocalizations.of(context)!;
    final open = task.status == TaskStatus.pending ||
        task.status == TaskStatus.inProgress;

    return Card.filled(
      margin: const EdgeInsetsDirectional.only(bottom: TashilSpacing.sm),
      clipBehavior: Clip.antiAlias,
      child: InkWell(
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
        child: Padding(
          padding: const EdgeInsets.all(TashilSpacing.md),
          child: Row(
            children: [
              Container(
                padding: const EdgeInsets.all(TashilSpacing.sm),
                decoration: BoxDecoration(
                  color: cs.primary,
                  shape: BoxShape.circle,
                ),
                child: Icon(Icons.task_alt_rounded, size: 20, color: cs.onPrimary),
              ),
              const SizedBox(width: TashilSpacing.md),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        decoration: task.status == TaskStatus.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.xs / 2),
                    Text(
                      task.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: cs.onSurfaceVariant,
                      ),
                    ),
                    const SizedBox(height: TashilSpacing.xs),
                    Wrap(
                      spacing: TashilSpacing.xs,
                      runSpacing: TashilSpacing.xs,
                      children: [
                        _StatusSmallChip(status: task.status),
                        if (task.priority == TaskPriority.high)
                          _TaskLabel(
                            text: l10n.high,
                            container: cs.tertiaryContainer,
                            onContainer: cs.onTertiaryContainer,
                          ),
                      ],
                    ),
                    TaskCardMeta(
                      hasImage: task.hasImage,
                      isEdited: task.isEdited,
                    ),
                  ],
                ),
              ),
              const SizedBox(width: TashilSpacing.sm),
              if (open)
                IconButton.filled(
                  key: ValueKey('task_quick_complete_${task.uid}'),
                  tooltip: l10n.complete,
                  onPressed: () => _updateStatus(context, TaskStatus.completed),
                  icon: const Icon(Icons.check_rounded),
                )
              else
                Text(
                  DateFormat.Hm().format(task.createdAt),
                  style: theme.textTheme.labelSmall?.copyWith(
                    color: cs.onSurfaceVariant,
                  ),
                ),
            ],
          ),
        ),
      ),
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
            style: Theme.of(context).textTheme.labelSmall?.copyWith(
              color: onContainer,
            ),
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
      TaskStatus.pending => (
        cs.surfaceContainerHighest,
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
        cs.surfaceContainerHighest,
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
