---
description: Create a new Clean Architecture feature with all layers (domain, data, presentation) following Tashil project conventions.
---

# Create a New Feature

Follow these steps to scaffold a complete Clean Architecture feature.

## 1. Create the folder structure

// turbo
Create the following directories under `lib/features/<feature_name>/`:

```
lib/features/<feature_name>/
├── data/
│   ├── datasources/
│   ├── models/
│   └── repositories/
├── domain/
│   ├── entities/
│   ├── repositories/
│   └── usecases/
└── presentation/
    ├── bloc/
    ├── pages/
    └── widgets/
```

## 2. Domain Layer — Entity

Create `lib/features/<feature_name>/domain/entities/<entity_name>.dart`:

- Class extends `Equatable`.
- Use camelCase field names matching the existing Firestore schema exactly.
- Use `List<Object?>` for `props`.

```dart
import 'package:equatable/equatable.dart';

class EntityName extends Equatable {
  final String uid;
  // ... all fields matching the Firestore document

  const EntityName({required this.uid});

  @override
  List<Object?> get props => [uid];
}
```

## 3. Domain Layer — Repository Contract

Create `lib/features/<feature_name>/domain/repositories/<feature>_repository.dart`:

- Abstract class.
- All methods return `Future<Either<Failure, T>>`.

```dart
import 'package:dartz/dartz.dart';

abstract class FeatureRepository {
  Future<Either<Failure, Entity>> getEntity(String id);
}
```

## 4. Domain Layer — Use Case

Create `lib/features/<feature_name>/domain/usecases/<use_case_name>.dart`:

- One class per use case.
- Inject the repository via constructor.
- Single `call()` method returning `Future<Either<Failure, T>>`.

## 5. Data Layer — Model

Create `lib/features/<feature_name>/data/models/<entity_name>_model.dart`:

- Extends the Domain Entity.
- Includes `fromJson()` factory and `toJson()` method.
- **CRITICAL:** JSON keys MUST use camelCase matching the existing Firestore schema (e.g., `nationalityID`, `companyUID`).
- Convert `Timestamp` ↔ `DateTime` in the model.

## 6. Data Layer — Remote Data Source

Create `lib/features/<feature_name>/data/datasources/<feature>_remote_data_source.dart`:

- Abstract class defining the contract.
- Impl class with `FirebaseFirestore` injected.
- Construct Firestore paths using: `/organizations/{orgId}/companies/{compId}/...`
- **Never access root-level collections directly.**

## 7. Data Layer — Repository Implementation

Create `lib/features/<feature_name>/data/repositories/<feature>_repository_impl.dart`:

- Implements the Domain repository.
- Wraps data source calls in try/catch.
- Returns `Left(Failure)` or `Right(Success)`.

## 8. Presentation Layer — Bloc

Create:
- `lib/features/<feature_name>/presentation/bloc/<feature>_event.dart`
- `lib/features/<feature_name>/presentation/bloc/<feature>_state.dart`
- `lib/features/<feature_name>/presentation/bloc/<feature>_bloc.dart`

- Events: clearly named (e.g., `LoadRequested`, `SubmitRequested`).
- States: extend `Equatable` (e.g., `Loading`, `Loaded`, `Error`).
- Bloc: inject Use Cases via constructor.

## 9. Presentation Layer — Page & Widgets

Create:
- `lib/features/<feature_name>/presentation/pages/<feature>_page.dart`
- Widget files under `presentation/widgets/`

- Use Material 3 components.
- Ensure RTL (Arabic) support.
- Use `BlocBuilder` or `BlocConsumer` to react to state changes.

## 10. Register in Dependency Injection

Update `lib/injection_container.dart`:

```dart
// ! Features - <FeatureName>
// Bloc
sl.registerFactory(() => FeatureBloc(useCase: sl()));

// Use cases
sl.registerLazySingleton(() => UseCaseName(sl()));

// Repository
sl.registerLazySingleton<FeatureRepository>(
  () => FeatureRepositoryImpl(remoteDataSource: sl()),
);

// Data sources
sl.registerLazySingleton<FeatureRemoteDataSource>(
  () => FeatureRemoteDataSourceImpl(firestore: sl()),
);
```

## 11. Add Route

Add the new page route in `go_router` configuration.

## 12. Verify

// turbo
```
flutter analyze
```

Run analyze to ensure no lint issues.
