import 'package:delegate_app/features/feedback/data/datasources/feedback_remote_datasource.dart';
import 'package:delegate_app/features/feedback/data/repositories/feedback_repository_impl.dart';
import 'package:delegate_app/features/feedback/domain/repositories/feedback_repository.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_user_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/submit_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/get_all_feedbacks_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/update_feedback_status_usecase.dart';
import 'package:delegate_app/features/feedback/domain/usecases/delete_feedback_usecase.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/feedback_bloc.dart';
import 'package:delegate_app/features/feedback/presentation/bloc/admin_feedback_bloc.dart';
import 'package:delegate_app/injection_container.dart';

/// تسجيل جميع dependencies الخاصة بميزة Feedback
void initFeedbackDependencies() {
  // Bloc
  sl.registerFactory(
    () => FeedbackBloc(
      submitFeedbackUseCase: sl(),
      getUserFeedbacksUseCase: sl(),
    ),
  );

  // Admin Bloc
  sl.registerFactory(
    () => AdminFeedbackBloc(
      getAllFeedbacksUseCase: sl(),
      updateFeedbackStatusUseCase: sl(),
      deleteFeedbackUseCase: sl(),
    ),
  );

  // Use Cases
  sl.registerLazySingleton(() => SubmitFeedbackUseCase(sl()));
  sl.registerLazySingleton(() => GetUserFeedbacksUseCase(sl()));
  sl.registerLazySingleton(() => GetAllFeedbacksUseCase(sl()));
  sl.registerLazySingleton(() => UpdateFeedbackStatusUseCase(sl()));
  sl.registerLazySingleton(() => DeleteFeedbackUseCase(sl()));

  // Repository
  sl.registerLazySingleton<FeedbackRepository>(
    () => FeedbackRepositoryImpl(remoteDataSource: sl()),
  );

  // Data Sources
  sl.registerLazySingleton<FeedbackRemoteDataSource>(
    () => FeedbackRemoteDataSourceImpl(firestore: sl(), storage: sl()),
  );
}
