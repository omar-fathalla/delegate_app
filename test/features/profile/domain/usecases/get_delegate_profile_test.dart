import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:delegate_app/features/profile/domain/usecases/get_delegate_profile.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockProfileRepository extends Mock implements ProfileRepository {}

void main() {
  late GetDelegateProfile usecase;
  late MockProfileRepository mockRepository;

  setUp(() {
    mockRepository = MockProfileRepository();
    usecase = GetDelegateProfile(mockRepository);
  });

  const tUid = 'user-123';

  final tDelegate = Delegate(
    uid: tUid,
    firstName: 'أحمد',
    middleName: 'محمد',
    lastName: 'علي',
    fullName: 'أحمد محمد علي',
    nationalityID: 'nat123',
    motherName: 'فاطمة',
    city: 'القاهرة',
    phoneNumber: '01234567890',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1995, 6, 15),
    organizationUID: 'org1',
    organizationName: 'المنظمة',
    companyUID: 'comp1',
    companyName: 'الشركة',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-456',
    allReceiptCodes: const ['REC-001', 'REC-002'],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 3,
    paymentAmount: 500,
    version: 1,
    documents: const [],
  );

  test('should return delegate profile from repository', () async {
    // arrange
    when(() => mockRepository.getDelegateProfile(any()))
        .thenAnswer((_) async => Right(tDelegate));

    // act
    final result = await usecase(
      const GetDelegateProfileParams(uid: tUid),
    );

    // assert
    expect(result, Right(tDelegate));
    verify(() => mockRepository.getDelegateProfile(tUid)).called(1);
  });

  test('should return failure when repository fails', () async {
    // arrange
    const tFailure = ServerFailure('فشل جلب الملف الشخصي');
    when(() => mockRepository.getDelegateProfile(any()))
        .thenAnswer((_) async => const Left(tFailure));

    // act
    final result = await usecase(
      const GetDelegateProfileParams(uid: tUid),
    );

    // assert
    expect(result, const Left(tFailure));
  });

  test('should return network failure on connection error', () async {
    // arrange
    const tFailure = NetworkFailure('لا يوجد اتصال بالإنترنت');
    when(() => mockRepository.getDelegateProfile(any()))
        .thenAnswer((_) async => const Left(tFailure));

    // act
    final result = await usecase(
      const GetDelegateProfileParams(uid: tUid),
    );

    // assert
    expect(result, const Left(tFailure));
  });

  test('GetDelegateProfileParams props should contain uid', () {
    const params = GetDelegateProfileParams(uid: tUid);
    expect(params.props, [tUid]);
  });
}
