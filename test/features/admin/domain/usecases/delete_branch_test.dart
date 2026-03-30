import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late DeleteBranch usecase;
  late MockAdminRepository mockRepo;

  setUp(() {
    mockRepo = MockAdminRepository();
    usecase = DeleteBranch(mockRepo);
  });

  test('should return unit on successful deletion', () async {
    when(
      () => mockRepo.deleteBranch(any()),
    ).thenAnswer((_) async => const Right(unit));

    final result = await usecase(const DeleteBranchParams(branchId: 'b1'));

    expect(result, const Right(unit));
    verify(() => mockRepo.deleteBranch('b1')).called(1);
  });

  test('should return ServerFailure when deletion fails', () async {
    when(
      () => mockRepo.deleteBranch(any()),
    ).thenAnswer((_) async => const Left(ServerFailure('فشل في حذف الفرع.')));

    final result = await usecase(const DeleteBranchParams(branchId: 'b1'));

    expect(result, const Left(ServerFailure('فشل في حذف الفرع.')));
  });
}
