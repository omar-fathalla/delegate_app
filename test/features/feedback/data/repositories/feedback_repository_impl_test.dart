import 'dart:io';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/data/datasources/feedback_remote_datasource.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockFeedbackRemoteDataSource extends Mock implements FeedbackRemoteDataSource {}
class MockFile extends Mock implements File {}

void main() {
  late FeedbackRepositoryImpl repository;
  late MockFeedbackRemoteDataSource mockRemoteDataSource;

  setUpAll(() {
    registerFallbackValue(FeedbackModel(
      userId: 'user',
      userName: 'name',
      userEmail: 'email',
      type: FeedbackType.other,
      content: 'content',
      createdAt: DateTime.now(),
    ));
    registerFallbackValue(File('test.png'));
    registerFallbackValue(FeedbackStatus.pending);
  });

  setUp(() {
    mockRemoteDataSource = MockFeedbackRemoteDataSource();
    repository = FeedbackRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  final tDate = DateTime(2023, 1, 1);
  final tFeedbackModel = FeedbackModel(
    id: 'test_id',
    userId: 'user_123',
    userName: 'Test User',
    userEmail: 'test@example.com',
    type: FeedbackType.featureRequest,
    content: 'Please add a dark mode feature',
    status: FeedbackStatus.pending,
    createdAt: tDate,
  );

  final tFeedbackList = <FeedbackModel>[tFeedbackModel];

  group('submitFeedback', () {
    test('should return Right(null) on success', () async {
      when(() => mockRemoteDataSource.submitFeedback(any(), any())).thenAnswer((_) async {});

      final result = await repository.submitFeedback(
        userId: 'user_123',
        userName: 'Test User',
        userEmail: 'test@example.com',
        type: FeedbackType.featureRequest,
        content: 'Please add a dark mode feature',
      );

      expect(result, const Right(null));
      verify(() => mockRemoteDataSource.submitFeedback(any(), null)).called(1);
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.submitFeedback(any(), any())).thenThrow(Exception());

      final result = await repository.submitFeedback(
        userId: 'user_123',
        userName: 'Test User',
        userEmail: 'test@example.com',
        type: FeedbackType.featureRequest,
        content: 'Please add a dark mode feature',
      );

      expect(result, isA<Left<Failure, void>>());
    });
  });

  group('getUserFeedbacks', () {
    test('should return list of FeedbackEntity on success', () async {
      when(() => mockRemoteDataSource.getUserFeedbacks(any())).thenAnswer((_) async => tFeedbackList);

      final result = await repository.getUserFeedbacks('user_123');

      expect(result, equals(Right<Failure, List<FeedbackEntity>>(tFeedbackList)));
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.getUserFeedbacks(any())).thenThrow(Exception());

      final result = await repository.getUserFeedbacks('user_123');

      expect(result, isA<Left<Failure, List<FeedbackEntity>>>());
    });
  });

  group('getFeedbackById', () {
    test('should return FeedbackEntity on success', () async {
      when(() => mockRemoteDataSource.getFeedbackById(any())).thenAnswer((_) async => tFeedbackModel);

      final result = await repository.getFeedbackById('test_id');

      expect(result, equals(Right(tFeedbackModel)));
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.getFeedbackById(any())).thenThrow(Exception());

      final result = await repository.getFeedbackById('test_id');

      expect(result, isA<Left<Failure, FeedbackEntity>>());
    });
  });

  group('getAllFeedbacks', () {
    test('should return list of FeedbackEntity on success', () async {
      when(() => mockRemoteDataSource.getAllFeedbacks()).thenAnswer((_) async => tFeedbackList);

      final result = await repository.getAllFeedbacks();

      expect(result, equals(Right<Failure, List<FeedbackEntity>>(tFeedbackList)));
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.getAllFeedbacks()).thenThrow(Exception());

      final result = await repository.getAllFeedbacks();

      expect(result, isA<Left<Failure, List<FeedbackEntity>>>());
    });
  });

  group('updateFeedbackStatus', () {
    test('should return Right(null) on success', () async {
      when(() => mockRemoteDataSource.updateFeedbackStatus(
        feedbackId: any(named: 'feedbackId'),
        status: any(named: 'status'),
        adminResponse: any(named: 'adminResponse'),
      )).thenAnswer((_) async {});

      final result = await repository.updateFeedbackStatus(feedbackId: 'test_id', status: FeedbackStatus.resolved);

      expect(result, const Right(null));
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.updateFeedbackStatus(
        feedbackId: any(named: 'feedbackId'),
        status: any(named: 'status'),
        adminResponse: any(named: 'adminResponse'),
      )).thenThrow(Exception());

      final result = await repository.updateFeedbackStatus(feedbackId: 'test_id', status: FeedbackStatus.resolved);

      expect(result, isA<Left<Failure, void>>());
    });
  });

  group('deleteFeedback', () {
    test('should return Right(null) on success', () async {
      when(() => mockRemoteDataSource.deleteFeedback(any())).thenAnswer((_) async {});

      final result = await repository.deleteFeedback('test_id');

      expect(result, const Right(null));
    });

    test('should return Left(ServerFailure) on exception', () async {
      when(() => mockRemoteDataSource.deleteFeedback(any())).thenThrow(Exception());

      final result = await repository.deleteFeedback('test_id');

      expect(result, isA<Left<Failure, void>>());
    });
  });
}
