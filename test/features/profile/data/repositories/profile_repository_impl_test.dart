import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

class MockProfileRemoteDataSource implements ProfileRemoteDataSource {
  Future<DelegateModel> Function(String)? getDelegateProfileStub;
  int callCount = 0;
  String? lastUid;

  @override
  Future<DelegateModel> getDelegateProfile(
    String uid, {
    String? organizationUID,
    String? companyUID,
  }) {
    callCount++;
    lastUid = uid;
    if (getDelegateProfileStub != null) return getDelegateProfileStub!(uid);
    throw UnimplementedError();
  }
}

void main() {
  late ProfileRepositoryImpl repository;
  late MockProfileRemoteDataSource mockDataSource;

  setUp(() {
    mockDataSource = MockProfileRemoteDataSource();
    repository = ProfileRepositoryImpl(remoteDataSource: mockDataSource);
  });

  final tDelegateModel = DelegateModel(
    uid: 'u1',
    firstName: 'أحمد',
    middleName: 'محمد',
    lastName: 'علي',
    fullName: 'أحمد محمد علي',
    nationalityID: '12345678901234',
    motherName: 'منى',
    city: 'القاهرة',
    phoneNumber: '01000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1995, 1, 1),
    organizationUID: 'org1',
    organizationName: 'منظمة تسهيل',
    companyUID: 'comp1',
    companyName: 'شركة تسهيل',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-001',
    allReceiptCodes: const [],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: const [],
  );

  group('getDelegateProfile', () {
    test('should return delegate profile on success', () async {
      mockDataSource.getDelegateProfileStub = (_) async => tDelegateModel;

      final result = await repository.getDelegateProfile('u1');

      expect(mockDataSource.callCount, 1);
      expect(mockDataSource.lastUid, 'u1');
      result.fold(
        (failure) => fail('Should have returned Right'),
        (delegate) => expect(delegate, equals(tDelegateModel)),
      );
    });

    test(
      'should return Left(ServerFailure) when ServerException is thrown',
      () async {
        mockDataSource.getDelegateProfileStub = (_) =>
            throw ServerException('User not found');

        final result = await repository.getDelegateProfile('u1');

        expect(result, isA<Left<Failure, dynamic>>());
        final failure = (result as Left).value as ServerFailure;
        expect(failure.message, 'User not found');
      },
    );

    test('should return Left(ServerFailure) on unexpected error', () async {
      mockDataSource.getDelegateProfileStub = (_) =>
          throw Exception('Unexpected');

      final result = await repository.getDelegateProfile('u1');

      expect(result, isA<Left<Failure, dynamic>>());
    });
  });
}
