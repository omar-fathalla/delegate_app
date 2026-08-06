import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarketingRepository extends Mock implements MarketingRepository {}

void main() {
  late GetMarketingCompanies usecase;
  late MockMarketingRepository mockRepository;

  setUp(() {
    mockRepository = MockMarketingRepository();
    usecase = GetMarketingCompanies(mockRepository);
  });

  final tOrganizationUID = 'org_uid';
  final tCompanies = [
    {'uid': '1', 'name': 'Company 1'}
  ];

  test('should get list of companies from the repository', () async {
    when(() => mockRepository.getCompanies(tOrganizationUID))
        .thenAnswer((_) async => Right(tCompanies));

    final result = await usecase(tOrganizationUID);

    expect(result, Right<Failure, List<Map<String, dynamic>>>(tCompanies));
    verify(() => mockRepository.getCompanies(tOrganizationUID)).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
