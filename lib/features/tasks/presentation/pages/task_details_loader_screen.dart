import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/core/services/firestore_resilience_helper.dart';
import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/data/models/task_model.dart';
import 'package:delegate_app/features/tasks/presentation/pages/task_details_screen.dart';
import 'package:delegate_app/features/tasks/presentation/task_details_access.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:material_symbols_icons/symbols.dart';

/// Loads a task by id (used by `/tasks/:taskId` from a notification).
class TaskDetailsLoaderScreen extends StatefulWidget {
  const TaskDetailsLoaderScreen({
    super.key,
    required this.taskId,
    this.delegate,
    this.firestore,
  });

  final String taskId;
  final Delegate? delegate;
  final FirebaseFirestore? firestore;

  @override
  State<TaskDetailsLoaderScreen> createState() => _TaskDetailsLoaderScreenState();
}

class _TaskDetailsLoaderScreenState extends State<TaskDetailsLoaderScreen> {
  Object? _error;
  bool _missing = false;
  TaskModel? _task;
  late final Delegate? _delegate;

  @override
  void initState() {
    super.initState();
    _delegate = widget.delegate;
    _load();
  }

  FirebaseFirestore get _db => widget.firestore ?? FirebaseFirestore.instance;

  Future<void> _load() async {
    final delegate = _delegate ?? _delegateFromAuth();
    final org = delegate?.organizationUID.trim() ?? '';
    final id = widget.taskId.trim();
    if (org.isEmpty || id.isEmpty) {
      setState(() {
        _missing = true;
        _error = null;
        _task = null;
      });
      return;
    }
    setState(() {
      _error = null;
      _missing = false;
    });
    try {
      final snap = await _db
          .collection('organizations')
          .doc(org)
          .collection('tasks')
          .doc(id)
          .getResilient();
      if (!mounted) return;
      if (!snap.exists) {
        setState(() {
          _missing = true;
          _task = null;
        });
        return;
      }
      setState(() {
        _task = TaskModel.fromFirestore(snap);
        _missing = false;
      });
    } catch (e) {
      if (!mounted) return;
      setState(() => _error = e);
    }
  }

  Delegate? _delegateFromAuth() {
    final state = context.read<AuthBloc>().state;
    if (state is AuthAuthenticated) return state.delegate;
    return null;
  }

  @override
  Widget build(BuildContext context) {
    final l10n = AppLocalizations.of(context)!;
    final delegate = _delegate ?? _delegateFromAuth();
    final task = _task;
    if (task != null && delegate != null) {
      return TaskDetailsScreen(
        task: task,
        isAdmin: taskNotificationOpensAsAdmin(delegate.role),
        organizationId: delegate.organizationUID,
        currentUserId: delegate.uid,
        currentUserRole: delegate.role.name,
        currentUserCompanyId: delegate.companyUID,
        currentUserName: delegate.fullName,
      );
    }
    return Scaffold(
      appBar: AppBar(
        title: Text(l10n.tasks),
      ),
      body: Center(
        child: Padding(
          padding: const EdgeInsets.all(24),
          child: _error != null || _missing || delegate == null
              ? Column(
                  mainAxisSize: MainAxisSize.min,
                  children: [
                    const Icon(Symbols.task_alt_rounded, size: 48),
                    const SizedBox(height: 12),
                    Text(
                      l10n.somethingWentWrong,
                      textAlign: TextAlign.center,
                    ),
                    const SizedBox(height: 16),
                    FilledButton(
                      onPressed: _load,
                      child: Text(l10n.retry),
                    ),
                  ],
                )
              : const CircularProgressIndicator(),
        ),
      ),
    );
  }
}
