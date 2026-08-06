import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/tasks/domain/entities/task_entity.dart';
import 'package:delegate_app/features/tasks/domain/usecases/create_task.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_event.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCreateTask extends Mock implements CreateTask {}
class MockGetCompanyDelegates extends Mock implements GetCompanyDelegates {}
class FakeTaskEntity extends Fake implements TaskEntity {}
class FakeGetCompanyDelegatesParams extends Fake implements GetCompanyDelegatesParams {}

void main() {
  late CreateTaskBloc bloc;
  late MockCreateTask mockCreateTask;
  late MockGetCompanyDelegates mockGetCompanyDelegates;

  setUpAll(() {
    registerFallbackValue(FakeTaskEntity());
    registerFallbackValue(FakeGetCompanyDelegatesParams());
  });

  setUp(() {
    mockCreateTask = MockCreateTask();
    mockGetCompanyDelegates = MockGetCompanyDelegates();

    bloc = CreateTaskBloc(
      createTask: mockCreateTask,
      getCompanyDelegates: mockGetCompanyDelegates,
    );
  });

  final List<Delegate> tDelegates = [
    Delegate(
      uid: 'del1',
      firstName: 'Del',
      middleName: '1',
      lastName: 'Test',
      fullName: 'Del 1 Test',
      nationalityID: '1234567890',
      motherName: 'Mother',
      city: 'City',
      phoneNumber: '1234567890',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990, 1, 1),
      organizationUID: 'org1',
      organizationName: 'Org 1',
      companyUID: 'comp1',
      companyName: 'Comp 1',
      status: DelegateStatus.active,
      delegatePublicId: 'del1_pub',
      allReceiptCodes: const [],
      createdAt: DateTime.now(),
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      role: UserRole.delegate,
      email: 'del1@test.com',
    ),
  ];

  test('initial state should be CreateTaskInitial', () {
    expect(bloc.state, equals(const CreateTaskInitial()));
  });

  blocTest<CreateTaskBloc, CreateTaskState>(
    'should emit [LoadingDelegates, CreateTaskInitial] when LoadDelegatesRequested is successful',
    build: () {
      when(() => mockGetCompanyDelegates(any()))
          .thenAnswer((_) async => Right(tDelegates));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadDelegatesRequested(organizationId: 'org1', companyId: 'comp1')),
    expect: () => [
      LoadingDelegates(),
      CreateTaskInitial(delegates: tDelegates),
    ],
  );

  blocTest<CreateTaskBloc, CreateTaskState>(
    'should emit [CreateTaskLoading, CreateTaskSuccess] when CreateTaskSubmitted is successful',
    build: () {
      when(() => mockCreateTask(any(), any()))
          .thenAnswer((_) async => Right(FakeTaskEntity())); // We just need a Right
      return bloc;
    },
    act: (bloc) => bloc.add(CreateTaskSubmitted(
      organizationId: 'org1',
      title: 'Task Title',
      description: 'Desc',
      priority: TaskPriority.high,
      dueDate: DateTime.now(),
      assignedTo: 'del1',
      assignedToName: 'Del 1',
      companyId: 'comp1',
      createdBy: 'admin',
      createdByName: 'Admin Name',
    )),
    expect: () => [
      const CreateTaskLoading(delegates: null),
      const CreateTaskSuccess(delegates: null),
    ],
  );

  blocTest<CreateTaskBloc, CreateTaskState>(
    'should emit [CreateTaskLoading, CreateTaskError] when CreateTaskSubmitted fails',
    build: () {
      when(() => mockCreateTask(any(), any()))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(CreateTaskSubmitted(
      organizationId: 'org1',
      title: 'Task Title',
      description: 'Desc',
      priority: TaskPriority.high,
      dueDate: DateTime.now(),
      assignedTo: 'del1',
      assignedToName: 'Del 1',
      companyId: 'comp1',
      createdBy: 'admin',
      createdByName: 'Admin Name',
    )),
    expect: () => [
      const CreateTaskLoading(delegates: null),
      const CreateTaskError(message: 'Error', delegates: null),
    ],
  );
}
