import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_state.dart';


import 'package:delegate_app/features/admin/domain/usecases/get_dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';

class MockGetDashboardSummary extends Mock implements GetDashboardSummary {}
class FakeGetDashboardSummaryParams extends Fake implements GetDashboardSummaryParams {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeGetDashboardSummaryParams());
  });

  late AdminDashboardBloc bloc;
  late MockGetDashboardSummary mockGetDashboardSummary;

  setUp(() {
    mockGetDashboardSummary = MockGetDashboardSummary();
    bloc = AdminDashboardBloc(
      getDashboardSummary: mockGetDashboardSummary
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be AdminDashboardInitial', () {
    expect(bloc.state, isA<AdminDashboardInitial>());
  });

  const tOrganizationUID = 'org1';
  const tCompanyUID = 'comp1';
  
  final tDashboardSummary = DashboardSummary(
    totalDelegates: 10,
    checkedInToday: 5,
    absentToday: 5,
    totalCompanies: 2,
  );

  blocTest<AdminDashboardBloc, AdminDashboardState>(
    'emits [AdminDashboardLoading, AdminDashboardLoaded] when LoadDashboard succeeds',
    build: () {
      when(() => mockGetDashboardSummary(any()))
          .thenAnswer((_) async => Right(tDashboardSummary));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadDashboard(
      organizationUID: tOrganizationUID,
      companyUID: tCompanyUID,
    )),
    expect: () => [
      isA<AdminDashboardLoading>(),
      isA<AdminDashboardLoaded>().having((state) => state.summary, 'summary', tDashboardSummary),
    ],
    verify: (_) {
      verify(() => mockGetDashboardSummary(const GetDashboardSummaryParams(
        organizationUID: tOrganizationUID,
        companyUID: tCompanyUID,
      ))).called(1);
    },
  );

  blocTest<AdminDashboardBloc, AdminDashboardState>(
    'emits [AdminDashboardLoading, AdminDashboardError] when LoadDashboard fails',
    build: () {
      when(() => mockGetDashboardSummary(any()))
          .thenAnswer((_) async => const Left(ServerFailure('Server Error')));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadDashboard(
      organizationUID: tOrganizationUID,
      companyUID: tCompanyUID,
    )),
    expect: () => [
      isA<AdminDashboardLoading>(),
      isA<AdminDashboardError>().having((state) => state.message, 'message', 'Server Error'),
    ],
  );
}
