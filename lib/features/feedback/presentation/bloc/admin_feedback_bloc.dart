import 'package:flutter_bloc/flutter_bloc.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_all_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/update_feedback_status_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/delete_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_event.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_state.dart';

/// BLoC لإدارة المقترحات من قبل Super Admin
class AdminFeedbackBloc extends Bloc<AdminFeedbackEvent, AdminFeedbackState> {
  final GetAllFeedbacksUseCase getAllFeedbacksUseCase;
  final UpdateFeedbackStatusUseCase updateFeedbackStatusUseCase;
  final DeleteFeedbackUseCase deleteFeedbackUseCase;

  AdminFeedbackBloc({
    required this.getAllFeedbacksUseCase,
    required this.updateFeedbackStatusUseCase,
    required this.deleteFeedbackUseCase,
  }) : super(AdminFeedbackInitial()) {
    on<LoadAllFeedbacksEvent>(_onLoadAllFeedbacks);
    on<UpdateFeedbackStatusEvent>(_onUpdateFeedbackStatus);
    on<DeleteFeedbackEvent>(_onDeleteFeedback);
  }

  Future<void> _onLoadAllFeedbacks(
    LoadAllFeedbacksEvent event,
    Emitter<AdminFeedbackState> emit,
  ) async {
    emit(AdminFeedbackLoading());

    final result = await getAllFeedbacksUseCase();

    result.fold(
      (failure) => emit(AdminFeedbackError(message: failure.message)),
      (feedbacks) => emit(AdminFeedbacksLoaded(feedbacks: feedbacks)),
    );
  }

  Future<void> _onUpdateFeedbackStatus(
    UpdateFeedbackStatusEvent event,
    Emitter<AdminFeedbackState> emit,
  ) async {
    final result = await updateFeedbackStatusUseCase(
      UpdateFeedbackStatusParams(
        feedbackId: event.feedbackId,
        status: event.status,
        adminResponse: event.adminResponse,
      ),
    );

    result.fold(
      (failure) => emit(AdminFeedbackError(message: failure.message)),
      (_) {
        // إعادة تحميل المقترحات بعد التحديث
        add(const LoadAllFeedbacksEvent());
      },
    );
  }

  Future<void> _onDeleteFeedback(
    DeleteFeedbackEvent event,
    Emitter<AdminFeedbackState> emit,
  ) async {
    final result = await deleteFeedbackUseCase(event.feedbackId);

    result.fold(
      (failure) => emit(AdminFeedbackError(message: failure.message)),
      (_) {
        // إعادة تحميل المقترحات بعد الحذف
        add(const LoadAllFeedbacksEvent());
      },
    );
  }
}
