import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/domain/usecases/get_delegate_profile.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockGetDelegateProfile extends Mock implements GetDelegateProfile {}

class FakeGetDelegateProfileParams extends Fake
    implements GetDelegateProfileParams {}

void main() {
  late ProfileBloc bloc;
  late MockGetDelegateProfile mockGetDelegateProfile;

  final tDelegate = Delegate(
    uid: 'user-1',
    firstName: 'أحمد',
    middleName: 'محمد',
    lastName: 'علي',
    fullName: 'أحمد محمد علي',
    nationalityID: '29901011234567',
    motherName: 'فاطمة',
    city: 'القاهرة',
    phoneNumber: '01234567890',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1999, 1, 1),
    organizationUID: 'org-1',
    organizationName: 'المنظمة',
    companyUID: 'comp-1',
    companyName: 'الشركة',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-001',
    allReceiptCodes: const ['RC-001', 'RC-002'],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'admin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: true,
    isProfileComplete: true,
    numberOfDocuments: 3,
    paymentAmount: 500,
    version: 2,
    documents: const [],
  );

  setUpAll(() {
    registerFallbackValue(FakeGetDelegateProfileParams());
  });

  setUp(() {
    mockGetDelegateProfile = MockGetDelegateProfile();
    bloc = ProfileBloc(getDelegateProfile: mockGetDelegateProfile);
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be ProfileInitial', () {
    expect(bloc.state, ProfileInitial());
  });

  group('LoadProfile', () {
    blocTest<ProfileBloc, ProfileState>(
      'emits [ProfileLoading, ProfileLoaded] when profile loads successfully',
      build: () {
        when(
          () => mockGetDelegateProfile(any()),
        ).thenAnswer((_) async => Right(tDelegate));
        return bloc;
      },
      act: (bloc) => bloc.add(const LoadProfile(uid: 'user-1')),
      expect: () => [ProfileLoading(), ProfileLoaded(delegate: tDelegate)],
      verify: (_) {
        verify(() => mockGetDelegateProfile(any())).called(1);
      },
    );

    blocTest<ProfileBloc, ProfileState>(
      'emits [ProfileLoading, ProfileError] when profile fails to load',
      build: () {
        when(() => mockGetDelegateProfile(any())).thenAnswer(
          (_) async => const Left(ServerFailure('فشل تحميل الملف الشخصي')),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(const LoadProfile(uid: 'user-1')),
      expect: () => [
        ProfileLoading(),
        const ProfileError(message: 'فشل تحميل الملف الشخصي'),
      ],
    );

    blocTest<ProfileBloc, ProfileState>(
      'emits [ProfileLoading, ProfileError] when network error occurs',
      build: () {
        when(() => mockGetDelegateProfile(any())).thenAnswer(
          (_) async => const Left(
            ServerFailure('فشل في الاتصال بقاعدة البيانات. حاول مرة أخرى.'),
          ),
        );
        return bloc;
      },
      act: (bloc) => bloc.add(const LoadProfile(uid: 'invalid-uid')),
      expect: () => [
        ProfileLoading(),
        const ProfileError(
          message: 'فشل في الاتصال بقاعدة البيانات. حاول مرة أخرى.',
        ),
      ],
    );
  });
}
