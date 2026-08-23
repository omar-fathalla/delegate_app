import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/photo_permission/domain/repositories/photo_permission_repository.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_photo_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPhotoPermissionRepository extends Mock
    implements PhotoPermissionRepository {}

void main() {
  late DeletePhotoPermission usecase;
  late MockPhotoPermissionRepository mockRepository;

  setUp(() {
    mockRepository = MockPhotoPermissionRepository();
    usecase = DeletePhotoPermission(mockRepository);
  });

  const tParams = DeletePhotoPermissionParams(
    organizationUID: 'org_uid',
    companyUID: 'company_uid',
    permissionId: 'perm_id',
  );

  test('should call deletePermission on repository and return Right(null) when successful', () async {
    when(() => mockRepository.deletePermission(
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
          permissionId: any(named: 'permissionId'),
        )).thenAnswer((_) async => const Right(null));

    final result = await usecase(tParams);

    expect(result, const Right(null));
    verify(() => mockRepository.deletePermission(
          organizationUID: 'org_uid',
          companyUID: 'company_uid',
          permissionId: 'perm_id',
        )).called(1);
    verifyNoMoreInteractions(mockRepository);
  });

  test('should return ServerFailure when repository call fails', () async {
    when(() => mockRepository.deletePermission(
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
          permissionId: any(named: 'permissionId'),
        )).thenAnswer((_) async => const Left(ServerFailure('Error')));

    final result = await usecase(tParams);

    expect(result, const Left(ServerFailure('Error')));
    verify(() => mockRepository.deletePermission(
          organizationUID: 'org_uid',
          companyUID: 'company_uid',
          permissionId: 'perm_id',
        )).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
