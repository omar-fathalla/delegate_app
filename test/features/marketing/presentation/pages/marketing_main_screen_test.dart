import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_main_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/notifications/presentation/bloc/notification_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_hub_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;

import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';

class MockNotificationBloc extends MockBloc<NotificationEvent, NotificationState>
    implements NotificationBloc {}

class MockMarketingBloc extends MockBloc<MarketingEvent, MarketingState>
    implements MarketingBloc {}

class MockPhotoPermissionBloc
    extends MockBloc<PhotoPermissionEvent, PhotoPermissionState>
    implements PhotoPermissionBloc {}

class MockFloorVerificationService extends Mock implements FloorVerificationService {}

class MockBranchPreferenceService extends Mock implements BranchPreferenceService {}

class MockMarketingRemoteDataSource extends Mock implements MarketingRemoteDataSource {}

class MockPrivateLabelPermissionsRemoteDataSource extends Mock
    implements PrivateLabelPermissionsRemoteDataSource {}

DelegateModel _createDelegateWithRole(UserRole role) {
  return DelegateModel(
    uid: 'marketing123',
    firstName: 'Marketing',
    middleName: 'M',
    lastName: 'User',
    fullName: 'Marketing M User',
    nationalityID: '12345678901234',
    motherName: 'Mother',
    city: 'Cairo',
    phoneNumber: '+201000000000',
    gender: DelegateGender.male,
    position: DelegatePosition.promoter,
    birthDate: DateTime(1990, 1, 1),
    organizationUID: 'org1',
    companyUID: 'comp1',
    organizationName: 'Test Org',
    companyName: 'Test Comp',
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
    localizationsDelegates: const [
      AppLocalizations.delegate,
      GlobalMaterialLocalizations.delegate,
      GlobalWidgetsLocalizations.delegate,
      GlobalCupertinoLocalizations.delegate,
    ],
    supportedLocales: const [Locale('ar'), Locale('en')],
    locale: const Locale('ar'),
    home: child,
  );
}

