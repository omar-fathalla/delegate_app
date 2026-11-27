import 'package:delegate_app/core/design/tokens.dart';
import 'package:delegate_app/core/design/widgets/button_group.dart';
import 'package:delegate_app/core/design/widgets/date_time_fields.dart';
import 'package:delegate_app/core/design/widgets/dialogs.dart';
import 'package:delegate_app/core/design/widgets/snackbars.dart';
import 'package:delegate_app/features/tasks/data/services/task_image_storage.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_proof.dart';
import 'package:delegate_app/features/tasks/domain/task_proof_paths.dart';

import 'package:delegate_app/features/tasks/presentation/widgets/task_image_widgets.dart';
import 'package:material_symbols_icons/symbols.dart';
import 'package:material_ui/material_ui.dart';
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
import 'package:delegate_app/core/security/delegate_identity.dart';

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
    final createdBy = _task.createdBy;
    if (createdBy.isEmpty) return false;
    if (createdBy == widget.currentUserId) return true;
    final override = widget.authUidOverride;
    if (override != null) return createdBy == override;
    // TAS-28: Auth uid (old equality) or the delegateId claim.
    return DelegateIdentity.selfIds().contains(createdBy);
  }

  String? get _viewerId =>
      widget.currentUserId ??
      widget.authUidOverride ??
      DelegateIdentity.current();

  bool get _canViewAllProofs {
    if (_isSender) return true;
    return isCompanySupervisorRole(widget.currentUserRole) &&
        (widget.currentUserCompanyId ?? '') == _task.companyId;
  }

  /// «إرفاق إثبات» only when the signed-in user may write proofs for this
  /// task: its assignee or an intended recipient, same company, not
  /// cancelled (B1; the server rules enforce the same).
  bool get _canEditOwnProofs {
    if (_viewerId == null || _viewerId!.isEmpty) return false;
    if (_isSender) return false;
    return canWriteTaskProof(
      role: widget.currentUserRole,
      viewerIds: [
        widget.currentUserId,
        widget.authUidOverride ?? DelegateIdentity.current(),
        if (widget.authUidOverride == null) ...DelegateIdentity.selfIds(),
      ],
      viewerCompanyId: widget.currentUserCompanyId,
      taskCompanyId: _task.companyId,
      assignedTo: _task.assignedTo,
      cancelled:
          _currentStatus == TaskStatus.cancelled ||
          _task.status == TaskStatus.cancelled,
    );
  }

  bool get _proofsChanged =>
      _ownProofPaths.join('\n') != _savedOwnProofPaths.join('\n');

  TaskRemoteDataSource get _proofs =>
      widget.proofSource ?? di.sl<TaskRemoteDataSource>();

  TaskImageStorage get _proofStorage => TaskImageStorage.proof(
    organizationId: widget.organizationId,
    taskId: _task.uid,
  );

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
          showTashilSnackBar(
            context,
            AppLocalizations.of(context)!.taskImageUploadFailed,
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
    showTashilSnackBar(
      context,
      AppLocalizations.of(context)!.taskUpdatedSuccessfully,
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
            // TAS-387: the sender's edit form is unchanged; everyone else
            // reads the task as content, not as a form.
            body: _isEditing
                ? _buildEditForm(context, l10n, theme)
                : _buildReadView(context, l10n, theme),
          );
        },
      ),
    );
  }

  /// Days a still-open task is past its due date (0 when on time).
  int get _overdueDays {
    if (_currentStatus == TaskStatus.completed ||
        _currentStatus == TaskStatus.cancelled) {
      return 0;
    }
    final today = DateUtils.dateOnly(DateTime.now());
    final due = DateUtils.dateOnly(_dueDate);
    return due.isBefore(today) ? today.difference(due).inDays : 0;
  }

  /// The delegate's next step (TAS-387): start a pending task, finish one
  /// in progress. Cancelling is the sender's call [UI only; the rules still
  /// accept any status from the assignee, USER-ROLES-LOGIC 5.10].
  TaskStatus? get _nextStatus => switch (_task.status) {
    TaskStatus.pending => TaskStatus.inProgress,
    TaskStatus.inProgress => TaskStatus.completed,
    _ => null,
  };

  bool get _notesChanged => _notesController.text != (_task.notes ?? '');

  /// Read view (TAS-387, user review 27 Nov 2026): the task as content.
  /// Title and labels, the description as text, the images, the facts as a
  /// list (C-23), «إثبات التنفيذ» (proofs + notes), and for the assignee
  /// one button with the next step. An overdue task shows a banner.
  Widget _buildReadView(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    final cs = theme.colorScheme;
    final tt = theme.textTheme;
    final sem = theme.extension<TashilSemanticColors>();
    final locale = Localizations.localeOf(context).toLanguageTag();
    final overdue = _overdueDays;
    final next = widget.isAdmin ? null : _nextStatus;

    Widget label(String text, Color bg, Color fg, IconData icon, {Key? key}) =>
        Container(
          key: key,
          padding: const EdgeInsetsDirectional.symmetric(
            horizontal: TashilSpacing.sm,
            vertical: TashilSpacing.xs / 2,
          ),
          decoration: BoxDecoration(
            color: bg,
            borderRadius: BorderRadius.circular(TashilRadius.small),
          ),
          child: Row(
            mainAxisSize: MainAxisSize.min,
            children: [
              Icon(icon, size: 14, color: fg),
              const SizedBox(width: TashilSpacing.xs),
              Text(text, style: tt.labelMedium?.copyWith(color: fg)),
            ],
          ),
        );

    final (Color sBg, Color sFg) = switch (_currentStatus) {
      TaskStatus.pending => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
      TaskStatus.inProgress => (cs.secondaryContainer, cs.onSecondaryContainer),
      TaskStatus.completed => (
        sem?.successContainer ?? cs.primaryContainer,
        sem?.onSuccessContainer ?? cs.onPrimaryContainer,
      ),
      TaskStatus.cancelled => (cs.surfaceContainerHighest, cs.onSurfaceVariant),
    };

    Widget fact(IconData icon, String title, String value, {Key? key}) =>
        ListTile(
          key: key,
          leading: Icon(icon, color: cs.primary),
          title: Text(value, style: tt.bodyLarge),
          subtitle: Text(
            title,
            style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
          ),
        );

    String dueText() {
      final date = DateFormat('EEEE، d MMMM', locale).format(_dueDate);
      final today = DateUtils.dateOnly(DateTime.now());
      final days = DateUtils.dateOnly(_dueDate).difference(today).inDays;
      final rel = days == 0
          ? l10n.today
          : days > 0
          ? l10n.taskDueInDays(days)
          : l10n.taskOverdueLabel;
      return '$date • $rel';
    }

    final facts = <Widget>[
      fact(
        Symbols.event_rounded,
        l10n.taskDueDate,
        dueText(),
        key: const Key('task_due_fact'),
      ),
      if (_task.createdByName.trim().isNotEmpty)
        fact(
          Symbols.person_rounded,
          l10n.taskFrom,
          _task.createdByName.trim(),
        ),
      fact(
        Symbols.group_rounded,
        l10n.taskAssignedToLabel,
        _task.assignedTo == 'all'
            ? l10n.taskAssignedAll
            : _task.assignedToName,
      ),
      fact(
        Symbols.schedule_send_rounded,
        l10n.taskSentAt,
        DateFormat('d MMMM • h:mm a', locale).format(_task.createdAt),
      ),
      if (_task.completedAt != null)
        fact(
          Symbols.task_alt_rounded,
          l10n.taskDoneAt,
          DateFormat('d MMMM • h:mm a', locale).format(_task.completedAt!),
        ),
    ];

    final proofs = _buildProofSection(l10n, theme, ownLabel: false);
    final notesEditable = !widget.isAdmin &&
        _currentStatus != TaskStatus.cancelled;
    final hasNotes = (_task.notes ?? '').trim().isNotEmpty;

    return ListView(
      key: const Key('task_read_view'),
      padding: const EdgeInsetsDirectional.fromSTEB(
        TashilSpacing.page,
        TashilSpacing.sm,
        TashilSpacing.page,
        TashilSpacing.xxl,
      ),
      children: [
        if (overdue > 0)
          Padding(
            padding: const EdgeInsetsDirectional.only(bottom: TashilSpacing.md),
            child: MaterialBanner(
              key: const Key('task_overdue_banner'),
              backgroundColor: cs.errorContainer,
              leading: Icon(Symbols.alarm_rounded, color: cs.onErrorContainer),
              content: Text(
                l10n.taskOverdueBanner(overdue),
                style: tt.bodyMedium?.copyWith(color: cs.onErrorContainer),
              ),
              actions: const [SizedBox.shrink()],
            ),
          ),
        Text(
          _task.title,
          key: const Key('task_title'),
          style: tt.titleLarge,
          textDirection: Bidi.hasAnyRtl(_task.title)
              ? TextDirection.rtl
              : TextDirection.ltr,
        ),
        const SizedBox(height: TashilSpacing.sm),
        Wrap(
          spacing: TashilSpacing.sm,
          runSpacing: TashilSpacing.xs,
          children: [
            label(
              _getStatusName(l10n, _currentStatus),
              sBg,
              sFg,
              _getStatusIcon(_currentStatus).icon!,
              key: const Key('task_status_label'),
            ),
            label(
              _getPriorityName(l10n, _currentPriority),
              _currentPriority == TaskPriority.high
                  ? cs.tertiaryContainer
                  : cs.surfaceContainerHighest,
              _currentPriority == TaskPriority.high
                  ? cs.onTertiaryContainer
                  : cs.onSurfaceVariant,
              _getPriorityIcon(_currentPriority).icon!,
            ),
            if (overdue > 0)
              label(
                l10n.taskOverdueLabel,
                cs.errorContainer,
                cs.onErrorContainer,
                Symbols.alarm_rounded,
                key: const Key('task_overdue_label'),
              ),
            if (_task.isEdited) const TaskEditedLabel(),
          ],
        ),
        if (_task.description.trim().isNotEmpty) ...[
          const SizedBox(height: TashilSpacing.lg),
          Text(
            _task.description,
            style: tt.bodyLarge,
            textDirection: Bidi.hasAnyRtl(_task.description)
                ? TextDirection.rtl
                : TextDirection.ltr,
          ),
        ],
        if (_task.hasImage) ...[
          const SizedBox(height: TashilSpacing.lg),
          TaskImageGallery(
            key: ValueKey(
              'view-$_imageViewEpoch-${_task.resolvedImagePaths.join(",")}',
            ),
            imagePaths: _task.resolvedImagePaths,
            taskId: _task.uid,
            organizationId: widget.organizationId,
          ),
        ],
        const SizedBox(height: TashilSpacing.lg),
        Card.filled(
          key: const Key('task_facts'),
          margin: EdgeInsets.zero,
          child: Column(
            children: [
              for (var i = 0; i < facts.length; i++) ...[
                if (i > 0)
                  const Divider(height: 1, indent: TashilSpacing.xxl * 2),
                facts[i],
              ],
            ],
          ),
        ),
        if (proofs.isNotEmpty || notesEditable || hasNotes) ...[
          const SizedBox(height: TashilSpacing.xl),
          Row(
            children: [
              Icon(Symbols.fact_check_rounded, size: 20, color: cs.primary),
              const SizedBox(width: TashilSpacing.sm),
              Text(l10n.taskProofSection, style: tt.titleSmall),
            ],
          ),
          ...proofs,
          const SizedBox(height: TashilSpacing.md),
          if (notesEditable)
            TextFormField(
              key: const Key('task_notes_field'),
              controller: _notesController,
              minLines: 2,
              maxLines: null,
              onChanged: (_) => setState(() {}),
              decoration: InputDecoration(
                border: const OutlineInputBorder(),
                labelText: l10n.notes,
                hintText: l10n.notesHint,
              ),
              keyboardType: TextInputType.multiline,
            )
          else if (hasNotes)
            Card.outlined(
              margin: EdgeInsets.zero,
              child: ListTile(
                leading: Icon(Symbols.notes_rounded, color: cs.primary),
                title: Text(_task.notes!.trim(), style: tt.bodyLarge),
                subtitle: Text(
                  l10n.notes,
                  style: tt.bodySmall?.copyWith(color: cs.onSurfaceVariant),
                ),
              ),
            ),
        ],
        const SizedBox(height: TashilSpacing.xl),
        if (next != null)
          FilledButton.icon(
            key: Key(
              next == TaskStatus.completed
                  ? 'taskCompleteButton'
                  : 'taskStartButton',
            ),
            onPressed: _proofUploading
                ? null
                : () {
                    setState(() => _currentStatus = next);
                    _saveChanges(context);
                  },
            icon: Icon(
              next == TaskStatus.completed
                  ? Symbols.task_alt_rounded
                  : Symbols.play_arrow_rounded,
            ),
            label: Text(
              next == TaskStatus.completed ? l10n.taskFinish : l10n.taskStart,
            ),
          ),
        if ((_notesChanged && notesEditable) ||
            (_canEditOwnProofs && _proofsChanged && !_proofUploading)) ...[
          const SizedBox(height: TashilSpacing.sm),
          FilledButton.tonalIcon(
            key: const Key('task_save_button'),
            onPressed: () => _saveChanges(context),
            icon: const Icon(Symbols.save_rounded),
            label: Text(l10n.saveChanges),
          ),
        ],
        if (_isSender) ...[
          const SizedBox(height: TashilSpacing.lg),
          OutlinedButton.icon(
            onPressed: () => _confirmDelete(context),
            icon: const Icon(Symbols.delete_rounded),
            label: Text(l10n.deleteTask),
          ),
        ],
      ],
    );
  }

  /// The sender's edit form (TAS-356 layout, unchanged).
  Widget _buildEditForm(
    BuildContext context,
    AppLocalizations l10n,
    ThemeData theme,
  ) {
    return SingleChildScrollView(
              padding: const EdgeInsetsDirectional.symmetric(
                horizontal: TashilSpacing.page,
                vertical: TashilSpacing.sm,
              ),
              // TAS-356: outlined fields, read-only values on Card.filled,
              // priority and status as kit ButtonGroups (C-06), the main
              // action a plain FilledButton (primary), delete a text-button
              // kit dialog. Who can change what is unchanged.
              child: Column(
                crossAxisAlignment: CrossAxisAlignment.start,
                children: [
                  _buildField(
                    label: l10n.taskTitle,
                    child: _isEditing
                        ? TextFormField(
                            controller: _titleController,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              prefixIcon: const Icon(Icons.title_rounded),
                              hintText: l10n.taskTitle,
                            ),
                            keyboardType: TextInputType.text,
                          )
                        : _readOnly(
                            theme,
                            Text(
                              _task.title,
                              style: theme.textTheme.titleLarge?.copyWith(
                                color: theme.colorScheme.onSurface,
                              ),
                              textDirection: Bidi.hasAnyRtl(_task.title)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          ),
                  ),
                  const SizedBox(height: TashilSpacing.md),
                  _buildField(
                    label: l10n.taskDescription,
                    child: _isEditing
                        ? TextFormField(
                            controller: _descriptionController,
                            minLines: 3,
                            maxLines: null,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: l10n.taskDescription,
                            ),
                            keyboardType: TextInputType.multiline,
                          )
                        : _readOnly(
                            theme,
                            Text(
                              _task.description,
                              style: theme.textTheme.bodyLarge,
                              textDirection: Bidi.hasAnyRtl(_task.description)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          ),
                  ),
                  if (_isEditing && _isSender) ...[
                    const SizedBox(height: TashilSpacing.md),
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
                    const SizedBox(height: TashilSpacing.md),
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
                    const SizedBox(height: TashilSpacing.sm),
                    const TaskEditedLabel(),
                  ],
                  ..._buildProofSection(l10n, theme),
                  const SizedBox(height: TashilSpacing.md),
                  _buildField(
                    label: l10n.taskPriority,
                    child: _isEditing
                        ? ButtonGroup<TaskPriority>(
                            key: const Key('taskPriorityGroup'),
                            variant: ButtonGroupVariant.connected,
                            expand: true,
                            selected: {_currentPriority},
                            onSelectionChanged: (v) =>
                                setState(() => _currentPriority = v.first),
                            items: [
                              for (final p in TaskPriority.values)
                                ButtonGroupItem(
                                  value: p,
                                  label: _getPriorityName(l10n, p),
                                ),
                            ],
                          )
                        : _readOnly(
                            theme,
                            Row(
                              children: [
                                _getPriorityIcon(
                                  _currentPriority,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: TashilSpacing.md),
                                Text(
                                  _getPriorityName(l10n, _currentPriority),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: TashilSpacing.md),
                  _buildField(
                    label: l10n.taskStatus,
                    child: _isEditing || !widget.isAdmin
                        ? ButtonGroup<TaskStatus>(
                            key: const Key('taskStatusGroup'),
                            variant: ButtonGroupVariant.connected,
                            expand: true,
                            selected: {_currentStatus},
                            onSelectionChanged: (v) =>
                                setState(() => _currentStatus = v.first),
                            items: [
                              for (final st in TaskStatus.values)
                                ButtonGroupItem(
                                  value: st,
                                  label: _getStatusName(l10n, st),
                                ),
                            ],
                          )
                        : _readOnly(
                            theme,
                            Row(
                              children: [
                                _getStatusIcon(
                                  _currentStatus,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: TashilSpacing.md),
                                Text(
                                  _getStatusName(l10n, _currentStatus),
                                  style: theme.textTheme.titleMedium,
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: TashilSpacing.md),
                  _buildField(
                    label: l10n.taskDueDate,
                    child: _isEditing
                        ? DateField(
                            key: const Key('taskDueDateField'),
                            label: l10n.taskDueDate,
                            value: _dueDate,
                            firstDate: DateUtils.dateOnly(DateTime.now()),
                            lastDate: DateTime(2101),
                            onChanged: (d) {
                              if (d != null) setState(() => _dueDate = d);
                            },
                          )
                        : _readOnly(
                            theme,
                            Row(
                              children: [
                                Icon(
                                  Icons.calendar_month_rounded,
                                  color: theme.colorScheme.onSurfaceVariant,
                                ),
                                const SizedBox(width: TashilSpacing.md),
                                Text(
                                  DateFormat.yMMMMd(
                                    Localizations.localeOf(context)
                                        .toLanguageTag(),
                                  ).format(_dueDate),
                                  style: theme.textTheme.bodyLarge,
                                ),
                              ],
                            ),
                          ),
                  ),
                  const SizedBox(height: TashilSpacing.md),
                  _buildField(
                    label: l10n.notes,
                    child: _isEditing || !widget.isAdmin
                        ? TextFormField(
                            controller: _notesController,
                            minLines: 2,
                            maxLines: null,
                            decoration: InputDecoration(
                              border: const OutlineInputBorder(),
                              hintText: l10n.notesHint,
                            ),
                            keyboardType: TextInputType.multiline,
                          )
                        : _task.notes != null && _task.notes!.isNotEmpty
                        ? _readOnly(
                            theme,
                            Text(
                              _task.notes!,
                              textDirection: Bidi.hasAnyRtl(_task.notes!)
                                  ? TextDirection.rtl
                                  : TextDirection.ltr,
                            ),
                          )
                        : const SizedBox.shrink(),
                  ),
                  const SizedBox(height: TashilSpacing.lg),
                  if (!widget.isAdmin)
                    if (_currentStatus != _task.status)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton(
                          onPressed: () => _saveChanges(context),
                          child: Text(l10n.saveChanges),
                        ),
                      )
                    else if (_currentStatus != TaskStatus.completed &&
                        _currentStatus != TaskStatus.cancelled)
                      SizedBox(
                        width: double.infinity,
                        child: FilledButton.icon(
                          key: const Key('taskCompleteButton'),
                          onPressed: () {
                            setState(() {
                              _currentStatus = TaskStatus.completed;
                            });
                            _saveChanges(context);
                          },
                          icon: const Icon(Icons.check_circle_outline_rounded),
                          label: Text(l10n.complete),
                        ),
                      ),
                  if (_canEditOwnProofs &&
                      _proofsChanged &&
                      !_proofUploading) ...[
                    const SizedBox(height: TashilSpacing.md),
                    FilledButton.tonalIcon(
                      onPressed: () => _saveChanges(context),
                      icon: const Icon(Icons.photo_library_outlined),
                      label: Text(l10n.taskProofSave),
                    ),
                  ],
                  if (_isSender && !_isEditing) ...[
                    const SizedBox(height: TashilSpacing.lg),
                    SizedBox(
                      width: double.infinity,
                      child: OutlinedButton.icon(
                        onPressed: () => _confirmDelete(context),
                        icon: const Icon(Icons.delete_outline_rounded),
                        label: Text(l10n.deleteTask),
                      ),
                    ),
                  ],
                ],
              ),
            );
  }

  /// A read-only value on the screen's one card style (TAS-356).
  Widget _readOnly(ThemeData theme, Widget child) => Card.filled(
    margin: EdgeInsets.zero,
    child: Padding(
      padding: const EdgeInsets.all(TashilSpacing.lg),
      child: SizedBox(width: double.infinity, child: child),
    ),
  );

  Widget _buildField({required String label, required Widget child}) {
    final theme = Theme.of(context);
    if (label.isEmpty) return child;
    return Column(
      crossAxisAlignment: CrossAxisAlignment.start,
      children: [
        Padding(
          padding: const EdgeInsetsDirectional.only(
            start: TashilSpacing.xs,
            bottom: TashilSpacing.xs,
          ),
          child: Text(
            label,
            style: theme.textTheme.labelLarge?.copyWith(
              color: theme.colorScheme.onSurfaceVariant,
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

  /// [ownLabel]: false under the read view's «إثبات التنفيذ» title.
  List<Widget> _buildProofSection(
    AppLocalizations l10n,
    ThemeData theme, {
    bool ownLabel = true,
  }) {
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
          label: ownLabel ? l10n.taskProofTitle : '',
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

  // TAS-356 (C-27): one kit dialog on every width, text buttons, the
  // confirm says what happens; the delete itself is unchanged.
  Future<void> _confirmDelete(BuildContext context) async {
    final l10n = AppLocalizations.of(context)!;
    bool isDeleting = false;

    await showTashilDialog<void>(
      context: context,
      builder: (modalContext) => StatefulBuilder(
        builder: (ctx, setModalState) => AlertDialog(
          key: const Key('deleteTaskDialog'),
          title: Text(l10n.deleteTask),
          content: Column(
            mainAxisSize: MainAxisSize.min,
            crossAxisAlignment: CrossAxisAlignment.start,
            children: [
              Text(
                _task.title,
                style: Theme.of(ctx).textTheme.titleSmall,
                maxLines: 1,
                overflow: TextOverflow.ellipsis,
              ),
              const SizedBox(height: TashilSpacing.sm),
              Text(l10n.deleteTaskConfirmation),
            ],
          ),
          actions: [
            TextButton(
              onPressed: isDeleting ? null : () => Navigator.pop(modalContext),
              child: Text(l10n.cancel),
            ),
            TextButton(
              onPressed: isDeleting
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
                            showTashilSnackBar(context, failure.message);
                          },
                          (_) {
                            Navigator.pop(modalContext);
                            Navigator.pop(context, true);
                            showTashilSnackBar(context, l10n.taskDeleted);
                          },
                        );
                      } catch (e) {
                        if (modalContext.mounted) {
                          setModalState(() => isDeleting = false);
                          showTashilSnackBar(
                            context,
                            l10n.taskDeleteFailed(e),
                          );
                        }
                      }
                    },
              child: isDeleting
                  ? const SizedBox.square(
                      dimension: 20,
                      child: CircularProgressIndicator(strokeWidth: 2),
                    )
                  : Text(l10n.delete),
            ),
          ],
        ),
      ),
    );
  }
}
