import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';

abstract class FeedbackState extends Equatable {
  const FeedbackState();

  @override
  List<Object?> get props => [];
}

class FeedbackInitial extends FeedbackState {}

class FeedbackSubmitting extends FeedbackState {}

class FeedbackSubmitted extends FeedbackState {}

class FeedbackLoading extends FeedbackState {}

class FeedbacksLoaded extends FeedbackState {
  final List<FeedbackEntity> feedbacks;

  const FeedbacksLoaded({required this.feedbacks});

  @override
  List<Object?> get props => [feedbacks];
}

class FeedbackError extends FeedbackState {
  final String message;

  const FeedbackError({required this.message});

  @override
  List<Object?> get props => [message];
}
