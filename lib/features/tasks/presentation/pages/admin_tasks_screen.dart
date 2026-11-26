import 'package:delegate_app/features/tasks/domain/task_assignee_label.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_image_widgets.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/config/theme/app_motion.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_state.dart';
import 'package:go_router/go_router.dart';
import 'package:delegate_app/features/tasks/presentation/pages/create_task_screen.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:intl/intl.dart';

class AdminTasksScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const AdminTasksScreen({super.key, required this.adminDelegate});

  @override
  State<AdminTasksScreen> createState() => _AdminTasksScreenState();
}

class _AdminTasksScreenState extends State<AdminTasksScreen> {
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
      context.read<AdminTasksBloc>().add(
        LoadMoreAdminTasksRequested(
          organizationId: widget.adminDelegate.organizationUID,
          companyId: widget.adminDelegate.companyUID,
          adminId: widget.adminDelegate.uid,
          adminRoleName: widget.adminDelegate.role.name,
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

  @override
  Widget build(BuildContext context) {
    return BlocProvider(
      create: (context) => di.sl<AdminTasksBloc>(),
      child: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          final theme = Theme.of(context);
          // Web HR shell (TAS-155): filters and «إنشاء مهمة» share one
          // toolbar row, and the form opens as an inner page.
          final inShell = HrInnerPageHost.maybeOf(context) != null;
          return Scaffold(
            appBar: inShell
                ? PreferredSize(
                    preferredSize: const Size.fromHeight(64),
                    child: _ShellToolbar(
                      adminDelegate: widget.adminDelegate,
                      onCreate: () => _openCreateTask(context, inShell: true),
                    ),
                  )
                : AppBar(
                    title: const SizedBox.shrink(),
                    bottom: PreferredSize(
                      preferredSize: const Size.fromHeight(110),
                      child: _FilterBar(adminDelegate: widget.adminDelegate),
                    ),
                  ),
            body: BlocBuilder<AdminTasksBloc, AdminTasksState>(
              builder: (context, state) {
                if (state is AdminTasksInitial) {
                  context.read<AdminTasksBloc>().add(
                    LoadAdminTasksRequested(
                      organizationId: widget.adminDelegate.organizationUID,
                      companyId: widget.adminDelegate.companyUID,
                      adminId: widget.adminDelegate.uid,
                      adminRoleName: widget.adminDelegate.role.name,
                    ),
                  );
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is AdminTasksLoading) {
                  return const Center(child: CircularProgressIndicator());
                }
                if (state is AdminTasksError) {
                  return Center(child: Text(state.message));
                }
                if (state is AdminTasksLoaded) {
                  if (state.tasks.isEmpty) {
                    return _NoTasksView(theme: theme, l10n: l10n);
                  }

                  return ListView.builder(
                    controller: _scrollController,
                    padding: const EdgeInsets.symmetric(
                      horizontal: 12,
                      vertical: 8,
                    ),
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
                      final prevTask = index > 0
                          ? state.tasks[index - 1]
                          : null;

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
                                adminDelegate: widget.adminDelegate,
                              ),
                            ],
                          ),
                        );
                      }

                      return M3StaggeredItem(
                        index: index,
                        child: _TaskCard(
                          task: task,
                          adminDelegate: widget.adminDelegate,
                        ),
                      );
                    },
                  );
                }
                return const SizedBox.shrink();
              },
            ),
            floatingActionButton: inShell
                ? null
                : FloatingActionButton(
                    heroTag: 'admin_tasks_add_task_fab',
                    tooltip: l10n.createTask,
                    onPressed: () => _openCreateTask(context, inShell: false),
                    child: const Icon(Icons.add_task_rounded),
                  ),
          );
        },
      ),
    );
  }

  void _openCreateTask(BuildContext context, {required bool inShell}) {
    final Future<void> opened;
    if (inShell) {
      opened = pushHrInnerPage<void>(
        context,
        title: AppLocalizations.of(context)!.createTask,
        builder: (_, shell) => CreateTaskScreen(
          adminDelegate: widget.adminDelegate,
          showAppBar: !shell,
        ),
      );
    } else if (HrInnerPageTracker.maybeOf(context) != null) {
      // Narrow web HR shell (TAS-189): full screen as before, counted in
      // the URL so the browser back button closes it.
      opened = pushHrInnerPage<void>(
        context,
        title: AppLocalizations.of(context)!.createTask,
        builder: (_, _) =>
            CreateTaskScreen(adminDelegate: widget.adminDelegate),
      );
    } else {
      opened = Navigator.push(
        context,
        MaterialPageRoute(
          builder: (context) =>
              CreateTaskScreen(adminDelegate: widget.adminDelegate),
        ),
      );
    }
    opened.then((_) {
      if (!context.mounted) return;
      context.read<AdminTasksBloc>().add(
        LoadAdminTasksRequested(
          organizationId: widget.adminDelegate.organizationUID,
          companyId: widget.adminDelegate.companyUID,
        ),
      );
    });
  }

  bool _isSameDay(DateTime date1, DateTime date2) {
    return date1.year == date2.year &&
        date1.month == date2.month &&
        date1.day == date2.day;
  }
}

/// Web HR shell toolbar: all status filters in one row, and the primary
/// «إنشاء مهمة» button with its label at the end.
class _ShellToolbar extends StatelessWidget {
  final Delegate adminDelegate;
  final VoidCallback onCreate;

