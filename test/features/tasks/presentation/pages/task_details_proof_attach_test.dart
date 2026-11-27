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

/// B1: «إرفاق إثبات» shows only to users who may write proofs for the task.
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
    dueDate: DateTime(2026, 11, 3),
    createdAt: DateTime(2026, 11, 2),
  );

  Future<void> pump(
    WidgetTester tester, {
    required TaskEntity t,
    required String uid,
    required String role,
    String company = 'c1',
  }) async {
    // TAS-368 added a fact on shared tasks; keep the whole page on screen.
    tester.view.physicalSize = const Size(1080, 4000);
    tester.view.devicePixelRatio = 2;
    addTearDown(tester.view.reset);
    final proofs = _MockProofs();
    when(
      () => proofs.getTaskProof(any(), any(), any()),
    ).thenAnswer((_) async => null);
    when(
      () => proofs.listTaskProofs(any(), any()),
    ).thenAnswer((_) async => const []);
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

  final attach = find.text('Attach proof');

  testWidgets('the assignee sees attach', (tester) async {
    await pump(tester, t: task(), uid: 'del-1', role: 'delegate');
    expect(attach, findsOneWidget);
  });

  testWidgets('a cancelled task hides attach for the assignee', (tester) async {
    await pump(
      tester,
      t: task(status: TaskStatus.cancelled),
      uid: 'del-1',
      role: 'delegate',
    );
    expect(attach, findsNothing);
  });

  testWidgets('unassigned marketing does not see attach', (tester) async {
    await pump(tester, t: task(), uid: 'mp-1', role: 'marketingPromotion');
    expect(attach, findsNothing);
  });

  testWidgets('«الكل»: marketing roles do not see attach', (tester) async {
    await pump(
      tester,
      t: task(assignedTo: 'all'),
      uid: 'bm-1',
      role: 'marketing',
    );
    expect(attach, findsNothing);
    await pump(
      tester,
      t: task(assignedTo: 'all'),
      uid: 'bm-2',
      role: 'branchesMarketingManager',
    );
    expect(attach, findsNothing);
  });

  testWidgets('«الكل»: a same-company delegate sees attach', (tester) async {
    await pump(
      tester,
      t: task(assignedTo: 'all'),
      uid: 'del-2',
      role: 'delegate',
    );
    expect(attach, findsOneWidget);
  });

  testWidgets('a sector task shows attach to the matching sector role', (
    tester,
  ) async {
    await pump(
      tester,
      t: task(assignedTo: 'all_marketing_promotion'),
      uid: 'mp-1',
      role: 'marketingPromotion',
    );
    expect(attach, findsOneWidget);
  });
}
