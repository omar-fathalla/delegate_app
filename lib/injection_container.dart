import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:cloud_functions/cloud_functions.dart';
import 'package:firebase_auth/firebase_auth.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/datasources/manage_marketing_remote_datasource.dart';
import 'package:delegate_app/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_admins.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_organizations.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_companies_for_org.dart';
import 'package:delegate_app/features/admin/domain/usecases/suspend_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_dashboard_summary.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_marketing_employees.dart';
import 'package:delegate_app/features/admin/domain/usecases/search_companies_by_code.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_companies.dart';
import 'package:delegate_app/features/admin/domain/repositories/company_repository.dart';
import 'package:delegate_app/features/admin/domain/repositories/delegate_subscription_repository.dart';
import 'package:delegate_app/features/admin/data/repositories/company_repository_impl.dart';
import 'package:delegate_app/features/admin/data/repositories/delegate_subscription_repository_impl.dart';
import 'package:delegate_app/features/admin/data/datasources/company_remote_datasource.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_dashboard_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/create_admin_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_admins_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_marketing_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/company_search_bloc.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_local_data_source.dart';
import 'package:delegate_app/features/attendance/data/datasources/attendance_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/marketing/data/repositories/marketing_repository_impl.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:delegate_app/features/marketing/domain/repositories/marketing_repository.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_companies.dart';
import 'package:delegate_app/features/marketing/domain/usecases/get_marketing_delegates.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/marketing_search/data/datasources/marketing_search_remote_datasource.dart';
import 'package:delegate_app/features/marketing_search/data/repositories/marketing_search_repository_impl.dart';
import 'package:delegate_app/features/marketing_search/domain/repositories/marketing_search_repository.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_company_by_code.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_delegate_by_phone.dart';
import 'package:delegate_app/features/marketing_search/domain/usecases/search_delegate_by_name.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_bloc.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_remote_data_source.dart';
import 'package:delegate_app/features/auth/data/datasources/delegate_login_api.dart';
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
import 'package:delegate_app/features/tracking/data/services/delegate_tracking_service.dart';
import 'package:delegate_app/core/providers/locale_provider.dart';
import 'package:delegate_app/core/cubit/theme_cubit.dart';
import 'package:delegate_app/features/penalties/data/datasources/penalty_remote_data_source.dart';
import 'package:delegate_app/features/penalties/data/repositories/penalty_repository_impl.dart';
import 'package:delegate_app/features/penalties/domain/repositories/penalty_repository.dart';
import 'package:delegate_app/features/penalties/domain/usecases/create_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_all_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_company_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/get_delegate_penalties_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/update_penalty_status_usecase.dart';
import 'package:delegate_app/features/penalties/domain/usecases/update_penalty_usecase.dart';
import 'package:delegate_app/features/penalties/presentation/bloc/penalty_bloc.dart';
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
import 'package:delegate_app/features/notifications/data/datasources/notification_local_data_source.dart';
import 'package:delegate_app/features/notifications/data/datasources/notification_remote_data_source.dart';
import 'package:delegate_app/features/notifications/data/repositories/notification_repository_impl.dart';
import 'package:delegate_app/features/notifications/domain/repositories/notification_repository.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_cached_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_notifications.dart';
import 'package:delegate_app/features/notifications/domain/usecases/get_unread_count.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_all_notifications_read.dart';
import 'package:delegate_app/features/notifications/domain/usecases/mark_notification_read.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_notification_for_user.dart';
import 'package:delegate_app/features/notifications/domain/usecases/delete_all_notifications_for_user.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/core/services/push_notification_service.dart';
import 'package:firebase_messaging/firebase_messaging.dart';
import 'package:flutter_local_notifications/flutter_local_notifications.dart';
import 'package:firebase_storage/firebase_storage.dart';
import 'package:delegate_app/features/feedback/feedback_injection.dart';
import 'package:delegate_app/features/private_label/private_label_injection.dart';
import 'package:delegate_app/core/services/trusted_time_service.dart';
import 'package:get_it/get_it.dart';

