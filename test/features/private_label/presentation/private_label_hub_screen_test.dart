import 'dart:async';
import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_permissions.dart';
import 'package:delegate_app/features/private_label/data/datasources/private_label_permissions_remote_data_source.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/features/private_label/domain/entities/private_label_product.dart';
import 'package:delegate_app/features/private_label/presentation/bloc/private_label_review_bloc.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_catalog_screen.dart';
import 'package:delegate_app/features/private_label/presentation/pages/private_label_hub_screen.dart';
import 'package:delegate_app/features/private_label/presentation/widgets/private_label_product_sheet.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MockPermissionsDataSource extends Mock
    implements PrivateLabelPermissionsRemoteDataSource {}

class MockPrivateLabelReviewBloc
    extends MockBloc<PrivateLabelReviewEvent, PrivateLabelReviewState>
    implements PrivateLabelReviewBloc {}

DelegateModel _createDelegate({
  required UserRole role,
  String uid = 'user123',
  String name = 'Osama Promotion',
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
    home: child,
  );
}

void main() {
  late MockPermissionsDataSource mockPermissionsDataSource;
  late StreamController<PrivateLabelPermissions?> streamController;

  setUp(() {
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

  testWidgets('PrivateLabelHubScreen renders core banner and tools without guidelines', (tester) async {
    final delegate = _createDelegate(role: UserRole.marketingPromotion);

    await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: delegate)));
    await tester.pump();

    // Verify Header Banner
    expect(find.text('مركز العلامة الخاصة'), findsOneWidget);
    expect(find.text('Private Label'), findsWidgets);

    // Verify Core Tools and Updated Subtitles
    expect(find.text('Private Label Audit'), findsOneWidget);
    expect(find.text('مراجعة وتدقيق المنتجات'), findsOneWidget);

    expect(find.text('Private Label Report'), findsOneWidget);
    expect(find.text('مؤشر ونسب إنجاز الفروع'), findsOneWidget);

    expect(find.text('Private Label Capture'), findsOneWidget);
    expect(find.text('التوثيق الميداني اليومي للمنتجات'), findsOneWidget);

    expect(find.text('Private Label Catalog'), findsOneWidget);
    expect(find.text('صفحة الكتالوج وإضافة وتعديل المنتجات'), findsOneWidget);

    // Verify Super Admin tool is NOT visible for marketingPromotion role
    expect(find.text('إدارة صلاحيات Private Label'), findsNothing);

    // Verify Guidelines Card is NOT rendered
    expect(find.text('إرشادات تشغيلية وملاحظات هامة'), findsNothing);
  });

  testWidgets('PrivateLabelHubScreen displays Super Admin permissions tool for superAdmin', (tester) async {
    final superAdmin = _createDelegate(role: UserRole.superAdmin);

    await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: superAdmin)));
    await tester.pump();

    // Verify Super Admin tool is visible
    expect(find.text('إدارة صلاحيات Private Label'), findsOneWidget);
    expect(find.text('Super Admin'), findsWidgets);
  });

  testWidgets('PrivateLabelHubScreen updates badges when permissions stream emits', (tester) async {
    final delegate = _createDelegate(role: UserRole.marketingPromotion);

    await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: delegate)));
    await tester.pump();

    // Initially without permissions, restricted/locked pills appear
    expect(find.text('يتطلب صلاحية'), findsWidgets);

    // Emit active permissions
    streamController.add(const PrivateLabelPermissions(
      userId: 'user123',
      canCapture: false,
      canReviewAudit: true,
      canViewReports: true,
    ));
    await tester.pump(Duration.zero);
    await tester.pump();

    // Audit and Report should now show permitted statuses
    expect(find.text('متاح للاعتماد'), findsOneWidget);
    expect(find.text('تقارير شهرية'), findsOneWidget);
    expect(find.text('يتطلب صلاحية'), findsOneWidget); // Capture is still restricted
  });

  testWidgets('PrivateLabelHubScreen shows locked snackbar when tapping restricted tool', (tester) async {
    final delegate = _createDelegate(role: UserRole.marketingPromotion);

    await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: delegate)));
    await tester.pump();

    // Stream empty permissions (all locked)
    streamController.add(const PrivateLabelPermissions(
      userId: 'user123',
      canCapture: false,
      canReviewAudit: false,
      canViewReports: false,
    ));
    await tester.pump(Duration.zero);
    await tester.pump();

    // Tap on locked Private Label Capture
    await tester.tap(find.text('Private Label Capture'));
    await tester.pump();

    // Verify info snackbar appears
    expect(find.textContaining('تتطلب صلاحية خاصة'), findsOneWidget);
  });

  testWidgets('PrivateLabelHubScreen opens catalog sheet when tapping permitted catalog tool', (tester) async {
    final delegate = _createDelegate(role: UserRole.marketingPromotion);

    final mockReviewBloc = MockPrivateLabelReviewBloc();
    when(() => mockReviewBloc.state).thenReturn(const PrivateLabelReviewState());
    when(() => mockReviewBloc.stream).thenAnswer((_) => const Stream.empty());

    if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
      di.sl.unregister<PrivateLabelReviewBloc>();
    }
    di.sl.registerFactory<PrivateLabelReviewBloc>(() => mockReviewBloc);

    try {
      await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: delegate)));
      await tester.pump();

      // Permit audit / catalog access
      streamController.add(const PrivateLabelPermissions(
        userId: 'user123',
        canCapture: false,
        canReviewAudit: true,
        canViewReports: true,
      ));
      await tester.pump(Duration.zero);
      await tester.pump();

      // Tap on Private Label Catalog
      await tester.tap(find.text('Private Label Catalog'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      // Verify catalog screen opened
      expect(find.text('كتالوج منتجات البرايفت ليبل'), findsOneWidget);
    } finally {
      if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
        di.sl.unregister<PrivateLabelReviewBloc>();
      }
    }
  });

  testWidgets('PrivateLabelCatalogScreen operates in view-only mode (للنظر فقط) for UserRole.marketing', (tester) async {
    final branchMarketing = _createDelegate(role: UserRole.marketing, name: 'رانيا');
    final promotionMarketing = _createDelegate(role: UserRole.marketingPromotion);
    final manager = _createDelegate(role: UserRole.branchesMarketingManager);
    final superAdmin = _createDelegate(role: UserRole.superAdmin);

    expect(PrivateLabelCatalogScreen.canEditCatalog(branchMarketing), isFalse);
    expect(PrivateLabelCatalogScreen.canEditCatalog(promotionMarketing), isTrue);
    expect(PrivateLabelCatalogScreen.canEditCatalog(manager), isTrue);
    expect(PrivateLabelCatalogScreen.canEditCatalog(superAdmin), isTrue);

    final mockReviewBloc = MockPrivateLabelReviewBloc();
    when(() => mockReviewBloc.state).thenReturn(
      PrivateLabelReviewState(
        status: PrivateLabelReviewStatusView.ready,
        products: PrivateLabelProduct.defaultCatalog('org1'),
      ),
    );
    when(() => mockReviewBloc.stream).thenAnswer((_) => const Stream.empty());

    if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
      di.sl.unregister<PrivateLabelReviewBloc>();
    }
    di.sl.registerFactory<PrivateLabelReviewBloc>(() => mockReviewBloc);

    try {
      await tester.pumpWidget(
        _buildTestApp(PrivateLabelCatalogScreen(delegate: branchMarketing)),
      );
      await tester.pump();

      // View-only indicators present
      expect(find.text('وضع العرض فقط'), findsOneWidget);
      expect(find.text('عرض'), findsWidgets);

      // Add/Edit controls strictly hidden
      expect(find.text('إضافة منتج للكتالوج'), findsNothing);
      expect(find.byIcon(Icons.add_box_rounded), findsNothing);
      expect(find.text('تعديل'), findsNothing);

      // Tapping a product opens the read-only details sheet (not edit form)
      await tester.tap(find.text('أرز فتح الله 1 كيلو'));
      await tester.pumpAndSettle();

      expect(
        find.text('بيانات المنتج في الكتالوج (وضع العرض فقط)'),
        findsOneWidget,
      );
      expect(find.text('حفظ التعديلات'), findsNothing);
      expect(find.text('إغلاق'), findsOneWidget);
    } finally {
      if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
        di.sl.unregister<PrivateLabelReviewBloc>();
      }
    }
  });

  testWidgets('PrivateLabelCatalogScreen shows add/edit controls for UserRole.marketingPromotion and handles empty catalog in both modes', (tester) async {
    final branchMarketing = _createDelegate(role: UserRole.marketing, name: 'رانيا');
    final promotionMarketing = _createDelegate(role: UserRole.marketingPromotion);

    final mockReviewBloc = MockPrivateLabelReviewBloc();
    when(() => mockReviewBloc.state).thenReturn(
      const PrivateLabelReviewState(
        status: PrivateLabelReviewStatusView.ready,
        products: [],
      ),
    );
    when(() => mockReviewBloc.stream).thenAnswer((_) => const Stream.empty());

    if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
      di.sl.unregister<PrivateLabelReviewBloc>();
    }
    di.sl.registerFactory<PrivateLabelReviewBloc>(() => mockReviewBloc);

    try {
      // 1) Empty catalog in read-only mode (UserRole.marketing)
      await tester.pumpWidget(
        _buildTestApp(PrivateLabelCatalogScreen(delegate: branchMarketing)),
      );
      await tester.pump();
      expect(
        find.text('لم يتم تسجيل منتجات في الكتالوج من قِبل إدارة التسويق بعد.'),
        findsOneWidget,
      );
      expect(find.text('إضافة منتج للكتالوج'), findsNothing);

      // 2) Empty catalog in editable mode (UserRole.marketingPromotion)
      await tester.pumpWidget(
        _buildTestApp(PrivateLabelCatalogScreen(delegate: promotionMarketing)),
      );
      await tester.pump();
      expect(
        find.text('اضغط على "إضافة منتج للكتالوج" لإدخال اسم المنتج والسعر والباركود والصورة.'),
        findsOneWidget,
      );
      expect(find.text('إضافة منتج للكتالوج'), findsOneWidget);
      expect(find.byIcon(Icons.add_box_rounded), findsOneWidget);

      // 3) Explicitly passing readOnly: false for UserRole.marketing still enforces isReadOnly == true
      final forcedScreen = PrivateLabelCatalogScreen(
        delegate: branchMarketing,
        readOnly: false,
      );
      expect(forcedScreen.isReadOnly, isTrue);
      await tester.pumpWidget(_buildTestApp(forcedScreen));
      await tester.pump();
      expect(find.text('وضع العرض فقط'), findsOneWidget);
      expect(find.text('إضافة منتج للكتالوج'), findsNothing);
      expect(find.byIcon(Icons.add_box_rounded), findsNothing);
    } finally {
      if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
        di.sl.unregister<PrivateLabelReviewBloc>();
      }
    }
  });

  testWidgets('PrivateLabelHubScreen enables catalog for UserRole.marketing (view-only) and UserRole.branchesMarketingManager (editable) without Firestore audit/capture permissions', (tester) async {
    final branchMarketing = _createDelegate(role: UserRole.marketing, name: 'رانيا');
    final manager = _createDelegate(role: UserRole.branchesMarketingManager, name: 'أحمد مدير');

    final mockReviewBloc = MockPrivateLabelReviewBloc();
    when(() => mockReviewBloc.state).thenReturn(
      PrivateLabelReviewState(
        status: PrivateLabelReviewStatusView.ready,
        products: PrivateLabelProduct.defaultCatalog('org1'),
      ),
    );
    when(() => mockReviewBloc.stream).thenAnswer((_) => const Stream.empty());

    if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
      di.sl.unregister<PrivateLabelReviewBloc>();
    }
    di.sl.registerFactory<PrivateLabelReviewBloc>(() => mockReviewBloc);

    try {
      // 1) UserRole.marketing sees 'الكتالوج' (TAS-270: Arabic, not 'Catalog')
      // and can open catalog in read-only mode
      await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: branchMarketing)));
      await tester.pump();
      streamController.add(const PrivateLabelPermissions(
        userId: 'user123',
        canCapture: false,
        canReviewAudit: false,
        canViewReports: false,
      ));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('الكتالوج'), findsOneWidget);
      expect(
        find.text('صفحة الكتالوج وعرض المنتجات والأسعار المعتمدة'),
        findsOneWidget,
      );

      await tester.tap(find.text('Private Label Catalog'));
      await tester.pumpAndSettle();

      expect(find.text('وضع العرض فقط'), findsOneWidget);
      expect(find.text('إضافة منتج للكتالوج'), findsNothing);

      Navigator.of(tester.element(find.byType(PrivateLabelCatalogScreen))).pop();
      await tester.pumpAndSettle();

      // 2) UserRole.branchesMarketingManager sees 'الكتالوج' and can open catalog in editable mode
      await tester.pumpWidget(_buildTestApp(PrivateLabelHubScreen(delegate: manager)));
      await tester.pump();
      streamController.add(const PrivateLabelPermissions(
        userId: 'user123',
        canCapture: false,
        canReviewAudit: false,
        canViewReports: false,
      ));
      await tester.pump(Duration.zero);
      await tester.pump();

      expect(find.text('الكتالوج'), findsOneWidget);
      expect(find.text('صفحة الكتالوج وإضافة وتعديل المنتجات'), findsOneWidget);

      await tester.tap(find.text('Private Label Catalog'));
      await tester.pumpAndSettle();

      expect(find.text('إضافة منتج للكتالوج'), findsOneWidget);
    } finally {
      if (di.sl.isRegistered<PrivateLabelReviewBloc>()) {
        di.sl.unregister<PrivateLabelReviewBloc>();
      }
    }
  });

  testWidgets('showPrivateLabelCatalogSheet enforces readOnly mode and case-insensitive alphanumeric barcode search', (tester) async {
    final mockReviewBloc = MockPrivateLabelReviewBloc();
    when(() => mockReviewBloc.state).thenReturn(
      const PrivateLabelReviewState(
        status: PrivateLabelReviewStatusView.ready,
        products: [
          PrivateLabelProduct(
            id: 'p1',
            organizationUID: 'org1',
            name: 'منتج تجريبي',
            barcode: 'WIX-ABC-99',
            category: 'منظفات',
            referencePrice: 45,
          ),
        ],
      ),
    );
    when(() => mockReviewBloc.stream).thenAnswer((_) => const Stream.empty());

    await tester.pumpWidget(
      _buildTestApp(
        Scaffold(
          body: Builder(
            builder: (context) => Center(
              child: ElevatedButton(
                onPressed: () => showPrivateLabelCatalogSheet(
                  context: context,
                  organizationUID: 'org1',
                  bloc: mockReviewBloc,
                  readOnly: true,
                ),
                child: const Text('open_sheet'),
              ),
            ),
          ),
        ),
      ),
    );

    await tester.tap(find.text('open_sheet'));
    await tester.pumpAndSettle();

    expect(find.textContaining('عرض المنتجات والأسعار المعتمدة'), findsOneWidget);
    expect(find.text('إضافة منتج'), findsNothing);
    expect(find.text('عرض'), findsOneWidget);

    // Search by lowercase alphanumeric barcode 'wix-abc' matches 'WIX-ABC-99'
    await tester.enterText(find.byType(SearchBar), 'wix-abc');
    await tester.pump();
    expect(find.text('منتج تجريبي'), findsOneWidget);

    // Tapping product in readOnly catalog sheet opens read-only details sheet
    await tester.tap(find.text('منتج تجريبي'));
    await tester.pumpAndSettle();
    expect(
      find.text('بيانات المنتج في الكتالوج (وضع العرض فقط)'),
      findsOneWidget,
    );
  });
}
