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
    MarketingBloc.clearCache();
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

  group('LoadAllFavoriteBranchesAttendance (SWR & Zero-Drop Sync)', () {
    final tBranches = ['Abo Yousif'];
    final tDate = DateTime(2026, 10, 7);
    final tAttendanceData = {
      'Abo Yousif': [
        {'delegateId': 'd1', 'delegateNameInLog': 'Ahmad', 'checkOutTime': null}
      ]
    };

    blocTest<MarketingBloc, MarketingState>(
      'should emit empty AllBranchesAttendanceLoaded when favoriteBranches is empty',
      build: () => bloc,
      act: (bloc) => bloc.add(LoadAllFavoriteBranchesAttendance(
        favoriteBranches: const [],
        organizationId: tOrganizationUID,
      )),
      expect: () => [
        const AllBranchesAttendanceLoaded(
          data: {},
          favoriteBranches: [],
          loadingBranches: {},
        ),
      ],
    );

    blocTest<MarketingBloc, MarketingState>(
      'should emit [Loading, Loaded] when no cache exists and fetch succeeds',
      build: () {
        when(() => mockRemoteDataSource.getTodayAttendanceForBranches(
          branchNames: any(named: 'branchNames'),
          organizationId: any(named: 'organizationId'),
          date: any(named: 'date'),
        )).thenAnswer((_) async => tAttendanceData);
        return bloc;
      },
      act: (bloc) => bloc.add(LoadAllFavoriteBranchesAttendance(
        favoriteBranches: tBranches,
        organizationId: tOrganizationUID,
        date: tDate,
      )),
      expect: () => [
        AllBranchesAttendanceLoading(),
        AllBranchesAttendanceLoaded(
          data: tAttendanceData,
          favoriteBranches: tBranches,
          loadingBranches: const {},
        ),
      ],
    );

    test('should emit cached state immediately (0ms) and revalidate from server in background (SWR)', () async {
      when(() => mockRemoteDataSource.getTodayAttendanceForBranches(
        branchNames: any(named: 'branchNames'),
        organizationId: any(named: 'organizationId'),
        date: any(named: 'date'),
      )).thenAnswer((_) async => tAttendanceData);

      // 1. Initial fetch populates cache
      bloc.add(LoadAllFavoriteBranchesAttendance(
        favoriteBranches: tBranches,
        organizationId: tOrganizationUID,
        date: tDate,
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          AllBranchesAttendanceLoading(),
          AllBranchesAttendanceLoaded(
            data: tAttendanceData,
            favoriteBranches: tBranches,
            loadingBranches: const {},
          ),
        ]),
      );

      // 2. Updated data arrives from remote server
      final tUpdatedAttendanceData = {
        'Abo Yousif': [
          {'delegateId': 'd1', 'delegateNameInLog': 'Ahmad', 'checkOutTime': null},
          {'delegateId': 'd2', 'delegateNameInLog': 'Mohamed', 'checkOutTime': null},
        ]
      };
      when(() => mockRemoteDataSource.getTodayAttendanceForBranches(
        branchNames: any(named: 'branchNames'),
        organizationId: any(named: 'organizationId'),
        date: any(named: 'date'),
      )).thenAnswer((_) async => tUpdatedAttendanceData);

      // SWR: Triggering load when cache is present
      bloc.add(LoadAllFavoriteBranchesAttendance(
        favoriteBranches: tBranches,
        organizationId: tOrganizationUID,
        date: tDate,
        forceRefresh: true,
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          // Instant cache rendering (0ms)
          AllBranchesAttendanceLoaded(
            data: tAttendanceData,
            favoriteBranches: tBranches,
            loadingBranches: {'Abo Yousif'},
          ),
          // Followed by fresh server data
          AllBranchesAttendanceLoaded(
            data: tUpdatedAttendanceData,
            favoriteBranches: tBranches,
            loadingBranches: const {},
          ),
        ]),
      );
    });

    test('should preserve cached data gracefully if background revalidation encounters server error', () async {
      when(() => mockRemoteDataSource.getTodayAttendanceForBranches(
        branchNames: any(named: 'branchNames'),
        organizationId: any(named: 'organizationId'),
        date: any(named: 'date'),
      )).thenAnswer((_) async => tAttendanceData);

      // Populate cache
      bloc.add(LoadAllFavoriteBranchesAttendance(
        favoriteBranches: tBranches,
        organizationId: tOrganizationUID,
        date: tDate,
      ));
      await expectLater(
        bloc.stream,
        emitsInOrder([
          AllBranchesAttendanceLoading(),
          AllBranchesAttendanceLoaded(
            data: tAttendanceData,
            favoriteBranches: tBranches,
            loadingBranches: const {},
          ),
        ]),
      );

      // Now server fails
      when(() => mockRemoteDataSource.getTodayAttendanceForBranches(
        branchNames: any(named: 'branchNames'),
        organizationId: any(named: 'organizationId'),
        date: any(named: 'date'),
      )).thenThrow(Exception('Network timeout'));

      bloc.add(LoadAllFavoriteBranchesAttendance(
        favoriteBranches: tBranches,
        organizationId: tOrganizationUID,
        date: tDate,
        forceRefresh: true,
      ));

      await expectLater(
        bloc.stream,
        emitsInOrder([
          AllBranchesAttendanceLoaded(
            data: tAttendanceData,
            favoriteBranches: tBranches,
            loadingBranches: {'Abo Yousif'},
          ),
          // Seamlessly preserves cached data, NO error screen!
          AllBranchesAttendanceLoaded(
            data: tAttendanceData,
            favoriteBranches: tBranches,
            loadingBranches: const {},
          ),
        ]),
      );
    });
  });
}
