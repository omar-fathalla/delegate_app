import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';

abstract class AdminFeedbackState extends Equatable {
  const AdminFeedbackState();

  @override
  List<Object?> get props => [];
}

class AdminFeedbackInitial extends AdminFeedbackState {}

class AdminFeedbackLoading extends AdminFeedbackState {}

class AdminFeedbacksLoaded extends AdminFeedbackState {
  final List<FeedbackEntity> feedbacks;

  const AdminFeedbacksLoaded({required this.feedbacks});

  @override
  List<Object?> get props => [feedbacks];
}

class AdminFeedbackError extends AdminFeedbackState {
  final String message;

  const AdminFeedbackError({required this.message});

  @override
  List<Object?> get props => [message];
}
