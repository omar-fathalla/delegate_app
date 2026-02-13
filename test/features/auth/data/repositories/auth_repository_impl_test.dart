import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/models/user_model.dart';
import 'package:delegate_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAuthRemoteDataSource implements AuthRemoteDataSource {
  Future<UserModel> Function(String, String)? loginStub;
  String? lastMobile;
  String? lastMotherName;
  int loginCallCount = 0;

  @override
  Future<UserModel> login(String mobile, String motherName) {
    loginCallCount++;
    lastMobile = mobile;
    lastMotherName = motherName;
    if (loginStub != null) return loginStub!(mobile, motherName);
    throw UnimplementedError();
  }
}

void main() {
  late AuthRepositoryImpl repository;
  late MockAuthRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockAuthRemoteDataSource();
    repository = AuthRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  const tMobile = '1234567890';
  const tMotherName = 'Mother';
  const tUserModel = UserModel(
    id: '1',
    name: 'Test User',
    mobile: tMobile,
    motherName: tMotherName,
    role: 'delegate',
  );

  group('login', () {
    test(
      'should return remote data when the call to remote data source is successful',
      () async {
        // arrange
        mockRemoteDataSource.loginStub = (_, __) async => tUserModel;
        // act
        final result = await repository.login(tMobile, tMotherName);
        // assert
        expect(mockRemoteDataSource.loginCallCount, 1);
        expect(mockRemoteDataSource.lastMobile, tMobile);
        expect(mockRemoteDataSource.lastMotherName, tMotherName);
        expect(result, equals(const Right(tUserModel)));
      },
    );

    test(
      'should return AuthFailure when the call to remote data source throws AuthFailure',
      () async {
        // arrange
        const tFailure = AuthFailure('Invalid credentials');
        mockRemoteDataSource.loginStub = (_, __) => throw tFailure;
        // act
        final result = await repository.login(tMobile, tMotherName);
        // assert
        expect(mockRemoteDataSource.loginCallCount, 1);
        expect(result, equals(const Left(tFailure)));
      },
    );

    test(
      'should return ServerFailure when the call to remote data source throws ServerFailure',
      () async {
        // arrange
        const tFailure = ServerFailure('Server Error');
        mockRemoteDataSource.loginStub = (_, __) => throw tFailure;
        // act
        final result = await repository.login(tMobile, tMotherName);
        // assert
        expect(mockRemoteDataSource.loginCallCount, 1);
        expect(result, equals(const Left(tFailure)));
      },
    );

    test(
      'should return ServerFailure when the call to remote data source throws an unexpected exception',
      () async {
        // arrange
        mockRemoteDataSource.loginStub = (_, __) => throw Exception('Unexpected error');
        // act
        final result = await repository.login(tMobile, tMotherName);
        // assert
        expect(result, isA<Left<Failure, dynamic>>());
        final failure = (result as Left).value;
        expect(failure, isA<ServerFailure>());
      },
    );
  });
}
