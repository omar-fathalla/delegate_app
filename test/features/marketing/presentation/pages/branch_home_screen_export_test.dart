import 'package:material_ui/material_ui.dart';
import 'package:cupertino_ui/cupertino_ui.dart'
    show GlobalCupertinoLocalizations;
import 'package:flutter_localizations/flutter_localizations.dart'
    show GlobalWidgetsLocalizations;
import 'package:flutter_test/flutter_test.dart';
import 'package:bloc_test/bloc_test.dart';
import 'package:intl/date_symbol_data_local.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/features/marketing/presentation/bloc/marketing_bloc.dart';
import 'package:delegate_app/features/marketing/presentation/pages/branch_home_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/features/profile/data/models/delegate_model.dart';
import 'package:delegate_app/features/marketing/data/services/floor_verification_service.dart';
import 'package:delegate_app/features/marketing/data/services/branch_preference_service.dart';
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:delegate_app/injection_container.dart' as di;

class MockFloorVerificationService extends Mock
    implements FloorVerificationService {}

class MockBranchPreferenceService extends Mock
    implements BranchPreferenceService {}

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

class MockMarketingBloc extends MockBloc<MarketingEvent, MarketingState>
    implements MarketingBloc {}

void main() {
  const branch = 'فرع الاختبار';
  late MockMarketingBloc bloc;

  setUpAll(() async {
    await initializeDateFormatting('ar');
  });

  setUp(() async {
    await di.sl.reset();
    bloc = MockMarketingBloc();
    final loaded = AllBranchesAttendanceLoaded(
      data: {
        branch: [
          {
            'delegateId': 'd1',
            'fullName': 'مندوب تجريبي',
            'branchName': branch,
          },
        ],
      },
      favoriteBranches: const [branch],
    );
    whenListen(
      bloc,
      const Stream<MarketingState>.empty(),
      initialState: loaded,
    );

    final floor = MockFloorVerificationService();
    when(() => floor.getLocalVerifications(any())).thenReturn({});
    when(
      () => floor.fetchCloudVerifications(
        date: any(named: 'date'),
        branchNames: any(named: 'branchNames'),
      ),
    ).thenAnswer((_) async => {});
    final prefs = MockBranchPreferenceService();
    when(() => prefs.getFavoriteBranches(any())).thenReturn(const [branch]);
    when(() => prefs.getActiveBranch(any())).thenReturn(null);

    di.sl.registerFactory<MarketingBloc>(() => bloc);
    di.sl.registerSingleton<FloorVerificationService>(floor);
    di.sl.registerSingleton<BranchPreferenceService>(prefs);
  });

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
  });

  tearDown(() async {
    await di.sl.reset();
  });

  testWidgets(
    'BranchHomeScreen shows the branch Excel export button and it opens the export modal',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);

      // The test font (Ahem) renders Arabic glyphs much wider than real fonts,
      // so ignore RenderFlex overflow noise; any other error still fails.
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      await tester.pumpWidget(
        _buildTestApp(
          BranchHomeScreen(
            marketingUser: _createDelegate(role: UserRole.marketing),
          ),
        ),
      );
      await tester.pump();

      final exportButton = find.byTooltip('تصدير كشف الفرع إلى Excel');
      expect(exportButton, findsOneWidget);
      expect(find.byIcon(Icons.table_chart_rounded), findsOneWidget);

      await tester.tap(exportButton);
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 500));

      expect(find.text('تصدير كشف الحضور إلى Excel'), findsOneWidget);
    },
  );
}
