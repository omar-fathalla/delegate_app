import 'package:delegate_app/config/theme/app_theme.dart';
import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_home_screen.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MockFloorVerificationService extends Mock implements FloorVerificationService {}
class MockBranchPreferenceService extends Mock implements BranchPreferenceService {}
class MockMarketingRemoteDataSource extends Mock implements MarketingRemoteDataSource {}

DelegateModel _createDelegate({
  required UserRole role,
  String uid = 'marketing123',
  String name = 'رانيا',
}) {
  return DelegateModel(
    uid: uid,
    firstName: 'رانيا',
    middleName: 'M',
    lastName: 'تسويق',
    fullName: name,
    nationalityID: '12345678901234',
    motherName: 'Mother',
    city: 'Alexandria',
    phoneNumber: '+201000000000',
    gender: DelegateGender.female,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1995, 1, 1),
    organizationUID: 'org1',
    companyUID: 'comp1',
    organizationName: 'سوبر ماركت فتح الله',
    companyName: 'شركة تجريبية',
    status: DelegateStatus.active,
    delegatePublicId: 'pub123',
    allReceiptCodes: const [],
    createdAt: DateTime(2026, 1, 1),
    createdBy: 'superAdmin',
    hasPendingUpdate: false,
    isDeductedFromCompany: false,
    isPrinted: false,
    isProfileComplete: true,
    numberOfDocuments: 0,
    paymentAmount: 0,
    version: 1,
    documents: const [],
    role: role,
  );
}

Widget _buildTestApp(Widget child) {
  return MaterialApp(
      theme: AppTheme.lightTheme(),
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ar'), Locale('en')],
    locale: const Locale('ar'),
    home: Scaffold(body: child),
  );
}

void main() {
  late MockFloorVerificationService mockFloorService;
  late MockBranchPreferenceService mockPrefService;
  late MockMarketingRemoteDataSource mockRemoteDataSource;
  late SharedPreferences prefs;

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    mockFloorService = MockFloorVerificationService();
    mockPrefService = MockBranchPreferenceService();
    mockRemoteDataSource = MockMarketingRemoteDataSource();

    when(() => mockFloorService.getLocalVerifications(any())).thenReturn({});
    when(() => mockFloorService.addListener(any())).thenReturn(null);
    when(() => mockFloorService.removeListener(any())).thenReturn(null);
    when(() => mockPrefService.getFavoriteBranches(any())).thenReturn([]);
    when(() => mockPrefService.getActiveBranch(any())).thenReturn(null);

    if (di.sl.isRegistered<FloorVerificationService>()) {
      di.sl.unregister<FloorVerificationService>();
    }
    if (di.sl.isRegistered<BranchPreferenceService>()) {
      di.sl.unregister<BranchPreferenceService>();
    }
    if (di.sl.isRegistered<MarketingRemoteDataSource>()) {
      di.sl.unregister<MarketingRemoteDataSource>();
    }
    if (di.sl.isRegistered<SharedPreferences>()) {
      di.sl.unregister<SharedPreferences>();
    }

    di.sl.registerSingleton<FloorVerificationService>(mockFloorService);
    di.sl.registerSingleton<BranchPreferenceService>(mockPrefService);
    di.sl.registerSingleton<MarketingRemoteDataSource>(mockRemoteDataSource);
    di.sl.registerSingleton<SharedPreferences>(prefs);
  });

  tearDown(() {
    if (di.sl.isRegistered<FloorVerificationService>()) {
      di.sl.unregister<FloorVerificationService>();
    }
    if (di.sl.isRegistered<BranchPreferenceService>()) {
      di.sl.unregister<BranchPreferenceService>();
    }
    if (di.sl.isRegistered<MarketingRemoteDataSource>()) {
      di.sl.unregister<MarketingRemoteDataSource>();
    }
    if (di.sl.isRegistered<SharedPreferences>()) {
      di.sl.unregister<SharedPreferences>();
    }
  });

  testWidgets('MarketingHomeScreen renders Private Label shortcut card pointing to tab 3', (tester) async {
    int? navigatedTab;
    final delegate = _createDelegate(role: UserRole.marketing);

    await tester.pumpWidget(_buildTestApp(MarketingHomeScreen(
      delegate: delegate,
      onNavigateTab: (tab) => navigatedTab = tab,
    )));
    await tester.pumpAndSettle();

    // Verify Welcome banner
    expect(find.textContaining('أهلاً بك، رانيا'), findsOneWidget);

    // Verify Private Label shortcut banner is rendered
    // TAS-392: Private Label is one of the quick-access cards.
    expect(find.text('Private Label'), findsOneWidget);
    expect(
      find.text('توثيق وتدقيق وتقارير'),
      findsOneWidget,
    );

    // Tap shortcut banner and verify navigation to tab 3 (PrivateLabelHubScreen)
    await tester.ensureVisible(find.byKey(const Key('marketing_quick_private_label')));
    await tester.tap(find.byKey(const Key('marketing_quick_private_label')));
    await tester.pumpAndSettle();
    expect(navigatedTab, equals(3));

    // Verify old view-only card is NOT rendered directly on home
    expect(find.text('كتالوج منتجات البرايفت ليبل'), findsNothing);
  });

  testWidgets('MarketingHomeScreen quick action card "تسجيل مخالفة" exists and does not route to tab 3', (tester) async {
    int? navigatedTab;
    final delegate = _createDelegate(role: UserRole.marketing);

    await tester.pumpWidget(_buildTestApp(MarketingHomeScreen(
      delegate: delegate,
      onNavigateTab: (tab) => navigatedTab = tab,
    )));
    await tester.pumpAndSettle();

    expect(find.text('المخالفات'), findsOneWidget);
    expect(find.text('تسجيل ومتابعة'), findsOneWidget);

    // Navigated tab should remain null when tapping the penalties card
    // (since it pushes CompanyPenaltiesSettingsPage rather than tab switching)
    expect(navigatedTab, isNull);
  });
}
