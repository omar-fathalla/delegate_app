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
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

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
  });
}
