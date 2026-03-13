import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/entities/branch.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late AddBranch usecase;
  late MockAdminRepository mockRepo;

  const tBranch = Branch(
    id: '',
    branchName: 'فرع جديد',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 100.0,
  );

  const tBranchWithId = Branch(
    id: 'new_id',
    branchName: 'فرع جديد',
    latitude: 30.0444,
    longitude: 31.2357,
    geofenceRadius: 100.0,
  );

  setUp(() {
    mockRepo = MockAdminRepository();
    usecase = AddBranch(mockRepo);
    registerFallbackValue(tBranch);
  });

  test('should return created branch on success', () async {
    when(() => mockRepo.addBranch(any()))
        .thenAnswer((_) async => const Right(tBranchWithId));

    final result = await usecase(const AddBranchParams(branch: tBranch));

    expect(result, const Right(tBranchWithId));
    verify(() => mockRepo.addBranch(tBranch)).called(1);
  });

  test('should return ServerFailure when add fails', () async {
    when(() => mockRepo.addBranch(any())).thenAnswer(
        (_) async => const Left(ServerFailure('فشل في إضافة الفرع.')));

    final result = await usecase(const AddBranchParams(branch: tBranch));

    expect(result, const Left(ServerFailure('فشل في إضافة الفرع.')));
  });
}
