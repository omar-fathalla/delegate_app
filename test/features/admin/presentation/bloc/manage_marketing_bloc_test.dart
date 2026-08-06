import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_marketing_bloc.dart';


import 'package:delegate_app/features/admin/domain/usecases/get_marketing_employees.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';

class MockGetMarketingEmployees extends Mock implements GetMarketingEmployees {}
class MockAdminRepository extends Mock implements AdminRepository {}

void main() {
  late ManageMarketingBloc bloc;
  late MockGetMarketingEmployees mockGetMarketingEmployees;
  late MockAdminRepository mockAdminRepository;

  setUp(() {
    mockGetMarketingEmployees = MockGetMarketingEmployees();
    mockAdminRepository = MockAdminRepository();
    bloc = ManageMarketingBloc(
      getMarketingEmployees: mockGetMarketingEmployees,
      adminRepository: mockAdminRepository,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be ManageMarketingInitial', () {
    expect(bloc.state, isA<ManageMarketingInitial>());
  });
}
