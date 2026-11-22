import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
      when(() => mockAdminRepository.getMarketingEmployees(
            companyUID: '',
            organizationUID: 'org1',
          )).thenAnswer((_) async => Right(tEmployees));
      // act
      final result = await usecase(
        const MarketingEmployeesScope(organizationUID: 'org1'),
      );
      // assert
      expect(result, Right(tEmployees));
      verify(() => mockAdminRepository.getMarketingEmployees(
            companyUID: '',
            organizationUID: 'org1',
          )).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );

  test('MarketingEmployeesScope.forUser: global staff list everyone (TAS-73)', () {
    expect(
      MarketingEmployeesScope.forUser(
        isGlobalStaff: true, companyUID: 'co', organizationUID: 'org'),
      const MarketingEmployeesScope(),
    );
    expect(
      MarketingEmployeesScope.forUser(
        isGlobalStaff: false, companyUID: ' co ', organizationUID: 'org'),
      const MarketingEmployeesScope(companyUID: 'co', organizationUID: 'org'),
    );
  });
}
