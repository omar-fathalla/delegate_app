import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';

abstract class AdminFeedbackEvent extends Equatable {
  const AdminFeedbackEvent();

  @override
  List<Object?> get props => [];
}

/// حدث لتحميل جميع المقترحات
class LoadAllFeedbacksEvent extends AdminFeedbackEvent {
  const LoadAllFeedbacksEvent();
}

/// حدث لتحديث حالة مقترح
class UpdateFeedbackStatusEvent extends AdminFeedbackEvent {
  final String feedbackId;
  final FeedbackStatus status;
  final String? adminResponse;

  const UpdateFeedbackStatusEvent({
    required this.feedbackId,
    required this.status,
    this.adminResponse,
  });

  @override
  List<Object?> get props => [feedbackId, status, adminResponse];
}

/// حدث لحذف مقترح
class DeleteFeedbackEvent extends AdminFeedbackEvent {
  final String feedbackId;

  const DeleteFeedbackEvent(this.feedbackId);

  @override
  List<Object?> get props => [feedbackId];
}
