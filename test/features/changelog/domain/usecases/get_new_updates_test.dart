import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:delegate_app/features/changelog/domain/repositories/changelog_repository.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_new_updates.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockChangelogRepository extends Mock implements ChangelogRepository {}

void main() {
  late GetNewUpdates usecase;
  late MockChangelogRepository mockRepository;

  setUp(() {
    mockRepository = MockChangelogRepository();
    usecase = GetNewUpdates(mockRepository);
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

  test('should get list of new AppUpdate from repository', () async {
    when(() => mockRepository.getNewUpdates())
        .thenAnswer((_) async => Right(tAppUpdates));

    final result = await usecase(NoParams());

    expect(result, Right<Failure, List<AppUpdate>>(tAppUpdates));
    verify(() => mockRepository.getNewUpdates()).called(1);
    verifyNoMoreInteractions(mockRepository);
  });

  test('should return Failure when repository fails', () async {
    const tFailure = ServerFailure('API Error');
    when(() => mockRepository.getNewUpdates())
        .thenAnswer((_) async => const Left(tFailure));

    final result = await usecase(NoParams());

    expect(result, const Left<Failure, List<AppUpdate>>(tFailure));
    verify(() => mockRepository.getNewUpdates()).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
