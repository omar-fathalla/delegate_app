import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

class FakeBranch extends Fake implements Branch {}

void main() {
  late UpdateBranch useCase;
  late MockAdminRepository mockRepository;

  const tBranch = Branch(
    id: 'b1',
    branchName: 'الفرع الرئيسي',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 150.0,
  );

  setUpAll(() {
    registerFallbackValue(FakeBranch());
  });

  setUp(() {
    mockRepository = MockAdminRepository();
    useCase = UpdateBranch(mockRepository);
  });

  test('should call repository.updateBranch with correct branch', () async {
    when(() => mockRepository.updateBranch(any()))
        .thenAnswer((_) async => const Right(tBranch));

    final result = await useCase(const UpdateBranchParams(branch: tBranch));

    expect(result, const Right(tBranch));
    verify(() => mockRepository.updateBranch(tBranch)).called(1);
    verifyNoMoreInteractions(mockRepository);
  });

  test('should return Failure when repository fails', () async {
    when(() => mockRepository.updateBranch(any())).thenAnswer(
        (_) async => const Left(ServerFailure('فشل في تحديث الفرع.')));

    final result = await useCase(const UpdateBranchParams(branch: tBranch));

    expect(result, const Left(ServerFailure('فشل في تحديث الفرع.')));
  });
}
