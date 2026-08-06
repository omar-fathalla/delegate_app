import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/repositories/photo_permission_repository.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_photo_permissions.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPhotoPermissionRepository extends Mock
    implements PhotoPermissionRepository {}

void main() {
  late GetPhotoPermissions usecase;
  late MockPhotoPermissionRepository mockRepository;

  setUp(() {
    mockRepository = MockPhotoPermissionRepository();
    usecase = GetPhotoPermissions(mockRepository);
  });

  final tDate = DateTime(2023, 1, 1);
  final tModel = PhotoPermission(
    uid: 'test_uid',
    organizationUID: 'org_uid',
    companyUID: 'company_uid',
    companyName: 'Company',
    companyCode: 123,
    branchIds: const ['b1'],
    branchNames: const ['Branch 1'],
    startDate: tDate,
    endDate: tDate,
    status: 'pending',
    requestedBy: 'user_1',
    createdAt: tDate,
    updatedAt: tDate,
    isSupervisorEnabled: true,
  );
  final tModels = [tModel];

  final tParams = GetPhotoPermissionsParams(
    organizationUID: 'org_uid',
    companyUID: 'company_uid',
  );

  test('should get list of PhotoPermission from repository', () async {
    when(() => mockRepository.getPermissions(
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
        )).thenAnswer((_) async => Right(tModels));

    final result = await usecase(tParams);

    expect(result, Right<Failure, List<PhotoPermission>>(tModels));
    verify(() => mockRepository.getPermissions(
          organizationUID: 'org_uid',
          companyUID: 'company_uid',
        )).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
