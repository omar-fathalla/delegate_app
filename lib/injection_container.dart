import 'package:cloud_firestore/cloud_firestore.dart';
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
import 'package:delegate_app/features/attendance/data/repositories/attendance_repository_impl.dart';
import 'package:delegate_app/features/attendance/domain/repositories/attendance_repository.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_in.dart';
import 'package:delegate_app/features/attendance/domain/usecases/check_out.dart';
import 'package:delegate_app/features/attendance/domain/usecases/get_history.dart';
import 'package:delegate_app/features/attendance/presentation/bloc/attendance_bloc.dart';

import 'package:delegate_app/features/auth/presentation/bloc/auth_bloc.dart';
import 'package:delegate_app/features/profile/data/datasources/profile_remote_data_source.dart';
import 'package:delegate_app/features/profile/data/repositories/profile_repository_impl.dart';
import 'package:delegate_app/features/profile/domain/repositories/profile_repository.dart';
import 'package:delegate_app/features/profile/domain/usecases/get_delegate_profile.dart';
import 'package:delegate_app/features/profile/presentation/bloc/profile_bloc.dart';
import 'package:get_it/get_it.dart';

final sl = GetIt.instance;

Future<void> init() async {
  // ! Core
  final sharedPreferences = await SharedPreferences.getInstance();
  sl.registerLazySingleton(() => sharedPreferences);

  // ! Features - Auth
  // Bloc
  sl.registerFactory(
    () => AuthBloc(
      loginUseCase: sl(),
      checkAutoLoginUseCase: sl(),
      logoutUseCase: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => Login(sl()));
  sl.registerLazySingleton(() => CheckAutoLogin(sl()));
  sl.registerLazySingleton(() => Logout(sl()));

  // Repository
  sl.registerLazySingleton<AuthRepository>(
    () => AuthRepositoryImpl(remoteDataSource: sl(), localDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<AuthLocalDataSource>(
    () => AuthLocalDataSourceImpl(sharedPreferences: sl()),
  );
  // USE MOCKS FOR DEMO
  // sl.registerLazySingleton<AuthRemoteDataSource>(() => MockAuthDataSource());
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
    () => AttendanceBloc(checkIn: sl(), checkOut: sl(), getHistory: sl()),
  );

  // Use cases
  sl.registerLazySingleton(() => CheckIn(sl()));
  sl.registerLazySingleton(() => CheckOut(sl()));
  sl.registerLazySingleton(() => GetHistory(sl()));

  // Repository
  sl.registerLazySingleton<AttendanceRepository>(
    () => AttendanceRepositoryImpl(
      remoteDataSource: sl(),
      localDataSource: sl(),
      isDemoMode: false,
    ),
  );

  // Data sources
  sl.registerLazySingleton<AttendanceLocalDataSource>(
    () => AttendanceLocalDataSourceImpl(sharedPreferences: sl()),
  );
  // USE MOCKS FOR DEMO
  // sl.registerLazySingleton<AttendanceRemoteDataSource>(
  //   () => MockAttendanceDataSource(),
  // );
  sl.registerLazySingleton<AttendanceRemoteDataSource>(
    () => AttendanceRemoteDataSourceImpl(firestore: sl()),
  );

  // ! Core

  // ! External
  // Firebase initialization is disabled in main.dart for Demo Mode.
  // We register them as lazy singletons if needed, but ensure they aren't
  // accessed unless Firebase.initializeApp() is actually called.

  final firestore = FirebaseFirestore.instance;
  sl.registerLazySingleton(() => firestore);
}
