import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';

class DeleteFeedbackUseCase implements UseCase<void, String> {
  final FeedbackRepository repository;

  DeleteFeedbackUseCase(this.repository);

  @override
  Future<Either<Failure, void>> call(String feedbackId) async {
    return await repository.deleteFeedback(feedbackId);
  }
}
