import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_admins.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late GetAdmins usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = GetAdmins(mockAdminRepository);
  });

  final tAdmins = [
    AdminUser(
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
    )
  ];

  test(
    'should get admins from the repository',
    () async {
      // arrange
      when(() => mockAdminRepository.getAdmins())
          .thenAnswer((_) async => Right(tAdmins));
      // act
      final result = await usecase(NoParams());
      // assert
      expect(result, Right(tAdmins));
      verify(() => mockAdminRepository.getAdmins()).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
