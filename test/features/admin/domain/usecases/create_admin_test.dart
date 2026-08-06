import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late CreateAdmin usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = CreateAdmin(mockAdminRepository);
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

  const tParams = CreateAdminParams(
    phoneNumber: '123456789',
    email: 'test@test.com',
    displayName: 'Test Admin',
    role: 'company-admin',
    organizationUID: 'org1',
  );

  test(
    'should create admin user via repository',
    () async {
      // arrange
      when(() => mockAdminRepository.createAdmin(
            phoneNumber: any(named: 'phoneNumber'),
            email: any(named: 'email'),
            displayName: any(named: 'displayName'),
            role: any(named: 'role'),
            organizationUID: any(named: 'organizationUID'),
          )).thenAnswer((_) async => Right(tAdmin));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, Right(tAdmin));
      verify(() => mockAdminRepository.createAdmin(
            phoneNumber: tParams.phoneNumber,
            email: tParams.email,
            displayName: tParams.displayName,
            role: tParams.role,
            organizationUID: tParams.organizationUID,
          )).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
