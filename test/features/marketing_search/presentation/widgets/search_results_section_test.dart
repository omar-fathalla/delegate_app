import 'package:delegate_app/core/design/widgets/loading_indicator.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/search_results_section.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_state.dart';
import 'package:delegate_app/features/admin/domain/entities/company.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/company_result_card.dart';
import 'package:intl/date_symbol_data_local.dart';

void main() {
  Widget createWidgetUnderTest(MarketingSearchState state) {
    return MaterialApp(
      home: Scaffold(
        body: SingleChildScrollView(
          child: SearchResultsSection(state: state),
        ),
      ),
    );
  }

  setUp(() {
    TestWidgetsFlutterBinding.ensureInitialized();
  });

  void setDisplaySize(WidgetTester tester) {
    tester.view.physicalSize = const Size(1080, 2400);
    tester.view.devicePixelRatio = 1.0;
    addTearDown(() {
      tester.view.resetPhysicalSize();
      tester.view.resetDevicePixelRatio();
    });
  }

  testWidgets('renders initial state correctly', (tester) async {
    await initializeDateFormatting('en', null);
    setDisplaySize(tester);
    await tester.pumpWidget(createWidgetUnderTest(MarketingSearchInitial()));

    expect(find.text('لم يتم البحث بعد'), findsOneWidget);
    expect(find.text('استخدم حقول البحث أعلاه'), findsOneWidget);
  });

  testWidgets('renders loading state correctly', (tester) async {
    await initializeDateFormatting('en', null);
    setDisplaySize(tester);
    await tester.pumpWidget(createWidgetUnderTest(const MarketingSearchLoading(searchType: 'company')));

    expect(find.byType(LoadingIndicator), findsOneWidget);
    expect(find.text('جاري البحث...'), findsOneWidget);
  });

  testWidgets('renders empty state correctly for company', (tester) async {
    await initializeDateFormatting('en', null);
    setDisplaySize(tester);
    await tester.pumpWidget(createWidgetUnderTest(const MarketingSearchEmpty(searchQuery: '123', searchType: 'company')));

    expect(find.text('لا توجد شركات مطابقة'), findsOneWidget);
    expect(find.text('البحث: "123"'), findsOneWidget);
  });

  testWidgets('renders error state correctly', (tester) async {
    await initializeDateFormatting('en', null);
    setDisplaySize(tester);
    await tester.pumpWidget(createWidgetUnderTest(const MarketingSearchError(message: 'Some error message')));

    expect(find.text('حدث خطأ'), findsOneWidget);
    expect(find.text('Some error message'), findsOneWidget);
  });

  testWidgets('renders company results correctly', (tester) async {
    await initializeDateFormatting('en', null);
    final companies = [
      Company(
        uid: '1',
        name: 'Test Company',
        companyCodeInOrg: '1234',
        organizationUID: 'org1',
        type: 'Retail',
        status: 'active',
        createdAt: DateTime.now(),
        updatedAt: DateTime.now(),
        admins: 1,
        delegates: 5,
        deferredPayment: true,
      ),
    ];
    setDisplaySize(tester);
    await tester.pumpWidget(createWidgetUnderTest(CompanySearchSuccess(companies: companies, searchQuery: '123')));

    expect(find.text('وُجد 1 شركة'), findsOneWidget);
    expect(find.byType(CompanyResultCard), findsOneWidget);
  });
}
