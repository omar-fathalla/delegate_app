import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAuthRepository implements AuthRepository {
  Future<Either<Failure, List<Delegate>>> Function(String)? getDelegatesByPhoneStub;
  Future<Either<Failure, void>> Function(Delegate)? cacheDelegateStub;
  Future<Either<Failure, void>> Function(List<Delegate>)? cacheAllDelegatesStub;

  int getDelegatesByPhoneCallCount = 0;
  int cacheDelegateCallCount = 0;
  int cacheAllDelegatesCallCount = 0;
  String? lastPhone;
  Delegate? lastCachedDelegate;
  List<Delegate>? lastCachedAllDelegates;

  @override
  Future<Either<Failure, List<Delegate>>> getDelegatesByPhone(
    String phoneNumber,
  ) async {
    getDelegatesByPhoneCallCount++;
    lastPhone = phoneNumber;
    if (getDelegatesByPhoneStub != null) {
      return getDelegatesByPhoneStub!(phoneNumber);
    }
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, void>> cacheDelegate(Delegate delegate) async {
    cacheDelegateCallCount++;
    lastCachedDelegate = delegate;
    if (cacheDelegateStub != null) {
      return cacheDelegateStub!(delegate);
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> cacheAllDelegates(
    List<Delegate> delegates,
  ) async {
    cacheAllDelegatesCallCount++;
    lastCachedAllDelegates = delegates;
    if (cacheAllDelegatesStub != null) {
      return cacheAllDelegatesStub!(delegates);
    }
    return const Right(null);
  }

  @override
  Future<Either<Failure, void>> clearCache() async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, Delegate?>> getCachedDelegate() async {
    throw UnimplementedError();
  }

  @override
  Future<Either<Failure, List<Delegate>>> getCachedAllDelegates() async {
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
  const tPassword =
      'nationalId123'; // Password matches nationalityID for success

  final tDelegate = Delegate(
    uid: '1',
    firstName: 'Test',
    middleName: 'User',
    lastName: 'Name',
    fullName: 'Test User Name',
    nationalityID: tPassword, // Matches password
    motherName: 'Mother Name',
    city: 'City',
    phoneNumber: tMobile,
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org1',
    organizationName: 'Org Name',
    companyUID: 'comp1',
    companyName: 'Comp Name',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-123',
    allReceiptCodes: const [],
    createdAt: DateTime.now(),
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

  test(
    'should return list of delegates when phoneNumber exists and password matches nationalityID',
    () async {
      // arrange
      mockAuthRepository.getDelegatesByPhoneStub =
          (_) async => Right([tDelegate]);
      // act
      final result = await usecase(
        const LoginParams(
          phoneNumber: tMobile,
          password: tPassword,
          rememberMe: true,
        ),
      );
      // assert
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Should be right'),
        (r) => expect(r, [tDelegate]),
      );
      expect(mockAuthRepository.getDelegatesByPhoneCallCount, 1);
      expect(
        mockAuthRepository.cacheDelegateCallCount,
        1,
      ); // rememberMe is true and only one delegate
    },
  );

  test(
    'should return AuthFailure when password does not match nationalityID',
    () async {
      // arrange
      mockAuthRepository.getDelegatesByPhoneStub =
          (_) async => Right([tDelegate]);
      // act
      final result = await usecase(
        const LoginParams(phoneNumber: tMobile, password: 'wrongPassword'),
      );
      // assert
      expect(result, const Left(AuthFailure('كلمة المرور غير صحيحة')));
      expect(mockAuthRepository.getDelegatesByPhoneCallCount, 1);
      expect(mockAuthRepository.cacheDelegateCallCount, 0);
    },
  );

  test('should return failure when repository fails to get delegate', () async {
    // arrange
    const tFailure = ServerFailure('Server Failure');
    mockAuthRepository.getDelegatesByPhoneStub = (_) async =>
        const Left(tFailure);
    // act
    final result = await usecase(
      const LoginParams(phoneNumber: tMobile, password: tPassword),
    );
    // assert
    expect(result, const Left(tFailure));
    expect(mockAuthRepository.getDelegatesByPhoneCallCount, 1);
  });

  group('User provided test cases', () {
    test('Admin login with exactly 01508899965 and 4816361Aa', () async {
      final adminDelegate = Delegate(
        uid: '1',
        firstName: 'Test',
        middleName: 'User',
        lastName: 'Name',
        fullName: 'Test User Name',
        nationalityID: '4816361Aa',
        motherName: 'Mother Name',
        city: 'City',
        phoneNumber: '01508899965',
        gender: DelegateGender.male,
        position: DelegatePosition.supervisor,
        birthDate: DateTime(1990, 1, 1),
        organizationUID: 'org1',
        organizationName: 'Org Name',
        companyUID: 'comp1',
        companyName: 'Comp Name',
        status: DelegateStatus.active,
        delegatePublicId: 'DEL-123',
        allReceiptCodes: const [],
        createdAt: DateTime.now(),
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

      mockAuthRepository.getDelegatesByPhoneStub = (_) async =>
          Right([adminDelegate]);

      final result = await usecase(
        const LoginParams(phoneNumber: '01508899965', password: '4816361Aa'),
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Should be right'),
        (r) => expect(r.first.position, DelegatePosition.supervisor),
      );
    });

    test('Delegate login with 01281769997 and 29712200201981', () async {
      final promoterDelegate = Delegate(
        uid: '1',
        firstName: 'Test',
        middleName: 'User',
        lastName: 'Name',
        fullName: 'Test User Name',
        nationalityID: '29712200201981',
        motherName: 'Mother Name',
        city: 'City',
        phoneNumber: '01281769997',
        gender: DelegateGender.male,
        position: DelegatePosition.promoter,
        birthDate: DateTime(1990, 1, 1),
        organizationUID: 'org1',
        organizationName: 'Org Name',
        companyUID: 'comp1',
        companyName: 'Comp Name',
        status: DelegateStatus.active,
        delegatePublicId: 'DEL-123',
        allReceiptCodes: const [],
        createdAt: DateTime.now(),
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

      mockAuthRepository.getDelegatesByPhoneStub = (_) async =>
          Right([promoterDelegate]);

      final result = await usecase(
        const LoginParams(
          phoneNumber: '01281769997',
          password: '29712200201981',
        ),
      );

      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Should be right'),
        (r) => expect(r.first.position, DelegatePosition.promoter),
      );
    });
  });
}
