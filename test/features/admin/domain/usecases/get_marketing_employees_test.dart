import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/entities/admin_user.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_marketing_employees.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late GetMarketingEmployees usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = GetMarketingEmployees(mockAdminRepository);
  });

  final tEmployees = [
    AdminUser(
      uid: '1',
      email: 'test@test.com',
      phoneNumber: '123456789',
      displayName: 'Test Marketing',
      role: 'marketing',
      isActive: true,
      organizationUID: 'org1',
      createdAt: DateTime.now(),
      createdBy: 'admin1',
      temporaryPassword: 'temp',
    )
  ];

  test(
    'should get marketing employees from the repository',
    () async {
      // arrange
      when(() => mockAdminRepository.getMarketingEmployees())
          .thenAnswer((_) async => Right(tEmployees));
      // act
      final result = await usecase(NoParams());
      // assert
      expect(result, Right(tEmployees));
      verify(() => mockAdminRepository.getMarketingEmployees()).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
