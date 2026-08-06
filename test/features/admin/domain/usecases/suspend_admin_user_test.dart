import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/suspend_admin_user.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late SuspendAdminUser usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = SuspendAdminUser(mockAdminRepository);
  });

  const tAdminId = '1';
  const tSuspend = true;
  const tParams = SuspendAdminUserParams(adminId: tAdminId, suspend: tSuspend);

  test(
    'should suspend admin user via repository',
    () async {
      // arrange
      when(() => mockAdminRepository.suspendAdminUser(any(), any()))
          .thenAnswer((_) async => const Right(unit));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, const Right(unit));
      verify(() => mockAdminRepository.suspendAdminUser(tAdminId, tSuspend)).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
