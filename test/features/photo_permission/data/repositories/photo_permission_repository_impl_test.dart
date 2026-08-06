import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/models/photo_permission_model.dart';
import 'package:delegate_app/features/photo_permission/data/repositories/photo_permission_repository_impl.dart';
import 'package:delegate_app/features/photo_permission/domain/entities/photo_permission.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPhotoPermissionRemoteDataSource extends Mock
    implements PhotoPermissionRemoteDataSource {}

void main() {
  late PhotoPermissionRepositoryImpl repository;
  late MockPhotoPermissionRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockPhotoPermissionRemoteDataSource();
    repository = PhotoPermissionRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
    );
  });

  final tDate = DateTime(2023, 1, 1);
  final tModel = PhotoPermissionModel(
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
  final List<PhotoPermission> tEntities = tModels;

  group('getPermissions', () {
    test('should return list of PhotoPermission when successful', () async {
      when(() => mockRemoteDataSource.getPermissions(
            organizationUID: any(named: 'organizationUID'),
            companyUID: any(named: 'companyUID'),
          )).thenAnswer((_) async => tModels);

      final result = await repository.getPermissions(
        organizationUID: 'org_uid',
        companyUID: 'company_uid',
      );

      expect(result, Right<Failure, List<PhotoPermission>>(tEntities));
      verify(() => mockRemoteDataSource.getPermissions(
            organizationUID: 'org_uid',
            companyUID: 'company_uid',
          )).called(1);
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.getPermissions(
            organizationUID: any(named: 'organizationUID'),
            companyUID: any(named: 'companyUID'),
          )).thenThrow(Exception());

      final result = await repository.getPermissions(
        organizationUID: 'org_uid',
        companyUID: 'company_uid',
      );

      expect(
          result,
          equals(const Left<Failure, List<PhotoPermission>>(
              ServerFailure('حدث خطأ غير متوقع أثناء جلب الأذونات.'))));
    });
  });

  group('requestPermission', () {
    test('should return PhotoPermission when successful', () async {
      when(() => mockRemoteDataSource.requestPermission(
            organizationUID: any(named: 'organizationUID'),
            companyUID: any(named: 'companyUID'),
            companyName: any(named: 'companyName'),
            branchIds: any(named: 'branchIds'),
            branchNames: any(named: 'branchNames'),
            startDate: any(named: 'startDate'),
            endDate: any(named: 'endDate'),
            requestedBy: any(named: 'requestedBy'),
          )).thenAnswer((_) async => tModel);

      final result = await repository.requestPermission(
        organizationUID: 'org_uid',
        companyUID: 'company_uid',
        companyName: 'Company',
        branchIds: ['b1'],
        branchNames: ['Branch 1'],
        startDate: tDate,
        endDate: tDate,
        requestedBy: 'user_1',
      );

      expect(result, Right<Failure, PhotoPermission>(tModel));
    });
  });
}
