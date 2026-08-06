import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/models/pagination_response.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/marketing_search/data/datasources/marketing_search_remote_datasource.dart';
import 'package:delegate_app/features/marketing_search/data/repositories/marketing_search_repository_impl.dart';
import 'package:delegate_app/features/admin/data/models/company_model.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarketingSearchRemoteDataSource extends Mock
    implements MarketingSearchRemoteDataSource {}

class MockDocumentSnapshot extends Mock implements DocumentSnapshot {}

void main() {
  late MarketingSearchRepositoryImpl repository;
  late MockMarketingSearchRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockMarketingSearchRemoteDataSource();
    repository = MarketingSearchRepositoryImpl(
        remoteDataSource: mockRemoteDataSource);
  });

  final tOrganizationUID = 'org_uid';
  final tCompanyName = 'Company';
  final tPhoneNumber = '123456789';

  final tCompanyModel = CompanyModel(
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


  final tCompanyModelResponse = PaginationResponse<CompanyModel>(
    items: [tCompanyModel],
    hasReachedMax: false,
    lastDoc: null,
  );


  final tDelegateModelResponse = PaginationResponse<DelegateModel>(
    items: [tDelegate],
    hasReachedMax: false,
    lastDoc: null,
  );

  group('searchCompanyByName', () {
    test('should return list of companies when successful', () async {
      when(() => mockRemoteDataSource.searchCompanyByName(
            organizationUID: tOrganizationUID,
            companyName: tCompanyName,
            limit: 20,
            startAfterDoc: null,
          )).thenAnswer((_) async => tCompanyModelResponse);

      final result = await repository.searchCompanyByName(
          organizationUID: tOrganizationUID, companyName: tCompanyName);

      expect(result, Right<Failure, PaginationResponse<Company>>(tCompanyModelResponse));
      verify(() => mockRemoteDataSource.searchCompanyByName(
            organizationUID: tOrganizationUID,
            companyName: tCompanyName,
            limit: 20,
            startAfterDoc: null,
          )).called(1);
    });

    test('should return Left(ServerFailure) on Exception', () async {
      when(() => mockRemoteDataSource.searchCompanyByName(
            organizationUID: tOrganizationUID,
            companyName: tCompanyName,
            limit: 20,
            startAfterDoc: null,
          )).thenThrow(Exception('test'));

      final result = await repository.searchCompanyByName(
          organizationUID: tOrganizationUID, companyName: tCompanyName);

      expect(result.isLeft(), true);
    });
  });

  group('searchDelegateByPhone', () {
    test('should return list of delegates when successful', () async {
      when(() => mockRemoteDataSource.searchDelegateByPhone(
            organizationUID: tOrganizationUID,
            phoneNumber: tPhoneNumber,
            limit: 20,
            startAfterDoc: null,
          )).thenAnswer((_) async => tDelegateModelResponse);

      final result = await repository.searchDelegateByPhone(
          organizationUID: tOrganizationUID, phoneNumber: tPhoneNumber);

      expect(result, Right<Failure, PaginationResponse<Delegate>>(tDelegateModelResponse));
      verify(() => mockRemoteDataSource.searchDelegateByPhone(
            organizationUID: tOrganizationUID,
            phoneNumber: tPhoneNumber,
            limit: 20,
            startAfterDoc: null,
          )).called(1);
    });

    test('should return Left(ServerFailure) on Exception', () async {
      when(() => mockRemoteDataSource.searchDelegateByPhone(
            organizationUID: tOrganizationUID,
            phoneNumber: tPhoneNumber,
            limit: 20,
            startAfterDoc: null,
          )).thenThrow(Exception('test'));

      final result = await repository.searchDelegateByPhone(
          organizationUID: tOrganizationUID, phoneNumber: tPhoneNumber);

      expect(result.isLeft(), true);
    });
  });
}
