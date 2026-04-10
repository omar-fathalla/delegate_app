import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_admins.dart';
import 'package:delegate_app/features/admin/domain/usecases/suspend_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_organizations.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/create_admin_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_admins_bloc.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/repositories/marketing_repository_impl.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/repositories/auth_repository_impl.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/login.dart';
import 'package:delegate_app/features/auth/domain/usecases/check_auto_login.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_delegate.dart';
import 'package:delegate_app/features/auth/domain/usecases/cache_all_delegates.dart';
import 'package:delegate_app/features/attendance/data/repositories/attendance_repository_impl.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_offline_queue.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history_paginated.dart';
import 'package:delegate_app/features/attendance/domain/usecases/sync_attendance.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';

import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:delegate_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:delegate_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:delegate_app/features/profile/domain/usecases/get_delegate_profile.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:delegate_app/features/changelog/data/datasources/changelog_remote_datasource.dart';
import 'package:delegate_app/features/changelog/data/repositories/changelog_repository_impl.dart';
import 'package:delegate_app/features/changelog/domain/repositories/changelog_repository.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_new_updates.dart';
import 'package:delegate_app/features/changelog/domain/usecases/get_all_updates.dart';
import 'package:delegate_app/features/changelog/presentation/bloc/changelog_bloc.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/features/tasks/data/datasources/task_remote_data_source.dart';
import 'package:delegate_app/features/tasks/data/repositories/task_repository_impl.dart';
import 'package:delegate_app/features/tasks/domain/repositories/task_repository.dart';
import 'package:delegate_app/features/tasks/domain/usecases/create_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/delete_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_admin_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/get_delegate_tasks.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task.dart';
import 'package:delegate_app/features/tasks/domain/usecases/update_task_status.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/admin_tasks_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/create_task_bloc.dart';
import 'package:delegate_app/features/tasks/presentation/bloc/delegate_tasks_bloc.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:delegate_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_unread_count.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_all_notifications_read.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_notification_read.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/features/feedback/feedback_injection.dart';
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