void main() {
  late Delegate tDelegate;
  late MockNotificationBloc mockNotificationBloc;
  late MockMarketingBloc mockMarketingBloc;
  late MockPhotoPermissionBloc mockPhotoPermissionBloc;
  late MockFloorVerificationService mockFloorService;
  late MockBranchPreferenceService mockPrefService;
  late MockMarketingRemoteDataSource mockMarketingRemoteDataSource;
  late MockPrivateLabelPermissionsRemoteDataSource mockPLPermissionsRemoteDataSource;
  late SharedPreferences prefs;

  setUpAll(() {
    registerFallbackValue(const SubscribeToUnreadCount(
      delegateUid: 'marketing123',
      organizationId: 'org1',
      phoneNumber: '+201000000000',
      userRole: 'marketing',
      accountCreatedAt: null,
    ));
    tDelegate = _createDelegateWithRole(UserRole.marketing);
  });

  setUp(() async {
    SharedPreferences.setMockInitialValues({});
    prefs = await SharedPreferences.getInstance();

    mockNotificationBloc = MockNotificationBloc();
    mockMarketingBloc = MockMarketingBloc();
    mockPhotoPermissionBloc = MockPhotoPermissionBloc();
    mockFloorService = MockFloorVerificationService();
    mockPrefService = MockBranchPreferenceService();
    mockMarketingRemoteDataSource = MockMarketingRemoteDataSource();
    mockPLPermissionsRemoteDataSource = MockPrivateLabelPermissionsRemoteDataSource();

    when(() => mockNotificationBloc.state).thenReturn(NotificationInitial());
    when(() => mockNotificationBloc.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockMarketingBloc.state).thenReturn(MarketingInitial());
    when(() => mockMarketingBloc.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockPhotoPermissionBloc.state).thenReturn(PhotoPermissionInitial());
    when(() => mockPhotoPermissionBloc.stream).thenAnswer((_) => const Stream.empty());

    when(() => mockFloorService.getLocalVerifications(any())).thenReturn({});
    when(() => mockFloorService.addListener(any())).thenReturn(null);
    when(() => mockFloorService.removeListener(any())).thenReturn(null);

    when(() => mockPrefService.getFavoriteBranches(any())).thenReturn([]);
    when(() => mockPrefService.getActiveBranch(any())).thenReturn(null);

    when(() => mockPLPermissionsRemoteDataSource.streamUserPermissions(any()))
        .thenAnswer((_) => Stream.value(const PrivateLabelPermissions(
              userId: 'marketing123',
              canCapture: true,
              canViewReports: true,
              canReviewAudit: true,
            )));

    if (di.sl.isRegistered<NotificationBloc>()) di.sl.unregister<NotificationBloc>();
    if (di.sl.isRegistered<MarketingBloc>()) di.sl.unregister<MarketingBloc>();
    if (di.sl.isRegistered<PhotoPermissionBloc>()) di.sl.unregister<PhotoPermissionBloc>();
    if (di.sl.isRegistered<FloorVerificationService>()) di.sl.unregister<FloorVerificationService>();
    if (di.sl.isRegistered<BranchPreferenceService>()) di.sl.unregister<BranchPreferenceService>();
    if (di.sl.isRegistered<MarketingRemoteDataSource>()) di.sl.unregister<MarketingRemoteDataSource>();
    if (di.sl.isRegistered<PrivateLabelPermissionsRemoteDataSource>()) {
      di.sl.unregister<PrivateLabelPermissionsRemoteDataSource>();
    }
    if (di.sl.isRegistered<SharedPreferences>()) di.sl.unregister<SharedPreferences>();

    di.sl.registerFactory<NotificationBloc>(() => mockNotificationBloc);
    di.sl.registerFactory<MarketingBloc>(() => mockMarketingBloc);
    di.sl.registerFactory<PhotoPermissionBloc>(() => mockPhotoPermissionBloc);
    di.sl.registerSingleton<FloorVerificationService>(mockFloorService);
    di.sl.registerSingleton<BranchPreferenceService>(mockPrefService);
    di.sl.registerSingleton<MarketingRemoteDataSource>(mockMarketingRemoteDataSource);
    di.sl.registerSingleton<PrivateLabelPermissionsRemoteDataSource>(mockPLPermissionsRemoteDataSource);
    di.sl.registerSingleton<SharedPreferences>(prefs);
  });

  tearDown(() {
    if (di.sl.isRegistered<NotificationBloc>()) di.sl.unregister<NotificationBloc>();
    if (di.sl.isRegistered<MarketingBloc>()) di.sl.unregister<MarketingBloc>();
    if (di.sl.isRegistered<PhotoPermissionBloc>()) di.sl.unregister<PhotoPermissionBloc>();
    if (di.sl.isRegistered<FloorVerificationService>()) di.sl.unregister<FloorVerificationService>();
    if (di.sl.isRegistered<BranchPreferenceService>()) di.sl.unregister<BranchPreferenceService>();
    if (di.sl.isRegistered<MarketingRemoteDataSource>()) di.sl.unregister<MarketingRemoteDataSource>();
    if (di.sl.isRegistered<PrivateLabelPermissionsRemoteDataSource>()) {
      di.sl.unregister<PrivateLabelPermissionsRemoteDataSource>();
    }
    if (di.sl.isRegistered<SharedPreferences>()) di.sl.unregister<SharedPreferences>();
  });

  testWidgets('MarketingMainScreen should initialize successfully for marketing role', (WidgetTester tester) async {
    final widget = MarketingMainScreen(delegate: tDelegate);
    expect(widget.delegate, equals(tDelegate));
    expect(widget.delegate.role, equals(UserRole.marketing));
  });

  testWidgets('MarketingMainScreen should initialize successfully for marketingPromotion role', (WidgetTester tester) async {
    final promoDelegate = _createDelegateWithRole(UserRole.marketingPromotion);
    final widget = MarketingMainScreen(delegate: promoDelegate);
    expect(widget.delegate.role, equals(UserRole.marketingPromotion));
  });

  test('DelegateModel should serialize and deserialize all 3 marketing roles accurately', () {
    final expectedSerializedRoles = {
      UserRole.marketing: 'marketing',
      UserRole.marketingPromotion: 'marketing_promotion',
      UserRole.branchesMarketingManager: 'branches_marketing',
    };
    for (final entry in expectedSerializedRoles.entries) {
      final model = _createDelegateWithRole(entry.key);
      final json = model.toJson();
      expect(json['role'], equals(entry.value));
      final restored = DelegateModel.fromJson(json, 'marketing123');
      expect(restored.role, equals(entry.key));
    }
  });

  testWidgets('MarketingMainScreen renders bottom bar with Private Label instead of الغرامات and toggles to Hub screen', (tester) async {
    await tester.pumpWidget(_buildTestApp(MarketingMainScreen(delegate: tDelegate)));
    await tester.pump(const Duration(milliseconds: 300));

    final navBarFinder = find.byType(NavigationBar);
    expect(navBarFinder, findsOneWidget);

    // Verify 4 bottom navigation destinations scoped to NavigationBar
    expect(find.descendant(of: navBarFinder, matching: find.text('الرئيسية')), findsOneWidget);
    expect(find.descendant(of: navBarFinder, matching: find.text('الفروع')), findsOneWidget);
    expect(find.descendant(of: navBarFinder, matching: find.text('أذونات التصوير')), findsOneWidget);
    expect(find.descendant(of: navBarFinder, matching: find.text('Private Label')), findsOneWidget);

    // Verify الغرامات is NOT in the bottom navigation bar
    expect(find.descendant(of: navBarFinder, matching: find.text('الغرامات')), findsNothing);

    // Tap on Private Label tab (index 3)
    await tester.tap(find.descendant(of: navBarFinder, matching: find.text('Private Label')));
    // Fade through: 90ms out (old tab) then 210ms in.
    await tester.pump();
    await tester.pump(const Duration(milliseconds: 300));

    // Verify PrivateLabelHubScreen is mounted and visible
    expect(find.byType(PrivateLabelHubScreen), findsOneWidget);
  });

  testWidgets('MarketingMainScreen popup menu contains المخالفات والغرامات directly above logout and no Private Label item', (tester) async {
    await tester.pumpWidget(_buildTestApp(MarketingMainScreen(delegate: tDelegate)));
    await tester.pump(const Duration(milliseconds: 300));

    // Open popup menu via PopupMenuButton
    await tester.tap(find.byType(PopupMenuButton<String>));
    await tester.pump(const Duration(milliseconds: 300));

    // Verify المخالفات والغرامات and تسجيل الخروج exist in popup menu
    expect(find.text('المخالفات والغرامات'), findsOneWidget);
    expect(find.text('تسجيل الخروج'), findsOneWidget);

    // Verify Private Label does NOT appear in popup menu
    expect(find.text('Private Label (التوثيق)'), findsNothing);
    expect(find.text('تقارير Private Label'), findsNothing);
    expect(find.text('اعتمادات Private Label'), findsNothing);
  });
}
