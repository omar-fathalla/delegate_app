import 'package:bloc_test/bloc_test.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/request_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/approve_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/toggle_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_photo_permissions.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_ongoing_photo_permissions.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/upload_captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_delegate_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_company_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/update_photo_permission_branches.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/update_photo_permission_dates.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockRequestPhotoPermission extends Mock implements RequestPhotoPermission {}
class MockApprovePhotoPermission extends Mock implements ApprovePhotoPermission {}
class MockTogglePhotoPermission extends Mock implements TogglePhotoPermission {}
class MockGetPhotoPermissions extends Mock implements GetPhotoPermissions {}
class MockGetOngoingPhotoPermissions extends Mock implements GetOngoingPhotoPermissions {}
class MockUploadCapturedPhoto extends Mock implements UploadCapturedPhoto {}
class MockGetCapturedPhotos extends Mock implements GetCapturedPhotos {}
class MockGetDelegateCapturedPhotos extends Mock implements GetDelegateCapturedPhotos {}
class MockGetCompanyCapturedPhotos extends Mock implements GetCompanyCapturedPhotos {}
class MockDeleteCapturedPhoto extends Mock implements DeleteCapturedPhoto {}
class MockDeletePhotoPermission extends Mock implements DeletePhotoPermission {}
class MockUpdatePhotoPermissionBranches extends Mock implements UpdatePhotoPermissionBranches {}
class MockUpdatePhotoPermissionDates extends Mock implements UpdatePhotoPermissionDates {}

class FakeRequestPhotoPermissionParams extends Fake implements RequestPhotoPermissionParams {}
class FakeApprovePhotoPermissionParams extends Fake implements ApprovePhotoPermissionParams {}
class FakeTogglePhotoPermissionParams extends Fake implements TogglePhotoPermissionParams {}
class FakeGetPhotoPermissionsParams extends Fake implements GetPhotoPermissionsParams {}
class FakeGetOngoingPhotoPermissionsParams extends Fake implements GetOngoingPhotoPermissionsParams {}
class FakeUploadCapturedPhotoParams extends Fake implements UploadCapturedPhotoParams {}
class FakeGetCapturedPhotosParams extends Fake implements GetCapturedPhotosParams {}
class FakeGetDelegateCapturedPhotosParams extends Fake implements GetDelegateCapturedPhotosParams {}
class FakeGetCompanyCapturedPhotosParams extends Fake implements GetCompanyCapturedPhotosParams {}
class FakeDeleteCapturedPhotoParams extends Fake implements DeleteCapturedPhotoParams {}
class FakeDeletePhotoPermissionParams extends Fake implements DeletePhotoPermissionParams {}
class FakeUpdatePhotoPermissionBranchesParams extends Fake implements UpdatePhotoPermissionBranchesParams {}
class FakeUpdatePhotoPermissionDatesParams extends Fake implements UpdatePhotoPermissionDatesParams {}

