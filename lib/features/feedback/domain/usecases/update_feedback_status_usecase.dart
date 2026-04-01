import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:equatable/equatable.dart';

/// Use Case لتحديث حالة المقترح (للـ Super Admin فقط)
class UpdateFeedbackStatusUseCase {
  final FeedbackRepository repository;

  UpdateFeedbackStatusUseCase(this.repository);

  Future<Either<Failure, void>> call(UpdateFeedbackStatusParams params) async {
    return await repository.updateFeedbackStatus(
      feedbackId: params.feedbackId,
      status: params.status,
      adminResponse: params.adminResponse,
    );
  }
}

class UpdateFeedbackStatusParams extends Equatable {
  final String feedbackId;
  final FeedbackStatus status;
  final String? adminResponse;

  const UpdateFeedbackStatusParams({
    required this.feedbackId,
    required this.status,
    this.adminResponse,
  });

  @override
  List<Object?> get props => [feedbackId, status, adminResponse];
}
