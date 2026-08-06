import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarketingRepository extends Mock implements MarketingRepository {}

void main() {
  late GetMarketingDelegates usecase;
  late MockMarketingRepository mockRepository;

  setUp(() {
    mockRepository = MockMarketingRepository();
    usecase = GetMarketingDelegates(mockRepository);
  });

  final tOrganizationUID = 'org_uid';
  final tCompanyUID = 'company_uid';
  final tDelegates = [
    Delegate(
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
    )
  ];

  test('should get list of delegates from the repository', () async {
    when(() => mockRepository.getDelegates(tOrganizationUID, tCompanyUID))
        .thenAnswer((_) async => Right(tDelegates));

    final result = await usecase(GetMarketingDelegatesParams(
        organizationUID: tOrganizationUID, companyUID: tCompanyUID));

    expect(result, Right<Failure, List<Delegate>>(tDelegates));
    verify(() => mockRepository.getDelegates(tOrganizationUID, tCompanyUID))
        .called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