  const _ShellToolbar({required this.adminDelegate, required this.onCreate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final cs = Theme.of(context).colorScheme;
    return Material(
      color: cs.surface,
      child: Padding(
        padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 12),
        child: Row(
          children: [
            Expanded(
              child: BlocBuilder<AdminTasksBloc, AdminTasksState>(
                builder: (context, state) {
                  final current = state.statusFilter;
                  final options = <(String, TaskStatus?)>[
                    (l10n.all, null),
                    (l10n.taskPending, TaskStatus.pending),
                    (l10n.taskInProgress, TaskStatus.inProgress),
                    (l10n.taskCompleted, TaskStatus.completed),
                    (l10n.taskCancelled, TaskStatus.cancelled),
                  ];
                  return SingleChildScrollView(
                    key: const ValueKey('admin_tasks_shell_filters'),
                    scrollDirection: Axis.horizontal,
                    child: Row(
                      children: [
                        for (final (label, status) in options) ...[
                          FilterChip(
                            label: Text(label),
                            selected: current == status,
                            onSelected: (_) => _FilterBar.updateFilter(
                              context,
                              adminDelegate,
                              status,
                            ),
                          ),
                          const SizedBox(width: 8),
                        ],
                      ],
                    ),
                  );
                },
              ),
            ),
            const SizedBox(width: 12),
            FilledButton.icon(
              key: const ValueKey('admin_tasks_create_button'),
              onPressed: onCreate,
              icon: const Icon(Icons.add_task_rounded),
              label: Text(l10n.createTask),
            ),
          ],
        ),
      ),
    );
  }
}

class _FilterBar extends StatelessWidget {
  final Delegate adminDelegate;

  const _FilterBar({required this.adminDelegate});

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;

    return BlocBuilder<AdminTasksBloc, AdminTasksState>(
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

  void _updateFilter(BuildContext context, TaskStatus? status) =>
      updateFilter(context, adminDelegate, status);

  static void updateFilter(
    BuildContext context,
    Delegate adminDelegate,
    TaskStatus? status,
  ) {
    context.read<AdminTasksBloc>().add(
      StatusFilterChanged(
        organizationId: adminDelegate.organizationUID,
        companyId: adminDelegate.companyUID,
        status: status,
        adminId: adminDelegate.uid,
        adminRoleName: adminDelegate.role.name,
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
      text = DateFormat.yMMMMd(
        Localizations.localeOf(context).toLanguageTag(),
      ).format(date);
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

class _NoTasksView extends StatelessWidget {
  final ThemeData theme;
  final AppLocalizations l10n;

  const _NoTasksView({required this.theme, required this.l10n});

  @override
  Widget build(BuildContext context) {
    return Center(
      child: Column(
        mainAxisAlignment: MainAxisAlignment.center,
        children: [
          Container(
            padding: const EdgeInsets.all(24),
            decoration: BoxDecoration(
              color: theme.colorScheme.primaryContainer.withValues(alpha: 0.4),
              shape: BoxShape.circle,
            ),
            child: Icon(
              Icons.task_alt_rounded,
              size: 48,
              color: theme.colorScheme.primary,
            ),
          ),
          const SizedBox(height: 16),
          Text(
            l10n.noTasksFound,
            style: theme.textTheme.titleMedium?.copyWith(
              color: theme.colorScheme.outline,
              fontWeight: FontWeight.bold,
            ),
          ),
        ],
      ),
    );
  }
}

class _TaskCard extends StatelessWidget {
  final TaskEntity task;
  final Delegate adminDelegate;

  const _TaskCard({required this.task, required this.adminDelegate});

  @override
  Widget build(BuildContext context) {
    final theme = Theme.of(context);
    final l10n = AppLocalizations.of(context)!;

    return Card(
      margin: const EdgeInsets.only(bottom: 8),
      elevation: 0,
      clipBehavior: Clip.antiAlias,
      child: InkWell(
        onTap: () async {
          await context.push(
            '/task-details',
            extra: {
              'task': task,
              'isAdmin': true,
              'organizationId': adminDelegate.organizationUID,
              'currentUserId': adminDelegate.uid,
              'currentUserRole': adminDelegate.role.name,
              'currentUserCompanyId': adminDelegate.companyUID,
              'currentUserName': adminDelegate.fullName,
            },
          );
          if (context.mounted) {
            context.read<AdminTasksBloc>().add(
              LoadAdminTasksRequested(
                organizationId: adminDelegate.organizationUID,
                companyId: adminDelegate.companyUID,
                adminId: adminDelegate.uid,
                adminRoleName: adminDelegate.role.name,
              ),
            );
          }
        },
        borderRadius: BorderRadius.circular(12),
        child: Padding(
          padding: const EdgeInsets.symmetric(horizontal: 12, vertical: 8),
          child: Row(
            children: [
              // Priority indicator bar
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
                      ),
                    ),
                    const SizedBox(height: 2),
                    Text(
                      task.assignedTo == 'all'
                          ? l10n.allDelegates
                          : taskAssigneeLabel(
                              assignedTo: task.assignedTo,
                              assignedToName: task.assignedToName,
                            ),
                      style: theme.textTheme.bodySmall?.copyWith(
                        color: theme.colorScheme.outline,
                      ),
                    ),
                    TaskCardMeta(
                      hasImage: task.hasImage,
                      isEdited: task.isEdited,
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

  Color _getPriorityColor(ThemeData theme, TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return theme.colorScheme.error;
      case TaskPriority.medium:
        return theme.colorScheme.tertiary;
      case TaskPriority.low:
        return theme.colorScheme.secondary;
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
