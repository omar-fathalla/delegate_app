import 'package:dartz/dartz.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';

import 'package:delegate_app/core/usecases/usecase.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_organizations.dart';

class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late GetOrganizations usecase;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockAdminRepository = MockAdminRepository();
    usecase = GetOrganizations(mockAdminRepository);
  });

  final tOrganizations = [
    {
      'id': 'org1',
      'name': 'Test Organization',
    }
  ];

  test(
    'should get organizations from the repository',
    () async {
      // arrange
      when(() => mockAdminRepository.getOrganizations())
          .thenAnswer((_) async => Right(tOrganizations));
      // act
      final result = await usecase(NoParams());
      // assert
      expect(result, Right(tOrganizations));
      verify(() => mockAdminRepository.getOrganizations()).called(1);
      verifyNoMoreInteractions(mockAdminRepository);
    },
  );
}
