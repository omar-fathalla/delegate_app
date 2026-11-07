import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_state.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_state.dart';
import 'package:delegate_app/features/tasks/presentation/pages/task_details_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:flutter/material.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:get_it/get_it.dart';
import 'package:mocktail/mocktail.dart';

class _MockAdminBloc extends Mock implements AdminTasksBloc {}

class _MockDelegateBloc extends Mock implements DelegateTasksBloc {}

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

  TaskEntity task({DateTime? editedAt}) => TaskEntity(
    uid: 't1',
    title: 'Title',
    description: 'Body',
    priority: TaskPriority.medium,
    status: TaskStatus.pending,
    assignedTo: 'del-1',
    assignedToName: 'Del',
    companyId: 'c1',
    createdBy: 'sup-1',
    createdByName: 'Sup',
    dueDate: DateTime(2026, 11, 3),
    createdAt: DateTime(2026, 11, 2),
    editedAt: editedAt,
  );

  Future<void> pump(WidgetTester tester, {required bool isAdmin, required String uid, DateTime? editedAt}) {
    return tester.pumpWidget(MaterialApp(
      locale: const Locale('en'),
      localizationsDelegates: AppLocalizations.localizationsDelegates,
      supportedLocales: AppLocalizations.supportedLocales,
      home: TaskDetailsScreen(
        task: task(editedAt: editedAt),
        isAdmin: isAdmin,
        organizationId: 'o1',
        authUidOverride: uid,
      ),
    ));
  }

  testWidgets('sender sees edit/delete menu', (tester) async {
    await pump(tester, isAdmin: true, uid: 'sup-1');
    await tester.tap(find.byKey(const Key('task-more-actions')));
    await tester.pumpAndSettle();
    expect(find.text('Edit'), findsOneWidget);
    expect(find.text('Delete'), findsOneWidget);
  });

  testWidgets('another supervisor gets no edit/delete', (tester) async {
    await pump(tester, isAdmin: true, uid: 'sup-2');
    expect(find.byKey(const Key('task-more-actions')), findsNothing);
  });

  testWidgets('delegate gets no edit/delete and sees the edited label', (tester) async {
    await pump(tester, isAdmin: false, uid: 'sup-1', editedAt: DateTime(2026, 11, 2, 9));
    expect(find.byKey(const Key('task-more-actions')), findsNothing);
    expect(find.text('Edited'), findsOneWidget);
  });
}
