import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetMarketingCompanies extends Mock implements GetMarketingCompanies {}
class MockGetMarketingDelegates extends Mock implements GetMarketingDelegates {}
class MockMarketingRemoteDataSource extends Mock implements MarketingRemoteDataSource {}
class MockBranchPreferenceService extends Mock implements BranchPreferenceService {}

void main() {
  late MarketingBloc bloc;
  late MockGetMarketingCompanies mockGetCompanies;
  late MockGetMarketingDelegates mockGetDelegates;
  late MockMarketingRemoteDataSource mockRemoteDataSource;
  late MockBranchPreferenceService mockBranchPreferenceService;

  setUpAll(() {
    registerFallbackValue(GetMarketingDelegatesParams(organizationUID: 'test'));
  });

  setUp(() {
    mockGetCompanies = MockGetMarketingCompanies();
    mockGetDelegates = MockGetMarketingDelegates();
    mockRemoteDataSource = MockMarketingRemoteDataSource();
    mockBranchPreferenceService = MockBranchPreferenceService();

    bloc = MarketingBloc(
      getCompanies: mockGetCompanies,
      getDelegates: mockGetDelegates,
      remoteDataSource: mockRemoteDataSource,
      branchPreferenceService: mockBranchPreferenceService,
    );
  });

  tearDown(() {
    bloc.close();
  });

  final tOrganizationUID = 'org_uid';
  final tCompanies = [
    {'uid': '1', 'name': 'Company 1'}
  ];

  test('initial state should be MarketingInitial', () {
    expect(bloc.state, MarketingInitial());
  });

  blocTest<MarketingBloc, MarketingState>(
    'should emit [CompaniesLoading, CompaniesLoaded] when LoadCompanies succeeds',
    build: () {
      when(() => mockGetCompanies(tOrganizationUID))
          .thenAnswer((_) async => Right(tCompanies));
      return bloc;
    },
    act: (bloc) => bloc.add(LoadCompanies(organizationUID: tOrganizationUID)),
    expect: () => [
      CompaniesLoading(),
      CompaniesLoaded(companies: tCompanies),
    ],
  );

  blocTest<MarketingBloc, MarketingState>(
    'should emit [CompaniesLoading, CompaniesError] when LoadCompanies fails',
    build: () {
      when(() => mockGetCompanies(tOrganizationUID))
          .thenAnswer((_) async => const Left(ServerFailure('Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(LoadCompanies(organizationUID: tOrganizationUID)),
    expect: () => [
      CompaniesLoading(),
      const CompaniesError(message: 'Error'),
    ],
  );
}
