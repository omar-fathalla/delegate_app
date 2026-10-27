import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:flutter_test/flutter_test.dart';

class MockAuthRepository implements AuthRepository {
  Future<Either<Failure, List<Delegate>>> Function(String)?
    getDelegatesByPhoneStub;
  Future<Either<Failure, List<Delegate>>> Function(String, String)?
    loginDelegateStub;
  Future<Either<Failure, void>> Function(Delegate)? cacheDelegateStub;
  Future<Either<Failure, void>> Function(List<Delegate>)? cacheAllDelegatesStub;
  Future<Either<Failure, bool>> Function(String, String)?
  verifyAdminPasswordStub;
  Future<Either<Failure, bool>> Function(String, String)?
  verifyPhonePasswordStub;

  int getDelegatesByPhoneCallCount = 0;
  int loginDelegateCallCount = 0;
  int cacheDelegateCallCount = 0;
  int cacheAllDelegatesCallCount = 0;
  String? lastPhone;
  String? lastNationalId;
  Delegate? lastCachedDelegate;
  List<Delegate>? lastCachedAllDelegates;

  @override
  Future<Either<Failure, List<Delegate>>> loginDelegate({
    required String phoneNumber,
    required String nationalId,
  }) async {
    loginDelegateCallCount++;
    lastPhone = phoneNumber;
    lastNationalId = nationalId;
    if (loginDelegateStub != null) {
      return loginDelegateStub!(phoneNumber, nationalId);
    }
    return const Left(
      DelegateCredentialsFailure('رقم الهاتف أو الرقم القومي غير صحيح'),
    );
  }

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
  Future<Either<Failure, void>> logout({String? userId}) async {
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

  @override
  Future<Either<Failure, bool>> verifyAdminPassword(
    String email,
    String password,
  ) async {
    if (verifyAdminPasswordStub != null) {
      return verifyAdminPasswordStub!(email, password);
    }
    return const Right(false);
  }

  @override
  Future<Either<Failure, bool>> verifyPhonePassword(
    String phone,
    String password,
  ) async {
    if (verifyPhonePasswordStub != null) {
      return verifyPhonePasswordStub!(phone, password);
    }
    return const Right(false);
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
    'should return delegates from the server login and skip the anonymous lookup',
    () async {
      mockAuthRepository.loginDelegateStub = (_, _) async => Right([tDelegate]);
      final result = await usecase(
        const LoginParams(
          phoneNumber: tMobile,
          password: tPassword,
          rememberMe: true,
        ),
      );
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Should be right'),
        (r) => expect(r, [tDelegate]),
      );
      expect(mockAuthRepository.loginDelegateCallCount, 1);
      expect(mockAuthRepository.lastNationalId, tPassword);
      expect(mockAuthRepository.getDelegatesByPhoneCallCount, 0);
      expect(mockAuthRepository.cacheDelegateCallCount, 1);
    },
  );

  test(
    'should not accept a client-side national ID match after the server rejects it',
    () async {
      mockAuthRepository.loginDelegateStub = (_, _) async => const Left(
        DelegateCredentialsFailure('رقم الهاتف أو الرقم القومي غير صحيح'),
      );
      mockAuthRepository.getDelegatesByPhoneStub = (_) async =>
          Right([tDelegate]);
      final result = await usecase(
        const LoginParams(phoneNumber: tMobile, password: tPassword),
      );
      expect(result, isA<Left<Failure, List<Delegate>>>());
      result.fold((failure) {
        expect(failure, isA<AuthFailure>());
        expect((failure as AuthFailure).code, 'invalid_credentials');
      }, (_) => fail('national ID must not be compared on the client'));
      expect(mockAuthRepository.getDelegatesByPhoneCallCount, 1);
      expect(mockAuthRepository.cacheDelegateCallCount, 0);
    },
  );

  test('should not fall back to staff login when the delegate account is inactive', () async {
    mockAuthRepository.loginDelegateStub = (_, _) async => const Left(
      DelegateAccountInactiveFailure('inactive'),
    );
    final result = await usecase(
      const LoginParams(phoneNumber: tMobile, password: tPassword),
    );
    expect(result, isA<Left<Failure, List<Delegate>>>());
    result.fold(
      (failure) => expect(failure, isA<DelegateAccountInactiveFailure>()),
      (_) => fail('inactive delegate must not sign in'),
    );
    expect(mockAuthRepository.getDelegatesByPhoneCallCount, 0);
  });

