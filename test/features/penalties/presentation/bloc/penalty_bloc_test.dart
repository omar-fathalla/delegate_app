import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCreatePenaltyUseCase extends Mock implements CreatePenaltyUseCase {}
class MockGetCompanyPenaltiesUseCase extends Mock implements GetCompanyPenaltiesUseCase {}
class MockGetAllPenaltiesUseCase extends Mock implements GetAllPenaltiesUseCase {}
class MockPenaltyRepository extends Mock implements PenaltyRepository {}

class FakePenaltyEntity extends Fake implements PenaltyEntity {}
class MockFile extends Mock implements File {}

void main() {
  late PenaltyBloc bloc;
  late MockCreatePenaltyUseCase mockCreatePenaltyUseCase;
  late MockGetCompanyPenaltiesUseCase mockGetCompanyPenaltiesUseCase;
  late MockGetAllPenaltiesUseCase mockGetAllPenaltiesUseCase;
  late MockPenaltyRepository mockPenaltyRepository;

  setUpAll(() {
    registerFallbackValue(FakePenaltyEntity());
    registerFallbackValue(MockFile());
    registerFallbackValue(PenaltyStatus.issued);
  });

  setUp(() {
    mockCreatePenaltyUseCase = MockCreatePenaltyUseCase();
    mockGetCompanyPenaltiesUseCase = MockGetCompanyPenaltiesUseCase();
    mockGetAllPenaltiesUseCase = MockGetAllPenaltiesUseCase();
    mockPenaltyRepository = MockPenaltyRepository();

    bloc = PenaltyBloc(
      createPenaltyUseCase: mockCreatePenaltyUseCase,
      getCompanyPenaltiesUseCase: mockGetCompanyPenaltiesUseCase,
      getAllPenaltiesUseCase: mockGetAllPenaltiesUseCase,
      repository: mockPenaltyRepository,
    );
  });

  final tDate = DateTime(2023, 1, 1);
  final tPenaltyEntity = PenaltyEntity(
    penaltyId: 'test_id',
    companyId: 'company_123',
    companyName: 'Test Company',
    createdById: 'admin_123',
    createdByName: 'Admin Name',
    title: 'Test Penalty',
    category: ViolationCategory.dataMissing,
    incidentDescription: 'Missing data in form',
    fineAmount: 50.0,
    currency: 'EGP',
    status: PenaltyStatus.issued,
    evidenceFiles: const [],
    createdAt: tDate,
    updatedAt: tDate,
  );

  test('initial state should be PenaltyInitialState', () {
    expect(bloc.state, isA<PenaltyInitialState>());
  });

  group('LoadCompanyPenaltiesEvent', () {
    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyLoadingState, PenaltyLoadedState] when successful',
      build: () {
        when(() => mockGetCompanyPenaltiesUseCase(any()))
            .thenAnswer((_) async => Right([tPenaltyEntity]));
        return bloc;
      },
      act: (bloc) => bloc.add(const LoadCompanyPenaltiesEvent('company_123')),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyLoadedState>().having((s) => s.penalties, 'penalties', [tPenaltyEntity])
            .having((s) => s.totalFineAmount, 'totalFineAmount', 50.0)
            .having((s) => s.deductedAmount, 'deductedAmount', 0.0),
      ],
    );

    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyLoadingState, PenaltyErrorState] when fails',
      build: () {
        when(() => mockGetCompanyPenaltiesUseCase(any()))
            .thenAnswer((_) async => const Left(ServerFailure('Error')));
        return bloc;
      },
      act: (bloc) => bloc.add(const LoadCompanyPenaltiesEvent('company_123')),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyErrorState>().having((s) => s.message, 'message', 'Error'),
      ],
    );
  });

  group('LoadAllPenaltiesEvent', () {
    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyLoadingState, PenaltyLoadedState] when successful',
      build: () {
        when(() => mockGetAllPenaltiesUseCase())
            .thenAnswer((_) async => Right([tPenaltyEntity]));
        return bloc;
      },
      act: (bloc) => bloc.add(LoadAllPenaltiesEvent()),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyLoadedState>().having((s) => s.penalties, 'penalties', [tPenaltyEntity])
            .having((s) => s.totalFineAmount, 'totalFineAmount', 50.0)
            .having((s) => s.deductedAmount, 'deductedAmount', 0.0),
      ],
    );
  });

  group('CreatePenaltyRequestedEvent', () {
    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyLoadingState, PenaltyActionSuccessState] when creation is successful',
      build: () {
        when(() => mockCreatePenaltyUseCase(any()))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(CreatePenaltyRequestedEvent(
        penalty: tPenaltyEntity,
        evidenceFilesToUpload: const [],
      )),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyActionSuccessState>(),
      ],
      verify: (_) {
        verify(() => mockCreatePenaltyUseCase(any())).called(1);
      }
    );

    final mockFile = MockFile();
    const tEvidenceFile = EvidenceFile(
      fileUrl: 'http://test.com/file.jpg',
      fileType: 'IMAGE',
      fileName: 'file.jpg',
    );

    blocTest<PenaltyBloc, PenaltyState>(
      'should upload files and emit success state',
      build: () {
        when(() => mockPenaltyRepository.uploadEvidenceFile(
                file: any(named: 'file'), penaltyId: any(named: 'penaltyId')))
            .thenAnswer((_) async => const Right(tEvidenceFile));
        when(() => mockCreatePenaltyUseCase(any()))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(CreatePenaltyRequestedEvent(
        penalty: tPenaltyEntity,
        evidenceFilesToUpload: [mockFile],
      )),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyActionSuccessState>(),
      ],
      verify: (_) {
        verify(() => mockPenaltyRepository.uploadEvidenceFile(
            file: any(named: 'file'), penaltyId: any(named: 'penaltyId'))).called(1);
        verify(() => mockCreatePenaltyUseCase(any())).called(1);
      }
    );
  });

  group('UpdatePenaltyStatusEvent', () {
    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyActionSuccessState] when status update is successful',
      build: () {
        when(() => mockPenaltyRepository.updatePenaltyStatus(any(), any()))
            .thenAnswer((_) async => const Right(unit));
        return bloc;
      },
      act: (bloc) => bloc.add(const UpdatePenaltyStatusEvent(
        penaltyId: 'test_id',
        status: PenaltyStatus.deducted,
      )),
      expect: () => [
        isA<PenaltyActionSuccessState>(),
      ],
    );

    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyErrorState] when status update fails',
      build: () {
        when(() => mockPenaltyRepository.updatePenaltyStatus(any(), any()))
            .thenAnswer((_) async => const Left(ServerFailure('Error')));
        return bloc;
      },
      act: (bloc) => bloc.add(const UpdatePenaltyStatusEvent(
        penaltyId: 'test_id',
        status: PenaltyStatus.deducted,
      )),
      expect: () => [
        isA<PenaltyErrorState>(),
      ],
    );
  });
}