Future<void> init({required SharedPreferences sharedPreferences}) async {
  // ! Core
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => LocaleProvider(sharedPreferences));
  sl.registerLazySingleton(() => ThemeCubit(sl()));

  // Push Notification Service
  sl.registerLazySingleton(
    () => PushNotificationService(
      firestore: sl(),
      messaging: FirebaseMessaging.instance,
      localNotifications: FlutterLocalNotificationsPlugin(),
    ),
  );

  // ! Features - Auth
  // Bloc
  sl.registerFactory(
    () => AuthBloc(
      loginUseCase: sl(),
      checkAutoLoginUseCase: sl(),
      logoutUseCase: sl(),
      cacheDelegateUseCase: sl(),
      cacheAllDelegatesUseCase: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => Login(sl()));
  sl.registerLazySingleton(() => CheckAutoLogin(sl()));
  sl.registerLazySingleton(() => Logout(sl()));
  sl.registerLazySingleton(() => CacheDelegate(sl()));
  sl.registerLazySingleton(() => CacheAllDelegates(sl()));

  // Repository
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(remoteDataSource: sl(), localDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(firestore: sl(), firebaseAuth: sl()),
  );

  // ! Features - Profile
  // Bloc
  sl.registerFactory(() => ProfileBloc(getDelegateProfile: sl()));

  // Use cases
  sl.registerLazySingleton(() => GetDelegateProfile(sl()));

  // Repository
  sl.registerLazySingleton<ProfileRepository>(
    () => ProfileRepositoryImpl(remoteDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<ProfileRemoteDataSource>(
    () => ProfileRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Attendance
  // Bloc
  sl.registerFactory(
    () => AttendanceBloc(
      checkIn: sl(),
      checkOut: sl(),
      getHistory: sl(),
      getHistoryPaginated: sl(),
      syncAttendance: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => CheckIn(sl()));
  sl.registerLazySingleton(() => CheckOut(sl()));
  sl.registerLazySingleton(() => GetHistory(sl()));
  sl.registerLazySingleton(() => GetHistoryPaginated(sl()));
  sl.registerLazySingleton(() => SyncAttendance(sl()));

  // Repository
  sl.registerLazySingleton<AttendanceRepository>(
    () => AttendanceRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      offlineQueue: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<AttendanceLocalDataSource>(
    () => AttendanceLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<AttendanceOfflineQueue>(
    () => AttendanceOfflineQueueImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<AttendanceRemoteDataSource>(
    () => AttendanceRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Admin
  // Bloc
  sl.registerFactory(
    () => BranchBloc(
      getBranches: sl(),
      addBranch: sl(),
      updateBranch: sl(),
      deleteBranch: sl(),
    ),
  );

  // Create Admin BLoC
  sl.registerFactory(
    () => CreateAdminBloc(createAdmin: sl(), getOrganizations: sl()),
  );

  // Manage Admins BLoC
  sl.registerFactory(
    () => ManageAdminsBloc(
      getAdmins: sl(),
      deleteAdminUser: sl(),
      suspendAdminUser: sl(),
      updateAdminUser: sl(),
    ),
  );

  // Admin Delegates BLoC
  sl.registerFactory(() => AdminDelegatesBloc(getCompanyDelegates: sl()));

  // Admin Dashboard BLoC
  sl.registerFactory(() => AdminDashboardBloc(getDashboardSummary: sl()));

  // Use cases
  sl.registerLazySingleton(() => GetBranches(sl()));
  sl.registerLazySingleton(() => AddBranch(sl()));
  sl.registerLazySingleton(() => UpdateBranch(sl()));
  sl.registerLazySingleton(() => DeleteBranch(sl()));
  sl.registerLazySingleton(() => CreateAdmin(sl()));
  sl.registerLazySingleton(() => GetAdmins(sl()));
  sl.registerLazySingleton(() => DeleteAdminUser(sl()));
  sl.registerLazySingleton(() => SuspendAdminUser(sl()));
  sl.registerLazySingleton(() => UpdateAdminUser(sl()));
  sl.registerLazySingleton(() => GetCompanyDelegates(sl()));
  sl.registerLazySingleton(() => GetDashboardSummary(sl()));
  sl.registerLazySingleton(() => GetOrganizations(sl()));

  // Repository
  sl.registerLazySingleton<AdminRepository>(
    () => AdminRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<AdminRemoteDataSource>(
    () => AdminRemoteDataSourceImpl(firestore: sl(), firebaseAuth: sl()),
  );

  // ! Features - Marketing
  // Bloc
  sl.registerFactory(
    () => MarketingBloc(
      getCompanies: sl(),
      getDelegates: sl(),
      remoteDataSource: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetMarketingCompanies(sl()));
  sl.registerLazySingleton(() => GetMarketingDelegates(sl()));

  // Repository
  sl.registerLazySingleton<MarketingRepository>(
    () => MarketingRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<MarketingRemoteDataSource>(
    () => MarketingRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Changelog
  // Bloc
  sl.registerFactory(
    () => ChangelogBloc(getNewUpdates: sl(), getAllUpdates: sl()),
  );

  // Use cases
  sl.registerLazySingleton(() => GetNewUpdates(sl()));
  sl.registerLazySingleton(() => GetAllUpdates(sl()));

  // Repository
  sl.registerLazySingleton<ChangelogRepository>(
    () => ChangelogRepositoryImpl(
      remoteDataSource: sl(),
      sharedPreferences: sl(),
    ),
  );

  // Data source
  sl.registerLazySingleton<ChangelogRemoteDataSource>(
    () => ChangelogRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Tasks
  sl.registerFactory(
    () => AdminTasksBloc(
      getAdminTasks: sl(),
      updateTaskStatus: sl(),
      updateTask: sl(),
    ),
  );
  sl.registerFactory(
    () => CreateTaskBloc(createTask: sl(), getCompanyDelegates: sl()),
  );
  sl.registerFactory(
    () => DelegateTasksBloc(
      getDelegateTasks: sl(),
      updateTaskStatus: sl(),
      updateTask: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetAdminTasks(sl()));
  sl.registerLazySingleton(() => GetDelegateTasks(sl()));
  sl.registerLazySingleton(() => CreateTask(sl()));
  sl.registerLazySingleton(() => UpdateTaskStatus(sl()));
  sl.registerLazySingleton(() => UpdateTask(sl()));
  sl.registerLazySingleton(() => DeleteTask(sl()));

  // Repository
  sl.registerLazySingleton<TaskRepository>(
    () => TaskRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<TaskRemoteDataSource>(
    () => TaskRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Notifications
  // Bloc
  sl.registerFactory(
    () => NotificationBloc(
      getNotifications: sl(),
      getUnreadCount: sl(),
      markNotificationRead: sl(),
      markAllNotificationsRead: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetNotifications(sl()));
  sl.registerLazySingleton(() => GetUnreadCount(sl()));
  sl.registerLazySingleton(() => MarkNotificationRead(sl()));
  sl.registerLazySingleton(() => MarkAllNotificationsRead(sl()));

  // Repository
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<NotificationRemoteDataSource>(
    () => NotificationRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Feedback
  initFeedbackDependencies();

  // ! Core

  // ! External
  // Firebase initialization is disabled in main.dart for Demo Mode.
  // We register them as lazy singletons if needed, but ensure they aren't
  // accessed unless Firebase.initializeApp() is actually called.

  sl.registerLazySingleton(() => FirebaseFirestore.instance);
  sl.registerLazySingleton(() => FirebaseAuth.instance);
  sl.registerLazySingleton(() => FirebaseStorage.instance);
}
