import 'package:cloud_firestore/cloud_firestore.dart';
import 'package:delegate_app/features/admin/data/datasources/admin_remote_data_source.dart';
import 'package:delegate_app/features/admin/data/repositories/admin_repository_impl.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/add_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_branch.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_branches.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_branch.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
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
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

Future<void> init({required SharedPreferences sharedPreferences}) async {
  // ! Core
  sl.registerLazySingleton(() => sharedPreferences);
  sl.registerLazySingleton(() => LocaleProvider(sharedPreferences));
  sl.registerLazySingleton(() => ThemeCubit(sl()));

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
    () => AuthRemoteDataSourceImpl(firestore: sl()),
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
      syncAttendance: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => CheckIn(sl()));
  sl.registerLazySingleton(() => CheckOut(sl()));
  sl.registerLazySingleton(() => GetHistory(sl()));
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

  // Use cases
  sl.registerLazySingleton(() => GetBranches(sl()));
  sl.registerLazySingleton(() => AddBranch(sl()));
  sl.registerLazySingleton(() => UpdateBranch(sl()));
  sl.registerLazySingleton(() => DeleteBranch(sl()));

  // Repository
  sl.registerLazySingleton<AdminRepository>(
    () => AdminRepositoryImpl(remoteDataSource: sl()),
  );

  // Data source
  sl.registerLazySingleton<AdminRemoteDataSource>(
    () => AdminRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Features - Changelog
  // Bloc
  sl.registerFactory(
    () => ChangelogBloc(
      getNewUpdates: sl(),
      getAllUpdates: sl(),
    ),
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

  // ! Core

  // ! External
  // Firebase initialization is disabled in main.dart for Demo Mode.
  // We register them as lazy singletons if needed, but ensure they aren't
  // accessed unless Firebase.initializeApp() is actually called.

  sl.registerLazySingleton(() => FirebaseFirestore.instance);
}
