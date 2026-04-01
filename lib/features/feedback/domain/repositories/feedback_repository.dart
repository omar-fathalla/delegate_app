import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'dart:io';

abstract class FeedbackRepository {
  /// إرسال مقترح جديد
  Future<Either<Failure, void>> submitFeedback({
    required String userId,
    required String userName,
    required String userEmail,
    required FeedbackType type,
    required String content,
    File? screenshot,
  });

  /// الحصول على جميع مقترحات المستخدم
  Future<Either<Failure, List<FeedbackEntity>>> getUserFeedbacks(String userId);

  /// الحصول على مقترح محدد
  Future<Either<Failure, FeedbackEntity>> getFeedbackById(String feedbackId);

  /// الحصول على جميع المقترحات (للـ Super Admin فقط)
  Future<Either<Failure, List<FeedbackEntity>>> getAllFeedbacks();

  /// تحديث حالة المقترح (للـ Super Admin فقط)
  Future<Either<Failure, void>> updateFeedbackStatus({
    required String feedbackId,
    required FeedbackStatus status,
    String? adminResponse,
  });
}
