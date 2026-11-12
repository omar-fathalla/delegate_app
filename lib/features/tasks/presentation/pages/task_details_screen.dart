import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/presentation/widgets/task_image_widgets.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:flutter/material.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/delete_task.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_event.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:intl/intl.dart' hide TextDirection;
import 'package:delegate_app/injection_container.dart' as di;

class TaskDetailsScreen extends StatefulWidget {
  final TaskEntity task;
  final bool isAdmin;
  final String organizationId;

  /// Profile id of the signed-in staff member, compared with
  /// [TaskEntity.createdBy] alongside the Firebase Auth uid.
  final String? currentUserId;

  /// Test seam; defaults to the Firebase Auth uid.
  final String? authUidOverride;

  const TaskDetailsScreen({
    super.key,
    required this.task,
    required this.isAdmin,
    required this.organizationId,
    this.currentUserId,
    this.authUidOverride,
  });

  @override
  State<TaskDetailsScreen> createState() => _TaskDetailsScreenState();
}

class _TaskDetailsScreenState extends State<TaskDetailsScreen> {
  late TaskEntity _task;
  late TextEditingController _titleController;
  late TextEditingController _descriptionController;
  late TextEditingController _notesController;
  late TaskStatus _currentStatus;
  late TaskPriority _currentPriority;
  late DateTime _dueDate;
  bool _isEditing = false;
  TaskImageUpload? _newImage;
  bool _imageRemoved = false;
  bool _imageUploading = false;

  /// Only the supervisor who sent the task may edit or delete it.
  bool get _isSender {
    if (!widget.isAdmin) return false;
    final authUid =
        widget.authUidOverride ?? FirebaseAuth.instance.currentUser?.uid;
    final createdBy = _task.createdBy;
    if (createdBy.isEmpty) return false;
    return createdBy == authUid || createdBy == widget.currentUserId;
  }

  @override
  void initState() {
    super.initState();
    _task = widget.task;
    _titleController = TextEditingController(text: _task.title);
    _descriptionController = TextEditingController(text: _task.description);
    _notesController = TextEditingController(text: _task.notes ?? '');
    _currentStatus = _task.status;
    _currentPriority = _task.priority;
    _dueDate = _task.dueDate;
  }

