import 'package:connectivity_plus/connectivity_plus.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_local_data_source.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_remote_data_source.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/data/repositories/private_label_repository_impl.dart';
import 'package:delegate_app/features/private_label/domain/repositories/private_label_repository.dart';
import 'package:delegate_app/features/private_label/domain/usecases/cancel_private_label_rest_day.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_cached_private_label_month.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_pending_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_branches.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_organization_private_label_days.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_month.dart';
import 'package:delegate_app/features/private_label/domain/usecases/get_private_label_products.dart';
import 'package:delegate_app/features/private_label/domain/usecases/register_private_label_rest_day.dart';
import 'package:delegate_app/features/private_label/domain/usecases/review_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/save_private_label_product.dart';
import 'package:delegate_app/features/private_label/domain/usecases/submit_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/sync_pending_private_label_audits.dart';
import 'package:delegate_app/features/private_label/domain/usecases/delete_private_label_audit.dart';
import 'package:delegate_app/features/private_label/domain/usecases/update_private_label_audit.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_report_bloc.dart';
import 'package:delegate_app/injection_container.dart';

/// تسجيل dependencies ميزة البرايفت ليبل (توثيق يومي + KPI شهري + تدقيق).
void initPrivateLabelDependencies() {
  // Blocs (factory: one instance per screen / home card).
  sl.registerFactory(
    () => PrivateLabelBloc(
      getCachedMonth: sl(),
      getMonth: sl(),
      submitAudit: sl(),
      syncPendingAudits: sl(),
      getPendingAudits: sl(),
      registerRestDay: sl(),
      cancelRestDay: sl(),
      getAudits: sl(),
      getProducts: sl(),
      getBranches: sl(),
      // Auto-upload offline documentation once the device is back online.
      connectivityStream: Connectivity()
          .onConnectivityChanged
          .map((results) => results.any((r) => r != ConnectivityResult.none)),
    ),
  );
  sl.registerFactory(
    () => PrivateLabelReviewBloc(
      getAudits: sl(),
      reviewAudit: sl(),
      getProducts: sl(),
      saveProduct: sl(),
      deleteAudit: sl(),
      updateAudit: sl(),
      getBranches: sl(),
    ),
  );
  sl.registerFactory(
    () => PrivateLabelReportBloc(
      getOrgMonthDays: sl(),
      getBranches: sl(),
    ),
  );

  // Use cases
  sl.registerLazySingleton(() => GetCachedPrivateLabelMonth(sl()));
  sl.registerLazySingleton(() => GetPrivateLabelMonth(sl()));
  sl.registerLazySingleton(() => SubmitPrivateLabelAudit(sl()));
  sl.registerLazySingleton(() => SyncPendingPrivateLabelAudits(sl()));
  sl.registerLazySingleton(() => GetPendingPrivateLabelAudits(sl()));
  sl.registerLazySingleton(() => RegisterPrivateLabelRestDay(sl()));
  sl.registerLazySingleton(() => CancelPrivateLabelRestDay(sl()));
  sl.registerLazySingleton(() => GetPrivateLabelAudits(sl()));
  sl.registerLazySingleton(() => ReviewPrivateLabelAudit(sl()));
  sl.registerLazySingleton(() => GetPrivateLabelProducts(sl()));
  sl.registerLazySingleton(() => SavePrivateLabelProduct(sl()));
  sl.registerLazySingleton(() => DeletePrivateLabelAudit(sl()));
  sl.registerLazySingleton(() => UpdatePrivateLabelAudit(sl()));
  sl.registerLazySingleton(() => GetPrivateLabelBranches(sl()));
  sl.registerLazySingleton(() => GetOrganizationPrivateLabelDays(sl()));

  // Repository (singleton: shares the in-flight sync guard across blocs).
  sl.registerLazySingleton<PrivateLabelRepository>(
    () => PrivateLabelRepositoryImpl(remoteDataSource: sl(), localDataSource: sl()),
  );

  // Data sources
  sl.registerLazySingleton<PrivateLabelLocalDataSource>(
    () => PrivateLabelLocalDataSourceImpl(sharedPreferences: sl()),
  );
  sl.registerLazySingleton<PrivateLabelRemoteDataSource>(
    () => PrivateLabelRemoteDataSourceImpl(firestore: sl(), storage: sl()),
  );
  sl.registerLazySingleton<PrivateLabelPermissionsRemoteDataSource>(
    () => PrivateLabelPermissionsRemoteDataSourceImpl(firestore: sl()),
  );
}
