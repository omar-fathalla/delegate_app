import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_state.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_state.dart';
import 'package:delegate_app/features/tasks/presentation/pages/task_details_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

class _MockAdminBloc extends Mock implements AdminTasksBloc {}

class _MockDelegateBloc extends Mock implements DelegateTasksBloc {}

class _MockProofs extends Mock implements TaskRemoteDataSource {}

/// TAS-387 (user review 27 Nov 2026): the task read view. Overdue banner
/// and label, the assignee's next step as one button, no «cancelled» option
/// for the assignee [UI only], no status ButtonGroup outside the edit form.
void main() {
  final sl = GetIt.instance;

  setUp(() {
    sl.reset();
    sl.registerFactory<AdminTasksBloc>(() {
      final b = _MockAdminBloc();
      when(() => b.state).thenReturn(AdminTasksInitial());
      when(() => b.stream).thenAnswer((_) => const Stream.empty());
      when(() => b.close()).thenAnswer((_) async {});
      return b;
    });
    sl.registerFactory<DelegateTasksBloc>(() {
      final b = _MockDelegateBloc();
      when(() => b.state).thenReturn(DelegateTasksInitial());
      when(() => b.stream).thenAnswer((_) => const Stream.empty());
      when(() => b.close()).thenAnswer((_) async {});
      return b;
    });
  });

  TaskEntity task({
    String assignedTo = 'del-1',
    TaskStatus status = TaskStatus.inProgress,
    DateTime? due,
  }) => TaskEntity(
    uid: 't1',
    title: 'Title',
    description: 'Body',
    priority: TaskPriority.medium,
    status: status,
    assignedTo: assignedTo,
    assignedToName: 'Del',
    companyId: 'c1',
    createdBy: 'sup-1',
    createdByName: 'Sup',
    dueDate: due ?? DateTime(2026, 11, 3),
    createdAt: DateTime(2026, 11, 2),
  );

  Future<void> pump(
    WidgetTester tester, {
    required TaskEntity t,
    required String uid,
    required String role,
    String company = 'c1',
  }) async {
    final proofs = _MockProofs();
    when(
      () => proofs.getTaskProof(any(), any(), any()),
    ).thenAnswer((_) async => null);
    when(
      () => proofs.listTaskProofs(any(), any()),
    ).thenAnswer((_) async => const []);
    // Tall enough that the whole read view (a lazy ListView) is built.
    tester.view.physicalSize = const Size(800, 3200);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('en'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: TaskDetailsScreen(
          task: t,
          isAdmin: false,
          organizationId: 'o1',
          authUidOverride: uid,
          currentUserId: uid,
          currentUserRole: role,
          currentUserCompanyId: company,
          proofSource: proofs,
        ),
      ),
    );
    await tester.pump();
  }

  final future = DateTime.now().add(const Duration(days: 3));

  testWidgets('an overdue open task shows the banner and the label', (t) async {
    await pump(t, t: task(), uid: 'del-1', role: 'delegate');
    expect(find.byKey(const Key('task_read_view')), findsOneWidget);
    expect(find.byKey(const Key('task_overdue_banner')), findsOneWidget);
    expect(find.byKey(const Key('task_overdue_label')), findsOneWidget);
  });

  testWidgets('on time: no banner', (t) async {
    await pump(t, t: task(due: future), uid: 'del-1', role: 'delegate');
    expect(find.byKey(const Key('task_overdue_banner')), findsNothing);
  });

  testWidgets('pending: the assignee gets «start», no status group', (t) async {
    await pump(
      t,
      t: task(status: TaskStatus.pending, due: future),
      uid: 'del-1',
      role: 'delegate',
    );
    expect(find.byKey(const Key('taskStartButton')), findsOneWidget);
    expect(find.byKey(const Key('taskCompleteButton')), findsNothing);
    expect(find.byKey(const Key('taskStatusGroup')), findsNothing);
    expect(find.text('Cancelled'), findsNothing);
  });

  testWidgets('in progress: the assignee gets «done»', (t) async {
    await pump(t, t: task(due: future), uid: 'del-1', role: 'delegate');
    expect(find.byKey(const Key('taskCompleteButton')), findsOneWidget);
    expect(find.byKey(const Key('taskStartButton')), findsNothing);
  });

  testWidgets('completed: no next-step button, no banner', (t) async {
    await pump(
      t,
      t: task(status: TaskStatus.completed),
      uid: 'del-1',
      role: 'delegate',
    );
    expect(find.byKey(const Key('taskCompleteButton')), findsNothing);
    expect(find.byKey(const Key('taskStartButton')), findsNothing);
    expect(find.byKey(const Key('task_overdue_banner')), findsNothing);
  });
}
