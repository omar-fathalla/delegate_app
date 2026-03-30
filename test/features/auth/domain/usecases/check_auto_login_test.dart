import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

void main() {
  late CheckAutoLogin usecase;
  late MockAuthRepository mockRepository;

  setUp(() {
    mockRepository = MockAuthRepository();
    usecase = CheckAutoLogin(mockRepository);
  });

  final tDelegate = Delegate(
    uid: '1',
    firstName: 'Test',
    middleName: 'User',
    lastName: 'Name',
    fullName: 'Test User Name',
    nationalityID: 'nat123',
    motherName: 'Mother',
    city: 'Cairo',
    phoneNumber: '01234567890',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org1',
    organizationName: 'Org',
    companyUID: 'comp1',
    companyName: 'Company',
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

  test('should return cached delegate when available', () async {
    // arrange
    when(
      () => mockRepository.getCachedDelegate(),
    ).thenAnswer((_) async => Right(tDelegate));
    // act
    final result = await usecase(NoParams());
    // assert
    expect(result, Right(tDelegate));
    verify(() => mockRepository.getCachedDelegate()).called(1);
  });

  test('should return null when no cached delegate', () async {
    // arrange
    when(
      () => mockRepository.getCachedDelegate(),
    ).thenAnswer((_) async => const Right(null));
    // act
    final result = await usecase(NoParams());
    // assert
    expect(result, const Right(null));
    verify(() => mockRepository.getCachedDelegate()).called(1);
  });

  test('should return failure when getCachedDelegate fails', () async {
    // arrange
    when(() => mockRepository.getCachedDelegate()).thenAnswer(
      (_) async => const Left(CacheFailure('فشل جلب البيانات المحفوظة')),
    );
    // act
    final result = await usecase(NoParams());
    // assert
    expect(result, const Left(CacheFailure('فشل جلب البيانات المحفوظة')));
  });
}
