import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_proof.dart';
import 'package:delegate_app/features/tasks/domain/task_proof_paths.dart';

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

  /// Role / company of the signed-in viewer, used for proof-photo access.
  final String? currentUserRole;
  final String? currentUserCompanyId;
  final String? currentUserName;

  /// Test seam for proof-photo reads and writes.
  final TaskRemoteDataSource? proofSource;

  const TaskDetailsScreen({
    super.key,
    required this.task,
    required this.isAdmin,
    required this.organizationId,
    this.currentUserId,
    this.authUidOverride,
    this.currentUserRole,
    this.currentUserCompanyId,
    this.currentUserName,
    this.proofSource,
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
  List<String> _editPaths = [];
  final List<String> _sessionUploads = [];
  bool _imageUploading = false;
  bool _editSaved = false;
  int _imageViewEpoch = 0;
  List<TaskProof> _visibleProofs = const [];
  List<String> _ownProofPaths = [];
  List<String> _savedOwnProofPaths = [];
  final List<String> _sessionProofUploads = [];
  bool _proofUploading = false;
  bool _proofSaved = false;
  int _proofViewEpoch = 0;

  /// Only the supervisor who sent the task may edit or delete it.
  bool get _isSender {
    if (!widget.isAdmin) return false;
    final authUid =
        widget.authUidOverride ?? FirebaseAuth.instance.currentUser?.uid;
    final createdBy = _task.createdBy;
    if (createdBy.isEmpty) return false;
    return createdBy == authUid || createdBy == widget.currentUserId;
  }

  String? get _viewerId =>
      widget.currentUserId ??
      widget.authUidOverride ??
      FirebaseAuth.instance.currentUser?.uid;

  bool get _canViewAllProofs {
    if (_isSender) return true;
    return isCompanySupervisorRole(widget.currentUserRole) &&
        (widget.currentUserCompanyId ?? '') == _task.companyId;
  }

  bool get _canEditOwnProofs {
    if (_viewerId == null || _viewerId!.isEmpty) return false;
    if (_isSender) return false;
    if (!isTaskProofUploaderRole(widget.currentUserRole)) return false;
    return _currentStatus != TaskStatus.cancelled &&
        _task.status != TaskStatus.cancelled;
  }

  bool get _proofsChanged =>
      _ownProofPaths.join('\n') != _savedOwnProofPaths.join('\n');

  TaskRemoteDataSource get _proofs =>
      widget.proofSource ?? di.sl<TaskRemoteDataSource>();

  TaskImageStorage get _proofStorage =>
      TaskImageStorage.proof(organizationId: widget.organizationId);

  TaskImageFetcher get _proofFetcher => TaskImageFetcher.proof();

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
    _loadProofs();
  }

  @override
  void dispose() {
    // Cancel / abandon must leave already-saved images intact. Only drop
    // uncommitted new uploads from this edit session.
    _discardUncommittedUploads();
    _discardUncommittedProofUploads();
    _titleController.dispose();
    _descriptionController.dispose();
    _notesController.dispose();
    super.dispose();
  }

  void _discardUncommittedUploads() {
    if (_editSaved) return;
    final keep = _task.resolvedImagePaths.toSet();
    for (final path in _sessionUploads) {
      if (path.isNotEmpty && !keep.contains(path)) {
        TaskImageStorage().deleteQuietly(path);
      }
    }
    _sessionUploads.clear();
  }

  void _discardUncommittedProofUploads() {
    if (_proofSaved) return;
    final keep = _savedOwnProofPaths.toSet();
    for (final path in _sessionProofUploads) {
      if (path.isNotEmpty && !keep.contains(path)) {
        _proofStorage.deleteQuietly(path);
      }
    }
    _sessionProofUploads.clear();
  }

  Future<void> _loadProofs() async {
    final uid = _viewerId;
    try {
      if (_canViewAllProofs) {
        final all = await _proofs.listTaskProofs(
          widget.organizationId,
          _task.uid,
        );
        if (!mounted) return;
        final own = [
          for (final p in all)
            if (p.uploaderUid == uid) p,
        ];
        final others = [
          for (final p in all)
            if (p.uploaderUid != uid && p.imagePaths.isNotEmpty) p,
        ];
        setState(() {
          _visibleProofs = others;
          _ownProofPaths = own.isEmpty
              ? []
              : List<String>.from(own.first.imagePaths);
          _savedOwnProofPaths = List<String>.from(_ownProofPaths);
          _proofViewEpoch++;
        });
        return;
      }
      if (uid == null || uid.isEmpty) return;
      final mine = await _proofs.getTaskProof(
        widget.organizationId,
        _task.uid,
        uid,
      );
      if (!mounted) return;
      setState(() {
        _visibleProofs = const [];
        _ownProofPaths = List<String>.from(mine?.imagePaths ?? const []);
        _savedOwnProofPaths = List<String>.from(_ownProofPaths);
        _proofViewEpoch++;
      });
    } catch (_) {
      // Hide rather than show a broken-load error.
      if (!mounted) return;
      setState(() {
        _visibleProofs = const [];
      });
    }
  }

  Future<bool> _saveProofs() async {
    if (!_canEditOwnProofs || !_proofsChanged) return true;
    final uid = _viewerId;
    if (uid == null) return false;
    try {
      await _proofs.saveTaskProof(
        organizationId: widget.organizationId,
        taskId: _task.uid,
        uploaderUid: uid,
        imagePaths: List<String>.from(_ownProofPaths),
        companyUID: _task.companyId,
        uploadedByName: widget.currentUserName ?? '',
      );
      _savedOwnProofPaths = List<String>.from(_ownProofPaths);
      _sessionProofUploads.clear();
      _proofSaved = true;
      _proofViewEpoch++;
      return true;
    } catch (_) {
      return false;
    }
  }

  void _beginEditing() {
    _editPaths = List<String>.from(_task.resolvedImagePaths);
    _sessionUploads.clear();
    _editSaved = false;
    _isEditing = true;
  }

  Future<void> _saveChanges(BuildContext context) async {
    if (_canEditOwnProofs && _proofsChanged) {
      final ok = await _saveProofs();
      if (!ok) {
        if (context.mounted) {
          ScaffoldMessenger.of(context).showSnackBar(
            SnackBar(
              content: Text(
                AppLocalizations.of(context)!.taskImageUploadFailed,
              ),
            ),
          );
        }
        return;
      }
    }
    if (!context.mounted) return;
    final original = _task.resolvedImagePaths;
    final imageChanged = _editPaths.join('\n') != original.join('\n');
    final contentChanged =
        imageChanged ||
        _titleController.text != _task.title ||
        _descriptionController.text != _task.description;
    var base = _task;
    if (imageChanged) {
      if (_editPaths.isEmpty) {
        base = base.copyWith(clearImage: true);
      } else {
        base = base.copyWith(
          imagePath: _editPaths.first,
          imagePaths: List<String>.from(_editPaths),
          clearImageUrl: true,
        );
      }
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
      _editSaved = true;
      _sessionUploads.clear();
      _imageViewEpoch++;
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
                        setState(_beginEditing);
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
                          leading: Icon(
                            Symbols.delete_rounded,
                            color: theme.colorScheme.error,
                          ),
                          title: Text(
                            l10n.taskDeleteAction,
                            style: TextStyle(color: theme.colorScheme.error),
                          ),
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
                    TaskImagePickerList(
                      organizationId: widget.organizationId,
                      companyId: _task.companyId,
                      initialPaths: _editPaths,
                      initialTaskId: _task.uid,
                      deleteStorageImmediately: false,
                      onChanged: (paths) {
                        final previous = _editPaths.toSet();
                        setState(() => _editPaths = paths);
                        for (final path in paths) {
                          if (!previous.contains(path) &&
                              !_task.resolvedImagePaths.contains(path)) {
                            _sessionUploads.add(path);
                          }
                        }
                        // Drop an uncommitted replacement that was swapped
                        // out before Save. Never delete a saved original.
                        final keep = paths.toSet().union(
                          _task.resolvedImagePaths.toSet(),
                        );
                        final leftover = [
                          for (final path in previous)
                            if (!keep.contains(path) &&
                                _sessionUploads.contains(path))
                              path,
                        ];
                        for (final path in leftover) {
                          TaskImageStorage().deleteQuietly(path);
                          _sessionUploads.remove(path);
                        }
                      },
                      onUploadingChanged: (v) =>
                          setState(() => _imageUploading = v),
                    ),
                  ] else if (_task.hasImage) ...[
                    const SizedBox(height: 12),
                    TaskImageGallery(
                      key: ValueKey(
                        'view-$_imageViewEpoch-${_task.resolvedImagePaths.join(",")}',
                      ),
                      imagePaths: _task.resolvedImagePaths,
                      taskId: _task.uid,
                      organizationId: widget.organizationId,
                    ),
                  ],
                  if (_task.isEdited && !_isEditing) ...[
                    const SizedBox(height: 8),
                    const TaskEditedLabel(),
                  ],
                  ..._buildProofSection(l10n, theme),
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
                  if (_canEditOwnProofs &&
                      _proofsChanged &&
                      !_proofUploading) ...[
                    const SizedBox(height: 12),
                    FilledButton.tonalIcon(
                      onPressed: () => _saveChanges(context),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l10n.taskProofSave),
                    ),
                  ],
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

  List<Widget> _buildProofSection(AppLocalizations l10n, ThemeData theme) {
    final others = [
      for (final proof in _visibleProofs)
        if (proof.imagePaths.isNotEmpty) proof,
    ];
    final showOwnEditor = _canEditOwnProofs;
    final showOwnViewer = !showOwnEditor && _ownProofPaths.isNotEmpty;
    if (others.isEmpty && !showOwnEditor && !showOwnViewer) {
      return const [];
    }
    final children = <Widget>[const SizedBox(height: 16)];
    for (final proof in others) {
      final name = proof.uploadedByName.trim();
      children.add(
        _buildField(
          label: name.isEmpty ? l10n.taskProofTitle : l10n.taskProofBy(name),
          child: TaskImageGallery(
            key: ValueKey('proof-${proof.uploaderUid}-$_proofViewEpoch'),
            imagePaths: proof.imagePaths,
            taskId: _task.uid,
            organizationId: widget.organizationId,
            fetcher: _proofFetcher,
          ),
        ),
      );
      children.add(const SizedBox(height: 12));
    }
    if (showOwnEditor) {
      children.add(
        _buildField(
          label: l10n.taskProofTitle,
          child: TaskImagePickerList(
            key: ValueKey('proof-edit-$_proofViewEpoch'),
            organizationId: widget.organizationId,
            companyId: _task.companyId,
            initialPaths: _ownProofPaths,
            initialTaskId: _task.uid,
            deleteStorageImmediately: false,
            storage: _proofStorage,
            fetcher: _proofFetcher,
            attachLabel: l10n.taskProofAttach,
            attachAnotherLabel: l10n.taskImageAttachAnother,
            onChanged: (paths) {
              final previous = _ownProofPaths.toSet();
              setState(() => _ownProofPaths = paths);
              for (final path in paths) {
                if (!previous.contains(path) &&
                    !_savedOwnProofPaths.contains(path)) {
                  _sessionProofUploads.add(path);
                }
              }
              final keep = paths.toSet().union(_savedOwnProofPaths.toSet());
              final leftover = [
                for (final path in previous)
                  if (!keep.contains(path) &&
                      _sessionProofUploads.contains(path))
                    path,
              ];
              for (final path in leftover) {
                _proofStorage.deleteQuietly(path);
                _sessionProofUploads.remove(path);
              }
            },
            onUploadingChanged: (v) => setState(() => _proofUploading = v),
          ),
        ),
      );
    } else if (showOwnViewer) {
      children.add(
        _buildField(
          label: l10n.taskProofTitle,
          child: TaskImageGallery(
            key: ValueKey(
              'proof-own-$_proofViewEpoch-${_ownProofPaths.join(",")}',
            ),
            imagePaths: _ownProofPaths,
            taskId: _task.uid,
            organizationId: widget.organizationId,
            fetcher: _proofFetcher,
          ),
        ),
      );
    }
    return children;
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

    Widget buildSheetContent(
      BuildContext modalContext,
      StateSetter setModalState,
      bool isDeleting,
    ) {
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
                  child: Icon(
                    Icons.delete_outline_rounded,
                    color: colorScheme.error,
                    size: 24,
                  ),
                ),
                const SizedBox(width: 12),
                Expanded(
                  child: Column(
                    crossAxisAlignment: CrossAxisAlignment.start,
                    children: [
                      Text(
                        l10n.deleteTask,
                        style: const TextStyle(
                          fontSize: 16,
                          fontWeight: FontWeight.bold,
                        ),
                      ),
                      const SizedBox(height: 2),
                      Text(
                        _task.title,
                        style: TextStyle(
                          fontSize: 12,
                          color: colorScheme.onSurfaceVariant,
                        ),
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
              style: TextStyle(
                fontSize: 13,
                color: colorScheme.onSurfaceVariant,
                height: 1.4,
              ),
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
                        onTap: isDeleting
                            ? null
                            : () => Navigator.pop(modalContext),
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
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(failure.message),
                                          backgroundColor: colorScheme.error,
                                        ),
                                      );
                                    },
                                    (_) {
                                      Navigator.pop(modalContext);
                                      Navigator.pop(context, true);
                                      ScaffoldMessenger.of(
                                        context,
                                      ).showSnackBar(
                                        SnackBar(
                                          content: Text(
                                            AppLocalizations.of(
                                              context,
                                            )!.taskDeleted,
                                          ),
                                          backgroundColor:
                                              Colors.green.shade700,
                                        ),
                                      );
                                    },
                                  );
                                } catch (e) {
                                  if (modalContext.mounted) {
                                    setModalState(() => isDeleting = false);
                                    ScaffoldMessenger.of(context).showSnackBar(
                                      SnackBar(
                                        content: Text(
                                          AppLocalizations.of(
                                            context,
                                          )!.taskDeleteFailed(e),
                                        ),
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
                                    Icon(
                                      Icons.delete_forever_rounded,
                                      size: 18,
                                      color: colorScheme.onError,
                                    ),
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
            builder: (ctx, setModalState) =>
                buildSheetContent(modalCtx, setModalState, isDeleting),
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
            shape: RoundedRectangleBorder(
              borderRadius: BorderRadius.circular(24),
            ),
            child: ConstrainedBox(
              constraints: const BoxConstraints(maxWidth: 480),
              child: StatefulBuilder(
                builder: (ctx, setModalState) =>
                    buildSheetContent(modalCtx, setModalState, isDeleting),
              ),
            ),
          );
        },
      );
    }
  }
}
