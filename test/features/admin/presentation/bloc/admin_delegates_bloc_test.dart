import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/admin_delegates_state.dart';


import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';

class MockGetCompanyDelegates extends Mock implements GetCompanyDelegates {}

void main() {
  late AdminDelegatesBloc bloc;
  late MockGetCompanyDelegates mockGetCompanyDelegates;

  setUp(() {
    mockGetCompanyDelegates = MockGetCompanyDelegates();
    bloc = AdminDelegatesBloc(
      getCompanyDelegates: mockGetCompanyDelegates
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be AdminDelegatesInitial', () {
    expect(bloc.state, isA<AdminDelegatesInitial>());
  });
}
