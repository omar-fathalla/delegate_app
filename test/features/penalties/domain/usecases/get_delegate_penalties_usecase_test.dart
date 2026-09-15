import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_delegate_penalties_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPenaltyRepository extends Mock implements PenaltyRepository {}

void main() {
  late GetDelegatePenaltiesUseCase usecase;
  late MockPenaltyRepository mockPenaltyRepository;

  setUp(() {
    mockPenaltyRepository = MockPenaltyRepository();
    usecase = GetDelegatePenaltiesUseCase(mockPenaltyRepository);
  });

  final tDate = DateTime(2026, 1, 1);
  final tPenaltyEntity = PenaltyEntity(
    penaltyId: 'test_del_pen_id',
    companyId: 'company_123',
    companyName: 'Direct',
    targetDelegateId: 'delegate_uid_123',
    targetDelegateName: 'Ahmed Test',
    createdById: 'admin_123',
    createdByName: 'Admin Name',
    title: 'Individual Violation',
    category: ViolationCategory.dataMissing,
    incidentDescription: 'Individual incident',
    fineAmount: 100.0,
    currency: 'EGP',
    status: PenaltyStatus.deducted,
    evidenceFiles: const [],
    createdAt: tDate,
    updatedAt: tDate,
  );

  final tPenaltiesList = [tPenaltyEntity];

  test('should get delegate penalties from repository with correct identifiers', () async {
    // Arrange
    when(() => mockPenaltyRepository.getDelegatePenalties(
          delegateId: any(named: 'delegateId'),
          companyId: any(named: 'companyId'),
          phoneNumber: any(named: 'phoneNumber'),
          fullName: any(named: 'fullName'),
        )).thenAnswer((_) async => Right(tPenaltiesList));

    // Act
    final result = await usecase(
      delegateId: 'delegate_uid_123',
      companyId: 'company_123',
      phoneNumber: '01012345678',
      fullName: 'Ahmed Test',
    );

    // Assert
    expect(result, Right(tPenaltiesList));
    verify(() => mockPenaltyRepository.getDelegatePenalties(
          delegateId: 'delegate_uid_123',
          companyId: 'company_123',
          phoneNumber: '01012345678',
          fullName: 'Ahmed Test',
        )).called(1);
    verifyNoMoreInteractions(mockPenaltyRepository);
  });
}
