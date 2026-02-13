---
description: Write Unit and Widget tests using mocktail and bloc_test following Clean Architecture test structure.
---

# Write Tests

## 1. Add test dependencies

// turbo
```
flutter pub add --dev mocktail bloc_test
```

## 2. Test directory structure

Mirror the `lib/` structure:

```
test/
├── features/
│   ├── auth/
│   │   ├── data/
│   │   │   ├── datasources/
│   │   │   └── repositories/
│   │   ├── domain/
│   │   │   └── usecases/
│   │   └── presentation/
│   │       └── bloc/
│   ├── attendance/
│   │   ├── data/
│   │   ├── domain/
│   │   └── presentation/
│   └── profile/
└── core/
```

## 3. Unit Test — Use Case

Create `test/features/<feature>/domain/usecases/<usecase>_test.dart`:

```dart
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dartz/dartz.dart';

class MockFeatureRepository extends Mock implements FeatureRepository {}

void main() {
  late UseCaseName useCase;
  late MockFeatureRepository mockRepository;

  setUp(() {
    mockRepository = MockFeatureRepository();
    useCase = UseCaseName(mockRepository);
  });

  group('UseCaseName', () {
    test('should return data when repository succeeds', () async {
      // Arrange
      when(() => mockRepository.getData(any()))
          .thenAnswer((_) async => const Right(expectedData));

      // Act
      final result = await useCase(params);

      // Assert
      expect(result, const Right(expectedData));
      verify(() => mockRepository.getData(any())).called(1);
      verifyNoMoreInteractions(mockRepository);
    });

    test('should return Failure when repository fails', () async {
      // Arrange
      when(() => mockRepository.getData(any()))
          .thenAnswer((_) async => const Left(
                ServerFailure(message: 'خطأ في الخادم'),
              ));

      // Act
      final result = await useCase(params);

      // Assert
      expect(result, isA<Left>());
    });
  });
}
```

## 4. Bloc Test

Create `test/features/<feature>/presentation/bloc/<feature>_bloc_test.dart`:

```dart
import 'package:bloc_test/bloc_test.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dartz/dartz.dart';

class MockUseCase extends Mock implements UseCaseName {}

void main() {
  late FeatureBloc bloc;
  late MockUseCase mockUseCase;

  setUp(() {
    mockUseCase = MockUseCase();
    bloc = FeatureBloc(useCase: mockUseCase);
  });

  tearDown(() => bloc.close());

  test('initial state should be FeatureInitial', () {
    expect(bloc.state, equals(FeatureInitial()));
  });

  blocTest<FeatureBloc, FeatureState>(
    'emits [Loading, Loaded] when data is fetched successfully',
    build: () {
      when(() => mockUseCase(any()))
          .thenAnswer((_) async => const Right(testData));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadRequested()),
    expect: () => [
      FeatureLoading(),
      FeatureLoaded(data: testData),
    ],
  );

  blocTest<FeatureBloc, FeatureState>(
    'emits [Loading, Error] when fetching fails',
    build: () {
      when(() => mockUseCase(any()))
          .thenAnswer((_) async => const Left(
                ServerFailure(message: 'حدث خطأ'),
              ));
      return bloc;
    },
    act: (bloc) => bloc.add(const LoadRequested()),
    expect: () => [
      FeatureLoading(),
      const FeatureError(message: 'حدث خطأ'),
    ],
  );
}
```

## 5. Repository Test

Create `test/features/<feature>/data/repositories/<feature>_repository_impl_test.dart`:

```dart
class MockRemoteDataSource extends Mock implements FeatureRemoteDataSource {}

void main() {
  late FeatureRepositoryImpl repository;
  late MockRemoteDataSource mockRemoteDataSource;

  setUp(() {
    mockRemoteDataSource = MockRemoteDataSource();
    repository = FeatureRepositoryImpl(remoteDataSource: mockRemoteDataSource);
  });

  test('should return Right(data) when remote call succeeds', () async {
    when(() => mockRemoteDataSource.getData(any()))
        .thenAnswer((_) async => testModel);

    final result = await repository.getData('id');

    expect(result, isA<Right>());
  });

  test('should return Left(ServerFailure) when remote call throws', () async {
    when(() => mockRemoteDataSource.getData(any()))
        .thenThrow(const ServerException(message: 'error'));

    final result = await repository.getData('id');

    expect(result, isA<Left>());
  });
}
```

## 6. Run tests

// turbo
```
flutter test
```

## 7. Run with coverage

```
flutter test --coverage
```

Then generate HTML report (optional):

```
genhtml coverage/lcov.info -o coverage/html
```

## Rules

- ✅ Every Use Case must have at least 2 tests (success + failure).
- ✅ Every Bloc must test: initial state, success flow, error flow.
- ✅ Use `setUp()` for initialization, `tearDown()` for cleanup.
- ✅ Group related tests with `group()`.
- ✅ Use `Arrange → Act → Assert` pattern.
- ❌ Never test implementation details — test behavior and outputs.
- ❌ Never use real Firebase in unit tests — always mock.
