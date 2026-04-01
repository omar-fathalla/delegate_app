import 'package:equatable/equatable.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'dart:io';

abstract class FeedbackEvent extends Equatable {
  const FeedbackEvent();

  @override
  List<Object?> get props => [];
}

class SubmitFeedbackEvent extends FeedbackEvent {
  final String userId;
  final String userName;
  final String userEmail;
  final FeedbackType type;
  final String content;
  final File? screenshot;

  const SubmitFeedbackEvent({
    required this.userId,
    required this.userName,
    required this.userEmail,
    required this.type,
    required this.content,
    this.screenshot,
  });

  @override
  List<Object?> get props => [
    userId,
    userName,
    userEmail,
    type,
    content,
    screenshot,
  ];
}

class LoadUserFeedbacksEvent extends FeedbackEvent {
  final String userId;

  const LoadUserFeedbacksEvent({required this.userId});

  @override
  List<Object?> get props => [userId];
}