void main() {
  late PhotoPermissionBloc bloc;
  late MockRequestPhotoPermission mockRequestPhotoPermission;
  late MockApprovePhotoPermission mockApprovePhotoPermission;
  late MockTogglePhotoPermission mockTogglePhotoPermission;
  late MockGetPhotoPermissions mockGetPhotoPermissions;
  late MockGetOngoingPhotoPermissions mockGetOngoingPhotoPermissions;
  late MockUploadCapturedPhoto mockUploadCapturedPhoto;
  late MockGetCapturedPhotos mockGetCapturedPhotos;
  late MockGetDelegateCapturedPhotos mockGetDelegateCapturedPhotos;
  late MockGetCompanyCapturedPhotos mockGetCompanyCapturedPhotos;
  late MockDeleteCapturedPhoto mockDeleteCapturedPhoto;
  late MockDeletePhotoPermission mockDeletePhotoPermission;
  late MockUpdatePhotoPermissionBranches mockUpdatePhotoPermissionBranches;
  late MockUpdatePhotoPermissionDates mockUpdatePhotoPermissionDates;

  setUpAll(() {
    registerFallbackValue(FakeRequestPhotoPermissionParams());
    registerFallbackValue(FakeApprovePhotoPermissionParams());
    registerFallbackValue(FakeTogglePhotoPermissionParams());
    registerFallbackValue(FakeGetPhotoPermissionsParams());
    registerFallbackValue(FakeGetOngoingPhotoPermissionsParams());
    registerFallbackValue(FakeUploadCapturedPhotoParams());
    registerFallbackValue(FakeGetCapturedPhotosParams());
    registerFallbackValue(FakeGetDelegateCapturedPhotosParams());
    registerFallbackValue(FakeGetCompanyCapturedPhotosParams());
    registerFallbackValue(FakeDeleteCapturedPhotoParams());
    registerFallbackValue(FakeDeletePhotoPermissionParams());
    registerFallbackValue(FakeUpdatePhotoPermissionBranchesParams());
    registerFallbackValue(FakeUpdatePhotoPermissionDatesParams());
  });

  setUp(() {
    mockRequestPhotoPermission = MockRequestPhotoPermission();
    mockApprovePhotoPermission = MockApprovePhotoPermission();
    mockTogglePhotoPermission = MockTogglePhotoPermission();
    mockGetPhotoPermissions = MockGetPhotoPermissions();
    mockGetOngoingPhotoPermissions = MockGetOngoingPhotoPermissions();
    mockUploadCapturedPhoto = MockUploadCapturedPhoto();
    mockGetCapturedPhotos = MockGetCapturedPhotos();
    mockGetDelegateCapturedPhotos = MockGetDelegateCapturedPhotos();
    mockGetCompanyCapturedPhotos = MockGetCompanyCapturedPhotos();
    mockDeleteCapturedPhoto = MockDeleteCapturedPhoto();
    mockDeletePhotoPermission = MockDeletePhotoPermission();
    mockUpdatePhotoPermissionBranches = MockUpdatePhotoPermissionBranches();
    mockUpdatePhotoPermissionDates = MockUpdatePhotoPermissionDates();

    bloc = PhotoPermissionBloc(
      requestPhotoPermission: mockRequestPhotoPermission,
      approvePhotoPermission: mockApprovePhotoPermission,
      togglePhotoPermission: mockTogglePhotoPermission,
      getPhotoPermissions: mockGetPhotoPermissions,
      getOngoingPhotoPermissions: mockGetOngoingPhotoPermissions,
      uploadCapturedPhoto: mockUploadCapturedPhoto,
      getCapturedPhotos: mockGetCapturedPhotos,
      getDelegateCapturedPhotos: mockGetDelegateCapturedPhotos,
      getCompanyCapturedPhotos: mockGetCompanyCapturedPhotos,
      deleteCapturedPhoto: mockDeleteCapturedPhoto,
      deletePhotoPermission: mockDeletePhotoPermission,
      updatePhotoPermissionBranches: mockUpdatePhotoPermissionBranches,
      updatePhotoPermissionDates: mockUpdatePhotoPermissionDates,
    );
  });

  final tPermission = PhotoPermission(
    uid: 'perm123',
    organizationUID: 'org123',
    companyUID: 'comp123',
    companyName: 'Test Company',
    companyCode: 99,
    branchIds: const ['b1', 'b2'],
    branchNames: const ['Branch 1', 'Branch 2'],
    startDate: DateTime(2026, 1, 1),
    endDate: DateTime(2026, 12, 31),
    status: 'pending',
    requestedBy: 'user1',
    isSupervisorEnabled: true,
    createdAt: DateTime(2026, 1, 1),
    updatedAt: DateTime(2026, 1, 1),
  );

  test('initial state should be PhotoPermissionInitial', () {
    expect(bloc.state, equals(PhotoPermissionInitial()));
  });

  group('RequestPermissionRequested', () {
    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, PermissionActionSuccess] when requesting permission succeeds',
      build: () {
        when(() => mockRequestPhotoPermission(any()))
            .thenAnswer((_) async => Right(tPermission));
        return bloc;
      },
      act: (bloc) => bloc.add(
        RequestPermissionRequested(
          organizationUID: 'org123',
          companyUID: 'comp123',
          companyName: 'Test Company',
          companyCode: 99,
          branchIds: const ['b1', 'b2'],
          branchNames: const ['Branch 1', 'Branch 2'],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          requestedBy: 'user1',
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        PermissionActionSuccess(
          permission: tPermission,
          message: 'تم إرسال طلب إذن التصوير بنجاح إلى إدارة التسويق.',
        ),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, PhotoPermissionError] when requesting permission fails',
      build: () {
        when(() => mockRequestPhotoPermission(any()))
            .thenAnswer((_) async => const Left(ServerFailure('Server Error')));
        return bloc;
      },
      act: (bloc) => bloc.add(
        RequestPermissionRequested(
          organizationUID: 'org123',
          companyUID: 'comp123',
          companyName: 'Test Company',
          companyCode: 99,
          branchIds: const ['b1', 'b2'],
          branchNames: const ['Branch 1', 'Branch 2'],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          requestedBy: 'user1',
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        const PhotoPermissionError(message: 'Server Error'),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, PhotoPermissionActionSuccess] when deleting photo permission succeeds',
      build: () {
        when(() => mockDeletePhotoPermission(any()))
            .thenAnswer((_) async => const Right(null));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const DeletePhotoPermissionRequested(
          organizationUID: 'org123',
          companyUID: 'comp123',
          permissionId: 'perm123',
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        const PhotoPermissionActionSuccess(message: 'تم حذف إذن التصوير بنجاح.'),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, PhotoPermissionError] when deleting photo permission fails',
      build: () {
        when(() => mockDeletePhotoPermission(any()))
            .thenAnswer((_) async => const Left(ServerFailure('Failed to delete')));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const DeletePhotoPermissionRequested(
          organizationUID: 'org123',
          companyUID: 'comp123',
          permissionId: 'perm123',
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        const PhotoPermissionError(message: 'Failed to delete'),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, PhotoPermissionActionSuccess] when updating permission dates succeeds',
      build: () {
        when(() => mockUpdatePhotoPermissionDates(any()))
            .thenAnswer((_) async => const Right(null));
        return bloc;
      },
      act: (bloc) => bloc.add(
        UpdatePhotoPermissionDatesRequested(
          organizationUID: 'org123',
          companyUID: 'comp123',
          permissionId: 'perm123',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 2, 1),
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        const PhotoPermissionActionSuccess(message: 'تم تعديل تاريخ صلاحية إذن التصوير بنجاح'),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, PhotoPermissionError] when updating permission dates fails',
      build: () {
        when(() => mockUpdatePhotoPermissionDates(any()))
            .thenAnswer((_) async => const Left(ServerFailure('Failed to update dates')));
        return bloc;
      },
      act: (bloc) => bloc.add(
        UpdatePhotoPermissionDatesRequested(
          organizationUID: 'org123',
          companyUID: 'comp123',
          permissionId: 'perm123',
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 2, 1),
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        const PhotoPermissionError(message: 'Failed to update dates'),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit [PhotoPermissionLoading, CapturedPhotosLoaded] when LoadCompanyCapturedPhotosRequested succeeds with branchName and limit',
      build: () {
        when(() => mockGetCompanyCapturedPhotos(any()))
            .thenAnswer((_) async => const Right([]));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const LoadCompanyCapturedPhotosRequested(
          companyUID: 'comp123',
          branchName: 'Gardenia',
          limit: 20,
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        const CapturedPhotosLoaded(photos: []),
      ],
      verify: (_) {
        verify(() => mockGetCompanyCapturedPhotos(
          const GetCompanyCapturedPhotosParams(
            companyUID: 'comp123',
            branchName: 'Gardenia',
            limit: 20,
          ),
        )).called(1);
      },
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should deduplicate permissions with identical companyUID and uid on LoadPermissionsRequested',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
      },
      build: () {
        when(() => mockGetPhotoPermissions(any()))
            .thenAnswer((_) async => Right([tPermission, tPermission]));
        return bloc;
      },
      act: (bloc) => bloc.add(
        const LoadPermissionsRequested(
          organizationUID: 'org_dedup',
          companyUID: 'comp123',
        ),
      ),
      expect: () => [
        PhotoPermissionLoading(),
        PhotoPermissionsLoaded(permissions: [tPermission]),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should emit cached permissions immediately without PhotoPermissionLoading on subsequent LoadPermissionsRequested (Stale-While-Revalidate)',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
      },
      build: () {
        final updatedPermission = PhotoPermission(
          uid: 'perm123',
          organizationUID: 'org_swr',
          companyUID: 'comp123',
          companyName: 'Updated Company',
          companyCode: 99,
          branchIds: const ['b1', 'b2'],
          branchNames: const ['Branch 1', 'Branch 2'],
          startDate: DateTime(2026, 1, 1),
          endDate: DateTime(2026, 12, 31),
          status: 'approved',
          requestedBy: 'user1',
          isSupervisorEnabled: true,
          createdAt: DateTime(2026, 1, 1),
          updatedAt: DateTime(2026, 1, 2),
        );
        var callCount = 0;
        when(() => mockGetPhotoPermissions(any())).thenAnswer((_) async {
          callCount++;
          return Right(callCount == 1 ? [tPermission] : [updatedPermission]);
        });
        return bloc;
      },
      act: (bloc) async {
        bloc.add(
          const LoadPermissionsRequested(
            organizationUID: 'org_swr',
            companyUID: 'comp123',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          const LoadPermissionsRequested(
            organizationUID: 'org_swr',
            companyUID: 'comp123',
          ),
        );
      },
      expect: () => [
        PhotoPermissionLoading(),
        PhotoPermissionsLoaded(permissions: [tPermission]),
        PhotoPermissionsLoaded(
          permissions: [
            PhotoPermission(
              uid: 'perm123',
              organizationUID: 'org_swr',
              companyUID: 'comp123',
              companyName: 'Updated Company',
              companyCode: 99,
              branchIds: const ['b1', 'b2'],
              branchNames: const ['Branch 1', 'Branch 2'],
              startDate: DateTime(2026, 1, 1),
              endDate: DateTime(2026, 12, 31),
              status: 'approved',
              requestedBy: 'user1',
              isSupervisorEnabled: true,
              createdAt: DateTime(2026, 1, 1),
              updatedAt: DateTime(2026, 1, 2),
            ),
          ],
        ),
      ],
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should optimistically update cached permission dates on UpdatePhotoPermissionDatesRequested so subsequent LoadPermissionsRequested emits updated dates immediately',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
      },
      build: () {
        var callCount = 0;
        when(() => mockGetPhotoPermissions(any())).thenAnswer((_) async {
          callCount++;
          if (callCount == 1) {
            return Right([tPermission]);
          }
          // Simulate slow network on second load so 0ms cache emit is distinct
          await Future<void>.delayed(const Duration(milliseconds: 30));
          return Right([
            PhotoPermission(
              uid: tPermission.uid,
              organizationUID: tPermission.organizationUID,
              companyUID: tPermission.companyUID,
              companyName: tPermission.companyName,
              companyCode: tPermission.companyCode,
              branchIds: tPermission.branchIds,
              branchNames: tPermission.branchNames,
              startDate: DateTime(2026, 3, 1),
              endDate: DateTime(2026, 4, 1),
              status: tPermission.status,
              requestedBy: tPermission.requestedBy,
              isSupervisorEnabled: tPermission.isSupervisorEnabled,
              createdAt: tPermission.createdAt,
              updatedAt: tPermission.updatedAt,
            ),
          ]);
        });
        when(() => mockUpdatePhotoPermissionDates(any()))
            .thenAnswer((_) async => const Right(null));
        return bloc;
      },
      act: (bloc) async {
        bloc.add(
          const LoadPermissionsRequested(
            organizationUID: 'org_dates_cache',
            companyUID: 'comp123',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          UpdatePhotoPermissionDatesRequested(
            organizationUID: 'org123',
            companyUID: 'comp123',
            permissionId: 'perm123',
            startDate: DateTime(2026, 3, 1),
            endDate: DateTime(2026, 4, 1),
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          const LoadPermissionsRequested(
            organizationUID: 'org_dates_cache',
            companyUID: 'comp123',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 50));
      },
      verify: (bloc) {
        final state = bloc.state;
        expect(state, isA<PhotoPermissionsLoaded>());
        final loaded = state as PhotoPermissionsLoaded;
        expect(loaded.permissions.first.startDate, DateTime(2026, 3, 1));
        expect(loaded.permissions.first.endDate, DateTime(2026, 4, 1));
      },
    );

    blocTest<PhotoPermissionBloc, PhotoPermissionState>(
      'should optimistically update cached permission branches on UpdatePhotoPermissionBranchesRequested',
      setUp: () {
        SharedPreferences.setMockInitialValues({});
      },
      build: () {
        when(() => mockGetPhotoPermissions(any()))
            .thenAnswer((_) async => Right([tPermission]));
        when(() => mockUpdatePhotoPermissionBranches(any()))
            .thenAnswer((_) async => const Right(null));
        return bloc;
      },
      act: (bloc) async {
        bloc.add(
          const LoadPermissionsRequested(
            organizationUID: 'org_branches_cache',
            companyUID: 'comp123',
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
        bloc.add(
          const UpdatePhotoPermissionBranchesRequested(
            organizationUID: 'org123',
            companyUID: 'comp123',
            permissionId: 'perm123',
            branchIds: ['b1', 'b2', 'b3'],
            branchNames: ['Branch 1', 'Branch 2', 'Branch 3'],
          ),
        );
        await Future<void>.delayed(const Duration(milliseconds: 20));
      },
      expect: () => [
        PhotoPermissionLoading(),
        PhotoPermissionsLoaded(permissions: [tPermission]),
        PhotoPermissionLoading(),
        const PhotoPermissionActionSuccess(
          message: 'تم تعديل الفروع بنجاح',
        ),
      ],
    );
  });
}
