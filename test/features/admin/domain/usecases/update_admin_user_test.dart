import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_admin_user.dart';

class MockAdminRepository extends Mock implements AdminRepository {}
class FakeAdminUser extends Fake implements AdminUser {}

void main() {
  late UpdateAdminUser usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = UpdateAdminUser(mockAdminRepository);
    registerFallbackValue(FakeAdminUser());
  });

  final tAdmin = AdminUser(
    uid: '1',
    email: 'test@test.com',
    phoneNumber: '123456789',
    displayName: 'Test Admin',
    role: 'company-admin',
    isActive: true,
    organizationUID: 'org1',
    createdAt: DateTime.now(),
    createdBy: 'admin1',
    temporaryPassword: 'temp',
  );

  final tParams = UpdateAdminUserParams(admin: tAdmin);

  test(
    'should update admin user via repository',
    () async {
      // arrange
      when(() => mockAdminRepository.updateAdminUser(any()))
          .thenAnswer((_) async => const Right(unit));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, const Right(unit));
      verify(() => mockAdminRepository.updateAdminUser(tAdmin)).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