  @override
  void dispose() {
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _saveChanges(BuildContext context) {
    final imageChanged = _newImage != null || _imageRemoved;
    final contentChanged = imageChanged ||
        _titleController.text != _task.title ||
        _descriptionController.text != _task.description;
    var base = _task;
    if (_newImage != null) {
      base = base.copyWith(
        imagePath: _newImage!.path,
        clearImageUrl: true,
      );
    } else if (_imageRemoved) {
      base = base.copyWith(clearImage: true);
    }
    if (contentChanged) base = base.copyWith(editedAt: DateTime.now());
    final updatedTask = base.copyWith(
      title: _titleController.text,
      description: _descriptionController.text,
      status: _currentStatus,
      priority: _currentPriority,
      dueDate: _dueDate,
      notes: _notesController.text,
    );

    if (widget.isAdmin) {
      context.read<AdminTasksBloc>().add(
        UpdateTaskRequested(
          organizationId: widget.organizationId,
          task: updatedTask,
        ),
      );
    } else {
      context.read<DelegateTasksBloc>().add(
        UpdateTaskRequestedDelegate(
          organizationId: widget.organizationId,
          task: updatedTask,
        ),
      );
    }

    setState(() {
      _task = updatedTask;
      _isEditing = false;
      _newImage = null;
      _imageRemoved = false;
    });
    ScaffoldMessenger.of(context).showSnackBar(
      SnackBar(
        content: Text(AppLocalizations.of(context)!.taskUpdatedSuccessfully),
      ),
    );
  }

  @override
  Widget build(BuildContext context) {
    return MultiBlocProvider(
      providers: [
        BlocProvider(create: (context) => di.sl<AdminTasksBloc>()),
        BlocProvider(create: (context) => di.sl<DelegateTasksBloc>()),
      ],
      child: Builder(
        builder: (context) {
          final l10n = AppLocalizations.of(context)!;
          final theme = Theme.of(context);

          return Scaffold(
            appBar: AppBar(
              centerTitle: true,
              title: Text(
                _isEditing ? l10n.addTask : l10n.taskDetails,
                style: const TextStyle(fontWeight: FontWeight.bold),
              ),
              actions: [
                if (_isSender && _isEditing)
                  Padding(
                    padding: const EdgeInsets.symmetric(horizontal: 8.0),
                    child: IconButton.filledTonal(
                      icon: const Icon(Symbols.check_rounded),
                      onPressed: _imageUploading
                          ? null
                          : () => _saveChanges(context),
                    ),
                  )
                else if (_isSender)
                  PopupMenuButton<String>(
                    key: const Key('task-more-actions'),
                    tooltip: l10n.taskMoreActions,
                    icon: const Icon(Symbols.more_vert_rounded),
                    onSelected: (value) {
                      if (value == 'edit') {
                        setState(() => _isEditing = true);
                      } else if (value == 'delete') {
                        _confirmDelete(context);
                      }
                    },
                    itemBuilder: (ctx) => [
                      PopupMenuItem(
                        value: 'edit',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: const Icon(Symbols.edit_rounded),
                          title: Text(l10n.taskEditAction),
                        ),
                      ),
                      PopupMenuItem(
                        value: 'delete',
                        child: ListTile(
                          contentPadding: EdgeInsets.zero,
                          leading: Icon(Symbols.delete_rounded,
                              color: theme.colorScheme.error),
                          title: Text(l10n.taskDeleteAction,
                              style: TextStyle(color: theme.colorScheme.error)),
                        ),
                      ),
                    ],
                  ),
              ],
            ),
            body: SingleChildScrollView(
              padding: const EdgeInsets.symmetric(horizontal: 16, vertical: 8),
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    label: l10n.taskTitle,
                    child: _isEditing
                        ? TextFormField(
                            controller: _titleController,
                            style: theme.textTheme.titleMedium?.copyWith(
                              fontWeight: FontWeight.bold,
                            ),
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              prefixIcon: const Icon(Icons.title_rounded),
                              hintText: l10n.taskTitle,
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
                            keyboardType: TextInputType.text,
                          )
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.primaryContainer
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _task.title,
                              style: theme.textTheme.headlineSmall?.copyWith(
                                fontWeight: FontWeight.bold,
                                color: theme.colorScheme.onSurface,
                              ),
                              textDirection: Bidi.hasAnyRtl(_task.title)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          ),
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    label: l10n.taskDescription,
                    child: _isEditing
                        ? TextFormField(
                            controller: _descriptionController,
                            minLines: 3,
                            maxLines: null,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              prefixIcon: const Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: 16),
                                    child: Icon(Icons.description_outlined),
                                  ),
                                ],
                              ),
                              hintText: l10n.taskDescription,
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
                            keyboardType: TextInputType.multiline,
                          )
                        : Container(
                            width: double.infinity,
                            padding: const EdgeInsets.all(16),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _task.description,
                              style: theme.textTheme.bodyLarge,
                              textDirection: Bidi.hasAnyRtl(_task.description)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          ),
                  ),
                  if (_isEditing && _isSender) ...[
                    const SizedBox(height: 12),
                    TaskImagePickerField(
                      organizationId: widget.organizationId,
                      companyId: _task.companyId,
                      initialPath: _imageRemoved ? null : _task.imagePath,
                      initialTaskId: _task.uid,
                      onChanged: (upload) => setState(() {
                        _newImage = upload;
                        _imageRemoved = upload == null;
                      }),
                      onUploadingChanged: (v) =>
                          setState(() => _imageUploading = v),
                    ),
                  ] else if (_task.imagePath != null &&
                      _task.imagePath!.isNotEmpty) ...[
                    const SizedBox(height: 12),
                    TaskImageThumbnail(
                      imagePath: _task.imagePath!,
                      taskId: _task.uid,
                      organizationId: widget.organizationId,
                    ),
                  ],
                  if (_task.isEdited && !_isEditing) ...[
                    const SizedBox(height: 8),
                    const TaskEditedLabel(),
                  ],
                  const SizedBox(height: 12),
                  _buildField(
                    label: l10n.taskPriority,
                    child: _isEditing
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: TaskPriority.values.map((p) {
                              final isSelected = _currentPriority == p;
                              final color = _getPriorityColor(p);
                              return ChoiceChip(
                                avatar: isSelected
                                    ? null
                                    : _getPriorityIcon(p, color: color),
                                label: Text(_getPriorityName(l10n, p)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _currentPriority = p);
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
                          )
                        : Card(
                            elevation: 0,
                            color: _getPriorityColor(
                              _currentPriority,
                            ).withValues(alpha: 0.1),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: _getPriorityColor(
                                  _currentPriority,
                                ).withValues(alpha: 0.5),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _getPriorityIcon(
                                    _currentPriority,
                                    color: _getPriorityColor(_currentPriority),
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _getPriorityName(l10n, _currentPriority),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: _getPriorityColor(
                                            _currentPriority,
                                          ),
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    label: l10n.taskStatus,
                    child: _isEditing || !widget.isAdmin
                        ? Wrap(
                            spacing: 8,
                            runSpacing: 8,
                            children: TaskStatus.values.map((s) {
                              final isSelected = _currentStatus == s;
                              final color = _getStatusColor(s, theme);
                              return ChoiceChip(
                                avatar: isSelected
                                    ? null
                                    : _getStatusIcon(s, color: color),
                                label: Text(_getStatusName(l10n, s)),
                                selected: isSelected,
                                onSelected: (selected) {
                                  if (selected) {
                                    setState(() => _currentStatus = s);
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
                          )
                        : Card(
                            elevation: 0,
                            color: theme.colorScheme.primaryContainer
                                .withValues(alpha: 0.2),
                            shape: RoundedRectangleBorder(
                              borderRadius: BorderRadius.circular(12),
                              side: BorderSide(
                                color: theme.colorScheme.primary.withValues(
                                  alpha: 0.5,
                                ),
                              ),
                            ),
                            child: Padding(
                              padding: const EdgeInsets.symmetric(
                                horizontal: 16,
                                vertical: 6,
                              ),
                              child: Row(
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  _getStatusIcon(
                                    _currentStatus,
                                    color: theme.colorScheme.primary,
                                  ),
                                  const SizedBox(width: 12),
                                  Text(
                                    _getStatusName(l10n, _currentStatus),
                                    style: theme.textTheme.titleMedium
                                        ?.copyWith(
                                          color: theme.colorScheme.primary,
                                          fontWeight: FontWeight.bold,
                                        ),
                                  ),
                                ],
                              ),
                            ),
                          ),
                  ),
                  const SizedBox(height: 12),
                  _buildField(
                    label: l10n.taskDueDate,
                    child: InkWell(
                      onTap: _isEditing ? () => _selectDate(context) : null,
                      borderRadius: BorderRadius.circular(16),
                      child: Container(
                        padding: const EdgeInsets.symmetric(
                          horizontal: 16,
                          vertical: 10,
                        ),
                        decoration: BoxDecoration(
                          color: theme.colorScheme.surfaceContainerHighest
                              .withValues(alpha: 0.3),
                          borderRadius: BorderRadius.circular(16),
                          border: _isEditing
                              ? Border.all(
                                  color: theme.colorScheme.outline.withValues(
                                    alpha: 0.5,
                                  ),
                                )
                              : null,
                        ),
                        child: Row(
                          children: [
                            Icon(
                              Icons.calendar_month_rounded,
                              color: theme.colorScheme.primary,
                            ),
                            const SizedBox(width: 16),
                            Text(
                              DateFormat.yMMMMd().format(_dueDate),
                              style: theme.textTheme.bodyLarge?.copyWith(
                                fontWeight: FontWeight.bold,
                              ),
                            ),
                            const Spacer(),
                            if (_isEditing)
                              Icon(
                                Icons.edit_calendar_rounded,
                                color: theme.colorScheme.outline,
                              ),
                          ],
                        ),
                      ),
                    ),
                  ),
                  const SizedBox(height: 10),
                  _buildField(
                    label: "Notes",
                    child: _isEditing || !widget.isAdmin
                        ? TextFormField(
                            controller: _notesController,
                            minLines: 2,
                            maxLines: null,
                            decoration: InputDecoration(
                              filled: true,
                              fillColor: theme
                                  .colorScheme
                                  .surfaceContainerHighest
                                  .withValues(alpha: 0.3),
                              prefixIcon: const Column(
                                mainAxisAlignment: MainAxisAlignment.start,
                                mainAxisSize: MainAxisSize.min,
                                children: [
                                  Padding(
                                    padding: EdgeInsets.only(top: 16),
                                    child: Icon(Icons.note_alt_outlined),
                                  ),
                                ],
                              ),
                              hintText: "Add notes here...",
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
                            keyboardType: TextInputType.multiline,
                          )
                        : _task.notes != null && _task.notes!.isNotEmpty
                        ? Container(
                            width: double.infinity,
                            padding: const EdgeInsets.symmetric(
                              horizontal: 16,
                              vertical: 10,
                            ),
                            decoration: BoxDecoration(
                              color: theme.colorScheme.surfaceContainerHighest
                                  .withValues(alpha: 0.1),
                              borderRadius: BorderRadius.circular(16),
                            ),
                            child: Text(
                              _task.notes!,
                              textDirection: Bidi.hasAnyRtl(_task.notes!)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: 16),
                  if (!widget.isAdmin)
                    if (_currentStatus != _task.status)
                      FilledButton(
                        onPressed: () => _saveChanges(context),
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        child: Text(
                          l10n.saveChanges,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      )
                    else if (_currentStatus != TaskStatus.completed &&
                        _currentStatus != TaskStatus.cancelled)
                      FilledButton.icon(
                        onPressed: () {
                          setState(() {
                            _currentStatus = TaskStatus.completed;
                          });
                          _saveChanges(context);
                        },
                        style: FilledButton.styleFrom(
                          minimumSize: const Size(double.infinity, 56),
                          backgroundColor: Colors.green.shade600,
                          foregroundColor: Colors.white,
                          shape: RoundedRectangleBorder(
                            borderRadius: BorderRadius.circular(16),
                          ),
                        ),
                        icon: const Icon(Icons.check_circle_outline_rounded),
                        label: Text(
                          l10n.complete,
                          style: const TextStyle(fontWeight: FontWeight.bold),
                        ),
                      ),
                  if (_isSender && !_isEditing) ...[
                    const SizedBox(height: 16),
                    FilledButton.tonalIcon(
                      onPressed: () => _confirmDelete(context),
                      style: FilledButton.styleFrom(
                        minimumSize: const Size(double.infinity, 56),
                        backgroundColor: theme.colorScheme.errorContainer
                            .withValues(alpha: 0.5),
                        foregroundColor: theme.colorScheme.error,
                        shape: RoundedRectangleBorder(
                          borderRadius: BorderRadius.circular(16),
                        ),
                      ),
                      icon: const Icon(Icons.delete_outline_rounded),
                      label: Text(
                        l10n.deleteTask,
                        style: const TextStyle(fontWeight: FontWeight.bold),
                      ),
                    ),
                  ],
                ],
              ),
            ),
          );
        },
      ),
    );
  }

  Widget _buildField({required String label, required Widget child}) {
    final theme = Theme.of(context);
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(start: 4, bottom: 4),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.primary,
              fontWeight: FontWeight.bold,
              letterSpacing: 1.1,
            ),
          ),
        ),
        child,
      ],
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

  Icon _getStatusIcon(TaskStatus status, {Color? color}) {
    switch (status) {
      case TaskStatus.pending:
        return Icon(Icons.pending_actions_rounded, color: color, size: 20);
      case TaskStatus.inProgress:
        return Icon(Icons.autorenew_rounded, color: color, size: 20);
      case TaskStatus.completed:
        return Icon(Icons.check_circle_outline_rounded, color: color, size: 20);
      case TaskStatus.cancelled:
        return Icon(Icons.cancel_outlined, color: color, size: 20);
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

  String _getStatusName(AppLocalizations l10n, TaskStatus status) {
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

  Color _getStatusColor(TaskStatus status, ThemeData theme) {
    switch (status) {
      case TaskStatus.pending:
        return Colors.amber.shade800;
      case TaskStatus.inProgress:
        return theme.colorScheme.primary;
      case TaskStatus.completed:
        return Colors.green.shade700;
      case TaskStatus.cancelled:
        return theme.colorScheme.error;
    }
  }

  Future<void> _selectDate(BuildContext context) async {
    final DateTime? picked = await showDatePicker(
      context: context,
      initialDate: _dueDate,
      firstDate: DateTime.now(),
      lastDate: DateTime(2101),
    );
    if (picked != null && picked != _dueDate) {
      setState(() => _dueDate = picked);
    }
  }

  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    final theme = Theme.of(context);
    final colorScheme = theme.colorScheme;
    final isMobile = MediaQuery.of(context).size.width <= 768;

    Widget buildSheetContent(BuildContext modalContext, StateSetter setModalState, bool isDeleting) {
      return Padding(
        padding: const EdgeInsets.fromLTRB(20, 12, 20, 24),
        child: Column(
          mainAxisSize: MainAxisSize.min,
          crossAxisAlignment: CrossAxisAlignment.stretch,
          children: [
            if (isMobile)
              Center(
                child: Container(
                  width: 38,
                  height: 4.5,
                  margin: const EdgeInsets.only(bottom: 16),
                  decoration: BoxDecoration(
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(3),
                  ),
                ),
              ),
            Row(
              children: [
                Container(
                  padding: const EdgeInsets.all(10),
                  decoration: BoxDecoration(
                    color: colorScheme.errorContainer.withValues(alpha: 0.6),
                    borderRadius: BorderRadius.circular(12),
                  ),
                  child: Icon(Icons.delete_outline_rounded, color: colorScheme.error, size: 24),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deleteTask,
                        style: const TextStyle(fontSize: 16, fontWeight: FontWeight.bold),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _task.title,
                        style: TextStyle(fontSize: 12, color: colorScheme.onSurfaceVariant),
                        maxLines: 1,
                        overflow: TextOverflow.ellipsis,
                      ),
                    ],
                  ),
                ),
              ],
            ),
            const SizedBox(height: 16),
            Text(
              l10n.deleteTaskConfirmation,
              style: TextStyle(fontSize: 13, color: colorScheme.onSurfaceVariant, height: 1.4),
            ),
            const SizedBox(height: 24),

            // Connected Dual Action Button Group
            Container(
              height: 48,
              decoration: BoxDecoration(
                color: colorScheme.surfaceContainerHigh,
                borderRadius: BorderRadius.circular(24),
                border: Border.all(
                  color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  width: 1.2,
                ),
              ),
              clipBehavior: Clip.antiAlias,
              child: Row(
                children: [
                  // Cancel Button (إلغاء)
                  Expanded(
                    flex: 2,
                    child: Material(
                      color: Colors.transparent,
                      child: InkWell(
                        onTap: isDeleting ? null : () => Navigator.pop(modalContext),
                        child: Center(
                          child: Text(
                            l10n.cancel,
                            style: TextStyle(
                              fontSize: 13.5,
                              fontWeight: FontWeight.bold,
                              color: colorScheme.onSurfaceVariant,
                            ),
                          ),
                        ),
                      ),
                    ),
                  ),

                  // Divider
                  VerticalDivider(
                    width: 1,
                    thickness: 1,
                    color: colorScheme.outlineVariant.withValues(alpha: 0.6),
                  ),

                  // Confirm Delete Button (حذف)
                  Expanded(
                    flex: 3,
                    child: Material(
                      color: colorScheme.error,
                      child: InkWell(
                        onTap: isDeleting
                            ? null
                            : () async {
                                setModalState(() => isDeleting = true);
                                try {
                                  final deleteTaskUseCase = di.sl<DeleteTask>();
                                  final result = await deleteTaskUseCase(
                                    widget.organizationId,
                                    _task.uid,
                                  );

                                  if (!modalContext.mounted) return;

                                  result.fold(
                                    (failure) {
                                      setModalState(() => isDeleting = false);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(failure.message),
                                          backgroundColor: colorScheme.error,
                                        ),
                                      );
                                    },
                                    (_) {
                                      Navigator.pop(modalContext);
                                      Navigator.pop(context, true);
                                      ScaffoldMessenger.of(context).showSnackBar(
                                        SnackBar(
                                          content: Text(AppLocalizations.of(context)!.taskDeleted),
                                          backgroundColor: Colors.green.shade700,
                                        ),
                                      );
                                    },
                                  );
                                } catch (e) {
                                  if (modalContext.mounted) {
                                    setModalState(() => isDeleting = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(AppLocalizations.of(context)!.taskDeleteFailed(e)),
                                        backgroundColor: colorScheme.error,
                                      ),
                                    );
                                  }
                                }
                              },
                        child: Center(
                          child: isDeleting
                              ? SizedBox(
                                  width: 20,
                                  height: 20,
                                  child: CircularProgressIndicator(
                                    strokeWidth: 2,
                                    color: colorScheme.onError,
                                  ),
                                )
                              : Row(
                                  mainAxisAlignment: MainAxisAlignment.center,
                                  children: [
                                    Icon(Icons.delete_forever_rounded, size: 18, color: colorScheme.onError),
                                    const SizedBox(width: 6),
                                    Text(
                                      l10n.delete,
                                      style: TextStyle(
                                        fontSize: 13.5,
                                        fontWeight: FontWeight.bold,
                                        color: colorScheme.onError,
                                      ),
                                    ),
                                  ],
                                ),
                        ),
                      ),
                    ),
                  ),
                ],
              ),
            ),
          ],
        ),
      );
    }

    if (isMobile) {
      await showModalBottomSheet<void>(
        context: context,
        backgroundColor: colorScheme.surface,
        shape: const RoundedRectangleBorder(
          borderRadius: BorderRadius.vertical(top: Radius.circular(28)),
        ),
        builder: (modalCtx) {
          bool isDeleting = false;
          return StatefulBuilder(
            builder: (ctx, setModalState) => buildSheetContent(modalCtx, setModalState, isDeleting),
          );
        },
      );
    } else {
      await showDialog<void>(
        context: context,
        builder: (modalCtx) {
          bool isDeleting = false;
          return Dialog(
            backgroundColor: colorScheme.surface,
            shape: RoundedRectangleBorder(borderRadius: BorderRadius.circular(24)),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: StatefulBuilder(
                builder: (ctx, setModalState) => buildSheetContent(modalCtx, setModalState, isDeleting),
              ),
            ),
          );
        },
      );
    }
  }
}
