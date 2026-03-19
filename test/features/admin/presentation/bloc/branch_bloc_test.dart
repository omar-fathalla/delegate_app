import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetBranches extends Mock implements GetBranches {}

class MockAddBranch extends Mock implements AddBranch {}

class MockUpdateBranch extends Mock implements UpdateBranch {}

class MockDeleteBranch extends Mock implements DeleteBranch {}

class FakeNoParams extends Fake implements NoParams {}

class FakeAddBranchParams extends Fake implements AddBranchParams {}

class FakeUpdateBranchParams extends Fake implements UpdateBranchParams {}

class FakeDeleteBranchParams extends Fake implements DeleteBranchParams {}

void main() {
  late BranchBloc bloc;
  late MockGetBranches mockGetBranches;
  late MockAddBranch mockAddBranch;
  late MockUpdateBranch mockUpdateBranch;
  late MockDeleteBranch mockDeleteBranch;

  const tBranch = Branch(
    id: 'b1',
    branchName: 'الفرع الرئيسي',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 150.0,
  );

  setUpAll(() {
    registerFallbackValue(FakeNoParams());
    registerFallbackValue(FakeAddBranchParams());
    registerFallbackValue(FakeUpdateBranchParams());
    registerFallbackValue(FakeDeleteBranchParams());
  });

  setUp(() {
    mockGetBranches = MockGetBranches();
    mockAddBranch = MockAddBranch();
    mockUpdateBranch = MockUpdateBranch();
    mockDeleteBranch = MockDeleteBranch();
    bloc = BranchBloc(
      getBranches: mockGetBranches,
      addBranch: mockAddBranch,
      updateBranch: mockUpdateBranch,
      deleteBranch: mockDeleteBranch,
    );
  });

  tearDown(() => bloc.close());

  test('initial state should be BranchInitial', () {
    expect(bloc.state, isA<BranchInitial>());
  });

  group('BranchLoadRequested', () {
    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchLoaded] on success',
      build: () {
        when(() => mockGetBranches(any()))
            .thenAnswer((_) async => const Right([tBranch]));
        return bloc;
      },
      act: (b) => b.add(const BranchLoadRequested()),
      expect: () => [
        isA<BranchLoading>(),
        isA<BranchLoaded>(),
      ],
      verify: (_) {
        verify(() => mockGetBranches(any())).called(1);
      },
    );

    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchError] on failure',
      build: () {
        when(() => mockGetBranches(any())).thenAnswer(
            (_) async => const Left(ServerFailure('خطأ في الجلب')));
        return bloc;
      },
      act: (b) => b.add(const BranchLoadRequested()),
      expect: () => [
        isA<BranchLoading>(),
        isA<BranchError>(),
      ],
    );

    blocTest<BranchBloc, BranchState>(
      'BranchLoaded contains correct branches list',
      build: () {
        when(() => mockGetBranches(any()))
            .thenAnswer((_) async => const Right([tBranch]));
        return bloc;
      },
      act: (b) => b.add(const BranchLoadRequested()),
      expect: () => [
        isA<BranchLoading>(),
        BranchLoaded(branches: const [tBranch]),
      ],
    );
  });

  group('BranchAddRequested', () {
    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchActionSuccess] on success',
      build: () {
        when(() => mockAddBranch(any()))
            .thenAnswer((_) async => const Right(tBranch));
        return bloc;
      },
      act: (b) =>
          b.add(const BranchAddRequested(branch: tBranch)),
      expect: () => [
        isA<BranchLoading>(),
        isA<BranchActionSuccess>(),
      ],
    );

    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchError] on failure',
      build: () {
        when(() => mockAddBranch(any())).thenAnswer(
            (_) async => const Left(ServerFailure('فشل في إضافة الفرع.')));
        return bloc;
      },
      act: (b) =>
          b.add(const BranchAddRequested(branch: tBranch)),
      expect: () => [
        isA<BranchLoading>(),
        BranchError(message: 'فشل في إضافة الفرع.'),
      ],
    );
  });

  group('BranchDeleteRequested', () {
    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchDeleteSuccess] on success',
      build: () {
        when(() => mockDeleteBranch(any()))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (b) =>
          b.add(const BranchDeleteRequested(branchId: 'b1')),
      expect: () => [
        isA<BranchLoading>(),
        isA<BranchDeleteSuccess>(),
      ],
    );

    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchError] on failure',
      build: () {
        when(() => mockDeleteBranch(any())).thenAnswer(
            (_) async => const Left(ServerFailure('فشل في حذف الفرع.')));
        return bloc;
      },
      act: (b) =>
          b.add(const BranchDeleteRequested(branchId: 'b1')),
      expect: () => [
        isA<BranchLoading>(),
        BranchError(message: 'فشل في حذف الفرع.'),
      ],
    );
  });

  group('BranchUpdateRequested', () {
    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchUpdateSuccess] on success',
      build: () {
        when(() => mockUpdateBranch(any()))
            .thenAnswer((_) async => const Right(tBranch));
        return bloc;
      },
      act: (b) => b.add(const BranchUpdateRequested(branch: tBranch)),
      expect: () => [
        isA<BranchLoading>(),
        isA<BranchUpdateSuccess>(),
      ],
      verify: (b) {
        final state = b.state as BranchUpdateSuccess;
        expect(state.branch.id, 'b1');
        expect(state.branch.branchName, 'الفرع الرئيسي');
      },
    );

    blocTest<BranchBloc, BranchState>(
      'emits [BranchLoading, BranchError] on failure',
      build: () {
        when(() => mockUpdateBranch(any())).thenAnswer(
            (_) async => const Left(ServerFailure('فشل في تحديث الفرع.')));
        return bloc;
      },
      act: (b) => b.add(const BranchUpdateRequested(branch: tBranch)),
      expect: () => [
        isA<BranchLoading>(),
        BranchError(message: 'فشل في تحديث الفرع.'),
      ],
    );
  });
}
