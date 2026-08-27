import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/data/datasources/feedback_remote_datasource.dart';
import 'package:delegate_app/features/feedback/data/models/feedback_model.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'dart:io';

class FeedbackRepositoryImpl implements FeedbackRepository {
  final FeedbackRemoteDataSource remoteDataSource;

  FeedbackRepositoryImpl({required this.remoteDataSource});

  @override
  Future<Either<Failure, void>> submitFeedback({
    required String userId,
    required String userName,
    required String userEmail,
    required FeedbackType type,
    required String content,
    File? screenshot,
  }) async {
    try {
      final feedback = FeedbackModel(
        userId: userId,
        userName: userName,
        userEmail: userEmail,
        type: type,
        content: content,
        createdAt: DateTime.now(),
      );

      await remoteDataSource.submitFeedback(feedback, screenshot);
      return const Right(null);
    } catch (e) {
      if (e.toString().contains('unauthorized') || e.toString().contains('permission-denied')) {
        return const Left(ServerFailure('حدث خطأ في صلاحيات رفع الصورة. يرجى إعادة المحاولة.'));
      }
      return Left(ServerFailure('فشل إرسال المقترح: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, List<FeedbackEntity>>> getUserFeedbacks(
    String userId,
  ) async {
    try {
      final feedbacks = await remoteDataSource.getUserFeedbacks(userId);
      return Right(feedbacks);
    } catch (e) {
      return Left(ServerFailure('فشل جلب المقترحات: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, FeedbackEntity>> getFeedbackById(
    String feedbackId,
  ) async {
    try {
      final feedback = await remoteDataSource.getFeedbackById(feedbackId);
      return Right(feedback);
    } catch (e) {
      return Left(ServerFailure('فشل جلب المقترح: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, List<FeedbackEntity>>> getAllFeedbacks() async {
    try {
      final feedbacks = await remoteDataSource.getAllFeedbacks();
      return Right(feedbacks);
    } catch (e) {
      return Left(ServerFailure('فشل جلب المقترحات: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> updateFeedbackStatus({
    required String feedbackId,
    required FeedbackStatus status,
    String? adminResponse,
  }) async {
    try {
      await remoteDataSource.updateFeedbackStatus(
        feedbackId: feedbackId,
        status: status,
        adminResponse: adminResponse,
      );
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('فشل تحديث المقترح: ${e.toString()}'));
    }
  }

  @override
  Future<Either<Failure, void>> deleteFeedback(String feedbackId) async {
    try {
      await remoteDataSource.deleteFeedback(feedbackId);
      return const Right(null);
    } catch (e) {
      return Left(ServerFailure('فشل حذف المقترح: ${e.toString()}'));
    }
  }
}
