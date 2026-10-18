import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:delegate_app/features/marketing/presentation/pages/marketing_promotion_home_screen.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:shared_preferences/shared_preferences.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MockPermissionsDataSource extends Mock
    implements PrivateLabelPermissionsRemoteDataSource {}

DelegateModel _createPromoDelegate({
  String uid = 'promo123',
  String name = 'Osama Marketing Promotion',
  UserRole role = UserRole.marketingPromotion,
}) {
  return DelegateModel(
    uid: uid,
    firstName: 'Osama',
    middleName: 'M',
    lastName: 'Promotion',
    fullName: name,
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
    home: Scaffold(body: child),
  );
}

void main() {
  late MockPermissionsDataSource mockPermissionsDataSource;
  late StreamController<PrivateLabelPermissions?> streamController;
  late FakeFirebaseFirestore fakeFirestore;

  setUp(() {
    SharedPreferences.setMockInitialValues({});
    fakeFirestore = FakeFirebaseFirestore();
    mockPermissionsDataSource = MockPermissionsDataSource();
    streamController = StreamController<PrivateLabelPermissions?>.broadcast();

    when(() => mockPermissionsDataSource.streamUserPermissions(any()))
        .thenAnswer((_) => streamController.stream);

    if (di.sl.isRegistered<PrivateLabelPermissionsRemoteDataSource>()) {
      di.sl.unregister<PrivateLabelPermissionsRemoteDataSource>();
    }
    di.sl.registerSingleton<PrivateLabelPermissionsRemoteDataSource>(
      mockPermissionsDataSource,
    );
  });

  tearDown(() async {
    await streamController.close();
    if (di.sl.isRegistered<PrivateLabelPermissionsRemoteDataSource>()) {
      di.sl.unregister<PrivateLabelPermissionsRemoteDataSource>();
    }
  });

  testWidgets('MarketingPromotionHomeScreen renders clean shortcut card to Private Label tab and triggers onNavigateTab(3)', (tester) async {
    final delegate = _createPromoDelegate();
    int? navigatedTab;

    await tester.pumpWidget(
      _buildTestApp(
        MarketingPromotionHomeScreen(
          delegate: delegate,
          firestore: fakeFirestore,
          onNavigateTab: (tabIndex) {
            navigatedTab = tabIndex;
          },
        ),
      ),
    );
    await tester.pump();

    // Verify Welcome Duties banner
    expect(find.text('متابعة تقارير الصور الميدانية'), findsOneWidget);

    // Verify Live Pulse is visible
    expect(find.text('المؤشرات والنبض اللحظي'), findsOneWidget);

    // Initially without permissions, shortcut card is not shown
    expect(find.text('مركز العلامة الخاصة'), findsNothing);

    // Emit private label permissions
    streamController.add(const PrivateLabelPermissions(
      userId: 'promo123',
      canCapture: true,
      canReviewAudit: true,
    ));
    await tester.pump(Duration.zero);
    await tester.pump();

    // Verify shortcut card appears
    expect(find.text('مركز العلامة الخاصة'), findsOneWidget);
    expect(find.text('Private Label'), findsOneWidget);
    expect(find.text('فتح'), findsOneWidget);

    // Tap on the shortcut card to navigate
    await tester.tap(find.text('مركز العلامة الخاصة'));
    await tester.pump();

    // Verify onNavigateTab was called with 3 (the Private Label tab index)
    expect(navigatedTab, equals(3));
  });
}
