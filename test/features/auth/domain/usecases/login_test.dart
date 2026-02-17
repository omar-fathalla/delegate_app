import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/auth/domain/entities/user.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAuthRepository implements AuthRepository {
  Future<Either<Failure, User>> Function(String, String)? loginStub;
  int loginCallCount = 0;
  String? lastMobile;
  String? lastMotherName;

  @override
  Future<Either<Failure, User>> login(String mobile, String motherName) async {
    loginCallCount++;
    lastMobile = mobile;
    lastMotherName = motherName;
    if (loginStub != null) {
      return loginStub!(mobile, motherName);
    }
    throw UnimplementedError();
  }
}

void main() {
  late Login usecase;
  late MockAuthRepository mockAuthRepository;

  setUp(() {
    mockAuthRepository = MockAuthRepository();
    usecase = Login(mockAuthRepository);
  });

  const tMobile = '1234567890';
  const tMotherName = 'testMotherName';
  const tUser = User(
    id: '1',
    name: 'Test User',
    mobile: tMobile,
    motherName: tMotherName,
    role: 'delegate',
  );

  test(
    'should get user from the repository',
    () async {
      // arrange
      mockAuthRepository.loginStub = (_, _) async => const Right(tUser);
      // act
      final result = await usecase(const LoginParams(mobile: tMobile, motherName: tMotherName));
      // assert
      expect(result, const Right(tUser));
      expect(mockAuthRepository.loginCallCount, 1);
      expect(mockAuthRepository.lastMobile, tMobile);
      expect(mockAuthRepository.lastMotherName, tMotherName);
    },
  );

  test(
    'should return failure when the call to repository is unsuccessful',
    () async {
      // arrange
      const tFailure = ServerFailure('Server Failure');
      mockAuthRepository.loginStub = (_, _) async => const Left(tFailure);
      // act
      final result = await usecase(const LoginParams(mobile: tMobile, motherName: tMotherName));
      // assert
      expect(result, const Left(tFailure));
      expect(mockAuthRepository.loginCallCount, 1);
      expect(mockAuthRepository.lastMobile, tMobile);
      expect(mockAuthRepository.lastMotherName, tMotherName);
    },
  );
}
