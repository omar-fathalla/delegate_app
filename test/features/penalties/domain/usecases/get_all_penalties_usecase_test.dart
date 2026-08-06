import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPenaltyRepository extends Mock implements PenaltyRepository {}

void main() {
  late GetAllPenaltiesUseCase usecase;
  late MockPenaltyRepository mockPenaltyRepository;

  setUp(() {
    mockPenaltyRepository = MockPenaltyRepository();
    usecase = GetAllPenaltiesUseCase(mockPenaltyRepository);
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

  test('should get all penalties from the repository', () async {
    // Arrange
    when(() => mockPenaltyRepository.getAllPenalties())
        .thenAnswer((_) async => Right(tPenaltiesList));

    // Act
    final result = await usecase();

    // Assert
    expect(result, Right(tPenaltiesList));
    verify(() => mockPenaltyRepository.getAllPenalties()).called(1);
    verifyNoMoreInteractions(mockPenaltyRepository);
  });
}