  test('should not fall back to staff login when the device does not match', () async {
    mockAuthRepository.loginDelegateStub = (_, _) async => const Left(
      AuthFailure(
        'هذا الحساب مقترن بجهاز آخر. تم إرسال طلب تغيير الجهاز إلى إدارة الشركة.',
        'device_mismatch',
      ),
    );
    final result = await usecase(
      const LoginParams(phoneNumber: tMobile, password: tPassword),
    );
    expect(result, isA<Left<Failure, List<Delegate>>>());
    result.fold(
      (failure) => expect((failure as AuthFailure).code, 'device_mismatch'),
      (_) => fail('a mismatched device must not sign in'),
    );
    expect(mockAuthRepository.getDelegatesByPhoneCallCount, 0);
  });

  test('should return failure when delegate login fails before staff lookup', () async {
    const tFailure = ServerFailure('Server Failure');
    mockAuthRepository.loginDelegateStub = (_, _) async => const Left(tFailure);
    final result = await usecase(
      const LoginParams(phoneNumber: tMobile, password: tPassword),
    );
    expect(result, const Left(tFailure));
    expect(mockAuthRepository.loginDelegateCallCount, 1);
    expect(mockAuthRepository.getDelegatesByPhoneCallCount, 0);
  });

  group('User provided test cases', () {
    test('staff login verifies the looked-up email with Firebase Auth', () async {
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

      final staffDelegate = Delegate(
        uid: adminDelegate.uid,
        firstName: adminDelegate.firstName,
        middleName: adminDelegate.middleName,
        lastName: adminDelegate.lastName,
        fullName: adminDelegate.fullName,
        nationalityID: '__firebase_auth__:staff@example.com',
        email: 'staff@example.com',
        motherName: adminDelegate.motherName,
        city: adminDelegate.city,
        phoneNumber: adminDelegate.phoneNumber,
        gender: adminDelegate.gender,
        position: adminDelegate.position,
        birthDate: adminDelegate.birthDate,
        organizationUID: adminDelegate.organizationUID,
        organizationName: adminDelegate.organizationName,
        companyUID: adminDelegate.companyUID,
        companyName: adminDelegate.companyName,
        status: adminDelegate.status,
        delegatePublicId: adminDelegate.delegatePublicId,
        allReceiptCodes: adminDelegate.allReceiptCodes,
        createdAt: adminDelegate.createdAt,
        createdBy: adminDelegate.createdBy,
        hasPendingUpdate: adminDelegate.hasPendingUpdate,
        isDeductedFromCompany: adminDelegate.isDeductedFromCompany,
        isPrinted: adminDelegate.isPrinted,
        isProfileComplete: adminDelegate.isProfileComplete,
        numberOfDocuments: adminDelegate.numberOfDocuments,
        paymentAmount: adminDelegate.paymentAmount,
        version: adminDelegate.version,
        documents: adminDelegate.documents,
        role: UserRole.superAdmin,
      );
      mockAuthRepository.loginDelegateStub = (_, _) async => const Left(
        DelegateCredentialsFailure('not a delegate'),
      );
      mockAuthRepository.getDelegatesByPhoneStub = (_) async =>
          Right([staffDelegate]);
      String? verifiedEmail;
      String? verifiedPassword;
      mockAuthRepository.verifyAdminPasswordStub = (email, password) async {
        verifiedEmail = email;
        verifiedPassword = password;
        return Right(password == 'correct-password');
      };

      final result = await usecase(
        const LoginParams(
          phoneNumber: '01500000000',
          password: 'correct-password',
        ),
      );

      expect(verifiedEmail, 'staff@example.com');
      expect(verifiedPassword, 'correct-password');
      expect(result.isRight(), isTrue);
      result.fold(
        (l) => fail('Should be right'),
        (r) => expect(r.first.role, UserRole.superAdmin),
      );

      final denied = await usecase(
        const LoginParams(
          phoneNumber: '01500000000',
          password: 'wrong-password',
        ),
      );
      expect(denied.isLeft(), isTrue);
      denied.fold(
        (failure) {
          expect(failure, isA<AuthFailure>());
          expect((failure as AuthFailure).code, 'invalid_credentials');
        },
        (_) => fail('wrong password must not sign in'),
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

      mockAuthRepository.loginDelegateStub = (_, _) async =>
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
