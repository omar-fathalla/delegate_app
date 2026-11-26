// TAS-149 / TAS-150: the «الصور» page on the web HR shell.
//
// * One-line toolbar in the same order on both views, with the one
//   «طلب إذن تصوير» button.
// * The permissions empty state has no button of its own.
// * «طلب إذن تصوير» opens a dialog on the web, a bottom sheet on mobile.
// * «التقرير الشهري» opens as an inner page of the shell without its own
//   app bar.
// * The shell can switch the page to its permissions view.
import 'dart:async';

import 'package:bloc_test/bloc_test.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/presentation/bloc/branch_bloc.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/tabs/hr_photos_tab.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_empty_state.dart';
import 'package:delegate_app/features/hr/presentation/widgets/hr_inner_page.dart';
import 'package:delegate_app/features/photo_permission/presentation/bloc/photo_permission_bloc.dart';
import 'package:delegate_app/features/photo_permission/presentation/pages/monthly_photo_report_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart' as di;
import 'package:delegate_app/l10n/app_localizations.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';
import 'package:mocktail/mocktail.dart';
import 'package:delegate_app/l10n/app_localizations_delegates.dart';

class _MockPhotoBloc extends MockBloc<PhotoPermissionEvent, PhotoPermissionState>
    implements PhotoPermissionBloc {}

class _MockBranchBloc extends MockBloc<BranchEvent, BranchState>
    implements BranchBloc {}

class _FakePhotoEvent extends Fake implements PhotoPermissionEvent {}

class _FakeBranchEvent extends Fake implements BranchEvent {}

Delegate _hr() => Delegate(
  uid: 'seed-fake-hr',
  firstName: 'موظف',
  middleName: '',
  lastName: 'تجريبي',
  fullName: 'موظف تجريبي',
  nationalityID: '29501010101234',
  motherName: '',
  city: 'القاهرة',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.promoter,
  birthDate: DateTime(1995, 1, 1),
  organizationUID: 'seed-fake-org',
  organizationName: 'منظمة تجريبية',
  companyUID: 'seed-fake-co-alpha',
  companyName: 'شركة تجريبية',
  status: DelegateStatus.active,
  delegatePublicId: 'seed-fake-hr-pub',
  allReceiptCodes: const [],
  createdAt: DateTime(2024, 1, 1),
  createdBy: 'seed',
  hasPendingUpdate: false,
  isDeductedFromCompany: false,
  isPrinted: false,
  isProfileComplete: true,
  numberOfDocuments: 0,
  paymentAmount: 0,
  version: 1,
  documents: const [],
  role: UserRole.hr,
);

