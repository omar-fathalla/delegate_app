import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/marketing_search/domain/repositories/marketing_search_repository.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_company_by_code.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarketingSearchRepository extends Mock
    implements MarketingSearchRepository {}

void main() {
  late SearchCompanyByCode usecase;
  late MockMarketingSearchRepository mockRepository;

  setUp(() {
    mockRepository = MockMarketingSearchRepository();
    usecase = SearchCompanyByCode(mockRepository);
  });

  final tOrganizationUID = 'org_uid';
  final tCompanyName = 'Company';

  final tCompany = Company(
    uid: '1',
    name: 'Company 1',
    companyCodeInOrg: 'comp_123',
    organizationUID: 'org_uid',
    type: 'type',
    status: 'active',
    createdAt: DateTime(2000),
    updatedAt: DateTime(2000),
    admins: 1,
    delegates: 1,
    deferredPayment: false,
  );

  final tCompanyResponse = PaginationResponse<Company>(
    items: [tCompany],
    hasReachedMax: false,
    lastDoc: null,
  );

  test('should search companies from the repository', () async {
    when(() => mockRepository.searchCompanyByName(
          organizationUID: tOrganizationUID,
          companyName: tCompanyName,
          limit: 20,
          startAfterDoc: null,
        )).thenAnswer((_) async => Right(tCompanyResponse));

    final result = await usecase(SearchCompanyByCodeParams(
        organizationUID: tOrganizationUID, companyName: tCompanyName));

    expect(result, Right<Failure, PaginationResponse<Company>>(tCompanyResponse));
    verify(() => mockRepository.searchCompanyByName(
          organizationUID: tOrganizationUID,
          companyName: tCompanyName,
          limit: 20,
          startAfterDoc: null,
        )).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
