import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/features/marketing_search/domain/repositories/marketing_search_repository.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_delegate_by_phone.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarketingSearchRepository extends Mock
    implements MarketingSearchRepository {}

void main() {
  late SearchDelegateByPhone usecase;
  late MockMarketingSearchRepository mockRepository;

  setUp(() {
    mockRepository = MockMarketingSearchRepository();
    usecase = SearchDelegateByPhone(mockRepository);
  });

  final tOrganizationUID = 'org_uid';
  final tPhoneNumber = '123456789';

  final tDelegate = DelegateModel(
    uid: 'uid_1',
    firstName: 'First',
    middleName: 'Middle',
    lastName: 'Last',
    fullName: 'Delegate 1',
    nationalityID: '1234567890',
    motherName: 'Mother',
    city: 'City',
    phoneNumber: '123456789',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(2000),
    organizationUID: 'org_uid',
    organizationName: 'Org',
    companyUID: 'company_uid',
    companyName: 'Company',
    status: DelegateStatus.active,
    delegatePublicId: 'del_123',
    allReceiptCodes: [],
    createdAt: DateTime.now(),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: [],
  );

  final tDelegateResponse = PaginationResponse<Delegate>(
    items: [tDelegate],
    hasReachedMax: false,
    lastDoc: null,
  );

  test('should search delegates from the repository', () async {
    when(() => mockRepository.searchDelegateByPhone(
          organizationUID: tOrganizationUID,
          phoneNumber: tPhoneNumber,
          limit: 20,
          startAfterDoc: null,
        )).thenAnswer((_) async => Right(tDelegateResponse));

    final result = await usecase(SearchDelegateByPhoneParams(
        organizationUID: tOrganizationUID, phoneNumber: tPhoneNumber));

    expect(
        result, Right<Failure, PaginationResponse<Delegate>>(tDelegateResponse));
    verify(() => mockRepository.searchDelegateByPhone(
          organizationUID: tOrganizationUID,
          phoneNumber: tPhoneNumber,
          limit: 20,
          startAfterDoc: null,
        )).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
