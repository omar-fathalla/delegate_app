import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_admin_user.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late DeleteAdminUser usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = DeleteAdminUser(mockAdminRepository);
  });

  const tAdminId = '1';
  const tParams = DeleteAdminUserParams(adminId: tAdminId);

  test(
    'should delete admin user via repository',
    () async {
      // arrange
      when(() => mockAdminRepository.deleteAdminUser(any()))
          .thenAnswer((_) async => const Right(unit));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, const Right(unit));
      verify(() => mockAdminRepository.deleteAdminUser(tAdminId)).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
