import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_company_by_code.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_delegate_by_phone.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_bloc.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_event.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_state.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockSearchCompanyByCode extends Mock implements SearchCompanyByCode {}
class MockSearchDelegateByPhone extends Mock implements SearchDelegateByPhone {}

void main() {
  late MarketingSearchBloc bloc;
  late MockSearchCompanyByCode mockSearchCompanyByCode;
  late MockSearchDelegateByPhone mockSearchDelegateByPhone;

  setUpAll(() {
    registerFallbackValue(SearchCompanyByCodeParams(
        organizationUID: 'test', companyName: 'test'));
    registerFallbackValue(SearchDelegateByPhoneParams(
        organizationUID: 'test', phoneNumber: 'test'));
  });

  setUp(() {
    mockSearchCompanyByCode = MockSearchCompanyByCode();
    mockSearchDelegateByPhone = MockSearchDelegateByPhone();

    bloc = MarketingSearchBloc(
      searchCompanyByCode: mockSearchCompanyByCode,
      searchDelegateByPhone: mockSearchDelegateByPhone,
    );
  });

  tearDown(() {
    bloc.close();
  });

  final tOrganizationUID = 'org_uid';
  final tCompanyName = 'Company 1';

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

  test('initial state should be MarketingSearchInitial', () {
    expect(bloc.state, const MarketingSearchInitial());
  });

  blocTest<MarketingSearchBloc, MarketingSearchState>(
    'should emit [MarketingSearchLoading, CompanySearchSuccess] when SearchCompanyRequested is successful',
    build: () {
      when(() => mockSearchCompanyByCode(any()))
          .thenAnswer((_) async => Right(tCompanyResponse));
      return bloc;
    },
    act: (bloc) => bloc.add(SearchCompanyRequested(
        organizationUID: tOrganizationUID, companyName: tCompanyName)),
    expect: () => [
      const MarketingSearchLoading(searchType: 'company'),
      CompanySearchSuccess(
        companies: [tCompany],
        searchQuery: tCompanyName,
        hasReachedMax: false,
        lastDoc: null,
      ),
    ],
  );

  blocTest<MarketingSearchBloc, MarketingSearchState>(
    'should emit [MarketingSearchLoading, MarketingSearchError] when SearchCompanyRequested fails',
    build: () {
      when(() => mockSearchCompanyByCode(any()))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(SearchCompanyRequested(
        organizationUID: tOrganizationUID, companyName: tCompanyName)),
    expect: () => [
      const MarketingSearchLoading(searchType: 'company'),
      const MarketingSearchError(message: 'Error'),
    ],
  );
}
