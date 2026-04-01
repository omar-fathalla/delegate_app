import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';

/// Use Case للحصول على جميع المقترحات (للـ Super Admin فقط)
class GetAllFeedbacksUseCase {
  final FeedbackRepository repository;

  GetAllFeedbacksUseCase(this.repository);

  Future<Either<Failure, List<FeedbackEntity>>> call() async {
    return await repository.getAllFeedbacks();
  }
}
