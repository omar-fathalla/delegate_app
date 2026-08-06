import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/admin/presentation/bloc/company_search_bloc.dart';
import 'package:delegate_app/features/admin/presentation/bloc/company_search_state.dart';


import 'package:delegate_app/features/admin/domain/usecases/search_companies_by_code.dart';

class MockSearchCompaniesByCode extends Mock implements SearchCompaniesByCode {}

void main() {
  late CompanySearchBloc bloc;
  late MockSearchCompaniesByCode mockSearchCompaniesByCode;

  setUp(() {
    mockSearchCompaniesByCode = MockSearchCompaniesByCode();
    bloc = CompanySearchBloc(
      searchCompaniesByCode: mockSearchCompaniesByCode
    );
  });

  tearDown(() {
    bloc.close();
  });

  test('initial state should be CompanySearchInitial', () {
    expect(bloc.state, isA<CompanySearchInitial>());
  });
}
