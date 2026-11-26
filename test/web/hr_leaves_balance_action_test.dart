import 'package:dartz/dartz.dart';
import 'package:fake_cloud_firestore/fake_cloud_firestore.dart';
import 'package:material_ui/material_ui.dart';
import 'package:flutter_test/flutter_test.dart';

import 'package:delegate_app/core/error/failures.dart';
import 'package:delegate_app/core/platform/web_runtime_policy.dart';
import 'package:delegate_app/features/admin/domain/repositories/admin_repository.dart';
import 'package:delegate_app/features/admin/domain/usecases/get_company_delegates.dart';
import 'package:delegate_app/features/hr/presentation/hr_shell_nav.dart';
import 'package:delegate_app/features/hr/presentation/pages/hr_leaves_and_excuses_screen.dart';
import 'package:delegate_app/features/profile/domain/entities/delegate.dart';
import 'package:delegate_app/injection_container.dart';
import 'package:delegate_app/web/hr_system/hr_web_header_bridge.dart';

/// Counts company-delegate loads, so the shell reload can be observed.
class _CountingGetCompanyDelegates extends Fake implements GetCompanyDelegates {
  int calls = 0;

  @override
  Future<Either<Failure, CompanyDelegatesResult>> call(
    GetCompanyDelegatesParams params,
  ) async {
    calls++;
    return const Left(ServerFailure('fake'));
  }
}

final _hr = Delegate(
  uid: 'hr-1',
  firstName: 'Fake',
  middleName: '',
  lastName: 'HR',
  fullName: 'Fake HR',
  nationalityID: '0',
  motherName: '',
  city: 'Cairo',
  phoneNumber: '01000000000',
  gender: DelegateGender.male,
  position: DelegatePosition.supervisor,
  birthDate: DateTime(1995),
  organizationUID: 'org-1',
  organizationName: 'Org',
  companyUID: 'co-1',
  companyName: 'Company',
  status: DelegateStatus.active,
  delegatePublicId: '',
  allReceiptCodes: const [],
  createdAt: DateTime(2026),
  createdBy: 'test',
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

/// TAS-183: inside the HR shell the page has no AppBar, so «إدارة الأرصدة»
/// must be reachable from the page itself. Web drops the page refresh (the
/// shell top bar has one).
void main() {
  const manage = ValueKey('hr_leaves_manage_balances');
  const sheetTitle = 'إدارة رصيد الإجازات السنوية للمناديب';

  tearDown(WebRuntimePolicy.debugReset);

  void window(WidgetTester tester, Size size) {
    tester.view.physicalSize = size;
    tester.view.devicePixelRatio = 1;
    addTearDown(tester.view.reset);
  }

  Future<void> pump(
    WidgetTester tester, {
    required bool showAppBar,
    HrWebHeaderBridge? bridge,
  }) async {
    Widget screen = HRLeavesAndExcusesScreen(
      hrDelegate: _hr,
      showAppBar: showAppBar,
      firestore: FakeFirebaseFirestore(),
    );
    if (bridge != null) {
      screen = HrWebHeaderBridgeScope(bridge: bridge, child: screen);
    }
    await tester.pumpWidget(
      MaterialApp(
        home: Directionality(textDirection: TextDirection.rtl, child: screen),
      ),
    );
    await tester.pumpAndSettle();
  }

  bool isInToolbarRow(WidgetTester tester) => find
      .ancestor(of: find.byKey(manage), matching: find.byType(OutlinedButton))
      .evaluate()
      .isNotEmpty;

  testWidgets('web shell tab (1440x900): button in the toolbar, no refresh', (
    tester,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    window(tester, const Size(1440, 900));
    await pump(tester, showAppBar: false);

    expect(find.byKey(manage), findsOneWidget);
    expect(find.text('إدارة الأرصدة'), findsOneWidget);
    expect(find.byType(OutlinedButton), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
    // Same row as the search field and the status filter.
    final searchY = tester.getCenter(find.byType(TextField)).dy;
    final buttonY = tester.getCenter(find.byKey(manage)).dy;
    expect((searchY - buttonY).abs(), lessThan(1));

    await tester.tap(find.byKey(manage));
    await tester.pumpAndSettle();
    expect(find.text(sheetTitle), findsOneWidget);
  });

  testWidgets('narrow web pane: button in the action row above', (
    tester,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = true;
    window(tester, const Size(800, 900));
    await pump(tester, showAppBar: false);

    expect(find.byKey(manage), findsOneWidget);
    expect(find.byType(OutlinedButton), findsNothing);
    expect(
      tester.getCenter(find.byKey(manage)).dy,
      lessThan(tester.getCenter(find.byType(TextField)).dy),
    );
  });

  testWidgets('mobile tab: button reachable, opens the balances sheet', (
    tester,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    window(tester, const Size(400, 860));
    await pump(tester, showAppBar: false);

    expect(find.byKey(manage), findsOneWidget);
    expect(isInToolbarRow(tester), isFalse);
    await tester.tap(find.byKey(manage));
    await tester.pumpAndSettle();
    expect(find.text(sheetTitle), findsOneWidget);
  });

  testWidgets('with its own AppBar: no extra button; refresh only on mobile', (
    tester,
  ) async {
    WebRuntimePolicy.debugIsWebOverride = false;
    window(tester, const Size(400, 860));
    await pump(tester, showAppBar: true);
    expect(find.byKey(manage), findsNothing);
    expect(find.byTooltip('إدارة إجازات وأرصدة المناديب'), findsOneWidget);
    expect(find.byIcon(Icons.refresh_rounded), findsOneWidget);

    WebRuntimePolicy.debugIsWebOverride = true;
    await pump(tester, showAppBar: true);
    expect(find.byKey(manage), findsNothing);
    expect(find.byIcon(Icons.refresh_rounded), findsNothing);
  });

  testWidgets('web shell: the top-bar refresh reloads this tab', (
    tester,
  ) async {
    sl.allowReassignment = true;
    final delegates = _CountingGetCompanyDelegates();
    sl.registerFactory<GetCompanyDelegates>(() => delegates);
    addTearDown(() => sl.unregister<GetCompanyDelegates>());
    final bridge = HrWebHeaderBridge();
    addTearDown(bridge.dispose);

    WebRuntimePolicy.debugIsWebOverride = true;
    window(tester, const Size(1440, 900));
    await pump(tester, showAppBar: false, bridge: bridge);
    final reload = bridge.pageReload(kHrTabLeaves);
    expect(reload, isNotNull);
    final before = delegates.calls;
    await tester.runAsync(reload!);
    await tester.pumpAndSettle();
    expect(delegates.calls, before + 1);

    // Leaving the tree releases the hook.
    await tester.pumpWidget(const SizedBox());
    expect(bridge.pageReload(kHrTabLeaves), isNull);
  });

  testWidgets('mobile tab does not register a shell reload', (tester) async {
    final bridge = HrWebHeaderBridge();
    addTearDown(bridge.dispose);
    WebRuntimePolicy.debugIsWebOverride = false;
    window(tester, const Size(400, 860));
    await pump(tester, showAppBar: false, bridge: bridge);
    expect(bridge.pageReload(kHrTabLeaves), isNull);
  });
}
