import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/presentation/bloc/manage_admins_bloc.dart';


import 'package:delegate_app/features/admin/domain/usecases/get_admins.dart';
import 'package:delegate_app/features/admin/domain/usecases/suspend_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/delete_admin_user.dart';
import 'package:delegate_app/features/admin/domain/usecases/update_admin_user.dart';

class MockGetAdmins extends Mock implements GetAdmins {}
class MockSuspendAdminUser extends Mock implements SuspendAdminUser {}
class MockDeleteAdminUser extends Mock implements DeleteAdminUser {}
class MockUpdateAdminUser extends Mock implements UpdateAdminUser {}

void main() {
  late ManageAdminsBloc bloc;
  late MockGetAdmins mockGetAdmins;
  late MockSuspendAdminUser mockSuspendAdminUser;
  late MockDeleteAdminUser mockDeleteAdminUser;
  late MockUpdateAdminUser mockUpdateAdminUser;

  setUp(() {
    mockGetAdmins = MockGetAdmins();
    mockSuspendAdminUser = MockSuspendAdminUser();
    mockDeleteAdminUser = MockDeleteAdminUser();
    mockUpdateAdminUser = MockUpdateAdminUser();
    bloc = ManageAdminsBloc(
      getAdmins: mockGetAdmins,
      suspendAdminUser: mockSuspendAdminUser,
      deleteAdminUser: mockDeleteAdminUser,
      updateAdminUser: mockUpdateAdminUser,
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be ManageAdminsInitial', () {
    expect(bloc.state, isA<ManageAdminsInitial>());
  });
}
