import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_event.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class MockGetCompanyDelegates extends Mock implements GetCompanyDelegates {}
class FakeGetCompanyDelegatesParams extends Fake implements GetCompanyDelegatesParams {}

void main() {
  setUpAll(() {
    registerFallbackValue(FakeGetCompanyDelegatesParams());
  });

  late AdminDelegatesBloc bloc;
  late MockGetCompanyDelegates mockGetCompanyDelegates;

  setUp(() {
    AdminDelegatesBloc.clearCache();
    mockGetCompanyDelegates = MockGetCompanyDelegates();
    bloc = AdminDelegatesBloc(
      getCompanyDelegates: mockGetCompanyDelegates,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be AdminDelegatesInitial', () {
    expect(bloc.state, isA<AdminDelegatesInitial>());
  });

  final tDelegate = Delegate(
    uid: 'del-1',
    firstName: 'مندوب',
    middleName: 'أحمد',
    lastName: 'علي',
    fullName: 'مندوب أحمد علي',
    nationalityID: '12345678901234',
    motherName: 'فاطمة',
    city: 'القاهرة',
    phoneNumber: '01000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.supervisor,
    birthDate: DateTime(1995, 1, 1),
    organizationUID: 'org-1',
    organizationName: 'المنظمة الأولى',
    companyUID: 'comp-1',
    companyName: 'الشركة الأولى',
    status: DelegateStatus.active,
    delegatePublicId: 'DEL-001',
    allReceiptCodes: const ['REC-001'],
    createdAt: DateTime(2024, 1, 1),
    createdBy: 'admin-1',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 1,
    paymentAmount: 100,
    version: 1,
    documents: const [],
  );

  final tDelegatesList = [tDelegate];

  blocTest<AdminDelegatesBloc, AdminDelegatesState>(
    'emits [AdminDelegatesLoading, AdminDelegatesLoaded] when LoadCompanyDelegates succeeds',
    build: () {
      when(() => mockGetCompanyDelegates(any()))
          .thenAnswer((_) async => Right(CompanyDelegatesResult(delegates: tDelegatesList)));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadCompanyDelegates(
      organizationUID: 'org-1',
      companyUID: 'comp-1',
    )),
    expect: () => [
      isA<AdminDelegatesLoading>(),
      isA<AdminDelegatesLoaded>().having(
        (state) => state.delegates,
        'delegates',
        tDelegatesList,
      ),
    ],
  );

  blocTest<AdminDelegatesBloc, AdminDelegatesState>(
    'emits [AdminDelegatesLoading, AdminDelegatesError] when LoadCompanyDelegates fails',
    build: () {
      when(() => mockGetCompanyDelegates(any()))
          .thenAnswer((_) async => const Left(ServerFailure('فشل التحميل')));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadCompanyDelegates(
      organizationUID: 'org-1',
      companyUID: 'comp-1',
    )),
    expect: () => [
      isA<AdminDelegatesLoading>(),
      isA<AdminDelegatesError>().having(
        (state) => state.message,
        'message',
        'فشل التحميل',
      ),
    ],
  );
}