void main() {
  late _MockPhotoBloc photoBloc;
  late StreamController<PhotoPermissionState> states;

  setUpAll(() {
    registerFallbackValue(_FakePhotoEvent());
    registerFallbackValue(_FakeBranchEvent());
  });

  setUp(() {
    photoBloc = _MockPhotoBloc();
    states = StreamController<PhotoPermissionState>.broadcast();
    whenListen(
      photoBloc,
      states.stream,
      initialState: PhotoPermissionInitial(),
    );
    when(() => photoBloc.close()).thenAnswer((_) async {});

    final branchBloc = _MockBranchBloc();
    when(() => branchBloc.state).thenReturn(const BranchLoaded(branches: []));
    when(() => branchBloc.stream).thenAnswer((_) => const Stream.empty());
    when(() => branchBloc.close()).thenAnswer((_) async {});

    if (di.sl.isRegistered<PhotoPermissionBloc>()) {
      di.sl.unregister<PhotoPermissionBloc>();
    }
    if (di.sl.isRegistered<BranchBloc>()) di.sl.unregister<BranchBloc>();
    di.sl.registerFactory<PhotoPermissionBloc>(() => photoBloc);
    di.sl.registerFactory<BranchBloc>(() => branchBloc);
  });

  tearDown(() async {
    WebRuntimePolicy.debugReset();
    await states.close();
    if (di.sl.isRegistered<PhotoPermissionBloc>()) {
      di.sl.unregister<PhotoPermissionBloc>();
    }
    if (di.sl.isRegistered<BranchBloc>()) di.sl.unregister<BranchBloc>();
  });

  /// Pumps the page at 1440x900. With [inShell] it sits in a nested
  /// navigator under an [HrInnerPageHost], like the wide web shell.
  Future<void> pumpPage(
    WidgetTester tester, {
    bool web = true,
    bool inShell = false,
    HrPhotosView initialView = HrPhotosView.photos,
    HrPhotosViewController? controller,
  }) async {
    WebRuntimePolicy.debugIsWebOverride = web;
    tester.view.physicalSize = const Size(1440, 900);
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.resetPhysicalSize);
    addTearDown(tester.view.resetDevicePixelRatio);

    final page = HRPhotosTab(
      hrDelegate: _hr(),
      initialView: initialView,
      viewController: controller,
    );
    final navKey = GlobalKey<NavigatorState>();
    final body = inShell
        ? HrInnerPageHost(
            navigatorKey: navKey,
            parentTitle: 'الصور',
            child: Navigator(
              key: navKey,
              onGenerateRoute: (_) =>
                  MaterialPageRoute(builder: (_) => Scaffold(body: page)),
            ),
          )
        : Scaffold(body: page);

    await tester.pumpWidget(
      MaterialApp(
        locale: const Locale('ar'),
        localizationsDelegates: appLocalizationsDelegates,
        supportedLocales: AppLocalizations.supportedLocales,
        home: body,
      ),
    );
    await tester.pump();
  }

  Future<void> showPermissions(WidgetTester tester) async {
    states.add(const PhotoPermissionsLoaded(permissions: []));
    // One pump delivers the state, the next one rebuilds with it.
    await tester.pump();
    await tester.pump();
  }

  group('web toolbar', () {
    testWidgets('one line, same order and place on both views', (
      tester,
    ) async {
      await pumpPage(tester);
      states.add(const CapturedPhotosLoaded(photos: []));
      await tester.pump();
      await tester.pump();
      expect(find.byKey(const ValueKey('hr_photos_empty')), findsOneWidget);

      final toolbar = find.byKey(const ValueKey('hr_photos_toolbar'));
      expect(toolbar, findsOneWidget);
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(48));

      Offset at(String key) => tester.getCenter(find.byKey(ValueKey(key)));
      final switchAt = at('hr_photos_view_switch');
      final reportAt = at('hr_photos_monthly_report');
      final requestAt = at('hr_photos_request_permission');
      // RTL: the view switch starts the line, the request button ends it.
      expect(switchAt.dx, greaterThan(reportAt.dx));
      expect(reportAt.dx, greaterThan(requestAt.dx));
      expect(switchAt.dy, reportAt.dy);
      expect(reportAt.dy, requestAt.dy);

      await tester.tap(find.text('أذونات التصوير'));
      await tester.pump();
      await showPermissions(tester);

      expect(
        find.byKey(const ValueKey('hr_photos_permission_filter')),
        findsOneWidget,
      );
      expect(at('hr_photos_view_switch'), switchAt);
      expect(at('hr_photos_monthly_report'), reportAt);
      expect(at('hr_photos_request_permission'), requestAt);
      expect(tester.getSize(toolbar).height, lessThanOrEqualTo(48));
    });

    testWidgets('mobile keeps its own two-row header', (tester) async {
      await pumpPage(tester, web: false);
      expect(find.byKey(const ValueKey('hr_photos_toolbar')), findsNothing);
      expect(find.text('طلب إذن تصوير'), findsOneWidget);
      expect(find.text('التقرير الشهري'), findsOneWidget);
    });
  });

  group('permissions view (TAS-149)', () {
    testWidgets('one request button and the shared empty state', (
      tester,
    ) async {
      await pumpPage(tester, initialView: HrPhotosView.permissions);
      await showPermissions(tester);

      expect(
        find.byKey(const ValueKey('hr_photos_permissions_empty')),
        findsOneWidget,
      );
      expect(find.byType(HrEmptyState), findsOneWidget);
      expect(find.text('لا توجد أذونات تصوير'), findsOneWidget);
      // The toolbar button is the only request entry point.
      expect(find.text('طلب إذن تصوير'), findsOneWidget);
      expect(find.text('إرسال طلب إذن تصوير جديد'), findsNothing);
      expect(find.byType(FloatingActionButton), findsNothing);
      expect(
        find.descendant(
          of: find.byType(HrEmptyState),
          matching: find.byType(FilledButton),
        ),
        findsNothing,
      );
    });

    testWidgets('the shell switches the page to the permissions view', (
      tester,
    ) async {
      final controller = HrPhotosViewController();
      addTearDown(controller.dispose);
      await pumpPage(tester, controller: controller);
      clearInteractions(photoBloc);

      controller.show(HrPhotosView.permissions);
      await tester.pump();
      verify(
        () => photoBloc.add(any(that: isA<LoadPermissionsRequested>())),
      ).called(1);
      await showPermissions(tester);
      expect(
        find.byKey(const ValueKey('hr_photos_permission_filter')),
        findsOneWidget,
      );
    });

    testWidgets('a request made before the page mounts is honoured', (
      tester,
    ) async {
      final controller = HrPhotosViewController()
        ..show(HrPhotosView.permissions);
      addTearDown(controller.dispose);
      await pumpPage(tester, controller: controller);
      verify(
        () => photoBloc.add(any(that: isA<LoadPermissionsRequested>())),
      ).called(1);
    });

    test('the retired permissions slot resolves to «الصور»', () {
      expect(hrShellResolveTab(kHrTabPhotoPermissions), kHrTabPhotos);
      expect(hrShellResolveTab(kHrTabPhotos), kHrTabPhotos);
      expect(hrShellItemById(kHrRetiredPhotoPermissionsId), isNull);
    });
  });

  group('request and report (TAS-150)', () {
    testWidgets('the report has no inline refresh outside the shell', (
      tester,
    ) async {
      await pumpPage(tester, web: false);

      await tester.tap(find.text('التقرير الشهري'));
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 400));

      final report = tester.widget<MonthlyPhotoReportScreen>(
        find.byType(MonthlyPhotoReportScreen),
      );
      expect(report.showAppBar, isTrue);
      expect(report.showInlineRefresh, isFalse);
      expect(
        find.byKey(const ValueKey('monthly_report_inline_refresh')),
        findsNothing,
      );
    });

    testWidgets('«طلب إذن تصوير» opens a dialog on the web', (tester) async {
      await pumpPage(tester, initialView: HrPhotosView.permissions);
      await showPermissions(tester);

      await tester.tap(find.byKey(const ValueKey('hr_photos_request_permission')));
      await tester.pumpAndSettle();

      expect(find.byType(Dialog), findsOneWidget);
      expect(find.byType(BottomSheet), findsNothing);
      expect(
        tester.widget<Text>(find.byKey(const ValueKey('hr_sheet_title'))).data,
        'طلب إذن تصوير',
      );
      expect(find.text('القسم المطلوب للتصوير:'), findsOneWidget);
    });

    testWidgets('«طلب إذن تصوير» stays a bottom sheet on mobile', (
      tester,
    ) async {
      await pumpPage(tester, web: false, initialView: HrPhotosView.permissions);
      await showPermissions(tester);

      await tester.tap(find.text('طلب إذن تصوير'));
      await tester.pumpAndSettle();

      expect(find.byType(BottomSheet), findsOneWidget);
      expect(find.byType(Dialog), findsNothing);
      expect(find.text('إرسال طلب إذن تصوير جديد'), findsWidgets);
    });

    testWidgets('«التقرير الشهري» is a wide inner page without an app bar', (
      tester,
    ) async {
      await pumpPage(tester, inShell: true);

      await tester.tap(find.byKey(const ValueKey('hr_photos_monthly_report')));
      // The report shows an endless loading animation; do not settle.
      await tester.pump();
      await tester.pump(const Duration(milliseconds: 300));

      expect(find.byType(HrInnerPage), findsOneWidget);
      expect(
        tester
            .widget<Text>(find.byKey(const ValueKey('hr_inner_page_title')))
            .data,
        'التقرير الشهري',
      );
      expect(
        tester.widget<HrInnerPage>(find.byType(HrInnerPage)).maxWidth,
        HrInnerPageWidth.wide,
      );
      final report = tester.widget<MonthlyPhotoReportScreen>(
        find.byType(MonthlyPhotoReportScreen),
      );
      expect(report.showAppBar, isFalse);
      expect(report.showInlineRefresh, isTrue);

      // The inline refresh reloads the company photos, like the old app
      // bar action.
      final refresh = find.byKey(
        const ValueKey('monthly_report_inline_refresh'),
      );
      expect(refresh, findsOneWidget);
      expect(tester.widget<IconButton>(refresh).tooltip, 'تحديث');
      clearInteractions(photoBloc);
      await tester.tap(refresh);
      await tester.pump();
      verify(() => photoBloc.add(any())).called(greaterThanOrEqualTo(1));
      expect(
        find.descendant(
          of: find.byType(MonthlyPhotoReportScreen),
          matching: find.byType(AppBar),
        ),
        findsNothing,
      );
    });
  });
}
