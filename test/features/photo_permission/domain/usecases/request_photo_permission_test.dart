import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/repositories/photo_permission_repository.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/request_photo_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPhotoPermissionRepository extends Mock
    implements PhotoPermissionRepository {}

void main() {
  late RequestPhotoPermission usecase;
  late MockPhotoPermissionRepository mockRepository;

  setUp(() {
    mockRepository = MockPhotoPermissionRepository();
    usecase = RequestPhotoPermission(mockRepository);
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

  final tParams = RequestPhotoPermissionParams(
    organizationUID: 'org_uid',
    companyUID: 'company_uid',
    companyName: 'Company',
    companyCode: 123,
    branchIds: const ['b1'],
    branchNames: const ['Branch 1'],
    startDate: tDate,
    endDate: tDate,
    requestedBy: 'user_1',
  );

  test('should request PhotoPermission from repository', () async {
    when(() => mockRepository.requestPermission(
          organizationUID: any(named: 'organizationUID'),
          companyUID: any(named: 'companyUID'),
          companyName: any(named: 'companyName'),
          companyCode: any(named: 'companyCode'),
          branchIds: any(named: 'branchIds'),
          branchNames: any(named: 'branchNames'),
          startDate: any(named: 'startDate'),
          endDate: any(named: 'endDate'),
          requestedBy: any(named: 'requestedBy'),
        )).thenAnswer((_) async => Right(tModel));

    final result = await usecase(tParams);

    expect(result, Right<Failure, PhotoPermission>(tModel));
    verify(() => mockRepository.requestPermission(
          organizationUID: 'org_uid',
          companyUID: 'company_uid',
          companyName: 'Company',
          companyCode: 123,
          branchIds: const ['b1'],
          branchNames: const ['Branch 1'],
          startDate: tDate,
          endDate: tDate,
          requestedBy: 'user_1',
        )).called(1);
    verifyNoMoreInteractions(mockRepository);
  });
}
