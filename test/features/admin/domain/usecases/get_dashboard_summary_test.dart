import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/features/admin/domain/entities/dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_dashboard_summary.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late GetDashboardSummary usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = GetDashboardSummary(mockAdminRepository);
  });

  const tDashboardSummary = DashboardSummary(
    totalDelegates: 10,
    checkedInToday: 5,
    absentToday: 3,
    totalCompanies: 2,
  );

  const tParams = GetDashboardSummaryParams(
    organizationUID: 'org1',
    companyUID: 'comp1',
  );

  test(
    'should get dashboard summary via repository',
    () async {
      // arrange
      when(() => mockAdminRepository.getDashboardSummary(any(), any()))
          .thenAnswer((_) async => const Right(tDashboardSummary));
      
      // act
      final result = await usecase(tParams);
      
      // assert
      expect(result, const Right(tDashboardSummary));
      verify(() => mockAdminRepository.getDashboardSummary(
            tParams.organizationUID,
            tParams.companyUID,
          )).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
