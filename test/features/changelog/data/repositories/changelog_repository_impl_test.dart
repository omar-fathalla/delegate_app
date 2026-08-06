import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/changelog/data/datasources/changelog_remote_datasource.dart';
import 'package:delegate_app/features/changelog/data/models/app_update_model.dart';
import 'package:delegate_app/features/changelog/data/repositories/changelog_repository_impl.dart';
import 'package:delegate_app/features/changelog/domain/entities/app_update.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';

class MockChangelogRemoteDataSource extends Mock
    implements ChangelogRemoteDataSource {}

class MockSharedPreferences extends Mock implements SharedPreferences {}

void main() {
  late ChangelogRepositoryImpl repository;
  late MockChangelogRemoteDataSource mockRemoteDataSource;
  late MockSharedPreferences mockSharedPreferences;

  setUp(() {
    mockRemoteDataSource = MockChangelogRemoteDataSource();
    mockSharedPreferences = MockSharedPreferences();
    repository = ChangelogRepositoryImpl(
      remoteDataSource: mockRemoteDataSource,
      sharedPreferences: mockSharedPreferences,
    );
  });

  final tDate = DateTime(2023, 1, 1);
  final tAppUpdateModel = AppUpdateModel(
    id: 'test_id',
    title: 'Test Update',
    titleEn: 'Test Update EN',
    description: 'Test Description',
    descriptionEn: 'Test Description EN',
    version: '1.0.0',
    type: UpdateType.feature,
    priority: UpdatePriority.normal,
    createdAt: tDate,
    isActive: true,
  );
  final tAppUpdateModels = [tAppUpdateModel];
  final List<AppUpdate> tAppUpdates = tAppUpdateModels;

  group('getUpdates', () {
    test('should return list of AppUpdate on success and mark as seen',
        () async {
      when(() => mockRemoteDataSource.getUpdates())
          .thenAnswer((_) async => tAppUpdateModels);
      when(() => mockSharedPreferences.setInt(any(), any()))
          .thenAnswer((_) async => true);

      final result = await repository.getUpdates();

      expect(result, Right<Failure, List<AppUpdate>>(tAppUpdates));
      verify(() => mockRemoteDataSource.getUpdates()).called(1);
      verify(() => mockSharedPreferences.setInt('changelog_last_seen', any()))
          .called(1);
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.getUpdates())
          .thenThrow(Exception('test exception'));

      final result = await repository.getUpdates();

      expect(
          result,
          equals(const Left<Failure, List<AppUpdate>>(
              ServerFailure('حدث خطأ غير متوقع أثناء جلب التحديثات.'))));
    });

    test('should return Left(Failure) when remoteDataSource throws Failure',
        () async {
      const failure = ServerFailure('API Error');
      when(() => mockRemoteDataSource.getUpdates()).thenThrow(failure);

      final result = await repository.getUpdates();

      expect(result, equals(const Left<Failure, List<AppUpdate>>(failure)));
    });
  });

  group('getNewUpdates', () {
    test('should return list of AppUpdate when successful', () async {
      final tLastSeen = DateTime(2023, 1, 1).millisecondsSinceEpoch;
      when(() => mockSharedPreferences.getInt('changelog_last_seen'))
          .thenReturn(tLastSeen);
      when(() => mockRemoteDataSource.getUpdatesSince(any()))
          .thenAnswer((_) async => tAppUpdateModels);

      final result = await repository.getNewUpdates();

      expect(result, Right<Failure, List<AppUpdate>>(tAppUpdates));
      verify(() => mockSharedPreferences.getInt('changelog_last_seen'))
          .called(1);
      verify(() => mockRemoteDataSource.getUpdatesSince(any())).called(1);
    });

    test('should return list of AppUpdate when never seen before', () async {
      when(() => mockSharedPreferences.getInt('changelog_last_seen'))
          .thenReturn(null);
      when(() => mockRemoteDataSource.getUpdatesSince(any()))
          .thenAnswer((_) async => tAppUpdateModels);

      final result = await repository.getNewUpdates();

      expect(result, Right<Failure, List<AppUpdate>>(tAppUpdates));
      verify(() => mockRemoteDataSource.getUpdatesSince(DateTime(2020)))
          .called(1);
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockSharedPreferences.getInt('changelog_last_seen'))
          .thenReturn(null);
      when(() => mockRemoteDataSource.getUpdatesSince(any()))
          .thenThrow(Exception('test error'));

      final result = await repository.getNewUpdates();

      expect(
          result,
          equals(const Left<Failure, List<AppUpdate>>(
              ServerFailure('حدث خطأ غير متوقع أثناء جلب التحديثات الجديدة.'))));
    });

    test('should return Left(Failure) when remoteDataSource throws Failure',
        () async {
      when(() => mockSharedPreferences.getInt('changelog_last_seen'))
          .thenReturn(null);
      const failure = ServerFailure('API Error');
      when(() => mockRemoteDataSource.getUpdatesSince(any()))
          .thenThrow(failure);

      final result = await repository.getNewUpdates();

      expect(result, equals(const Left<Failure, List<AppUpdate>>(failure)));
    });
  });
}
