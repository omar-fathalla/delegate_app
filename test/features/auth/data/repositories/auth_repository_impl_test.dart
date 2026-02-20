import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAuthRemoteDataSource implements AuthRemoteDataSource {
  Future<DelegateModel?> Function(String)? getDelegateByPhoneStub;
  String? lastPhoneNumber;
  int callCount = 0;

  @override
  Future<DelegateModel?> getDelegateByPhone(String phoneNumber) {
    callCount++;
    lastPhoneNumber = phoneNumber;
    if (getDelegateByPhoneStub != null) {
      return getDelegateByPhoneStub!(phoneNumber);
    }
    throw UnimplementedError();
  }

  Future<void> Function()? signInAnonymouslyStub;

  @override
  Future<void> signInAnonymously() async {
    if (signInAnonymouslyStub != null) {
      return signInAnonymouslyStub!();
    }
  }
}

class MockAuthLocalDataSource implements AuthLocalDataSource {
  DelegateModel? cachedDelegate;
  int cacheCallCount = 0;
  int clearCallCount = 0;

  @override
  Future<void> cacheDelegateData(DelegateModel delegate) async {
    cacheCallCount++;
    cachedDelegate = delegate;
  }

  @override
  DelegateModel? getCachedDelegateData() {
    return cachedDelegate;
  }

  @override
  Future<void> clearCachedData() async {
    clearCallCount++;
    cachedDelegate = null;
  }
}

void main() {
  late AuthRepositoryImpl repository;
  late MockAuthRemoteDataSource mockRemoteDataSource;
  late MockAuthLocalDataSource mockLocalDataSource;

  setUp(() {
    mockRemoteDataSource = MockAuthRemoteDataSource();
    mockLocalDataSource = MockAuthLocalDataSource();
    repository = AuthRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      localDataSource: mockLocalDataSource,
    );
  });

  const tPhoneNumber = '01000000000';
  final tDelegateModel = DelegateModel(
    uid: '1',
    firstName: 'أحمد',
    middleName: 'محمد',
    lastName: 'علي',
    fullName: 'أحمد محمد علي',
    nationalityID: '12345678901234',
    motherName: 'منى',
    city: 'القاهرة',
    phoneNumber: tPhoneNumber,
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

  group('getDelegateByPhone', () {
    test('should return delegate when phone number is found', () async {
      // arrange
      mockRemoteDataSource.getDelegateByPhoneStub = (_) async => tDelegateModel;
      // act
      final result = await repository.getDelegateByPhone(tPhoneNumber);
      // assert
      expect(mockRemoteDataSource.callCount, 1);
      expect(mockRemoteDataSource.lastPhoneNumber, tPhoneNumber);
      expect(result, equals(Right(tDelegateModel)));
    });

    test(
      'should return AuthFailure when phone number is not found (null)',
      () async {
        // arrange
        mockRemoteDataSource.getDelegateByPhoneStub = (_) async => null;
        // act
        final result = await repository.getDelegateByPhone(tPhoneNumber);
        // assert
        expect(mockRemoteDataSource.callCount, 1);
        expect(result, isA<Left<Failure, dynamic>>());
        final failure = (result as Left).value;
        expect(failure, isA<AuthFailure>());
      },
    );

    test(
      'should return ServerFailure when data source throws ServerFailure',
      () async {
        // arrange
        const tFailure = ServerFailure('Server Error');
        mockRemoteDataSource.getDelegateByPhoneStub = (_) => throw tFailure;
        // act
        final result = await repository.getDelegateByPhone(tPhoneNumber);
        // assert
        expect(mockRemoteDataSource.callCount, 1);
        expect(result, equals(const Left(tFailure)));
      },
    );

    test(
      'should return ServerFailure when an unexpected exception is thrown',
      () async {
        // arrange
        mockRemoteDataSource.getDelegateByPhoneStub = (_) =>
            throw Exception('Unexpected error');
        // act
        final result = await repository.getDelegateByPhone(tPhoneNumber);
        // assert
        expect(result, isA<Left<Failure, dynamic>>());
        final failure = (result as Left).value;
        expect(failure, isA<ServerFailure>());
      },
    );
  });

  group('cacheDelegate', () {
    test('should cache delegate data successfully', () async {
      final result = await repository.cacheDelegate(tDelegateModel);
      expect(result, equals(const Right(null)));
      expect(mockLocalDataSource.cacheCallCount, 1);
    });
  });

  group('getCachedDelegate', () {
    test('should return null when no cached data', () async {
      final result = await repository.getCachedDelegate();
      expect(result, equals(const Right(null)));
    });

    test('should return cached delegate when data exists', () async {
      mockLocalDataSource.cachedDelegate = tDelegateModel;
      final result = await repository.getCachedDelegate();
      result.fold(
        (failure) => fail('Should have returned Right'),
        (delegate) => expect(delegate, equals(tDelegateModel)),
      );
    });
  });

  group('clearCache', () {
    test('should clear cached data successfully', () async {
      final result = await repository.clearCache();
      expect(result, equals(const Right(null)));
      expect(mockLocalDataSource.clearCallCount, 1);
    });
  });
}
