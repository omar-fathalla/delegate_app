import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/feedback/domain/usecases/submit_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_user_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_state.dart';

class FeedbackBloc extends Bloc<FeedbackEvent, FeedbackState> {
  final SubmitFeedbackUseCase submitFeedbackUseCase;
  final GetUserFeedbacksUseCase getUserFeedbacksUseCase;

  FeedbackBloc({
    required this.submitFeedbackUseCase,
    required this.getUserFeedbacksUseCase,
  }) : super(FeedbackInitial()) {
    on<SubmitFeedbackEvent>(_onSubmitFeedback);
    on<LoadUserFeedbacksEvent>(_onLoadUserFeedbacks);
  }

  Future<void> _onSubmitFeedback(
    SubmitFeedbackEvent event,
    Emitter<FeedbackState> emit,
  ) async {
    emit(FeedbackSubmitting());

    final result = await submitFeedbackUseCase(
      SubmitFeedbackParams(
        userId: event.userId,
        userName: event.userName,
        userEmail: event.userEmail,
        type: event.type,
        content: event.content,
        screenshot: event.screenshot,
      ),
    );

    result.fold(
      (failure) => emit(FeedbackError(message: failure.message)),
      (_) => emit(FeedbackSubmitted()),
    );
  }

  Future<void> _onLoadUserFeedbacks(
    LoadUserFeedbacksEvent event,
    Emitter<FeedbackState> emit,
  ) async {
    emit(FeedbackLoading());

    final result = await getUserFeedbacksUseCase(event.userId);

    result.fold(
      (failure) => emit(FeedbackError(message: failure.message)),
      (feedbacks) => emit(FeedbacksLoaded(feedbacks: feedbacks)),
    );
  }
}
