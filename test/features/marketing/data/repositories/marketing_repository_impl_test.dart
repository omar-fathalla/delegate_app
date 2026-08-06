import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/repositories/marketing_repository_impl.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockMarketingRemoteDataSource extends Mock
    implements MarketingRemoteDataSource {}

void main() {
  late MarketingRepositoryImpl repository;
  late MockMarketingRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockMarketingRemoteDataSource();
    repository = MarketingRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  final tOrganizationUID = 'org_uid';
  final tCompanyUID = 'company_uid';

  group('getCompanies', () {
    final tCompanies = [
      {'uid': '1', 'name': 'Company 1'}
    ];

    test('should return list of companies when successful', () async {
      when(() => mockRemoteDataSource.getCompanies(tOrganizationUID))
          .thenAnswer((_) async => tCompanies);

      final result = await repository.getCompanies(tOrganizationUID);

      expect(result, Right<Failure, List<Map<String, dynamic>>>(tCompanies));
      verify(() => mockRemoteDataSource.getCompanies(tOrganizationUID))
          .called(1);
    });

    test('should return Left(ServerFailure) when exception occurs', () async {
      when(() => mockRemoteDataSource.getCompanies(tOrganizationUID))
          .thenThrow(Exception());

      final result = await repository.getCompanies(tOrganizationUID);

      expect(result, const Left(ServerFailure('حدث خطأ غير متوقع.')));
    });
  });

  group('getDelegates', () {
    final tDelegates = [
      DelegateModel(
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

    test('should return list of delegates when successful', () async {
      when(() => mockRemoteDataSource.getDelegates(
              tOrganizationUID, tCompanyUID))
          .thenAnswer((_) async => tDelegates);

      final result =
          await repository.getDelegates(tOrganizationUID, tCompanyUID);

      expect(result, Right<Failure, List<Delegate>>(tDelegates));
      verify(() => mockRemoteDataSource.getDelegates(
          tOrganizationUID, tCompanyUID)).called(1);
    });

    test('should return Left(ServerFailure) when exception occurs', () async {
      when(() => mockRemoteDataSource.getDelegates(
              tOrganizationUID, tCompanyUID))
          .thenThrow(Exception());

      final result =
          await repository.getDelegates(tOrganizationUID, tCompanyUID);

      expect(result, const Left(ServerFailure('حدث خطأ غير متوقع.')));
    });
  });
}