// Photo Permission Feature Imports
import 'package:delegate_app/core/services/sync_manager.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_offline_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/datasources/photo_permission_remote_datasource.dart';
import 'package:delegate_app/features/photo_permission/data/repositories/photo_permission_repository_impl.dart';
import 'package:delegate_app/features/photo_permission/domain/repositories/photo_permission_repository.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/request_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/approve_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/toggle_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_photo_permissions.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_ongoing_photo_permissions.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/upload_captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_company_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_captured_photo.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/delete_photo_permission.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/update_photo_permission_branches.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/update_photo_permission_dates.dart';
import 'package:delegate_app/features/photo_permission/domain/usecases/get_delegate_captured_photos.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/core/services/review_service.dart';

final sl = GetIt.instance;

Future<void> init({required SharedPreferences sharedPreferences}) async {
  // ! Core
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => ReviewService(prefs: sl()));
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
      isAnonymousSession: () =>
          sl<FirebaseAuth>().currentUser?.isAnonymous == true,
      signOutAuth: () => sl<FirebaseAuth>().signOut(),
      anonymousSessionRestored: sl<FirebaseAuth>().authStateChanges().map(
        (user) => user?.isAnonymous == true,
      ),
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
    () => AuthRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      clearPushRegistration: (userId) async {
        if (sl.isRegistered<PushNotificationService>()) {
          await sl<PushNotificationService>().clearToken(userId);
        }
      },
    ),
  );

  // Data sources
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<DelegateLoginApi>(
    () => FirebaseDelegateLoginApi(
      FirebaseFunctions.instanceFor(region: 'us-central1'),
    ),
  );
  sl.registerLazySingleton<AuthRemoteDataSource>(
    () => AuthRemoteDataSourceImpl(
      firestore: sl(),
      firebaseAuth: sl(),
      delegateLoginApi: sl(),
    ),
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
      reviewService: sl<ReviewService>(),
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
    () => CreateAdminBloc(
      createAdmin: sl(),
      getOrganizations: sl(),
      getCompaniesForOrg: sl(),
    ),
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

  // Company Search BLoC
  sl.registerFactory(() => CompanySearchBloc(searchCompaniesByCode: sl()));

  // Manage Marketing BLoC
  sl.registerFactory(
    () => ManageMarketingBloc(
      getMarketingEmployees: sl(),
      adminRepository: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetBranches(sl()));
  sl.registerLazySingleton(() => AddBranch(sl()));
  sl.registerLazySingleton(() => UpdateBranch(sl()));
  sl.registerLazySingleton(() => DeleteBranch(sl()));
  sl.registerLazySingleton(() => CreateAdmin(sl()));
  sl.registerLazySingleton(() => GetAdmins(sl()));
  sl.registerLazySingleton(() => GetOrganizations(sl()));
  sl.registerLazySingleton(() => GetCompaniesForOrg(sl()));
  sl.registerLazySingleton(() => DeleteAdminUser(sl()));
  sl.registerLazySingleton(() => SuspendAdminUser(sl()));
  sl.registerLazySingleton(() => UpdateAdminUser(sl()));
  sl.registerLazySingleton(() => GetCompanyDelegates(sl()));
  sl.registerLazySingleton(() => GetDashboardSummary(sl()));
  sl.registerLazySingleton(() => GetMarketingEmployees(sl()));
  sl.registerLazySingleton(() => SearchCompaniesByCode(sl()));
  sl.registerLazySingleton(() => GetCompanies(sl()));

  // Repository
  sl.registerLazySingleton<AdminRepository>(
    () => AdminRepositoryImpl(
      remoteDataSource: sl(),
      marketingDataSource: sl(),
    ),
  );

  // Company Repository
  sl.registerLazySingleton<CompanyRepository>(
    () => CompanyRepositoryImpl(remoteDataSource: sl()),
  );

  // Delegate Subscription Repository
  sl.registerLazySingleton<DelegateSubscriptionRepository>(
    () => DelegateSubscriptionRepositoryImpl(),
  );

  // Data source
  sl.registerLazySingleton<AdminRemoteDataSource>(
    () => AdminRemoteDataSourceImpl(firestore: sl()),
  );

  // Marketing data source
  sl.registerLazySingleton<ManageMarketingRemoteDataSource>(
    () => ManageMarketingRemoteDataSourceImpl(firestore: sl()),
  );

  // Company Data source
  sl.registerLazySingleton<CompanyRemoteDataSource>(
    () => CompanyRemoteDataSourceImpl(firestore: sl()),
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
      deleteTask: sl(),
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
      getCachedNotifications: sl(),
      getUnreadCount: sl(),
      markNotificationRead: sl(),
      markAllNotificationsRead: sl(),
      deleteNotificationForUser: sl(),
      deleteAllNotificationsForUser: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetNotifications(sl()));
  sl.registerLazySingleton(() => GetCachedNotifications(sl()));
  sl.registerLazySingleton(() => GetUnreadCount(sl()));
  sl.registerLazySingleton(() => MarkNotificationRead(sl()));
  sl.registerLazySingleton(() => MarkAllNotificationsRead(sl()));
  sl.registerLazySingleton(() => DeleteNotificationForUser(sl()));
  sl.registerLazySingleton(() => DeleteAllNotificationsForUser(sl()));

  // Repository
  sl.registerLazySingleton<NotificationRepository>(
    () => NotificationRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
    ),
  );

  // Data sources
  sl.registerLazySingleton<NotificationLocalDataSource>(
    () => NotificationLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<NotificationRemoteDataSource>(
    () => NotificationRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Feedback
  initFeedbackDependencies();

  // ! Features - Private Label (توثيق يومي + KPI شهري)
  initPrivateLabelDependencies();

  // ! Features - Marketing
  sl.registerLazySingleton(
    () => BranchPreferenceService(prefs: sl()),
  );
  sl.registerLazySingleton(
    () => FloorVerificationService(prefs: sl(), firestore: sl()),
  );
  sl.registerFactory(
    () => MarketingBloc(
      getCompanies: sl(),
      getDelegates: sl(),
      remoteDataSource: sl(),
      branchPreferenceService: sl(),
    ),
  );
  sl.registerLazySingleton(() => GetMarketingCompanies(sl()));
  sl.registerLazySingleton(() => GetMarketingDelegates(sl()));
  sl.registerLazySingleton<MarketingRepository>(
    () => MarketingRepositoryImpl(remoteDataSource: sl()),
  );
  sl.registerLazySingleton<MarketingRemoteDataSource>(
    () => MarketingRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Marketing Search
  // Bloc
  sl.registerFactory(
    () => MarketingSearchBloc(
      searchCompanyByCode: sl(),
      searchDelegateByPhone: sl(),
      searchDelegateByName: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => SearchCompanyByCode(sl()));
  sl.registerLazySingleton(() => SearchDelegateByPhone(sl()));
  sl.registerLazySingleton(() => SearchDelegateByName(sl()));

  // Repository
  sl.registerLazySingleton<MarketingSearchRepository>(
    () => MarketingSearchRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<MarketingSearchRemoteDataSource>(
    () => MarketingSearchRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Penalties
  sl.registerFactory(
    () => PenaltyBloc(
      createPenaltyUseCase: sl(),
      getCompanyPenaltiesUseCase: sl(),
      getAllPenaltiesUseCase: sl(),
      getDelegatePenaltiesUseCase: sl(),
      updatePenaltyUseCase: sl(),
      repository: sl(),
    ),
  );

  sl.registerLazySingleton(() => CreatePenaltyUseCase(sl()));
  sl.registerLazySingleton(() => GetCompanyPenaltiesUseCase(sl()));
  sl.registerLazySingleton(() => GetDelegatePenaltiesUseCase(sl()));
  sl.registerLazySingleton(() => GetAllPenaltiesUseCase(sl()));
  sl.registerLazySingleton(() => UpdatePenaltyStatusUseCase(sl()));
  sl.registerLazySingleton(() => UpdatePenaltyUseCase(sl()));

  sl.registerLazySingleton<PenaltyRepository>(
    () => PenaltyRepositoryImpl(remoteDataSource: sl()),
  );

  sl.registerLazySingleton<PenaltyRemoteDataSource>(
    () => PenaltyRemoteDataSourceImpl(
      firestore: sl(),
      storage: sl(),
    ),
  );

  // ! Features - Photo Permission
  // Bloc
  sl.registerFactory(
    () => PhotoPermissionBloc(
      requestPhotoPermission: sl(),
      approvePhotoPermission: sl(),
      togglePhotoPermission: sl(),
      getPhotoPermissions: sl(),
      getOngoingPhotoPermissions: sl(),
      uploadCapturedPhoto: sl(),
      getCapturedPhotos: sl(),
      getDelegateCapturedPhotos: sl(),
      getCompanyCapturedPhotos: sl(),
      deleteCapturedPhoto: sl(),
      deletePhotoPermission: sl(),
      updatePhotoPermissionBranches: sl(),
      updatePhotoPermissionDates: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => RequestPhotoPermission(sl()));
  sl.registerLazySingleton(() => ApprovePhotoPermission(sl()));
  sl.registerLazySingleton(() => TogglePhotoPermission(sl()));
  sl.registerLazySingleton(() => GetPhotoPermissions(sl()));
  sl.registerLazySingleton(() => GetOngoingPhotoPermissions(sl()));
  sl.registerLazySingleton(() => UploadCapturedPhoto(sl()));
  sl.registerLazySingleton(() => GetCapturedPhotos(sl()));
  sl.registerLazySingleton(() => GetDelegateCapturedPhotos(sl()));
  sl.registerLazySingleton(() => GetCompanyCapturedPhotos(sl()));
  sl.registerLazySingleton(() => DeleteCapturedPhoto(sl()));
  sl.registerLazySingleton(() => DeletePhotoPermission(sl()));
  sl.registerLazySingleton(() => UpdatePhotoPermissionBranches(sl()));
  sl.registerLazySingleton(() => UpdatePhotoPermissionDates(sl()));

  // Repository
  sl.registerLazySingleton<PhotoPermissionRepository>(
    () => PhotoPermissionRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<PhotoPermissionRemoteDataSource>(
    () => PhotoPermissionRemoteDataSourceImpl(
      firestore: sl(),
      storage: sl(),
    ),
  );
  sl.registerLazySingleton<PhotoOfflineDataSource>(
    () => PhotoOfflineDataSource(),
  );
  
  // Sync Manager
  sl.registerLazySingleton<SyncManager>(
    () => SyncManager(
      offlineDataSource: sl(),
      remoteDataSource: sl(),
    ),
  );

  // Trusted Time Service
  sl.registerLazySingleton<TrustedTimeService>(
    () => TrustedTimeService(firestore: sl()),
  );

  // Delegate Tracking Service
  sl.registerLazySingleton<DelegateTrackingService>(
    () => DelegateTrackingService(firestore: sl()),
  );

  // ! Core

  // ! External
  // Firebase initialization is disabled in main.dart for Demo Mode.
  // We register them as lazy singletons if needed, but ensure they aren't
  // accessed unless Firebase.initializeApp() is actually called.

  sl.registerLazySingleton(() => FirebaseFirestore.instance);
  sl.registerLazySingleton(() => FirebaseAuth.instance);
  sl.registerLazySingleton(() => FirebaseStorage.instance);
}

/// Minimal dependency initialization specifically for background isolates (e.g. WorkManager photo sync).
/// Avoids loading hundreds of BLoCs, UI UseCases, and services into background memory.
Future<void> initBackgroundSync() async {
  if (!sl.isRegistered<FirebaseFirestore>()) {
    sl.registerLazySingleton(() => FirebaseFirestore.instance);
  }
  if (!sl.isRegistered<FirebaseStorage>()) {
    sl.registerLazySingleton(() => FirebaseStorage.instance);
  }
  if (!sl.isRegistered<PhotoOfflineDataSource>()) {
    sl.registerLazySingleton<PhotoOfflineDataSource>(
      () => PhotoOfflineDataSource(),
    );
  }
  if (!sl.isRegistered<PhotoPermissionRemoteDataSource>()) {
    sl.registerLazySingleton<PhotoPermissionRemoteDataSource>(
      () => PhotoPermissionRemoteDataSourceImpl(
        firestore: sl(),
        storage: sl(),
      ),
    );
  }
  if (!sl.isRegistered<SyncManager>()) {
    sl.registerLazySingleton<SyncManager>(
      () => SyncManager(
        offlineDataSource: sl(),
        remoteDataSource: sl(),
        isBackground: true,
      ),
    );
  }
}
