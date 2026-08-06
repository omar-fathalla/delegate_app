import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPenaltyRepository extends Mock implements PenaltyRepository {}

class FakePenaltyEntity extends Fake implements PenaltyEntity {}

void main() {
  late CreatePenaltyUseCase usecase;
  late MockPenaltyRepository mockPenaltyRepository;

  setUpAll(() {
    registerFallbackValue(FakePenaltyEntity());
  });

  setUp(() {
    mockPenaltyRepository = MockPenaltyRepository();
    usecase = CreatePenaltyUseCase(mockPenaltyRepository);
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

  test('should create penalty in the repository', () async {
    // Arrange
    when(() => mockPenaltyRepository.createPenalty(any()))
        .thenAnswer((_) async => const Right(unit));

    // Act
    final result = await usecase(tPenaltyEntity);

    // Assert
    expect(result, const Right(unit));
    verify(() => mockPenaltyRepository.createPenalty(tPenaltyEntity)).called(1);
    verifyNoMoreInteractions(mockPenaltyRepository);
  });
}
