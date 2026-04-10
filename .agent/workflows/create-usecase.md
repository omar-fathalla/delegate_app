---
description: Create a Use Case class with Params, repository injection, and Either return type following Clean Architecture.
---

# Create a Use Case

## 1. Base UseCase abstract class

Ensure `lib/core/usecases/usecase.dart` exists:

```dart
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';

abstract class UseCase<Type, Params> {
  Future<Either<Failure, Type>> call(Params params);
}

/// For use cases that don't need parameters
class NoParams extends Equatable {
  @override
  List<Object?> get props => [];
}
```

## 2. Create the Use Case with Params

Create `lib/features/<feature>/domain/usecases/<action_name>.dart`:

```dart
import 'package:dartz/dartz.dart';
import 'package:equatable/equatable.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';

class GetDelegateProfile extends UseCase<DelegatePerson, GetDelegateProfileParams> {
  final ProfileRepository repository;

  GetDelegateProfile(this.repository);

  @override
  Future<Either<Failure, DelegatePerson>> call(GetDelegateProfileParams params) {
    return repository.getDelegateProfile(
      organizationUID: params.organizationUID,
      companyUID: params.companyUID,
      uid: params.uid,
    );
  }
}

class GetDelegateProfileParams extends Equatable {
  final String organizationUID;
  final String companyUID;
  final String uid;

  const GetDelegateProfileParams({
    required this.organizationUID,
    required this.companyUID,
    required this.uid,
  });

  @override
  List<Object?> get props => [organizationUID, companyUID, uid];
}
```

## 3. Use Case without Params

```dart
class GetCurrentUser extends UseCase<User, NoParams> {
  final AuthRepository repository;

  GetCurrentUser(this.repository);

  @override
  Future<Either<Failure, User>> call(NoParams params) {
    return repository.getCurrentUser();
  }
}
```

## 4. Register in DI

Add to `lib/injection_container.dart`:

```dart
sl.registerLazySingleton(() => GetDelegateProfile(sl()));
```

## 5. Use in Bloc

```dart
class ProfileBloc extends Bloc<ProfileEvent, ProfileState> {
  final GetDelegateProfile getDelegateProfile;

  ProfileBloc({required this.getDelegateProfile}) : super(ProfileInitial()) {
    on<LoadProfileRequested>(_onLoadProfile);
  }

  Future<void> _onLoadProfile(
    LoadProfileRequested event,
    Emitter<ProfileState> emit,
  ) async {
    emit(ProfileLoading());
    final result = await getDelegateProfile(
      GetDelegateProfileParams(
        organizationUID: event.organizationUID,
        companyUID: event.companyUID,
        uid: event.uid,
      ),
    );
    result.fold(
      (failure) => emit(ProfileError(message: failure.message)),
      (delegate) => emit(ProfileLoaded(delegate: delegate)),
    );
  }
}
```

## Rules

- ✅ One class per Use Case (Single Responsibility Principle).
- ✅ Use Case only calls repository — no business logic leaks.
- ✅ Params class extends `Equatable` for value comparison.
- ✅ Use `NoParams` when no input is needed.
- ✅ Always return `Future<Either<Failure, T>>`.
- ❌ Never access data sources directly from a Use Case.
- ❌ Never import Flutter/UI packages in domain layer.
