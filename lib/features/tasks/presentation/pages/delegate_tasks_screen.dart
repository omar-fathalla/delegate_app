import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
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
    context.read<DelegateTasksBloc>().add(
      LoadDelegateTasksRequested(
        organizationId: widget.delegate.organizationUID,
        delegateId: widget.delegate.uid,
        companyId: widget.delegate.companyUID,
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return Scaffold(
      appBar: AppBar(
        title: const SizedBox.shrink(),
        bottom: PreferredSize(
          preferredSize: const Size.fromHeight(110),
          child: _FilterBarDelegate(delegate: widget.delegate),
        ),
        actions: [
          IconButton(
            icon: const Icon(Icons.refresh_rounded),
            onPressed: _loadTasks,
          ),
        ],
      ),
      body: BlocConsumer<DelegateTasksBloc, DelegateTasksState>(
        listener: (context, state) {
          if (state is TaskStatusUpdateSuccess) {
            _loadTasks();
          }
        },
        builder: (context, state) {
          if (state is DelegateTasksInitial) {
            _loadTasks();
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DelegateTasksLoading) {
            return const Center(child: CircularProgressIndicator());
          }
          if (state is DelegateTasksError) {
            return Center(
              child: Column(
                mainAxisAlignment: MainAxisAlignment.center,
                children: [
                  Text(
                    state.message,
                    style: const TextStyle(color: Colors.red),
                  ),
                  const SizedBox(height: 16),
                  ElevatedButton(
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
                child: Column(
                  mainAxisAlignment: MainAxisAlignment.center,
                  children: [
                    Icon(
                      Icons.task_alt_rounded,
                      size: 64,
                      color: theme.colorScheme.outlineVariant,
                    ),
                    const SizedBox(height: 16),
                    Text(l10n.noTasksYet, style: theme.textTheme.titleMedium),
                  ],
                ),
              );
            }

            return ListView.builder(
              controller: _scrollController,
              padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
              itemCount: state.hasReachedMax
                  ? state.tasks.length
                  : state.tasks.length + 1,
              itemBuilder: (context, index) {
                if (index >= state.tasks.length) {
                  return const Center(
                    child: Padding(
                      padding: EdgeInsets.all(16.0),
                      child: CircularProgressIndicator(strokeWidth: 2),
                    ),
                  );
                }

                final task = state.tasks[index];
                final prevTask = index > 0 ? state.tasks[index - 1] : null;

                final showHeader =
                    prevTask == null ||
                    !_isSameDay(task.createdAt, prevTask.createdAt);

                if (showHeader) {
                  return Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      _DateHeader(date: task.createdAt),
                      _TaskCard(
                        task: task,
                        delegate: widget.delegate,
                        organizationId: widget.delegate.organizationUID,
                      ),
                    ],
                  );
                }

                return _TaskCard(
                  task: task,
                  delegate: widget.delegate,
                  organizationId: widget.delegate.organizationUID,
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
          padding: const EdgeInsets.only(bottom: 8),
          child: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Padding(
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(l10n.all),
                      selected: currentFilter == null,
                      onSelected: (_) => _updateFilter(context, null),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l10n.taskCancelled),
                      selected: currentFilter == TaskStatus.cancelled,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.cancelled),
                    ),
                  ],
                ),
              ),
              const SizedBox(height: 4),
              SingleChildScrollView(
                scrollDirection: Axis.horizontal,
                padding: const EdgeInsets.symmetric(horizontal: 16),
                child: Row(
                  children: [
                    FilterChip(
                      label: Text(l10n.taskPending),
                      selected: currentFilter == TaskStatus.pending,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.pending),
                    ),
                    const SizedBox(width: 8),
                    FilterChip(
                      label: Text(l10n.taskInProgress),
                      selected: currentFilter == TaskStatus.inProgress,
                      onSelected: (_) =>
                          _updateFilter(context, TaskStatus.inProgress),
                    ),
                    const SizedBox(width: 8),
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
      text = DateFormat.yMMMMd().format(date);
    }

    return Padding(
      padding: const EdgeInsets.fromLTRB(4, 16, 4, 8),
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

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      shape: RoundedRectangleBorder(
        borderRadius: BorderRadius.circular(12),
        side: BorderSide(
          color: theme.colorScheme.outlineVariant.withValues(alpha: 0.5),
        ),
      ),
      child: InkWell(
        onTap: () async {
          await context.push(
            '/task-details',
            extra: {
              'task': task,
              'isAdmin': false,
              'organizationId': organizationId,
            },
          );
          if (context.mounted) {
            context.read<DelegateTasksBloc>().add(
              LoadDelegateTasksRequested(
                organizationId: organizationId,
                delegateId: delegate.uid,
                companyId: delegate.companyUID,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              Container(
                width: 4,
                height: 40,
                decoration: BoxDecoration(
                  color: _getPriorityColor(theme, task.priority),
                  borderRadius: BorderRadius.circular(2),
                ),
              ),
              const SizedBox(width: 12),
              Expanded(
                child: Column(
                  crossAxisAlignment: CrossAxisAlignment.start,
                  children: [
                    Text(
                      task.title,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.titleSmall?.copyWith(
                        fontWeight: FontWeight.bold,
                        decoration: task.status == TaskStatus.completed
                            ? TextDecoration.lineThrough
                            : null,
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.description,
                      maxLines: 1,
                      overflow: TextOverflow.ellipsis,
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                  ],
                ),
              ),
              const SizedBox(width: 8),
              Column(
                crossAxisAlignment: CrossAxisAlignment.end,
                children: [
                  _StatusSmallChip(status: task.status),
                  const SizedBox(height: 4),
                  if (task.status == TaskStatus.pending ||
                      task.status == TaskStatus.inProgress)
                    GestureDetector(
                      onTap: () => _updateStatus(context, TaskStatus.completed),
                      child: Container(
                        padding: const EdgeInsets.all(4),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.primaryContainer,
                          shape: BoxShape.circle,
                        ),
                        child: Icon(
                          Icons.check_rounded,
                          size: 14,
                          color: theme.colorScheme.primary,
                        ),
                      ),
                    )
                  else
                    Text(
                      DateFormat.Hm().format(task.createdAt),
                      style: theme.textTheme.labelSmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                ],
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

  Color _getPriorityColor(ThemeData theme, TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return theme.colorScheme.error;
      case TaskPriority.medium:
        return Colors.orange;
      case TaskPriority.low:
        return Colors.green;
    }
  }
}

class _StatusSmallChip extends StatelessWidget {
  final TaskStatus status;

  const _StatusSmallChip({required this.status});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);

    Color color;
    IconData icon;

    switch (status) {
      case TaskStatus.pending:
        color = theme.colorScheme.outline;
        icon = Icons.access_time_rounded;
        break;
      case TaskStatus.inProgress:
        color = theme.colorScheme.primary;
        icon = Icons.sync_rounded;
        break;
      case TaskStatus.completed:
        color = Colors.green;
        icon = Icons.check_circle_outline_rounded;
        break;
      case TaskStatus.cancelled:
        color = theme.colorScheme.error;
        icon = Icons.block_flipped;
        break;
    }

    return Container(
      padding: const EdgeInsets.symmetric(horizontal: 6, vertical: 2),
      decoration: BoxDecoration(
        color: color.withValues(alpha: 0.1),
        borderRadius: BorderRadius.circular(4),
      ),
      child: Row(
        mainAxisSize: MainAxisSize.min,
        children: [
          Icon(icon, size: 10, color: color),
          const SizedBox(width: 2),
          Text(
            _getStatusLabel(context, status),
            style: TextStyle(
              color: color,
              fontSize: 9,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
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
