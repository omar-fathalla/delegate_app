import 'dart:io';
import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_delegate_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_event.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_state.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockCreatePenaltyUseCase extends Mock implements CreatePenaltyUseCase {}
class MockGetCompanyPenaltiesUseCase extends Mock implements GetCompanyPenaltiesUseCase {}
class MockGetDelegatePenaltiesUseCase extends Mock implements GetDelegatePenaltiesUseCase {}
class MockGetAllPenaltiesUseCase extends Mock implements GetAllPenaltiesUseCase {}
class MockPenaltyRepository extends Mock implements PenaltyRepository {}

class FakePenaltyEntity extends Fake implements PenaltyEntity {}
class MockFile extends Mock implements File {}

void main() {
  late PenaltyBloc bloc;
  late MockCreatePenaltyUseCase mockCreatePenaltyUseCase;
  late MockGetCompanyPenaltiesUseCase mockGetCompanyPenaltiesUseCase;
  late MockGetDelegatePenaltiesUseCase mockGetDelegatePenaltiesUseCase;
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
    mockGetDelegatePenaltiesUseCase = MockGetDelegatePenaltiesUseCase();
    mockGetAllPenaltiesUseCase = MockGetAllPenaltiesUseCase();
    mockPenaltyRepository = MockPenaltyRepository();

    bloc = PenaltyBloc(
      createPenaltyUseCase: mockCreatePenaltyUseCase,
      getCompanyPenaltiesUseCase: mockGetCompanyPenaltiesUseCase,
      getAllPenaltiesUseCase: mockGetAllPenaltiesUseCase,
      getDelegatePenaltiesUseCase: mockGetDelegatePenaltiesUseCase,
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

  final tDelegate = Delegate(
    uid: 'delegate_uid_123',
    firstName: 'Ahmed',
    middleName: 'M.',
    lastName: 'Test',
    fullName: 'Ahmed Test',
    nationalityID: '12345678901234',
    motherName: 'Mother',
    city: 'Alexandria',
    phoneNumber: '01012345678',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    paymentAmount: 0.0,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org_123',
    organizationName: 'Org',
    companyUID: 'company_123',
    companyName: 'Direct',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-101',
    allReceiptCodes: const [],
    createdAt: DateTime(2023, 1, 1),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    version: 1,
    documents: const [],
    role: UserRole.delegate,
  );

  group('LoadDelegatePenaltiesEvent', () {
    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyLoadingState, PenaltyLoadedState] with delegate personal totals',
      build: () {
        when(() => mockGetDelegatePenaltiesUseCase(
              delegateId: any(named: 'delegateId'),
              companyId: any(named: 'companyId'),
              phoneNumber: any(named: 'phoneNumber'),
              fullName: any(named: 'fullName'),
            )).thenAnswer((_) async => Right([tPenaltyEntity]));
        return bloc;
      },
      act: (bloc) => bloc.add(LoadDelegatePenaltiesEvent(tDelegate)),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyLoadedState>()
            .having((s) => s.penalties, 'penalties', [tPenaltyEntity])
            .having((s) => s.totalFineAmount, 'totalFineAmount', 50.0)
            .having((s) => s.deductedAmount, 'deductedAmount', 0.0),
      ],
    );

    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyLoadingState, PenaltyErrorState] when fails',
      build: () {
        when(() => mockGetDelegatePenaltiesUseCase(
              delegateId: any(named: 'delegateId'),
              companyId: any(named: 'companyId'),
              phoneNumber: any(named: 'phoneNumber'),
              fullName: any(named: 'fullName'),
            )).thenAnswer((_) async => const Left(ServerFailure('Failed')));
        return bloc;
      },
      act: (bloc) => bloc.add(LoadDelegatePenaltiesEvent(tDelegate)),
      expect: () => [
        isA<PenaltyLoadingState>(),
        isA<PenaltyErrorState>().having((s) => s.message, 'message', 'Failed'),
      ],
    );
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
                file: any(named: 'file'), penaltyId: any(named: 'penaltyId'), companyId: any(named: 'companyId')))
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
            file: any(named: 'file'), penaltyId: any(named: 'penaltyId'), companyId: any(named: 'companyId'))).called(1);
        verify(() => mockCreatePenaltyUseCase(any())).called(1);
      }
    );
  });

  group('UpdatePenaltyStatusEvent', () {
    blocTest<PenaltyBloc, PenaltyState>(
      'should emit [PenaltyActionSuccessState] when status update is successful',
      build: () {
        when(() => mockPenaltyRepository.updatePenaltyStatus(
              penaltyId: any(named: 'penaltyId'),
              status: any(named: 'status'),
              rejectionReason: any(named: 'rejectionReason'),
              reviewerName: any(named: 'reviewerName'),
            )).thenAnswer((_) async => const Right(unit));
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
        when(() => mockPenaltyRepository.updatePenaltyStatus(
              penaltyId: any(named: 'penaltyId'),
              status: any(named: 'status'),
              rejectionReason: any(named: 'rejectionReason'),
              reviewerName: any(named: 'reviewerName'),
            )).thenAnswer((_) async => const Left(ServerFailure('Error')));
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
