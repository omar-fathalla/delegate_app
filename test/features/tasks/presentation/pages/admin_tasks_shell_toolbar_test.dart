import 'package:dartz/dartz.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/delete_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_admin_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/pages/admin_tasks_screen.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/l10n/app_localizations.dart';

class _MockGetAdminTasks extends Mock implements GetAdminTasks {}

class _MockUpdateTaskStatus extends Mock implements UpdateTaskStatus {}

class _MockUpdateTask extends Mock implements UpdateTask {}

class _MockDeleteTask extends Mock implements DeleteTask {}

Delegate _hr() => Delegate(
  uid: 'seed-fake-hr',
  firstName: 'HR',
  middleName: '',
  lastName: 'وهمي',
  fullName: 'HR وهمي',
  nationalityID: '__firebase_auth__:fake@example.com',
  motherName: '',
  city: '',
  phoneNumber: '01000000099',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1990),
  organizationUID: 'seed-fake-hr-org',
  organizationName: 'Fake Test Organization',
  companyUID: 'seed-fake-co-alpha',
  companyName: 'Fake Company Alpha',
  status: DelegateStatus.approved,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'system_admin',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.hr,
  email: 'fake@example.com',
);

/// TAS-155: inside the web HR shell the tasks page shows its filters and a
/// labelled «إنشاء مهمة» button in one toolbar row, without the FAB.
void main() {
  setUpAll(() => registerFallbackValue(TaskStatus.pending));

  setUp(() {
    sl.allowReassignment = true;
    final get = _MockGetAdminTasks();
    when(
      () => get(
        any(),
        any(),
        status: any(named: 'status'),
        limit: any(named: 'limit'),
        lastDoc: any(named: 'lastDoc'),
        adminId: any(named: 'adminId'),
        adminRoleName: any(named: 'adminRoleName'),
      ),
    ).thenAnswer((_) async => const Right(<TaskEntity>[]));
    sl.registerFactory<AdminTasksBloc>(
      () => AdminTasksBloc(
        getAdminTasks: get,
        updateTaskStatus: _MockUpdateTaskStatus(),
        updateTask: _MockUpdateTask(),
        deleteTask: _MockDeleteTask(),
      ),
    );
  });

  tearDown(() => sl.unregister<AdminTasksBloc>());

  Future<void> pump(WidgetTester tester, {required bool inShell}) async {
    tester.view.physicalSize = const Size(1200, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
    final key = GlobalKey<NavigatorState>();
    final screen = AdminTasksScreen(adminDelegate: _hr());
    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: const [
          AppLocalizations.delegate,
          GlobalMaterialLocalizations.delegate,
          GlobalWidgetsLocalizations.delegate,
          GlobalCupertinoLocalizations.delegate,
        ],
        supportedLocales: AppLocalizations.supportedLocales,
        home: inShell
            ? HrInnerPageHost(
                navigatorKey: key,
                parentTitle: 'المهام',
                child: Navigator(
                  key: key,
                  pages: [MaterialPage<void>(child: screen)],
                  onDidRemovePage: (_) {},
                ),
              )
            : screen,
      ),
    );
    await tester.pumpAndSettle();
  }

  testWidgets('in the shell: one toolbar row, labelled create button', (
    tester,
  ) async {
    await pump(tester, inShell: true);
    final button = find.byKey(const ValueKey('admin_tasks_create_button'));
    expect(button, findsOneWidget);
    expect(
      find.descendant(of: button, matching: find.text('إنشاء مهمة')),
      findsOneWidget,
    );
    expect(find.byType(FloatingActionButton), findsNothing);

    // All five filters sit on the same row as the button.
    final filters = find.descendant(
      of: find.byKey(const ValueKey('admin_tasks_shell_filters')),
      matching: find.byType(FilterChip),
    );
    expect(filters, findsNWidgets(5));
    final buttonY = tester.getCenter(button).dy;
    for (final chip in filters.evaluate()) {
      final y = tester.getCenter(find.byWidget(chip.widget)).dy;
      expect((y - buttonY).abs(), lessThan(4));
    }
  });

  testWidgets('outside the shell: FAB stays and has a tooltip', (tester) async {
    await pump(tester, inShell: false);
    expect(find.byType(FloatingActionButton), findsOneWidget);
    expect(
      find.byKey(const ValueKey('admin_tasks_create_button')),
      findsNothing,
    );
    expect(find.byTooltip('إنشاء مهمة'), findsOneWidget);
  });
}
