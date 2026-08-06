import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPenaltyRepository extends Mock implements PenaltyRepository {}

void main() {
  late GetCompanyPenaltiesUseCase usecase;
  late MockPenaltyRepository mockPenaltyRepository;

  setUp(() {
    mockPenaltyRepository = MockPenaltyRepository();
    usecase = GetCompanyPenaltiesUseCase(mockPenaltyRepository);
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
  
  final tPenaltiesList = [tPenaltyEntity];
  const tCompanyId = 'company_123';

  test('should get company penalties from the repository', () async {
    // Arrange
    when(() => mockPenaltyRepository.getCompanyPenalties(any()))
        .thenAnswer((_) async => Right(tPenaltiesList));

    // Act
    final result = await usecase(tCompanyId);

    // Assert
    expect(result, Right(tPenaltiesList));
    verify(() => mockPenaltyRepository.getCompanyPenalties(tCompanyId)).called(1);
    verifyNoMoreInteractions(mockPenaltyRepository);
  });
}
