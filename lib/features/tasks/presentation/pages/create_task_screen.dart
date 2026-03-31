import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_state.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:intl/intl.dart' hide TextDirection;

class CreateTaskScreen extends StatefulWidget {
  final Delegate adminDelegate;

  const CreateTaskScreen({super.key, required this.adminDelegate});

  @override
  State<CreateTaskScreen> createState() => _CreateTaskScreenState();
}

class _CreateTaskScreenState extends State<CreateTaskScreen> {
  final _formKey = GlobalKey<FormState>();
  final _titleController = TextEditingController();
  final _descriptionController = TextEditingController();

  TaskPriority _selectedPriority = TaskPriority.medium;
  DateTime _selectedDate = DateTime.now().add(const Duration(days: 1));
  String _selectedAssignedTo = 'all';
  String _selectedAssignedToName = '';

  @override
  void initState() {
    super.initState();
    // Dispatch load delegates event
    WidgetsBinding.instance.addPostFrameCallback((_) {
      if (mounted) {
        // We need the organizationId and companyId
        // These are available through widget.adminDelegate
      }
    });
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    super.dispose();
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _selectedDate,
      firstDate: DateTime.now(),
      lastDate: DateTime.now().add(const Duration(days: 365)),
    );
    if (picked != null && picked != _selectedDate) {
      setState(() {
        _selectedDate = picked;
      });
    }
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);

    return BlocProvider(
      create: (context) => di.sl<CreateTaskBloc>(),
      child: BlocListener<CreateTaskBloc, CreateTaskState>(
        listener: (context, state) {
          if (state is CreateTaskSuccess) {
            ScaffoldMessenger.of(context).showSnackBar(
              SnackBar(content: Text(l10n.taskCreatedSuccessfully)),
            );
            Navigator.pop(context);
          } else if (state is CreateTaskError) {
            ScaffoldMessenger.of(
              context,
            ).showSnackBar(SnackBar(content: Text(state.message)));
          }
        },
        child: Builder(
          builder: (context) {
            // Trigger initial load
            if (context.read<CreateTaskBloc>().state is CreateTaskInitial &&
                context.read<CreateTaskBloc>().state.delegates == null) {
              context.read<CreateTaskBloc>().add(
                LoadDelegatesRequested(
                  organizationId: widget.adminDelegate.organizationUID,
                  companyId: widget.adminDelegate.companyUID,
                ),
              );
            }

            return Scaffold(
              appBar: AppBar(
                centerTitle: true,
                title: Text(
                  l10n.createTask,
                  style: const TextStyle(fontWeight: FontWeight.bold),
                ),
                bottom: PreferredSize(
                  preferredSize: const Size.fromHeight(1),
                  child: BlocBuilder<CreateTaskBloc, CreateTaskState>(
                    builder: (context, state) {
                      if (state is LoadingDelegates) {
                        return const LinearProgressIndicator();
                      }
                      return const SizedBox.shrink();
                    },
                  ),
                ),
              ),
              body: SingleChildScrollView(
                padding: const EdgeInsets.symmetric(
                  horizontal: 24,
                  vertical: 16,
                ),
                child: Form(
                  key: _formKey,
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.stretch,
                    children: [
                      _buildSectionHeader(theme, l10n.taskDetails),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _titleController,
                        style: theme.textTheme.titleMedium?.copyWith(
                          fontWeight: FontWeight.bold,
                        ),
                        decoration: InputDecoration(
                          labelText: l10n.taskTitle,
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          prefixIcon: const Icon(Icons.title_rounded),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.errorFieldRequired;
                          }
                          return null;
                        },
                        keyboardType: TextInputType.text,
                      ),
                      const SizedBox(height: 16),
                      TextFormField(
                        controller: _descriptionController,
                        decoration: InputDecoration(
                          labelText: l10n.taskDescription,
                          alignLabelWithHint: true,
                          filled: true,
                          fillColor: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          prefixIcon: const Padding(
                            padding: EdgeInsets.only(bottom: 50),
                            child: Icon(Icons.description_outlined),
                          ),
                          border: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide.none,
                          ),
                          focusedBorder: OutlineInputBorder(
                            borderRadius: BorderRadius.circular(16),
                            borderSide: BorderSide(
                              color: theme.colorScheme.primary,
                              width: 2,
                            ),
                          ),
                        ),
                        maxLines: 4,
                        validator: (value) {
                          if (value == null || value.isEmpty) {
                            return l10n.errorFieldRequired;
                          }
                          return null;
                        },
                        keyboardType: TextInputType.multiline,
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(theme, l10n.taskPriority),
                      const SizedBox(height: 12),
                      Wrap(
                        spacing: 8,
                        runSpacing: 8,
                        children: TaskPriority.values.map((p) {
                          final isSelected = _selectedPriority == p;
                          final color = _getPriorityColor(p);
                          return ChoiceChip(
                            avatar: isSelected
                                ? null
                                : _getPriorityIcon(p, color: color),
                            label: Text(_getPriorityName(l10n, p)),
                            selected: isSelected,
                            onSelected: (selected) {
                              if (selected) {
                                setState(() => _selectedPriority = p);
                              }
                            },
                            showCheckmark: true,
                            selectedColor: color.withValues(alpha: 0.2),
                            labelStyle: TextStyle(
                              fontWeight: isSelected
                                  ? FontWeight.bold
                                  : FontWeight.normal,
                              color: isSelected ? color : null,
                            ),
                          );
                        }).toList(),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(theme, l10n.taskSchedule),
                      const SizedBox(height: 12),
                      InkWell(
                        onTap: () => _selectDate(context),
                        borderRadius: BorderRadius.circular(16),
                        child: Container(
                          padding: const EdgeInsets.all(16),
                          decoration: BoxDecoration(
                            color: theme.colorScheme.surfaceContainerHighest
                                .withValues(alpha: 0.3),
                            borderRadius: BorderRadius.circular(16),
                          ),
                          child: Row(
                            children: [
                              Container(
                                padding: const EdgeInsets.all(10),
                                decoration: BoxDecoration(
                                  color: theme.colorScheme.primaryContainer
                                      .withValues(alpha: 0.5),
                                  borderRadius: BorderRadius.circular(12),
                                ),
                                child: Icon(
                                  Icons.calendar_month_rounded,
                                  color: theme.colorScheme.primary,
                                ),
                              ),
                              const SizedBox(width: 16),
                              Expanded(
                                child: Column(
                                  crossAxisAlignment: CrossAxisAlignment.start,
                                  children: [
                                    Text(
                                      l10n.taskDueDate,
                                      style: theme.textTheme.labelMedium
                                          ?.copyWith(
                                            color: theme.colorScheme.primary,
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                    const SizedBox(height: 2),
                                    Text(
                                      DateFormat.yMMMMd().format(_selectedDate),
                                      style: theme.textTheme.bodyLarge
                                          ?.copyWith(
                                            fontWeight: FontWeight.bold,
                                          ),
                                    ),
                                  ],
                                ),
                              ),
                              Icon(
                                Icons.edit_calendar_rounded,
                                color: theme.colorScheme.outline,
                              ),
                            ],
                          ),
                        ),
                      ),
                      const SizedBox(height: 24),
                      _buildSectionHeader(theme, l10n.assignTo),
                      const SizedBox(height: 12),
                      BlocBuilder<CreateTaskBloc, CreateTaskState>(
                        builder: (context, state) {
                          final delegates = (state.delegates ?? [])
                              .cast<Delegate>();

                          return LayoutBuilder(
                            builder: (context, constraints) {
                              return DropdownMenu<String>(
                                width: constraints.maxWidth,
                                initialSelection: _selectedAssignedTo,
                                leadingIcon: const Icon(
                                  Icons.person_search_rounded,
                                ),
                                label: Text(l10n.selectDelegate),
                                inputDecorationTheme: InputDecorationTheme(
                                  filled: true,
                                  fillColor: theme
                                      .colorScheme
                                      .surfaceContainerHighest
                                      .withValues(alpha: 0.3),
                                  border: OutlineInputBorder(
                                    borderRadius: BorderRadius.circular(16),
                                    borderSide: BorderSide.none,
                                  ),
                                ),
                                onSelected: (String? value) {
                                  if (value != null) {
                                    setState(() {
                                      _selectedAssignedTo = value;
                                      if (value == 'all') {
                                        _selectedAssignedToName =
                                            l10n.allDelegates;
                                      } else {
                                        final selected = delegates.firstWhere(
                                          (d) => d.uid == value,
                                          orElse: () =>
                                              widget.adminDelegate, // Fallback
                                        );
                                        _selectedAssignedToName =
                                            '${selected.firstName} ${selected.lastName}';
                                      }
                                    });
                                  }
                                },
                                dropdownMenuEntries: [
                                  DropdownMenuEntry(
                                    value: 'all',
                                    label: l10n.allDelegates,
                                    leadingIcon: const Icon(
                                      Icons.group_rounded,
                                    ),
                                  ),
                                  ...delegates.map(
                                    (delegate) => DropdownMenuEntry(
                                      value: delegate.uid,
                                      label:
                                          '${delegate.firstName} ${delegate.lastName}',
                                      leadingIcon: const Icon(
                                        Icons.person_pin_rounded,
                                      ),
                                    ),
                                  ),
                                ],
                              );
                            },
                          );
                        },
                      ),
                      const SizedBox(height: 48),
                      BlocBuilder<CreateTaskBloc, CreateTaskState>(
                        builder: (context, state) {
                          return FilledButton.icon(
                            onPressed: state is CreateTaskLoading
                                ? null
                                : () {
                                    if (_formKey.currentState!.validate()) {
                                      context.read<CreateTaskBloc>().add(
                                        CreateTaskSubmitted(
                                          organizationId: widget
                                              .adminDelegate
                                              .organizationUID,
                                          title: _titleController.text,
                                          description:
                                              _descriptionController.text,
                                          priority: _selectedPriority,
                                          dueDate: _selectedDate,
                                          assignedTo: _selectedAssignedTo,
                                          assignedToName:
                                              _selectedAssignedToName.isEmpty
                                              ? l10n.allDelegates
                                              : _selectedAssignedToName,
                                          companyId:
                                              widget.adminDelegate.companyUID,
                                          createdBy: widget.adminDelegate.uid,
                                          createdByName:
                                              '${widget.adminDelegate.firstName} ${widget.adminDelegate.lastName}',
                                        ),
                                      );
                                    }
                                  },
                            style: FilledButton.styleFrom(
                              minimumSize: const Size(double.infinity, 64),
                              shape: RoundedRectangleBorder(
                                borderRadius: BorderRadius.circular(20),
                              ),
                              elevation: 0,
                            ),
                            icon: state is CreateTaskLoading
                                ? const SizedBox(
                                    width: 24,
                                    height: 24,
                                    child: CircularProgressIndicator(
                                      strokeWidth: 3,
                                      color: Colors.white,
                                    ),
                                  )
                                : const Icon(
                                    Icons.check_circle_rounded,
                                    size: 28,
                                  ),
                            label: Text(
                              l10n.createTask,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: Colors.white,
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                          );
                        },
                      ),
                      const SizedBox(height: 24),
                    ],
                  ),
                ),
              ),
            );
          },
        ),
      ),
    );
  }

  Widget _buildSectionHeader(ThemeData theme, String title) {
    return Padding(
      padding: const EdgeInsets.only(left: 4, bottom: 8),
      child: Text(
        title,
        style: theme.textTheme.labelLarge?.copyWith(
          color: theme.colorScheme.primary,
          fontWeight: FontWeight.bold,
          letterSpacing: 1.1,
        ),
      ),
    );
  }

  Icon _getPriorityIcon(TaskPriority priority, {Color? color}) {
    switch (priority) {
      case TaskPriority.high:
        return Icon(Icons.priority_high_rounded, color: color, size: 20);
      case TaskPriority.medium:
        return Icon(Icons.low_priority_rounded, color: color, size: 20);
      case TaskPriority.low:
        return Icon(Icons.arrow_downward_rounded, color: color, size: 20);
    }
  }

  String _getPriorityName(AppLocalizations l10n, TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return l10n.high;
      case TaskPriority.medium:
        return l10n.medium;
      case TaskPriority.low:
        return l10n.low;
    }
  }

  Color _getPriorityColor(TaskPriority priority) {
    switch (priority) {
      case TaskPriority.high:
        return Colors.red.shade700;
      case TaskPriority.medium:
        return Colors.orange.shade700;
      case TaskPriority.low:
        return Colors.green.shade700;
    }
  }
}
