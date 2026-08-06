import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/admin/domain/repositories/company_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_companies.dart';

class MockCompanyRepository extends Mock implements CompanyRepository {}
class FakeDocumentSnapshot extends Fake implements DocumentSnapshot {}

void main() {
  late GetCompanies usecase;
  late MockCompanyRepository mockCompanyRepository;

  setUp(() {
    mockCompanyRepository = MockCompanyRepository();
    usecase = GetCompanies(mockCompanyRepository);
    
    registerFallbackValue(FakeDocumentSnapshot());
  });

  final tCompany = Company(
    uid: '1',
    name: 'Test Company',
    companyCodeInOrg: '1234',
    organizationUID: 'org1',
    type: 'Retail',
    status: 'active',
    createdAt: DateTime.now(),
    updatedAt: DateTime.now(),
    admins: 1,
    delegates: 5,
    deferredPayment: true,
  );

  final tResponse = PaginationResponse<Company>(
    items: [tCompany],
    lastDoc: FakeDocumentSnapshot(),
    hasReachedMax: false,
  );

  const tParams = GetCompaniesParams(
    organizationUID: 'org1',
    limit: 20,
  );

  test(
    'should get companies via repository',
    () async {
      // arrange
      when(() => mockCompanyRepository.getCompanies(
            organizationUID: any(named: 'organizationUID'),
            lastDocument: any(named: 'lastDocument'),
            limit: any(named: 'limit'),
          )).thenAnswer((_) async => Right(tResponse));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, Right(tResponse));
      verify(() => mockCompanyRepository.getCompanies(
            organizationUID: tParams.organizationUID,
            lastDocument: tParams.lastDocument,
            limit: tParams.limit,
          )).called(1);
      verifyNoMoreInteractions(mockCompanyRepository);
    },
  );
}
