import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:dartz/dartz.dart';
import 'package:delegate_app/features/admin/presentation/bloc/create_admin_bloc.dart';
import 'package:delegate_app/features/admin/domain/usecases/create_admin.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_organizations.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_companies_for_org.dart';

class MockCreateAdmin extends Mock implements CreateAdmin {}
class MockGetOrganizations extends Mock implements GetOrganizations {}
class MockGetCompaniesForOrg extends Mock implements GetCompaniesForOrg {}

void main() {
  late CreateAdminBloc bloc;
  late MockCreateAdmin mockCreateAdmin;
  late MockGetOrganizations mockGetOrganizations;
  late MockGetCompaniesForOrg mockGetCompaniesForOrg;

  setUp(() {
    mockCreateAdmin = MockCreateAdmin();
    mockGetOrganizations = MockGetOrganizations();
    mockGetCompaniesForOrg = MockGetCompaniesForOrg();
    bloc = CreateAdminBloc(
      createAdmin: mockCreateAdmin,
      getOrganizations: mockGetOrganizations,
      getCompaniesForOrg: mockGetCompaniesForOrg,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be CreateAdminInitial', () {
    expect(bloc.state, isA<CreateAdminInitial>());
  });

  test('should emit [CreateAdminCompaniesLoading, CreateAdminCompaniesLoaded] when LoadCompaniesForOrgRequested is added', () async {
    final tCompanies = [
      {'uid': 'comp_1', 'name': 'شركة أ'},
      {'uid': 'comp_2', 'name': 'شركة ب'},
    ];

    when(() => mockGetCompaniesForOrg.call(any()))
        .thenAnswer((_) async => Right(tCompanies));

    expectLater(
      bloc.stream,
      emitsInOrder([
        isA<CreateAdminCompaniesLoading>(),
        CreateAdminCompaniesLoaded(companies: tCompanies),
      ]),
    );

    bloc.add(const LoadCompaniesForOrgRequested(organizationUID: 'org_123'));
  });
}
