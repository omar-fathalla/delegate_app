import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late GetBranches usecase;
  late MockAdminRepository mockRepo;

  const tBranch = Branch(
    id: 'b1',
    branchName: 'الفرع الرئيسي',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 150.0,
  );

  setUp(() {
    mockRepo = MockAdminRepository();
    usecase = GetBranches(mockRepo);
  });

  test('should return list of branches on success', () async {
    when(() => mockRepo.getBranches())
        .thenAnswer((_) async => const Right([tBranch]));

    final result = await usecase(NoParams());

    expect(result, const Right([tBranch]));
    verify(() => mockRepo.getBranches()).called(1);
  });

  test('should return ServerFailure when repository fails', () async {
    when(() => mockRepo.getBranches())
        .thenAnswer((_) async => const Left(ServerFailure('خطأ في الجلب')));

    final result = await usecase(NoParams());

    expect(result, const Left(ServerFailure('خطأ في الجلب')));
  });

  test('should return empty list when no branches exist', () async {
    when(() => mockRepo.getBranches())
        .thenAnswer((_) async => const Right([]));

    final result = await usecase(NoParams());

    result.fold(
      (l) => fail('Expected Right'),
      (branches) => expect(branches, isEmpty),
    );
  });
}
