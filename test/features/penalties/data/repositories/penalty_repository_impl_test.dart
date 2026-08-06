import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/exceptions.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/penalties/data/datasources/penalty_remote_data_source.dart';
import 'package:delegate_app/features/penalties/data/models/penalty_model.dart';
import 'package:delegate_app/features/penalties/data/repositories/penalty_repository_impl.dart';
import 'package:delegate_app/features/penalties/domain/entities/penalty_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockPenaltyRemoteDataSource extends Mock
    implements PenaltyRemoteDataSource {}

class MockFile extends Mock implements File {}

void main() {
  late PenaltyRepositoryImpl repository;
  late MockPenaltyRemoteDataSource mockRemoteDataSource;

  setUpAll(() {
    registerFallbackValue(
      PenaltyModel(
        penaltyId: 'test_id',
        companyId: 'company_123',
        companyName: 'Test Company',
        createdById: 'admin_123',
        createdByName: 'Admin Name',
        title: 'Test Penalty',
        category: ViolationCategory.dataMissing,
        incidentDescription: 'Missing data in form',
        fineAmount: 50.0,
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
      ),
    );
    registerFallbackValue(MockFile());
    registerFallbackValue(PenaltyStatus.issued);
  });

  setUp(() {
    mockRemoteDataSource = MockPenaltyRemoteDataSource();
    repository = PenaltyRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  final tDate = DateTime(2023, 1, 1);
  final tPenaltyModel = PenaltyModel(
    penaltyId: 'test_id',
    companyId: 'company_123',
    companyName: 'Test Company',
    createdById: 'admin_123',
    createdByName: 'Admin Name',
    title: 'Test Penalty',
    category: ViolationCategory.dataMissing,
    incidentDescription: 'Missing data in form',
    fineAmount: 50.0,
    currency: 'EGP',
    status: PenaltyStatus.issued,
    evidenceFiles: const [],
    createdAt: tDate,
    updatedAt: tDate,
  );
  
  final PenaltyEntity tPenaltyEntity = tPenaltyModel;

  group('createPenalty', () {
    test('should return Right(unit) when call is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.createPenalty(any()))
          .thenAnswer((_) async {});

      // Act
      final result = await repository.createPenalty(tPenaltyEntity);

      // Assert
      expect(result, const Right(unit));
      verify(() => mockRemoteDataSource.createPenalty(any())).called(1);
    });

    test('should return Left(ServerFailure) when call fails', () async {
      // Arrange
      when(() => mockRemoteDataSource.createPenalty(any()))
          .thenThrow(ServerException('Error'));

      // Act
      final result = await repository.createPenalty(tPenaltyEntity);

      // Assert
      expect(result, const Left(ServerFailure('Error')));
    });
  });

  group('getCompanyPenalties', () {
    test('should return list of penalties when call is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.getCompanyPenalties('company_123'))
          .thenAnswer((_) async => [tPenaltyModel]);

      // Act
      final result = await repository.getCompanyPenalties('company_123');

      // Assert
      result.fold(
        (l) => fail('Should return Right'),
        (r) {
          expect(r, equals([tPenaltyEntity]));
        },
      );
    });

    test('should return Left(ServerFailure) when call fails', () async {
      // Arrange
      when(() => mockRemoteDataSource.getCompanyPenalties(any()))
          .thenThrow(ServerException('Error'));

      // Act
      final result = await repository.getCompanyPenalties('company_123');

      // Assert
      expect(result, const Left(ServerFailure('Error')));
    });
  });

  group('getAllPenalties', () {
    test('should return list of penalties when call is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.getAllPenalties())
          .thenAnswer((_) async => [tPenaltyModel]);

      // Act
      final result = await repository.getAllPenalties();

      // Assert
      result.fold(
        (l) => fail('Should return Right'),
        (r) {
          expect(r, equals([tPenaltyEntity]));
        },
      );
    });

    test('should return Left(ServerFailure) when call fails', () async {
      // Arrange
      when(() => mockRemoteDataSource.getAllPenalties())
          .thenThrow(ServerException('Error'));

      // Act
      final result = await repository.getAllPenalties();

      // Assert
      expect(result, const Left(ServerFailure('Error')));
    });
  });

  group('updatePenaltyStatus', () {
    test('should return Right(unit) when call is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.updatePenaltyStatus(any(), any()))
          .thenAnswer((_) async {});

      // Act
      final result = await repository.updatePenaltyStatus(
          'test_id', PenaltyStatus.acknowledged);

      // Assert
      expect(result, const Right(unit));
      verify(() => mockRemoteDataSource.updatePenaltyStatus(
          'test_id', PenaltyStatus.acknowledged)).called(1);
    });

    test('should return Left(ServerFailure) when call fails', () async {
      // Arrange
      when(() => mockRemoteDataSource.updatePenaltyStatus(any(), any()))
          .thenThrow(ServerException('Error'));

      // Act
      final result = await repository.updatePenaltyStatus(
          'test_id', PenaltyStatus.acknowledged);

      // Assert
      expect(result, const Left(ServerFailure('Error')));
    });
  });

  group('uploadEvidenceFile', () {
    final tFile = MockFile();
    const tEvidenceFile = EvidenceFile(
      fileUrl: 'http://test.com/img.jpg',
      fileType: 'IMAGE',
      fileName: 'img.jpg',
    );

    test('should return EvidenceFile when call is successful', () async {
      // Arrange
      when(() => mockRemoteDataSource.uploadEvidenceFile(
              file: any(named: 'file'), penaltyId: any(named: 'penaltyId')))
          .thenAnswer((_) async => tEvidenceFile);

      // Act
      final result = await repository.uploadEvidenceFile(
          file: tFile, penaltyId: 'test_id');

      // Assert
      expect(result, const Right(tEvidenceFile));
    });

    test('should return Left(ServerFailure) when call fails', () async {
      // Arrange
      when(() => mockRemoteDataSource.uploadEvidenceFile(
              file: any(named: 'file'), penaltyId: any(named: 'penaltyId')))
          .thenThrow(ServerException('Error'));

      // Act
      final result = await repository.uploadEvidenceFile(
          file: tFile, penaltyId: 'test_id');

      // Assert
      expect(result, const Left(ServerFailure('Error')));
    });
  });
}
