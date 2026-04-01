import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';

class GetUserFeedbacksUseCase {
  final FeedbackRepository repository;

  GetUserFeedbacksUseCase(this.repository);

  Future<Either<Failure, List<FeedbackEntity>>> call(String userId) async {
    return await repository.getUserFeedbacks(userId);
  }
}
