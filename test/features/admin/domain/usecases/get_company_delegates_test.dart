import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late GetCompanyDelegates usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = GetCompanyDelegates(mockAdminRepository);
  });

  final tDelegates = [
    Delegate(
      uid: '1',
      firstName: 'Test',
      middleName: 'M',
      lastName: 'Delegate',
      fullName: 'Test M Delegate',
      nationalityID: '1234567890',
      motherName: 'Mother',
      city: 'City',
      phoneNumber: '123456789',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990),
      organizationUID: 'org1',
      organizationName: 'Org 1',
      companyUID: 'comp1',
      companyName: 'Comp 1',
      status: DelegateStatus.active,
      delegatePublicId: 'del1',
      allReceiptCodes: const [],
      createdAt: DateTime.now(),
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
    )
  ];

  const tParams = GetCompanyDelegatesParams(
    organizationUID: 'org1',
    companyUID: 'comp1',
  );

  test(
    'should get company delegates via repository',
    () async {
      // arrange
      when(() => mockAdminRepository.getCompanyDelegates(any(), any()))
          .thenAnswer((_) async => Right(CompanyDelegatesResult(delegates: tDelegates)));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, Right(CompanyDelegatesResult(delegates: tDelegates)));
      verify(() => mockAdminRepository.getCompanyDelegates(
            tParams.organizationUID,
            tParams.companyUID,
          )).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
