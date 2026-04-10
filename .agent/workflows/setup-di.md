---
description: Register a new dependency (Bloc, UseCase, Repository, DataSource) in the GetIt service locator.
---

# Register a Dependency in GetIt

## File Location

All registrations go in `lib/injection_container.dart`.

## Registration Order (Top → Bottom)

Always register dependencies in this order within each feature section:

```dart
// ! Features - <FeatureName>

// 1. Bloc (registerFactory — new instance each time)
sl.registerFactory(() => FeatureBloc(useCaseA: sl(), useCaseB: sl()));

// 2. Use Cases (registerLazySingleton — single instance)
sl.registerLazySingleton(() => UseCaseA(sl()));
sl.registerLazySingleton(() => UseCaseB(sl()));

// 3. Repository (registerLazySingleton with abstract type)
sl.registerLazySingleton<FeatureRepository>(
  () => FeatureRepositoryImpl(remoteDataSource: sl(), localDataSource: sl()),
);

// 4. Data Sources (registerLazySingleton with abstract type)
sl.registerLazySingleton<FeatureRemoteDataSource>(
  () => FeatureRemoteDataSourceImpl(firestore: sl()),
);
sl.registerLazySingleton<FeatureLocalDataSource>(
  () => FeatureLocalDataSourceImpl(sharedPreferences: sl()),
);
```

## Rules

1. **Blocs** → `registerFactory` (new instance per widget tree).
2. **Everything else** → `registerLazySingleton` (shared instance).
3. **Abstract type** → Always register with the abstract type for Repositories and DataSources: `sl.registerLazySingleton<AbstractType>(() => ConcreteImpl())`.
4. **Use `sl()`** to resolve dependencies — never manually instantiate.
5. **External services** (Firebase, SharedPreferences) go under the `// ! External` section at the bottom.

## Switching to Mock Mode

For demo/testing, comment out the real implementation and register a mock:

```dart
// Real
// sl.registerLazySingleton<FeatureRemoteDataSource>(
//   () => FeatureRemoteDataSourceImpl(firestore: sl()),
// );

// Mock
sl.registerLazySingleton<FeatureRemoteDataSource>(
  () => MockFeatureDataSource(),
);
```
