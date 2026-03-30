import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/auth/domain/repositories/auth_repository.dart';
import 'package:delegate_app/features/auth/domain/usecases/logout.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

class MockAuthRepository extends Mock implements AuthRepository {}

class FakeDelegate extends Fake implements Delegate {}

void main() {
  late Logout usecase;
  late MockAuthRepository mockRepository;

  setUpAll(() {
    registerFallbackValue(FakeDelegate());
  });

  setUp(() {
    mockRepository = MockAuthRepository();
    usecase = Logout(mockRepository);
  });

  test('should call clearCache on the repository', () async {
    // arrange
    when(
      () => mockRepository.clearCache(),
    ).thenAnswer((_) async => const Right(null));
    // act
    final result = await usecase(NoParams());
    // assert
    expect(result, const Right(null));
    verify(() => mockRepository.clearCache()).called(1);
  });

  test('should return failure when clearCache fails', () async {
    // arrange
    when(
      () => mockRepository.clearCache(),
    ).thenAnswer((_) async => const Left(CacheFailure('فشل مسح البيانات')));
    // act
    final result = await usecase(NoParams());
    // assert
    expect(result, const Left(CacheFailure('فشل مسح البيانات')));
  });
}
