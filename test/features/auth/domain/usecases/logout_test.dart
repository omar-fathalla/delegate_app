import 'package:dartz/dartz.dart';
import 'package:delegate_app/core/error/failures.dart';
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

  test('signs out through the repository and passes the user id', () async {
    when(
      () => mockRepository.logout(userId: 'uid-1'),
    ).thenAnswer((_) async => const Right(null));

    final result = await usecase(const LogoutParams(userId: 'uid-1'));

    expect(result, const Right(null));
    verify(() => mockRepository.logout(userId: 'uid-1')).called(1);
    verifyNever(() => mockRepository.clearCache());
  });

  test('returns the repository failure', () async {
    when(
      () => mockRepository.logout(userId: any(named: 'userId')),
    ).thenAnswer((_) async => const Left(CacheFailure('فشل مسح البيانات')));

    final result = await usecase(const LogoutParams());

    expect(result, const Left(CacheFailure('فشل مسح البيانات')));
  });
}
