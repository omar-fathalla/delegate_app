import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/features/feedback/domain/entities/feedback_entity.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:equatable/equatable.dart';
import 'dart:io';

class SubmitFeedbackUseCase {
  final FeedbackRepository repository;

  SubmitFeedbackUseCase(this.repository);

  Future<Either<Failure, void>> call(SubmitFeedbackParams params) async {
    return await repository.submitFeedback(
      userId: params.userId,
      userName: params.userName,
      userEmail: params.userEmail,
      type: params.type,
      content: params.content,
      screenshot: params.screenshot,
    );
  }
}

class SubmitFeedbackParams extends Equatable {
  final String userId;
  final String userName;
  final String userEmail;
  final FeedbackType type;
  final String content;
  final File? screenshot;

  const SubmitFeedbackParams({
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
