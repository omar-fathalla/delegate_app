import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_all_updates.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_new_updates.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_bloc.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_event.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetAllUpdates extends Mock implements GetAllUpdates {}

class MockGetNewUpdates extends Mock implements GetNewUpdates {}

void main() {
  late ChangelogBloc bloc;
  late MockGetAllUpdates mockGetAllUpdates;
  late MockGetNewUpdates mockGetNewUpdates;

  setUpAll(() {
    registerFallbackValue(NoParams());
  });

  setUp(() {
    mockGetAllUpdates = MockGetAllUpdates();
    mockGetNewUpdates = MockGetNewUpdates();
    bloc = ChangelogBloc(
      getAllUpdates: mockGetAllUpdates,
      getNewUpdates: mockGetNewUpdates,
    );
  });

  tearDown(() {
    bloc.close();
  });

  final tAppUpdate = AppUpdate(
    id: 'test_id',
    title: 'Test Update',
    titleEn: 'Test Update EN',
    description: 'Test Description',
    descriptionEn: 'Test Description EN',
    version: '1.0.0',
    type: UpdateType.feature,
    priority: UpdatePriority.normal,
    createdAt: DateTime(2023, 1, 1),
    isActive: true,
  );
  final tAppUpdates = [tAppUpdate];

  test('initial state should be ChangelogInitial', () {
    expect(bloc.state, ChangelogInitial());
  });

  blocTest<ChangelogBloc, ChangelogState>(
    'LoadAllUpdates should emit [ChangelogLoading, ChangelogAllLoaded] on success',
    build: () {
      when(() => mockGetAllUpdates(any()))
          .thenAnswer((_) async => Right(tAppUpdates));
      return bloc;
    },
    act: (bloc) => bloc.add(LoadAllUpdates()),
    expect: () => [
      ChangelogLoading(),
      ChangelogAllLoaded(tAppUpdates),
    ],
    verify: (_) {
      verify(() => mockGetAllUpdates(any())).called(1);
    },
  );

  blocTest<ChangelogBloc, ChangelogState>(
    'LoadAllUpdates should emit [ChangelogLoading, ChangelogError] on failure',
    build: () {
      when(() => mockGetAllUpdates(any()))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(LoadAllUpdates()),
    expect: () => [
      ChangelogLoading(),
      const ChangelogError('Error'),
    ],
    verify: (_) {
      verify(() => mockGetAllUpdates(any())).called(1);
    },
  );

  blocTest<ChangelogBloc, ChangelogState>(
    'CheckForNewUpdates should emit [ChangelogHasNewUpdates] on success with updates',
    build: () {
      when(() => mockGetNewUpdates(any()))
          .thenAnswer((_) async => Right(tAppUpdates));
      return bloc;
    },
    act: (bloc) => bloc.add(CheckForNewUpdates()),
    expect: () => [
      ChangelogHasNewUpdates(tAppUpdates),
    ],
    verify: (_) {
      verify(() => mockGetNewUpdates(any())).called(1);
    },
  );

  blocTest<ChangelogBloc, ChangelogState>(
    'CheckForNewUpdates should emit [ChangelogNoNewUpdates] when list is empty',
    build: () {
      when(() => mockGetNewUpdates(any()))
          .thenAnswer((_) async => const Right([]));
      return bloc;
    },
    act: (bloc) => bloc.add(CheckForNewUpdates()),
    expect: () => [
      ChangelogNoNewUpdates(),
    ],
    verify: (_) {
      verify(() => mockGetNewUpdates(any())).called(1);
    },
  );

  blocTest<ChangelogBloc, ChangelogState>(
    'CheckForNewUpdates should emit [ChangelogNoNewUpdates] on failure (silent fail)',
    build: () {
      when(() => mockGetNewUpdates(any()))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(CheckForNewUpdates()),
    expect: () => [
      ChangelogNoNewUpdates(),
    ],
    verify: (_) {
      verify(() => mockGetNewUpdates(any())).called(1);
    },
  );
  
  blocTest<ChangelogBloc, ChangelogState>(
    'DismissNewUpdates should emit [ChangelogNoNewUpdates]',
    build: () => bloc,
    act: (bloc) => bloc.add(DismissNewUpdates()),
    expect: () => [
      ChangelogNoNewUpdates(),
    ],
  );
}
