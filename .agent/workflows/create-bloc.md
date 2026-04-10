---
description: Create a new Bloc with strictly typed Events and States following flutter_bloc conventions and Equatable.
---

# Create a New Bloc

## 1. Create the Event file

Create `lib/features/<feature>/presentation/bloc/<feature>_event.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class FeatureEvent extends Equatable {
  const FeatureEvent();

  @override
  List<Object?> get props => [];
}

class LoadFeatureRequested extends FeatureEvent {
  const LoadFeatureRequested();
}

class SubmitFeatureRequested extends FeatureEvent {
  final String data;
  const SubmitFeatureRequested({required this.data});

  @override
  List<Object?> get props => [data];
}
```

## 2. Create the State file

Create `lib/features/<feature>/presentation/bloc/<feature>_state.dart`:

```dart
import 'package:equatable/equatable.dart';

abstract class FeatureState extends Equatable {
  const FeatureState();

  @override
  List<Object?> get props => [];
}

class FeatureInitial extends FeatureState {}

class FeatureLoading extends FeatureState {}

class FeatureLoaded extends FeatureState {
  final EntityType data;
  const FeatureLoaded({required this.data});

  @override
  List<Object?> get props => [data];
}

class FeatureError extends FeatureState {
  final String message;
  const FeatureError({required this.message});

  @override
  List<Object?> get props => [message];
}
```

## 3. Create the Bloc file

Create `lib/features/<feature>/presentation/bloc/<feature>_bloc.dart`:

```dart
import 'package:flutter_bloc/flutter_bloc.dart';

class FeatureBloc extends Bloc<FeatureEvent, FeatureState> {
  final UseCaseName useCase;

  FeatureBloc({required this.useCase}) : super(FeatureInitial()) {
    on<LoadFeatureRequested>(_onLoadRequested);
    on<SubmitFeatureRequested>(_onSubmitRequested);
  }

  Future<void> _onLoadRequested(
    LoadFeatureRequested event,
    Emitter<FeatureState> emit,
  ) async {
    emit(FeatureLoading());
    final result = await useCase();
    result.fold(
      (failure) => emit(FeatureError(message: failure.message)),
      (data) => emit(FeatureLoaded(data: data)),
    );
  }
}
```

## 4. Register in DI

Add to `lib/injection_container.dart`:

```dart
// Bloc
sl.registerFactory(() => FeatureBloc(useCase: sl()));
```

## 5. Use in Widget

```dart
BlocProvider(
  create: (_) => sl<FeatureBloc>()..add(const LoadFeatureRequested()),
  child: BlocBuilder<FeatureBloc, FeatureState>(
    builder: (context, state) {
      if (state is FeatureLoading) return const CircularProgressIndicator();
      if (state is FeatureLoaded) return FeatureView(data: state.data);
      if (state is FeatureError) return ErrorWidget(message: state.message);
      return const SizedBox.shrink();
    },
  ),
)
```

## Rules Reminder

- Events and States MUST extend `Equatable`.
- Use `const` constructors wherever possible.
- Never access Bloc logic outside the Presentation layer.
- Error messages should be user-friendly and Arabic-compatible.
- Each Bloc handler should use `Either.fold()` to map results.
