import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/presentation/bloc/create_admin_bloc.dart';


import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_organizations.dart';

class MockCreateAdmin extends Mock implements CreateAdmin {}
class MockGetOrganizations extends Mock implements GetOrganizations {}

void main() {
  late CreateAdminBloc bloc;
  late MockCreateAdmin mockCreateAdmin;
  late MockGetOrganizations mockGetOrganizations;

  setUp(() {
    mockCreateAdmin = MockCreateAdmin();
    mockGetOrganizations = MockGetOrganizations();
    bloc = CreateAdminBloc(
      createAdmin: mockCreateAdmin,
      getOrganizations: mockGetOrganizations,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be CreateAdminInitial', () {
    expect(bloc.state, isA<CreateAdminInitial>());
  });
}
