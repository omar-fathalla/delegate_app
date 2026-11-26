import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:get_it/get_it.dart';
import 'package:delegate_app/features/marketing_search/presentation/pages/marketing_search_screen.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_bloc.dart';
import 'package:delegate_app/features/marketing_search/presentation/bloc/marketing_search_state.dart';
import 'package:delegate_app/features/auth/data/datasources/auth_local_data_source.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/company_search_section.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/delegate_search_section.dart';
import 'package:delegate_app/features/marketing_search/presentation/widgets/search_results_section.dart';

class MockMarketingSearchBloc extends Mock implements MarketingSearchBloc {}
class MockAuthLocalDataSource extends Mock implements AuthLocalDataSource {}

void main() {
  late MockMarketingSearchBloc mockBloc;
  late MockAuthLocalDataSource mockAuthLocalDataSource;
  final getIt = GetIt.instance;

  setUp(() async {
    mockBloc = MockMarketingSearchBloc();
    mockAuthLocalDataSource = MockAuthLocalDataSource();

    when(() => mockBloc.state).thenReturn(MarketingSearchInitial());
    when(() => mockBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => mockBloc.close()).thenAnswer((_) async {});

    await getIt.reset();
    getIt.registerFactory<MarketingSearchBloc>(() => mockBloc);
    getIt.registerLazySingleton<AuthLocalDataSource>(() => mockAuthLocalDataSource);
  });

  tearDown(() async {
    await getIt.reset();
  });

  Widget createWidgetUnderTest({String? orgUID}) {
    return MaterialApp(
      home: Scaffold(
        body: MarketingSearchScreen(organizationUID: orgUID),
      ),
    );
  }

  testWidgets('renders properly with organizationUID from parameter', (tester) async {
    await tester.pumpWidget(createWidgetUnderTest(orgUID: 'org_123'));
    await tester.pump();

    expect(find.text('البحث'), findsWidgets);
    expect(find.byType(CompanySearchSection), findsOneWidget);
    expect(find.byType(DelegateSearchSection), findsOneWidget);
    expect(find.byType(SearchResultsSection), findsOneWidget);
  });

  testWidgets('renders properly with organizationUID from AuthLocalDataSource if not provided', (tester) async {
    final tDelegate = DelegateModel(
      uid: 'delegate_1',
      firstName: 'Test',
      lastName: 'Delegate',
      phoneNumber: '123456789',
      organizationUID: 'org_cached_123',
      organizationName: 'Org Name',
      middleName: 'Test',
      fullName: 'Test Delegate',
      nationalityID: '1234567890',
      motherName: 'Mother',
      city: 'City',
      gender: DelegateGender.male,
      position: DelegatePosition.promoter,
      birthDate: DateTime(1990),
      status: DelegateStatus.active,
      delegatePublicId: 'pub_1',
      allReceiptCodes: const [],
      createdBy: 'admin',
      hasPendingUpdate: false,
      isDeductedFromCompany: false,
      isPrinted: false,
      isProfileComplete: true,
      numberOfDocuments: 0,
      paymentAmount: 0,
      version: 1,
      documents: const [],
      companyUID: 'company_1',
      companyName: 'Company Name',
      updatedAt: DateTime.now(),
      createdAt: DateTime.now(),
    );
    when(() => mockAuthLocalDataSource.getCachedDelegateData()).thenReturn(tDelegate);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    expect(find.text('البحث'), findsWidgets);
    expect(find.byType(CompanySearchSection), findsOneWidget);
  });

  testWidgets('shows error screen if organizationUID is null and not in cache', (tester) async {
    when(() => mockAuthLocalDataSource.getCachedDelegateData()).thenReturn(null);

    await tester.pumpWidget(createWidgetUnderTest());
    await tester.pump();

    expect(find.text('لم يتم العثور على معرف المنظمة'), findsOneWidget);
    expect(find.text('يرجى تسجيل الدخول مرة أخرى'), findsOneWidget);
  });
}
