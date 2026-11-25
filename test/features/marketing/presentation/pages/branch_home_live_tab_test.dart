// TAS-231 (from PR #188): the branch tab's live listener only runs while
// the tab is selected.
import 'dart:async';

import 'package:flutter/material.dart';
import 'package:flutter_localizations/flutter_localizations.dart';
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
import 'package:delegate_app/features/marketing/data/datasources/marketing_remote_data_source.dart';

class MockFloorVerificationService extends Mock
    implements FloorVerificationService {}

class MockMarketingRemoteDataSource extends Mock
    implements MarketingRemoteDataSource {}

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
  late StreamController<void> changes;
  var listens = 0;
  var cancels = 0;

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

    listens = 0;
    cancels = 0;
    changes = StreamController<void>.broadcast(
      onListen: () => listens++,
      onCancel: () => cancels++,
    );
    final ds = MockMarketingRemoteDataSource();
    when(
      () => ds.watchTodayAttendanceChanges(
        branchNames: any(named: 'branchNames'),
        organizationId: any(named: 'organizationId'),
        date: any(named: 'date'),
      ),
    ).thenAnswer((_) => changes.stream);
    di.sl.registerSingleton<MarketingRemoteDataSource>(ds);
    di.sl.registerFactory<MarketingBloc>(() => bloc);
    di.sl.registerSingleton<FloorVerificationService>(floor);
    di.sl.registerSingleton<BranchPreferenceService>(prefs);
  });

  setUpAll(() {
    registerFallbackValue(DateTime(2026));
    registerFallbackValue(LoadBranchPreferences(userId: 'fallback'));
  });

  tearDown(() async {
    await di.sl.reset();
  });

  testWidgets(
    'hidden tab stops the live listener; showing it reloads and listens again',
    (tester) async {
      tester.view.physicalSize = const Size(1400, 1000);
      tester.view.devicePixelRatio = 1.0;
      addTearDown(tester.view.reset);
      final originalOnError = FlutterError.onError;
      FlutterError.onError = (details) {
        if (details.exceptionAsString().contains('RenderFlex overflowed')) {
          return;
        }
        originalOnError?.call(details);
      };
      addTearDown(() => FlutterError.onError = originalOnError);

      final user = _createDelegate(role: UserRole.marketing);
      Widget screen(bool active) => _buildTestApp(
            BranchHomeScreen(marketingUser: user, isActive: active),
          );

      await tester.pumpWidget(screen(true));
      await tester.pump();
      expect(listens, 1);
      expect(cancels, 0);

      clearInteractions(bloc);
      await tester.pumpWidget(screen(false));
      await tester.pump();
      expect(cancels, 1, reason: 'listener stops while the tab is hidden');

      // A change while hidden must not trigger a reload.
      changes.add(null);
      await tester.pump(const Duration(seconds: 4));
      verifyNever(() => bloc.add(any()));

      await tester.pumpWidget(screen(true));
      await tester.pump();
      expect(listens, 2, reason: 'listener restarts when the tab is shown');
      final events = verify(() => bloc.add(captureAny())).captured;
      expect(
        events.whereType<LoadAllFavoriteBranchesAttendance>().where(
              (e) => e.forceRefresh,
            ),
        isNotEmpty,
        reason: 'showing the tab catches up with one forced reload',
      );
      await changes.close();
    },
  );
}
